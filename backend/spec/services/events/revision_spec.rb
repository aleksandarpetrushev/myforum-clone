require "rails_helper"

# MF-106: every change to an event row takes the next revision, so Go can keep the newest snapshot when
# outbox rows arrive out of order.
RSpec.describe "event revisions" do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:user) { User.create!(email: "attendee@example.com", name: "Attendee", password: "password") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 10, status: "published"
    )
  end

  def snapshot_revisions
    OutboxEvent.where(aggregate_id: [event.id, *event.registrations.ids]).order(:id)
      .filter_map { |row| row.payload.dig("event", "revision") }
  end

  it "bumps the revision on each edit, registration, cancelled registration and event cancellation" do
    Events::Update.new(event: event, attributes: { "title" => "Renamed" }).call
    Events::Register.new(user: user, event: event).call
    Registrations::Cancel.new(user: user, event: event).call
    Events::Register.new(user: user, event: event).call
    Events::Cancel.new(event: event).call

    expect(event.reload.revision).to eq(5)
    expect(snapshot_revisions).to eq([1, 2, 3, 4, 5])
  end

  it "bumps the revision when the cancellation cascade recounts seats" do
    Events::Register.new(user: user, event: event).call
    Events::Cancel.new(event: event).call
    before = event.reload.revision

    CancelEventRegistrationsJob.perform_now(event.id)

    expect(event.reload).to have_attributes(reserved_spots: 0, revision: before + 1)
  end
end
