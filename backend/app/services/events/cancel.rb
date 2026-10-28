module Events
  # Cancels an event and hands its registrations to CancelEventRegistrationsJob through the outbox.
  # Cancelling an event that is already cancelled returns it unchanged, with no further effect.
  class Cancel
    class EventStarted < StandardError; end

    def initialize(event:)
      @event = event
    end

    def call
      event = nil
      cancelled_now = false

      ApplicationRecord.transaction do
        event = Event.lock.find(@event.id)
        next if event.cancelled?
        raise EventStarted if event.starts_at <= Time.current

        # A draft has no cancel transition, so this raises StateMachines::InvalidTransition (422).
        event.cancel!
        OutboxEvent.record!(
          event_type: "EventCancelled",
          aggregate_type: "Event",
          aggregate_id: event.id,
          idempotency_key: "event_cancelled:#{event.id}",
          payload: { "event" => event.snapshot }
        )
        cancelled_now = true
      end

      if cancelled_now
        Events::Cache.invalidate(event.id)
        RebuildEventCacheJob.perform_later(event.id)
      end
      event
    end
  end
end
