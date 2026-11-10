module Registrations
  class Cancel
    class UserNotRegistered < StandardError; end
    class InvalidState < StandardError; end
    class EventStarted < StandardError; end
    class InvariantViolation < StandardError; end

    def initialize(user:, event:)
      @user = user
      @event = event
    end

    def call
      registration = nil

      ApplicationRecord.transaction do
        event = Event.lock.includes(:topics).find(@event.id)
        registration = event.registrations.lock.find_by(user_id: @user.id)
        raise UserNotRegistered unless registration

        if registration.waitlisted?
          # Leaving the line holds no seat, so nothing else changes and nobody is told.
          Registrations::Cancellation.apply!(registration, by: "participant")
        elsif registration.confirmed? || registration.offered?
          raise EventStarted if event.starts_at <= Time.current
          ensure_reserved_spot!(event, registration)

          # Declining an offer frees its held seat without a notification: the person chose it, and the next
          # WaitlistOffered row carries the new seat count to the personalization service.
          declined_offer = registration.offered?
          Registrations::Cancellation.apply!(registration, by: "participant")
          event.update!(reserved_spots: event.reserved_spots - 1, revision: event.revision + 1)
          record_cancelled(event, registration) unless declined_offer
          @offers = Waitlist::OfferFreedSeats.call(event)
        elsif !registration.cancelled?
          raise InvalidState
        end
      end

      Waitlist::ScheduleExpiry.call(offers)
      registration
    end

    # Waitlist registrations this cancel offered a seat to (MF-202).
    def offers
      @offers || []
    end

    private

    def record_cancelled(event, registration)
      OutboxEvent.record!(
        event_type: "RegistrationCancelled",
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "registration_cancelled:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => @user.id,
          "event_id" => event.id,
          "user_location" => @user.location,
          "event" => event.snapshot
        }
      )
    end

    def ensure_reserved_spot!(event, registration)
      return if event.reserved_spots >= 1

      Rails.logger.error({
        event: "registration.cancel.invariant_violation",
        event_id: event.id,
        registration_id: registration.id,
        reserved_spots: event.reserved_spots
      }.to_json)
      Metrics.increment("registration_cancel_invariant_violation_total")
      raise InvariantViolation, "confirmed registration #{registration.id} has no reserved spot on event #{event.id}"
    end
  end
end
