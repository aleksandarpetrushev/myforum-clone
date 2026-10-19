require "rails_helper"

RSpec.describe "Outbox::Publisher" do
  let(:organization) { Organization.create!(name: "Lumen", slug: "lumen") }
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password", location: "Berlin") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Health forum",
      description: "Public session",
      starts_at: 4.days.from_now,
      ends_at: 4.days.from_now + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 5,
      status: "published"
    )
  end

  it "creates the notification and analytics row once when the outbox is published twice" do
    registration = Events::Register.new(user: user, event: event).call

    perform_enqueued_jobs { Outbox::Publisher.new.call }
    perform_enqueued_jobs { Outbox::Publisher.new.call }

    expect(registration.reload.status).to eq("confirmed")
    expect(OutboxEvent.find_by!(aggregate_id: registration.id).status).to eq("published")
    expect(Notification.where(user: user, kind: "registration_confirmed").count).to eq(1)
    expect(AnalyticsEvent.count).to eq(1)
  end

  it "creates a cancellation notification from the outbox event type" do
    Events::Register.new(user: user, event: event).call
    Registrations::Cancel.new(user: user, event: event).call

    perform_enqueued_jobs { Outbox::Publisher.new.call }

    notification = Notification.find_by!(user: user, kind: "registration_cancelled")
    expect(notification.title).to eq("Registration cancelled")
    expect(notification.body).to eq("Your registration for Health forum was cancelled.")
  end
end
