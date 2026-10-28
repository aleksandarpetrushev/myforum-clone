require "rails_helper"
require "rake"

RSpec.describe "events:resume_cancellations" do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:user) { User.create!(email: "registrant@example.com", name: "Registrant", password: "password") }

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "events:resume_cancellations" }
  end

  def run_task
    task = Rake::Task["events:resume_cancellations"]
    task.reenable
    expect { task.invoke }.to output.to_stdout
  end

  def cancelled_event_with_registration
    event = Event.create!(
      organization: organization,
      title: "Stuck",
      description: "Talk",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
    Events::Register.new(user: user, event: event).call
    Events::Cancel.new(event: event).call
    event
  end

  it "re-enqueues the cascade once for each stuck event, and the job clears it" do
    stuck = cancelled_event_with_registration

    run_task

    expect(CancelEventRegistrationsJob).to have_been_enqueued.with(stuck.id).exactly(:once)
    perform_enqueued_jobs
    expect(Metrics.cancelled_events_with_confirmed_registrations).to eq(0)
  end

  it "enqueues nothing when no cascade is stuck" do
    run_task

    expect(CancelEventRegistrationsJob).not_to have_been_enqueued
  end
end
