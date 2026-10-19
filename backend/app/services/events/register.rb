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
        registration = event.registrations.lock.find_by(user_id: @user.id)

        if registration.nil?
          raise EventFull if event.reserved_spots >= event.capacity

          registration = event.registrations.create!(user: @user, status: "confirmed", lifecycle_version: 1)
        elsif registration.cancelled?
          raise EventFull if event.reserved_spots >= event.capacity

          registration.lifecycle_version += 1
          registration.reconfirm!
        elsif registration.confirmed? || registration.failed?
          raise AlreadyRegistered
        else
          raise AlreadyRegistered
        end

        event.update!(reserved_spots: event.reserved_spots + 1)
        record_created(event, registration)
      end

      registration
    rescue ActiveRecord::RecordNotUnique
      raise AlreadyRegistered
    end

    private

    def record_created(event, registration)
      OutboxEvent.record!(
        event_type: "RegistrationCreated",
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "registration_created:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => @user.id,
          "event_id" => event.id,
          "user_location" => @user.location,
          "event" => event.snapshot
        }
      )
    end
  end
end
