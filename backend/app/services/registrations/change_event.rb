module Registrations
  # The one outbox row for a change to a registration: RegistrationCreated, RegistrationCancelled, WaitlistOffered,
  # WaitlistOfferExpired. Same payload for all (the contract's registrationChange), keyed by event type,
  # registration and lifecycle_version, which together name one change. create!, so a repeat fails loudly.
  class ChangeEvent
    def self.record!(event_type, event, registration, extra = {})
      OutboxEvent.create!(
        event_type: event_type,
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "#{event_type.underscore}:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => registration.user_id,
          "event_id" => event.id,
          "user_location" => registration.user.location,
          "event" => event.snapshot
        }.merge(extra)
      )
    end
  end
end
