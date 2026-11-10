module Personalization
  # The personalization service answered with an error other than unsupported_contract, or could not be reached.
  # Raised from DeliverEvent; it stops the outbox poller on that row.
  class DeliveryError < StandardError; end
end
