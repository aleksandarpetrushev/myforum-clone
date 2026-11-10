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
        # A lapsed offer is refused even if its expiry job has not run yet.
        raise NoOffer unless registration&.offered? && registration.offer_expires_at > @now

        registration.accept_offer!
        Registrations::CreatedEvent.record!(event, registration)
      end

      registration
    end
  end
end
