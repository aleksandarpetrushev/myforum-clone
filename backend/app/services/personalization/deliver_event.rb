module Personalization
  class DeliveryError < StandardError; end

  class DeliverEvent
    def self.call(outbox_event)
      return if Rails.application.config.x.personalization_delivery == "none"

      response = Http.post_json(
        "internal/events",
        body: {
          idempotency_key: outbox_event.idempotency_key,
          event_type: outbox_event.event_type,
          payload: outbox_event.payload
        },
        open_timeout: 2,
        read_timeout: 2
      )
      return if response.is_a?(Net::HTTPSuccess)

      raise DeliveryError, "personalization returned #{response.code}"
    end
  end
end
