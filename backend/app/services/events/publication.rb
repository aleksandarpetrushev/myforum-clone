module Events
  # EventPublished marks the moment an event becomes published, whether on create or on a later update.
  # The idempotency key keeps it to one outbox row per event, however often it is recorded.
  class Publication
    def self.record!(event)
      OutboxEvent.record_once!(
        event_type: "EventPublished",
        aggregate_type: "Event",
        aggregate_id: event.id,
        idempotency_key: "event_published:#{event.id}",
        payload: { "event" => event.snapshot }
      )
    end
  end
end
