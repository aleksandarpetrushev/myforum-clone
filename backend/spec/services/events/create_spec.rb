require "rails_helper"

RSpec.describe Events::Create do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:starts_at) { 3.days.from_now.change(usec: 0) }
  let(:attributes) do
    {
      "title" => "Financing the energy transition",
      "description" => "A working session",
      "starts_at" => starts_at,
      "ends_at" => starts_at + 90.minutes,
      "location" => "Geneva",
      "kind" => "in_person",
      "capacity" => 80,
      "status" => "published"
    }
  end

  def create(overrides = {})
    described_class.new(organization: organization, attributes: attributes.merge(overrides)).call
  end

  it "writes the detail cache entry after the event is committed" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    event = create

    expect(Rails.cache.read(Events::Cache.detail_key(event.id))).to eq(event.as_detail_json)
  ensure
    Rails.cache = previous
  end

  it "records one EventPublished outbox row for a published event" do
    topic = Topic.create!(name: "Climate", slug: "climate")
    event = create("topic_ids" => [topic.id])

    rows = OutboxEvent.where(event_type: "EventPublished", aggregate_id: event.id)
    expect(rows.count).to eq(1)
    expect(rows.first.idempotency_key).to eq("event_published:#{event.id}")
    expect(rows.first.payload["event"]).to include("id" => event.id, "status" => "published", "topic_ids" => [topic.id])
  end

  it "records no EventPublished row for a draft" do
    event = create("status" => "draft")

    expect(OutboxEvent.where(event_type: "EventPublished", aggregate_id: event.id)).to be_empty
  end

  it "keeps one EventPublished row when publication is recorded again" do
    event = create

    Events::Publication.record!(event)

    expect(OutboxEvent.where(event_type: "EventPublished", aggregate_id: event.id).count).to eq(1)
  end

  it "writes the outbox row in the same transaction as the event" do
    allow(OutboxEvent).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, "outbox unavailable")

    expect { create }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Event.where(title: "Financing the energy transition")).to be_empty
  end
end
