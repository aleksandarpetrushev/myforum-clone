module Waitlist
  # Offers every free seat to the people first in line, in one batch. Call it inside the transaction that freed
  # the seats, with the event row already locked, so no direct registration can take a seat that belongs to the
  # line. Returns the registrations it offered; the caller schedules their expiry after the transaction commits.
  class OfferFreedSeats
    def self.call(event, now: Time.current)
      return [] unless event.status == "published"
      return [] if Rules.closed?(event, now)

      free = event.capacity - event.reserved_spots
      return [] if free <= 0

      offered = event.registrations.waitlisted_in_order.includes(:user).lock.limit(free).to_a
      return [] if offered.empty?

      expires_at = Rules.offer_expires_at(event, now)
      offered.each do |registration|
        registration.offered_at = now
        registration.offer_expires_at = expires_at
        registration.offer!
      end
      # One seat count and one revision for the whole batch.
      event.update!(reserved_spots: event.reserved_spots + offered.size, revision: event.revision + 1)
      offered.each { |registration| record_offer(event, registration) }
      offered
    end

    def self.record_offer(event, registration)
      OutboxEvent.create!(
        event_type: "WaitlistOffered",
        aggregate_type: "Registration",
        aggregate_id: registration.id,
        idempotency_key: "waitlist_offered:#{registration.id}:#{registration.lifecycle_version}",
        payload: {
          "registration_id" => registration.id,
          "user_id" => registration.user_id,
          "event_id" => event.id,
          "user_location" => registration.user.location,
          "event" => event.snapshot
        }
      )
    end
    private_class_method :record_offer
  end
end
