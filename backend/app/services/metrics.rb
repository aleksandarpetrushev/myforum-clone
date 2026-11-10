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
    recommendations_fetched_total
    recommendations_stale_total
    recommendations_unavailable_total
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

    # Above 0 means the personalization service cannot read some rows yet: deploy a version that can, then
    # run bin/rails outbox:redeliver_deferred (personalization/contract/README.md).
    def outbox_deferred_count
      OutboxEvent.deferred.count
    end

    # Above 0 means an offer's expiry job was lost: run bin/rails waitlist:expire_overdue.
    def overdue_waitlist_offers
      Waitlist::ExpireOverdue.scope.count
    end

    # Above 0 for longer than the job retry window means a cancellation cascade is stuck.
    # Recover with bin/rails events:resume_cancellations.
    def cancelled_events_with_confirmed_registrations
      Events::StuckCancellations.scope.count
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
