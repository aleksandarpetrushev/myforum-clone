require "rails_helper"

RSpec.describe "event cancellation cascade under concurrency" do
  self.use_transactional_tests = false

  after do
    Notification.delete_all
    Registration.delete_all
    OutboxEvent.delete_all
    Event.delete_all
    Organization.delete_all
    User.delete_all
  end

  it "leaves one notification per registrant when two copies of the job run at once" do
    organization = Organization.create!(name: "Harbor", slug: "harbor-cancel-race")
    event = Event.create!(
      organization: organization,
      title: "Called off",
      description: "Two workers",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Lisbon",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
    users = Array.new(5) do |index|
      User.create!(email: "cancel-racer#{index}@example.com", name: "Racer #{index}", password: "password")
    end
    users.each { |user| Events::Register.new(user: user, event: event).call }
    Events::Cancel.new(event: event).call

    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { CancelEventRegistrationsJob.perform_now(event.id) }
      end
    end
    threads.each(&:join)

    expect(Notification.where(kind: "event_cancelled").count).to eq(5)
    expect(Registration.where(event: event, status: "cancelled", cancelled_by: "organizer").count).to eq(5)
    expect(event.reload.reserved_spots).to eq(0)
  end
end
