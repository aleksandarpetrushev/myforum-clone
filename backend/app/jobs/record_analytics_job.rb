class RecordAnalyticsJob < ApplicationJob
  queue_as :analytics

  def perform(outbox_event_id)
    outbox_event = OutboxEvent.find(outbox_event_id)
    AnalyticsEvent.create!(
      outbox_event: outbox_event,
      name: outbox_event.event_type,
      user_id: outbox_event.payload["user_id"],
      properties: outbox_event.payload
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
