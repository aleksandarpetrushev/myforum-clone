module Events
  class Update
    def initialize(event:, attributes:)
      @event = event
      @attributes = attributes.to_h.stringify_keys
    end

    # Any status may be sent; the Event state machine decides whether the change is allowed. Cancelling is refused
    # here: it only happens through Events::Cancel (POST /api/events/:id/cancel).
    def call
      allowed_ids = extract_allowed_ids
      validate_allowed_organizations!(allowed_ids)
      was_published = @event.status == "published"
      ApplicationRecord.transaction do
        @event.update!(@attributes) if @attributes.present?
        Events::AllowedOrganizations.replace(@event, allowed_ids) unless allowed_ids.nil?
        @event.touch if allowed_ids && @attributes.blank?
        OutboxEvent.record!(
          event_type: "EventUpdated",
          aggregate_type: "Event",
          aggregate_id: @event.id,
          idempotency_key: "event_updated:#{@event.id}:#{@event.reload.updated_at.to_i}",
          payload: { "event" => @event.snapshot }
        )
        Events::Publication.record!(@event) if !was_published && @event.status == "published"
      end

      Events::Cache.invalidate(@event.id)
      RebuildEventCacheJob.perform_later(@event.id)
      @event
    end

    private

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
