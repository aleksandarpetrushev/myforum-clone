module Waitlist
  # Puts the user in line for a full event. Joining twice returns the same place in line.
  class Join
    class AlreadyRegistered < StandardError; end
    class SeatsAvailable < StandardError; end
    class Closed < StandardError; end

    Result = Struct.new(:registration, :created, keyword_init: true)

    def initialize(user:, event:, now: Time.current)
      @user = user
      @event = event
      @now = now
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        event = Event.lock.find(@event.id)
        # Only published events take registrations; anything else looks the same as an event the caller cannot see.
        raise ActiveRecord::RecordNotFound unless event.status == "published"

        registration = event.registrations.lock.find_by(user_id: @user.id)
        if registration&.waitlisted? || registration&.offered?
          result = Result.new(registration: registration, created: false)
          next
        end
        raise AlreadyRegistered if registration&.confirmed? || registration&.failed?
        raise Closed if Rules.closed?(event, @now)
        raise SeatsAvailable if event.reserved_spots < event.capacity

        result = Result.new(registration: join(event, registration), created: true)
      end

      result
    rescue ActiveRecord::RecordNotUnique
      # Another request created this user's row first: a second join, or a registration. Answer for what it is.
      existing = @event.registrations.find_by!(user_id: @user.id)
      raise AlreadyRegistered unless existing.waitlisted? || existing.offered?

      Result.new(registration: existing, created: false)
    end

    private

    def join(event, registration)
      if registration
        registration.lifecycle_version += 1
        registration.cancelled_by = nil
        registration.waitlisted_at = @now
        registration.offered_at = nil
        registration.offer_expires_at = nil
        registration.join_waitlist!
        registration
      else
        event.registrations.create!(user: @user, status: "waitlisted", waitlisted_at: @now, lifecycle_version: 1)
      end
    end
  end
end
