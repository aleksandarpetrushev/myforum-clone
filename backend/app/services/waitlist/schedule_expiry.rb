module Waitlist
  # Schedules each offer's expiry. Call it after the transaction that made the offers has committed, so a rollback
  # schedules nothing. Waitlist::ExpireOverdue catches any job that is lost.
  class ScheduleExpiry
    def self.call(offers)
      offers.each do |registration|
        ExpireWaitlistOfferJob.set(wait_until: registration.offer_expires_at)
                              .perform_later(registration.id, registration.lifecycle_version)
      end
    end
  end
end
