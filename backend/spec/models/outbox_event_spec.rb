require "rails_helper"

RSpec.describe OutboxEvent do
  let(:attrs) do
    { event_type: "EventUpdated", aggregate_type: "Event", aggregate_id: 1, idempotency_key: "event_updated:1:100", payload: {} }
  end

  it "refuses a repeated key in record! so a second change is never silently dropped" do
    described_class.record!(attrs)

    expect { described_class.record!(attrs.merge(payload: { "status" => "cancelled" })) }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "returns the existing row for a repeated key in record_once!" do
    first = described_class.record_once!(attrs)

    expect(described_class.record_once!(attrs.merge(payload: { "other" => true }))).to eq(first)
    expect(described_class.where(idempotency_key: "event_updated:1:100").count).to eq(1)
  end
end
