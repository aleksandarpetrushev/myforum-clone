module Registrations
  # The RegistrationCreated outbox row, written when someone ends up holding a confirmed seat: a direct
  # registration, a waitlisted person registering in the last hour, or an accepted waitlist offer.
  class CreatedEvent
    def self.record!(event, registration)
      OutboxEvent.record!(
        event_type: "RegistrationCreated",
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "registration_created:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => registration.user_id,
          "event_id" => event.id,
          "user_location" => registration.user.location,
          "event" => event.snapshot
        }
      )
    end
  end
end
