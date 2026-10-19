class Metrics
  NAMES = %w[
    http_requests_total
    http_request_duration_ms_count
    http_request_duration_ms_sum
    registration_success_total
    registration_failure_total
    registration_cancel_success_total
    registration_cancel_failure_total
    registration_cancel_invariant_violation_total
  ].freeze

  LOCK = Mutex.new

  class << self
    def increment(name, by: 1)
      LOCK.synchronize do
        values[name] += by
      end
    end

    def observe_duration(milliseconds)
      increment("http_request_duration_ms_count")
      increment("http_request_duration_ms_sum", by: milliseconds.to_i)
    end

    def snapshot
      LOCK.synchronize { values.dup }
    end

    def outbox_pending_age_seconds
      oldest = OutboxEvent.pending.minimum(:created_at)
      return 0 unless oldest

      (Time.current - oldest).round
    end

    def reset!
      LOCK.synchronize { @values = Hash.new(0) }
    end

    private

    def values
      @values ||= Hash.new(0)
    end
  end
end
