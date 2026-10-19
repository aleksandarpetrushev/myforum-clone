require "rails_helper"

RSpec.describe Registrations::Cancel do
  include ActiveSupport::Testing::TimeHelpers
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

  it "cancels immediately before the start and refuses at or after the start" do
    registration = Events::Register.new(user: user, event: event).call
    start = Time.zone.parse("2026-06-01 09:00:00")
    event.update!(starts_at: start, ends_at: start + 2.hours)
    persisted_start = event.reload.starts_at

    travel_to(persisted_start - 1.second) do
      expect(described_class.new(user: user, event: event).call.status).to eq("cancelled")
    end

    Events::Register.new(user: user, event: event).call

    travel_to(persisted_start) do
      expect {
        described_class.new(user: user, event: event).call
      }.to raise_error(described_class::EventStarted)
    end

    travel_to(persisted_start + 1.minute) do
      expect {
        described_class.new(user: user, event: event).call
      }.to raise_error(described_class::EventStarted)
    end

    expect(registration.reload.status).to eq("confirmed")
    expect(event.reload.reserved_spots).to eq(1)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled").count).to eq(1)
  end

  it "fails instead of hiding a confirmed registration with no reserved spot" do
    registration = Registration.create!(user: user, event: event, status: "confirmed", lifecycle_version: 1)
    event.update!(reserved_spots: 0)
    before_count = Metrics.snapshot["registration_cancel_invariant_violation_total"]

    expect(Rails.logger).to receive(:error).with(a_string_including("\"reserved_spots\":0"))

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(described_class::InvariantViolation)

    expect(registration.reload.status).to eq("confirmed")
    expect(event.reload.reserved_spots).to eq(0)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled")).to be_empty
    expect(Metrics.snapshot["registration_cancel_invariant_violation_total"]).to eq(before_count + 1)
  end

  it "rolls back the cancellation when the outbox write fails" do
    registration = Events::Register.new(user: user, event: event).call
    allow(OutboxEvent).to receive(:record!).and_raise(RuntimeError, "outbox down")

    expect {
      described_class.new(user: user, event: event).call
    }.to raise_error(RuntimeError, "outbox down")

    expect(registration.reload.status).to eq("confirmed")
    expect(registration.lifecycle_version).to eq(1)
    expect(event.reload.reserved_spots).to eq(1)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled")).to be_empty
  end

  it "writes a distinct outbox event for every successful register and cancel" do
    registration = Events::Register.new(user: user, event: event).call
    described_class.new(user: user, event: event).call
    Events::Register.new(user: user, event: event).call
    described_class.new(user: user, event: event).call

    expect(registration.reload.status).to eq("cancelled")
    expect(registration.lifecycle_version).to eq(4)
    expect(event.reload.reserved_spots).to eq(0)
    expect(OutboxEvent.where(aggregate_id: registration.id).order(:id).pluck(:event_type, :idempotency_key)).to eq([
      ["RegistrationCreated", "registration_created:#{registration.id}:1"],
      ["RegistrationCancelled", "registration_cancelled:#{registration.id}:2"],
      ["RegistrationCreated", "registration_created:#{registration.id}:3"],
      ["RegistrationCancelled", "registration_cancelled:#{registration.id}:4"]
    ])
  end
end
