require "net/http"

module Personalization
  class DeliveryError < StandardError; end

  class DeliverEvent
    def self.call(outbox_event)
      return if Rails.application.config.x.personalization_delivery == "none"

      uri = URI.join("#{base_url}/", "internal/events")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = {
        idempotency_key: outbox_event.idempotency_key,
        event_type: outbox_event.event_type,
        payload: outbox_event.payload
      }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 2) do |http|
        http.request(request)
      end

      return if response.is_a?(Net::HTTPSuccess)

      raise DeliveryError, "personalization returned #{response.code}"
    end

    def self.base_url
      Rails.application.config.x.personalization_url
    end
  end
end
