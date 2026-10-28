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

        if registration.can_cancel?
          raise EventStarted if event.starts_at <= Time.current
          ensure_reserved_spot!(event, registration)

          Registrations::Cancellation.apply!(registration, by: "participant")
          event.update!(reserved_spots: event.reserved_spots - 1)
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
        elsif !registration.cancelled?
          raise InvalidState
        end
      end

      registration
    end

    private

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
