module Events
  class Update
    def initialize(event:, attributes:)
      @event = event
      @attributes = attributes
    end

    def call
      ApplicationRecord.transaction do
        @event.update!(@attributes)
        OutboxEvent.record!(
          event_type: "EventUpdated",
          aggregate_type: "Event",
          aggregate_id: @event.id,
          idempotency_key: "event_updated:#{@event.id}:#{@event.updated_at.to_i}",
          payload: { "event" => @event.reload.snapshot }
        )
      end

      Events::Cache.invalidate(@event.id)
      RebuildEventCacheJob.perform_later(@event.id)
      @event
    end
  end
end
