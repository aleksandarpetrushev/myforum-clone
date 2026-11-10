require "rails_helper"

RSpec.describe "two seats freed at the same moment" do
  self.use_transactional_tests = false

  after do
    OutboxEvent.delete_all
    Registration.delete_all
    Event.delete_all
    User.delete_all
    Organization.delete_all
  end

  it "offers them to two different people and never oversells" do
    event = Event.create!(
      organization: Organization.create!(name: "Harbor", slug: "harbor-wait"), title: "Full", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Lisbon",
      kind: "in_person", capacity: 2, status: "published"
    )
    people = Array.new(5) { |i| User.create!(email: "p#{i}@example.com", name: "P#{i}", password: "password") }
    people.first(2).each { |user| Events::Register.new(user: user, event: event).call }
    waiting = people.last(3).each_with_index.map do |user, index|
      Registration.create!(user: user, event: event, status: "waitlisted", waitlisted_at: (10 - index).minutes.ago,
                           lifecycle_version: 1)
    end

    # Several guards overlap here: the event row lock in Registrations::Cancel, the row-level lock Postgres
    # takes on the events UPDATE, and FOR UPDATE on the waitlist rows. Removing any one of them still passes
    # (checked on 2026-11-10), so this spec checks the outcome, not a single guard. The seat-count race the event
    # lock prevents is covered by cancel_concurrency_spec.
    gate = Queue.new
    threads = people.first(2).map do |user|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          Registrations::Cancel.new(user: User.find(user.id), event: Event.find(event.id)).call
        end
      end
    end
    2.times { gate << :go }
    threads.each(&:join)

    expect(waiting.map { |r| r.reload.status }).to eq(%w[offered offered waitlisted])
    expect(event.reload.reserved_spots).to eq(2)
    expect(OutboxEvent.where(event_type: "WaitlistOffered").pluck(:aggregate_id)).to match_array(waiting.first(2).map(&:id))
  end
end
