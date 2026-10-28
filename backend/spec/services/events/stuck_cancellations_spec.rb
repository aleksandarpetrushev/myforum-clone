require "rails_helper"

RSpec.describe Events::StuckCancellations do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:user) { User.create!(email: "registrant@example.com", name: "Registrant", password: "password") }

  def registered_event(title)
    event = Event.create!(
      organization: organization,
      title: title,
      description: "Talk",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
    Events::Register.new(user: user, event: event).call
    event
  end

  it "lists a cancelled event that still has confirmed registrations" do
    stuck = registered_event("Stuck")
    Events::Cancel.new(event: stuck).call

    expect(described_class.scope).to contain_exactly(stuck)
    expect(Metrics.cancelled_events_with_confirmed_registrations).to eq(1)
  end

  it "does not list a cancelled event whose cascade finished, or a published event" do
    finished = registered_event("Finished")
    Events::Cancel.new(event: finished).call
    CancelEventRegistrationsJob.perform_now(finished.id)
    registered_event("Still running")

    expect(described_class.scope).to be_empty
    expect(Metrics.cancelled_events_with_confirmed_registrations).to eq(0)
  end
end
