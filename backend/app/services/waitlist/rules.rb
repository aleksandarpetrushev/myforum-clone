module Waitlist
  # The PO's timing rules for MF-202, in one place for joining and offering.
  module Rules
    # No offers and no new joins this close to the start: a seat still free is open for normal registration.
    CLOSES_BEFORE_START = 1.hour
    MAX_OFFER_LENGTH = 24.hours

    def self.closed?(event, now = Time.current)
      event.starts_at - now <= CLOSES_BEFORE_START
    end

    # min(24 hours, half the time until the event starts), so an offer always ends well before the event.
    def self.offer_expires_at(event, now = Time.current)
      now + [MAX_OFFER_LENGTH, (event.starts_at - now) / 2].min
    end
  end
end
