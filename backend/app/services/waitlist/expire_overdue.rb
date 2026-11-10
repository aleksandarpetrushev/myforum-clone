module Waitlist
  # Offers past their deadline whose expiry job never ran, for example because a scheduled job was lost. Run with
  # bin/rails waitlist:expire_overdue; Metrics.overdue_waitlist_offers above 0 is the signal.
  class ExpireOverdue
    # A scheduled job may run a little late; only count an offer as overdue after this grace.
    GRACE = 1.minute

    def self.scope(now = Time.current)
      Registration.where(status: "offered").where("offer_expires_at <= ?", now - GRACE)
    end

    def self.call(now: Time.current)
      ids = scope(now).pluck(:id, :lifecycle_version)
      ids.each { |id, version| ExpireOffer.call(id, version, now: now) }
      ids.size
    end
  end
end
