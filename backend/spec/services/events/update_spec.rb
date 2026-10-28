require "rails_helper"

RSpec.describe Events::Update do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Embargoed session",
      description: "Speakers not announced",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "draft"
    )
  end

  def published_rows
    OutboxEvent.where(event_type: "EventPublished", aggregate_id: event.id)
  end

  it "records EventPublished when a draft is published" do
    described_class.new(event: event, attributes: { "status" => "published" }).call

    expect(published_rows.count).to eq(1)
    expect(OutboxEvent.where(event_type: "EventUpdated", aggregate_id: event.id).count).to eq(1)
  end

  it "records EventPublished once across later updates" do
    described_class.new(event: event, attributes: { "status" => "published" }).call
    # EventUpdated keys are per second; a second update in the same second is refused, not dropped.
    travel 1.second
    described_class.new(event: event, attributes: { "title" => "Announced session" }).call

    expect(published_rows.count).to eq(1)
  end

  it "rejects an allowed organization that does not exist with a validation error" do
    unknown = Organization.maximum(:id).to_i + 1

    expect {
      described_class.new(
        event: event,
        attributes: { "visibility" => "organization_restricted", "allowed_organization_ids" => [unknown] }
      ).call
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(event.reload.visibility).to eq("public")
  end

  it "rejects making an event restricted with no allowed organizations" do
    expect {
      described_class.new(event: event, attributes: { "visibility" => "organization_restricted" }).call
    }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "records no EventPublished for a draft that stays a draft" do
    described_class.new(event: event, attributes: { "title" => "Still embargoed" }).call

    expect(published_rows).to be_empty
  end
end
