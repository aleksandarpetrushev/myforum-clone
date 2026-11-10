module Waitlist
  # Offers past their deadline whose expiry job never ran, for example because a scheduled job was lost. Run with
  # bin/rails waitlist:expire_overdue; Metrics.overdue_waitlist_offers above 0 is the signal.
  class ExpireOverdue
    # A scheduled job may run a little late; only count an offer as overdue after this grace.
    GRACE = 1.minute

    def self.scope(now = Time.current)
      Registration.where(status: "offered").where("offer_expires_at <= ?", now - GRACE)
    end

    class IncompleteSweep < StandardError; end

    # Each offer on its own: one that fails is logged and retried next run, and does not hold back the rest.
    # Raises at the end if any failed, so the task exits non-zero.
    def self.call(now: Time.current)
      failures = []
      expired = 0
      scope(now).pluck(:id, :lifecycle_version).each do |id, version|
        ExpireOffer.call(id, version, now: now)
        expired += 1
      rescue StandardError => error
        failures << id
        Rails.logger.error({ event: "waitlist.expire_overdue_failed", registration_id: id, error: error.class.name,
                             message: error.message }.to_json)
      end
      raise IncompleteSweep, "registrations #{failures.join(", ")} not expired" if failures.any?

      expired
    end
  end
end
