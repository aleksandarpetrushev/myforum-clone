module Personalization
  # The body Rails sends to the Go service's POST /internal/events. The schema lives with the consumer, in
  # personalization/contract/, and its README says when to change VERSION and in what order to deploy.
  module Contract
    VERSION = 1
    SCHEMA_PATH = Rails.root.join("../personalization/contract/v1/events.schema.json")

    # schema_version comes from the row, not from VERSION: a row written before a version change is still
    # sent with the version its payload was written in.
    def self.envelope(outbox_event)
      {
        "schema_version" => outbox_event.schema_version,
        "idempotency_key" => outbox_event.idempotency_key,
        "event_type" => outbox_event.event_type,
        "payload" => outbox_event.payload
      }
    end
  end
end
