module Events
  class Register
    class EventFull < StandardError; end
    class AlreadyRegistered < StandardError; end

    def initialize(user:, event:)
      @user = user
      @event = event
    end

    def call
      registration = nil

      ApplicationRecord.transaction do
        event = Event.lock.includes(:topics).find(@event.id)

        if event.registrations.exists?(user_id: @user.id)
          raise AlreadyRegistered
        end
        raise EventFull if event.reserved_spots >= event.capacity

        registration = event.registrations.create!(user: @user, status: "confirmed")
        event.update!(reserved_spots: event.reserved_spots + 1)

        OutboxEvent.record!(
          event_type: "RegistrationCreated",
          aggregate_type: "Registration",
          aggregate_id: registration.id,
          idempotency_key: "registration_created:#{registration.id}",
          payload: {
            "registration_id" => registration.id,
            "user_id" => @user.id,
            "event_id" => event.id,
            "user_location" => @user.location,
            "event" => event.snapshot
          }
        )
      end

      registration
    rescue ActiveRecord::RecordNotUnique
      raise AlreadyRegistered
    end
  end
end
