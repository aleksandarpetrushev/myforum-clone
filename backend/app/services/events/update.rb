module Events
  class Update
    def initialize(event:, attributes:)
      @event = event
      @attributes = attributes.to_h.stringify_keys
    end

    # Any status may be sent; the Event state machine decides whether the change is allowed. Cancelling is refused
    # here: it only happens through Events::Cancel (POST /api/events/:id/cancel).
    #
    # Saves to one event run one after the other (row lock), and each save that changes something gets the next
    # revision, which keys its EventUpdated row. A save that changes nothing writes nothing and still succeeds;
    # it is not validated, because a stored event is always valid and nothing about it changed.
    def call
      allowed_ids = extract_allowed_ids
      changed = false

      ApplicationRecord.transaction do
        @event.lock!
        validate_allowed_organizations!(allowed_ids)
        was_published = @event.status == "published"

        @event.assign_attributes(@attributes)
        organizations_changed = !allowed_ids.nil? && allowed_ids.sort != @event.allowed_organization_ids.sort
        changed = @event.changed? || organizations_changed
        next unless changed

        @event.revision += 1
        @event.save!
        # Read now: the reload below for the snapshot forgets what this save changed.
        raised_capacity = capacity_raised?
        moved_start = @event.saved_change_to_starts_at?
        Events::AllowedOrganizations.replace(@event, allowed_ids) if organizations_changed
        # create!, not record!: with the lock and the revision a repeated key cannot happen, so if one does it must
        # fail loudly rather than return the earlier row and drop this change.
        OutboxEvent.create!(
          event_type: "EventUpdated",
          aggregate_type: "Event",
          aggregate_id: @event.id,
          idempotency_key: "event_updated:#{@event.id}:#{@event.revision}",
          payload: { "event" => @event.reload.snapshot }
        )
        Events::Publication.record!(@event) if !was_published && @event.status == "published"
        # More seats, or a start moved out of the closed last hour: offer free seats to the line in the same
        # transaction, before a direct registration can take them. A moved start also shortens open offers that
        # would now end after it.
        @shortened = moved_start ? Waitlist::FitOffersToStart.call(@event) : []
        @offers = Waitlist::OfferFreedSeats.call(@event) if raised_capacity || moved_start
      end
      return @event unless changed

      Waitlist::ScheduleExpiry.call(offers + (@shortened || []))
      Events::Cache.invalidate(@event.id)
      RebuildEventCacheJob.perform_later(@event.id)
      @event
    end

    # Waitlist registrations this update offered a seat to (MF-202).
    def offers
      @offers || []
    end

    private

    def capacity_raised?
      before, after = @event.saved_change_to_capacity
      before && after && after > before
    end

    def extract_allowed_ids
      return nil unless @attributes.key?("allowed_organization_ids")

      Array(@attributes.delete("allowed_organization_ids")).map(&:to_i).uniq
    end

    # Judges the list the event will end up with: the ids sent, or the current ones when none were sent.
    def validate_allowed_organizations!(allowed_ids)
      visibility = @attributes.fetch("visibility", @event.visibility)
      Events::AllowedOrganizations.validate(@event, allowed_ids || @event.allowed_organization_ids, visibility: visibility)
      raise ActiveRecord::RecordInvalid, @event if @event.errors.any?
    end
  end
end
