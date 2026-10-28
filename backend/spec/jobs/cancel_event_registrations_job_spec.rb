require "rails_helper"

RSpec.describe CancelEventRegistrationsJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Climate finance session",
      description: "A working session",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
  end
  let(:users) do
    (1..3).map { |n| User.create!(email: "registrant#{n}@example.com", name: "Registrant #{n}", password: "password") }
  end

  before do
    users.each { |user| Events::Register.new(user: user, event: event).call }
    Events::Cancel.new(event: event).call
  end

  def notifications
    Notification.where(kind: "event_cancelled")
  end

  it "cancels every confirmed registration as the organizer and lowers the seat count" do
    described_class.perform_now(event.id)

    expect(event.registrations.reload.map(&:status)).to all(eq("cancelled"))
    expect(event.registrations.map(&:cancelled_by)).to all(eq("organizer"))
    expect(event.reload.reserved_spots).to eq(0)
  end

  it "sends each registrant exactly one event_cancelled notification, even when run twice" do
    described_class.perform_now(event.id)
    described_class.perform_now(event.id)

    expect(notifications.count).to eq(3)
    expect(notifications.pluck(:user_id)).to match_array(users.map(&:id))
    expect(Notification.where(kind: "registration_cancelled")).to be_empty
    expect(event.reload.reserved_spots).to eq(0)
  end

  it "leaves a registrant who cancelled earlier alone" do
    early = users.first
    Registration.find_by!(user: early, event: event).update_columns(status: "cancelled", cancelled_by: "participant")
    event.update_column(:reserved_spots, 2)

    described_class.perform_now(event.id)

    expect(Registration.find_by!(user: early, event: event).cancelled_by).to eq("participant")
    expect(notifications.where(user_id: early.id)).to be_empty
    expect(event.reload.reserved_spots).to eq(0)
  end

  it "cancels without notifying a registrant who switched event cancellations off" do
    muted = users.first
    NotificationPreference.create!(user: muted, event_cancelled_enabled: false)

    described_class.perform_now(event.id)

    expect(Registration.find_by!(user: muted, event: event).status).to eq("cancelled")
    expect(notifications.where(user_id: muted.id)).to be_empty
    expect(notifications.count).to eq(2)
  end

  it "still finishes after the event's start time has passed" do
    travel_to(event.starts_at + 1.hour) do
      described_class.perform_now(event.id)
    end

    expect(event.registrations.reload.map(&:status)).to all(eq("cancelled"))
  end

  it "keeps going past a failing registration, then raises so Sidekiq retries it" do
    stuck = Registration.find_by!(user: users.first, event: event)
    original = Registrations::Cancellation.method(:apply!)
    allow(Registrations::Cancellation).to receive(:apply!) do |registration, *args, **kwargs|
      raise ActiveRecord::StatementInvalid, "row failed" if registration.id == stuck.id

      original.call(registration, *args, **kwargs)
    end

    expect { described_class.perform_now(event.id) }.to raise_error(described_class::IncompleteCascade)
    expect(stuck.reload.status).to eq("confirmed")
    expect(Registration.where(event: event, status: "cancelled").count).to eq(2)
    expect(notifications.count).to eq(2)
    expect(event.reload.reserved_spots).to eq(1)

    allow(Registrations::Cancellation).to receive(:apply!).and_call_original
    described_class.perform_now(event.id)
    expect(stuck.reload.status).to eq("cancelled")
    expect(notifications.count).to eq(3)
  end

  it "sets the seat count once from the registrations still confirmed, even when it had drifted" do
    event.update_column(:reserved_spots, 1)

    described_class.perform_now(event.id)

    expect(event.registrations.reload.map(&:status)).to all(eq("cancelled"))
    expect(event.reload.reserved_spots).to eq(0)
  end

  it "invalidates the list cache once, not once per registration" do
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    before = Events::Cache.list_epoch

    described_class.perform_now(event.id)

    expect(Events::Cache.list_epoch - before).to eq(1)
  ensure
    Rails.cache = previous
  end

  it "does nothing for an event that is not cancelled" do
    live = Event.create!(
      organization: organization, title: "Live", description: "Still on", starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour, location: "Geneva", kind: "in_person", capacity: 10, status: "published"
    )
    Events::Register.new(user: users.first, event: live).call

    described_class.perform_now(live.id)

    expect(live.registrations.reload.map(&:status)).to all(eq("confirmed"))
    expect(live.reload.reserved_spots).to eq(1)
  end
end
