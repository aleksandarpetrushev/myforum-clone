require "rails_helper"

RSpec.describe Registrations::Cancel do
  let(:organization) { Organization.create!(name: "Northwind", slug: "northwind-cancel") }
  let(:user) { User.create!(email: "cancel@example.com", name: "Alex", password: "password", location: "Berlin") }
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

  it "raises when the user is not registered" do
    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(described_class::UserNotRegistered)

    expect(event.reload.reserved_spots).to eq(0)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled")).to be_empty
  end

  it "cancels a confirmed registration and frees one spot" do
    registration = Events::Register.new(user: user, event: event).call

    cancelled = described_class.new(user: user, event: event).call

    expect(cancelled.id).to eq(registration.id)
    expect(cancelled.status).to eq("cancelled")
    expect(event.reload.reserved_spots).to eq(0)
    outbox = OutboxEvent.find_by!(event_type: "RegistrationCancelled", aggregate_id: registration.id)
    expect(outbox.idempotency_key).to eq("registration_cancelled:#{registration.id}:2")
    expect(outbox.payload.dig("event", "reserved_spots")).to eq(0)
  end

  it "does not free a second spot when cancel is repeated" do
    Events::Register.new(user: user, event: event).call
    described_class.new(user: user, event: event).call
    described_class.new(user: user, event: event).call

    expect(event.reload.reserved_spots).to eq(0)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled").count).to eq(1)
  end

  it "does not cancel a failed registration" do
    registration = Registration.create!(user: user, event: event, status: "failed", lifecycle_version: 1)
    event.update!(reserved_spots: 1)

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(described_class::InvalidState)

    expect(registration.reload.status).to eq("failed")
    expect(event.reload.reserved_spots).to eq(1)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled")).to be_empty
  end
end
