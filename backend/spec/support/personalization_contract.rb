require "json_schemer"

# MF-203: every outbox row a spec writes must match the Rails-Go contract, so a Rails change that sends Go
# something off-schema fails the spec that made it, with no contract code in that spec.
module PersonalizationContract
  def self.schemer
    @schemer ||= JSONSchemer.schema(Personalization::Contract::SCHEMA_PATH)
  end

  # The envelope as Go receives it: through JSON, so times and symbols arrive as they would over HTTP.
  def self.errors_for(outbox_event)
    body = JSON.parse(Personalization::Contract.envelope(outbox_event).to_json)
    schemer.validate(body).map { |error| error["error"] }
  end
end

RSpec.configure do |config|
  config.before do
    @outbox_id_before_example = OutboxEvent.maximum(:id).to_i
  end

  config.after do |example|
    next if example.exception

    problems = OutboxEvent.where("id > ?", @outbox_id_before_example).order(:id).filter_map do |row|
      errors = PersonalizationContract.errors_for(row)
      "#{row.event_type} #{row.idempotency_key}: #{errors.join('; ')}" if errors.any?
    end
    next if problems.empty?

    raise RSpec::Expectations::ExpectationNotMetError,
          "Outbox payloads do not match personalization/contract/v1/events.schema.json:\n  #{problems.join("\n  ")}"
  end
end
