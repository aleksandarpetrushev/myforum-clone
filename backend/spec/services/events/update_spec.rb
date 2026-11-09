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

  describe "saving the same event more than once (MF-106)" do
    let(:partner) { Organization.create!(name: "Partner", slug: "partner") }

    def updated_rows
      OutboxEvent.where(event_type: "EventUpdated", aggregate_id: event.id).order(:id)
    end

    def save(attributes)
      described_class.new(event: Event.find(event.id), attributes: attributes).call
    end

    it "accepts the same changes twice in one second and records them once" do
      save("title" => "Announced")
      save("title" => "Announced")

      expect(event.reload.revision).to eq(1)
      expect(updated_rows.pluck(:idempotency_key)).to eq(["event_updated:#{event.id}:1"])
    end

    it "accepts the same changes twice minutes apart and records them once" do
      save("title" => "Announced")
      travel 5.minutes
      save("title" => "Announced")

      expect(updated_rows.count).to eq(1)
    end

    it "keeps two different changes made in the same second" do
      save("title" => "First")
      save("location" => "Davos")

      expect(event.reload).to have_attributes(title: "First", location: "Davos", revision: 2)
      expect(updated_rows.pluck(:idempotency_key)).to eq(["event_updated:#{event.id}:1", "event_updated:#{event.id}:2"])
      expect(updated_rows.last.payload.dig("event", "revision")).to eq(2)
    end

    it "keeps an edit back to an earlier value" do
      save("title" => "A")
      save("title" => "B")
      save("title" => "A")

      expect(event.reload).to have_attributes(title: "A", revision: 3)
      expect(updated_rows.count).to eq(3)
    end

    it "does not touch the cache for a save that changes nothing" do
      save("title" => "Announced")
      allow(Events::Cache).to receive(:invalidate)

      expect { save("title" => "Announced") }.not_to have_enqueued_job(RebuildEventCacheJob)
      expect(Events::Cache).not_to have_received(:invalidate)
    end

    it "counts a change to the allowed organizations alone as a change" do
      save("allowed_organization_ids" => [partner.id])

      expect(event.reload.revision).to eq(1)
      expect(event.allowed_organization_ids).to eq([partner.id])
      expect(updated_rows.count).to eq(1)
    end

    it "treats the same allowed organizations, in any order, as no change" do
      other = Organization.create!(name: "Other", slug: "other")
      save("allowed_organization_ids" => [partner.id, other.id])
      save("allowed_organization_ids" => [other.id, partner.id])

      expect(event.reload.revision).to eq(1)
      expect(updated_rows.count).to eq(1)
    end

    it "changes nothing when validation fails" do
      expect { save("visibility" => "organization_restricted", "title" => "Hidden") }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(event.reload).to have_attributes(title: "Embargoed session", revision: 0)
      expect(updated_rows).to be_empty
    end
  end

  it "records no EventPublished for a draft that stays a draft" do
    described_class.new(event: event, attributes: { "title" => "Still embargoed" }).call

    expect(published_rows).to be_empty
  end
end
