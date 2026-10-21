class SendNotificationJob < ApplicationJob
  queue_as :notifications

  COPY = {
    "RegistrationCreated" => ["registration_confirmed", "Registration confirmed", "You are registered for %s."],
    "RegistrationCancelled" => ["registration_cancelled", "Registration cancelled", "Your registration for %s was cancelled."]
  }.freeze

  def perform(outbox_event_id)
    outbox_event = OutboxEvent.find(outbox_event_id)
    kind, title, body = COPY[outbox_event.event_type]
    return unless title

    payload = outbox_event.payload
    user_id = payload.fetch("user_id")
    event_title = payload.dig("event", "title") || "an event"

    User.transaction do
      User.lock.find(user_id)
      unless NotificationPreference.allows?(user_id, kind)
        Rails.logger.info({
          event: "notification.suppressed",
          user_id: user_id,
          kind: kind,
          outbox_event_id: outbox_event.id
        }.to_json)
        next
      end

      Notification.create!(
        user_id: user_id,
        kind: kind,
        title: title,
        body: format(body, event_title),
        idempotency_key: "notification:#{outbox_event.idempotency_key}",
        metadata: { "registration_id" => payload["registration_id"], "event_id" => payload["event_id"] }
      )
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record.errors.of_kind?(:idempotency_key, :taken)
    nil
  end
end
