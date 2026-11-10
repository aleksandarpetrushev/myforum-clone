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
        # Only published events take registrations; anything else looks the same as an event the caller cannot see.
        raise ActiveRecord::RecordNotFound unless event.status == "published"

        registration = event.registrations.lock.find_by(user_id: @user.id)

        if registration.nil?
          raise EventFull if event.reserved_spots >= event.capacity

          registration = event.registrations.create!(user: @user, status: "confirmed", lifecycle_version: 1)
        elsif registration.cancelled?
          raise EventFull if event.reserved_spots >= event.capacity

          registration.lifecycle_version += 1
          registration.cancelled_by = nil
          registration.reconfirm!
        elsif registration.waitlisted?
          # A free seat while someone is still in line only happens in the last hour, when the line is closed
          # and seats go to whoever registers first (MF-202). The person in line may take it too.
          raise EventFull if event.reserved_spots >= event.capacity

          registration.confirm_from_waitlist!
        else
          # confirmed, failed, or offered: an offer is accepted through Waitlist::AcceptOffer.
          raise AlreadyRegistered
        end

        event.update!(reserved_spots: event.reserved_spots + 1, revision: event.revision + 1)
        Registrations::ChangeEvent.record!("RegistrationCreated", event, registration)
      end

      registration
    rescue ActiveRecord::RecordNotUnique
      raise AlreadyRegistered
    end
  end
end
