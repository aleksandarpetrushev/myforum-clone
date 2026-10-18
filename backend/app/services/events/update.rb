module Events
  class Update
    def initialize(event:, attributes:)
      @event = event
      @attributes = attributes.to_h.stringify_keys
    end

    def call
      allowed_ids = extract_allowed_ids
      ApplicationRecord.transaction do
        @event.update!(@attributes) if @attributes.present?
        replace_allowed_organizations(allowed_ids) unless allowed_ids.nil?
        @event.touch if allowed_ids && @attributes.blank?
        OutboxEvent.record!(
          event_type: "EventUpdated",
          aggregate_type: "Event",
          aggregate_id: @event.id,
          idempotency_key: "event_updated:#{@event.id}:#{@event.reload.updated_at.to_i}",
          payload: { "event" => @event.snapshot }
        )
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

    def replace_allowed_organizations(organization_ids)
      @event.event_allowed_organizations.destroy_all
      organization_ids.each do |organization_id|
        @event.event_allowed_organizations.create!(organization_id: organization_id)
      end
    end
  end
end
