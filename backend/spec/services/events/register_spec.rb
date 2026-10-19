require "rails_helper"

RSpec.describe Events::Register do
  let(:organization) { Organization.create!(name: "Northwind", slug: "northwind") }
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password", location: "Berlin") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Cities forum",
      description: "A public working session",
      starts_at: 2.days.from_now,
      ends_at: 2.days.from_now + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 2,
      status: "published"
    )
  end

  it "creates one confirmed registration and a matching outbox event" do
    registration = described_class.new(user: user, event: event).call

    expect(registration.status).to eq("confirmed")
    expect(event.reload.reserved_spots).to eq(1)
    outbox = OutboxEvent.find_by!(event_type: "RegistrationCreated", aggregate_id: registration.id)
    expect(outbox.idempotency_key).to eq("registration_created:#{registration.id}:1")
    expect(outbox.payload["user_id"]).to eq(user.id)
    expect(outbox.payload["event_id"]).to eq(event.id)
  end

  it "confirms a cancelled registration again with a new outbox key" do
    registration = described_class.new(user: user, event: event).call
    Registrations::Cancel.new(user: user, event: event).call

    again = described_class.new(user: user, event: event).call

    expect(again.id).to eq(registration.id)
    expect(again.status).to eq("confirmed")
    expect(again.lifecycle_version).to eq(3)
    expect(event.reload.reserved_spots).to eq(1)
    keys = OutboxEvent.where(event_type: "RegistrationCreated", aggregate_id: registration.id).order(:id).pluck(:idempotency_key)
    expect(keys).to eq([
      "registration_created:#{registration.id}:1",
      "registration_created:#{registration.id}:3"
    ])
  end

  it "rejects a second registration for the same user" do
    described_class.new(user: user, event: event).call

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(described_class::AlreadyRegistered)

    expect(Registration.count).to eq(1)
    expect(OutboxEvent.where(event_type: "RegistrationCreated").count).to eq(1)
  end

  it "rejects registration when the event is full" do
    event.update!(capacity: 1, reserved_spots: 1)

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(described_class::EventFull)

    expect(Registration.count).to eq(0)
  end

  it "rolls back the registration when the outbox write fails" do
    allow(OutboxEvent).to receive(:record!).and_raise(RuntimeError, "outbox down")

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(RuntimeError, "outbox down")

    expect(Registration.count).to eq(0)
    expect(event.reload.reserved_spots).to eq(0)
  end
end
