module Outbox
  # Dispatches pending outbox rows oldest first. A row whose dispatch fails stays pending and backs off on its own
  # (attempts, next_attempt_at), and the pass carries on with other rows, so one consumer being down never stops
  # notifications and analytics for everyone (MF-204). Later rows with the failed row's ordering key wait behind it.
  #
  # Known limit: the pass reads the oldest BATCH_SIZE pending rows. If all of them wait behind failing rows, newer
  # rows wait too until the failures clear; Metrics.outbox_stall_seconds shows it.
  class Publisher
    BATCH_SIZE = 100
    MAX_BACKOFF = 5.minutes

    def call(now: Time.current)
      published = 0
      waiting_keys = Set.new

      OutboxEvent.pending.order(:id).limit(BATCH_SIZE).each do |event|
        key = event.ordering_key
        next if waiting_keys.include?(key)

        if event.next_attempt_at && event.next_attempt_at > now
          waiting_keys << key
          next
        end

        begin
          published += 1 if dispatch(event)
        rescue StandardError => error
          record_failure(event, error, now)
          waiting_keys << key
        end
      end

      published
    end

    def self.backoff(attempts)
      [2**attempts, MAX_BACKOFF.to_i].min.seconds
    end

    private

    # true when the row was published.
    def dispatch(event)
      event.with_lock do
        next false unless event.status == "pending"

        if Dispatcher.call(event) == :deferred
          event.update!(status: "deferred")
          false
        else
          event.update!(status: "published", published_at: Time.current)
          true
        end
      end
    end

    # Written outside the row's transaction, which the error rolled back, so the attempt is always counted.
    def record_failure(event, error, now)
      attempts = event.attempts + 1
      OutboxEvent.where(id: event.id, status: "pending").update_all(
        attempts: attempts,
        next_attempt_at: now + self.class.backoff(attempts),
        last_error: "#{error.class}: #{error.message}".truncate(250),
        updated_at: now
      )
      Metrics.increment("outbox_dispatch_failed_total")
      Rails.logger.error({ event: "outbox.dispatch_failed", outbox_event_id: event.id, event_type: event.event_type,
                           attempts: attempts, error: error.class.name, message: error.message }.to_json)
    end
  end
end
