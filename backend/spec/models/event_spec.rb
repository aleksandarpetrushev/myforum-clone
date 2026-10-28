require "rails_helper"

RSpec.describe Event do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }

  def event_with(status)
    described_class.create!(
      organization: organization,
      title: "Session",
      description: "Talk",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: status
    )
  end

  describe "status state machine" do
    it "publishes a draft" do
      event = event_with("draft")

      expect(event.publish).to be(true)
      expect(event.reload.status).to eq("published")
    end

    it "cancels a published event and records when" do
      event = event_with("published")

      freeze_time do
        event.cancel!
        expect(event.reload.status).to eq("cancelled")
        expect(event.cancelled_at).to eq(Time.current)
      end
    end

    it "refuses to cancel a draft" do
      event = event_with("draft")

      expect { event.cancel! }.to raise_error(StateMachines::InvalidTransition)
      expect(event.reload.status).to eq("draft")
    end

    it "never lets a cancelled event change status again" do
      event = event_with("published")
      event.cancel!

      expect(event.can_publish?).to be(false)
      %w[published draft].each do |status|
        expect(event.reload.update(status: status)).to be(false)
        expect(event.errors.details[:status]).to include(error: :invalid_transition)
      end
    end

    it "refuses plain writes that are not machine transitions" do
      published = event_with("published")
      expect(published.update(status: "draft")).to be(false)

      draft = event_with("draft")
      expect(draft.update(status: "cancelled")).to be(false)

      expect(event_with("published").update(status: "cancelled")).to be(false)

      expect(event_with("draft").update(status: "published")).to be(true)
    end

    it "lets a new event start as a draft or published" do
      expect(event_with("draft").status).to eq("draft")
      expect(event_with("published").status).to eq("published")
    end
  end
end
