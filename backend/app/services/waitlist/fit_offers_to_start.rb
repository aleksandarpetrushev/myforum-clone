module Waitlist
  # After the start moves, no open offer may run past min(24 hours, half the time to the new start). Run inside
  # the update's transaction with the event locked; returns the offers it shortened, whose expiry the caller
  # schedules after commit. Their old expiry jobs find nothing to do once the offer has ended.
  class FitOffersToStart
    def self.call(event, now: Time.current)
      latest = Rules.offer_expires_at(event, now)
      event.registrations.where(status: "offered").where("offer_expires_at > ?", latest).lock.to_a.each do |offer|
        offer.update!(offer_expires_at: latest)
      end
    end
  end
end
