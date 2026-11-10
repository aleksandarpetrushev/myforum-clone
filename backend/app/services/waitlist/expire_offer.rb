module Waitlist
  # Ends one lapsed offer: the person leaves the line and is told, and the seat goes to the next in line.
  # Does nothing for an offer that was accepted, declined or replaced since (another lifecycle_version), and
  # reschedules itself if it runs before the deadline.
  class ExpireOffer
    def self.call(registration_id, lifecycle_version, now: Time.current)
      offers = []
      reschedule_at = nil

      ApplicationRecord.transaction do
        registration = Registration.find_by(id: registration_id)
        next unless registration

        event = Event.lock.find(registration.event_id)
        registration.lock!
        next unless registration.offered? && registration.lifecycle_version == lifecycle_version

        if registration.offer_expires_at > now
          reschedule_at = registration.offer_expires_at
          next
        end

        Registrations::Cancellation.apply!(registration, by: "offer_expired")
        event.update!(reserved_spots: event.reserved_spots - 1, revision: event.revision + 1)
        record_expired(event, registration)
        offers = OfferFreedSeats.call(event, now: now)
      end

      if reschedule_at
        ExpireWaitlistOfferJob.set(wait_until: reschedule_at).perform_later(registration_id, lifecycle_version)
      end
      ScheduleExpiry.call(offers)
    end

    def self.record_expired(event, registration)
      OutboxEvent.create!(
        event_type: "WaitlistOfferExpired",
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "waitlist_offer_expired:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => registration.user_id,
          "event_id" => event.id,
          "user_location" => registration.user.location,
          "event" => event.snapshot
        }
      )
    end
    private_class_method :record_expired
  end
end
