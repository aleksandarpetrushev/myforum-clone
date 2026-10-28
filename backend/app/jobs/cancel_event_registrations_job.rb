# Cancels every confirmed registration of a cancelled event and sends each registrant one event_cancelled
# notification. Safe to run any number of times: each registration is handled in its own transaction and
# skipped once it is no longer confirmed, so a rerun or a second copy changes nothing and sends nothing twice.
#
# The event row is never locked per registration. The seat count is set once at the end from the registrations
# that are still confirmed, which is exact because a cancelled event takes no new registrations.
class CancelEventRegistrationsJob < ApplicationJob
  queue_as :notifications

  class IncompleteCascade < StandardError; end

  def perform(event_id)
    event = Event.find(event_id)
    # Only a cancelled event's registrations may be cancelled; a stray enqueue for a live event does nothing.
    return unless event.cancelled?

    failures = []
    Registration.where(event_id: event.id, status: "confirmed").find_each do |registration|
      cancel_one(event, registration.id)
    rescue StandardError => error
      # One bad row must not hold back the rest; it is retried with the whole job below.
      failures << registration.id
      Metrics.increment("event_cancel_registration_failed_total")
      Rails.logger.error({
        event: "event.cancel.registration_failed",
        event_id: event.id,
        registration_id: registration.id,
        error: error.class.name,
        message: error.message
      }.to_json)
    end

    recount_seats(event)
    raise IncompleteCascade, "event #{event.id}: registrations #{failures.join(", ")} not cancelled" if failures.any?
  end

  private

  # Lock order: registration, then user. The event row is not locked, so no request waits on this job.
  def cancel_one(event, registration_id)
    ApplicationRecord.transaction do
      registration = Registration.lock.find(registration_id)
      next unless registration.confirmed?

      # No start-time check: the organizer cancelled before the start, and the cascade must finish regardless.
      # The notification commits together with the cancellation; a duplicate key rolls both back and surfaces
      # as a failure in perform rather than being swallowed.
      Registrations::Cancellation.apply!(registration, by: "organizer")
      notify(registration, event)
    end
  end

  def notify(registration, event)
    User.lock.find(registration.user_id)
    return unless NotificationPreference.allows?(registration.user_id, "event_cancelled")

    Notification.create!(
      user_id: registration.user_id,
      kind: "event_cancelled",
      title: "Event cancelled",
      body: "The organizer cancelled #{event.title}. Your registration has been cancelled.",
      idempotency_key: "notification:event_cancelled:#{registration.id}",
      metadata: { "registration_id" => registration.id, "event_id" => event.id }
    )
  end

  # One statement, no model callbacks, then one cache invalidation, instead of one per registration.
  def recount_seats(event)
    confirmed = Registration.where(event_id: event.id, status: "confirmed").select("COUNT(*)")
    Event.where(id: event.id).update_all(["reserved_spots = (#{confirmed.to_sql}), updated_at = ?", Time.current])
    Events::Cache.invalidate(event.id)
  end
end
