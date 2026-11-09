module Personalization
  class DeliveryError < StandardError; end

  class DeliverEvent
    # Returns :delivered, :deferred, or :skipped when delivery is switched off; raises DeliveryError otherwise.
    def self.call(outbox_event)
      return :skipped if Rails.application.config.x.personalization_delivery == "none"

      response = Http.post_json(
        "internal/events",
        body: Contract.envelope(outbox_event),
        open_timeout: 2,
        read_timeout: 2
      )
      return :delivered if response.is_a?(Net::HTTPSuccess)
      return :deferred if unsupported_contract?(response)

      raise DeliveryError, "personalization returned #{response.code}"
    end

    # The service cannot read this row's schema_version or event_type yet, for example while Rails is ahead of
    # it during a rollout. The row is kept as deferred, not failed: the poller moves on, and
    # bin/rails outbox:redeliver_deferred sends it again later.
    def self.unsupported_contract?(response)
      return false unless response.code == "422"

      JSON.parse(response.body.to_s).dig("error", "code") == "unsupported_contract"
    rescue JSON::ParserError
      false
    end
    private_class_method :unsupported_contract?
  end
end
