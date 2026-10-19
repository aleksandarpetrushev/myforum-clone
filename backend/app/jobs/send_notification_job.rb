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
    event_title = payload.dig("event", "title") || "an event"

    Notification.create!(
      user_id: payload.fetch("user_id"),
      kind: kind,
      title: title,
      body: format(body, event_title),
      idempotency_key: "notification:#{outbox_event.idempotency_key}",
      metadata: { "registration_id" => payload["registration_id"], "event_id" => payload["event_id"] }
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
