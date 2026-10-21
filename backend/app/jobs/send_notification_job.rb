class SendNotificationJob < ApplicationJob
  queue_as :notifications

  COPY = {
    "RegistrationCreated" => ["registration_confirmed", "Registration confirmed", "You are registered for %s."],
    "RegistrationCancelled" => ["registration_cancelled", "Registration cancelled", "Your registration for %s was cancelled."]
  }.freeze

  def perform(outbox_event_id)
    outbox_event = OutboxEvent.find(outbox_event_id)
    return if outbox_event.notification_outcome.present?

    kind, title, body = COPY[outbox_event.event_type]
    return unless title

    payload = outbox_event.payload
    user_id = payload.fetch("user_id")
    event_title = payload.dig("event", "title") || "an event"

    User.transaction do
      User.lock.find(user_id)
      outbox_event.lock!
      next if outbox_event.notification_outcome.present?

      if NotificationPreference.allows?(user_id, kind)
        Notification.create!(
          user_id: user_id,
          kind: kind,
          title: title,
          body: format(body, event_title),
          idempotency_key: "notification:#{outbox_event.idempotency_key}",
          metadata: { "registration_id" => payload["registration_id"], "event_id" => payload["event_id"] }
        )
        outbox_event.update!(notification_outcome: "delivered")
      else
        Rails.logger.info({
          event: "notification.suppressed",
          user_id: user_id,
          kind: kind,
          outbox_event_id: outbox_event.id
        }.to_json)
        outbox_event.update!(notification_outcome: "suppressed")
      end
    end
  rescue ActiveRecord::RecordNotUnique
    mark_delivered(outbox_event_id)
  rescue ActiveRecord::RecordInvalid => error
    raise unless error.record.is_a?(Notification) && error.record.errors.of_kind?(:idempotency_key, :taken)

    mark_delivered(outbox_event_id)
  end

  private

  # A notification row already exists, so this event was delivered. Record that
  # when an earlier attempt stored the row without an outcome.
  def mark_delivered(outbox_event_id)
    OutboxEvent.where(id: outbox_event_id, notification_outcome: nil).update_all(
      notification_outcome: "delivered",
      updated_at: Time.current
    )
    nil
  end
end
