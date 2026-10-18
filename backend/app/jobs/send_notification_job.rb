class SendNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(outbox_event_id)
    outbox_event = OutboxEvent.find(outbox_event_id)
    return unless outbox_event.event_type == "RegistrationCreated"

    payload = outbox_event.payload
    event_title = payload.dig("event", "title") || "an event"

    Notification.create!(
      user_id: payload.fetch("user_id"),
      kind: "registration_confirmed",
      title: "Registration confirmed",
      body: "You are registered for #{event_title}.",
      idempotency_key: "notification:#{outbox_event.idempotency_key}",
      metadata: { "registration_id" => payload["registration_id"], "event_id" => payload["event_id"] }
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
