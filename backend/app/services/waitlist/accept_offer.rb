module Waitlist
  # Confirms the seat a waitlist offer holds. The seat is already counted, so only the registration changes.
  class AcceptOffer
    class NoOffer < StandardError; end

    def initialize(user:, event:, now: Time.current)
      @user = user
      @event = event
      @now = now
    end

    def call
      registration = nil

      ApplicationRecord.transaction do
        event = Event.lock.find(@event.id)
        registration = event.registrations.lock.find_by(user_id: @user.id)
        # A lapsed offer is refused even if its expiry job has not run yet, and so is an offer for an event that
        # was cancelled (before the cascade reached this row) or has already started.
        raise NoOffer unless registration&.offered? && registration.offer_expires_at > @now
        raise NoOffer unless event.status == "published" && event.starts_at > @now

        registration.accept_offer!
        Registrations::ChangeEvent.record!("RegistrationCreated", event, registration)
      end

      registration
    end
  end
end
