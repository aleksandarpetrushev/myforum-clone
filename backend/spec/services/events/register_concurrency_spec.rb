require "rails_helper"

RSpec.describe "registration capacity under concurrency" do
  self.use_transactional_tests = false

  after do
    Registration.delete_all
    OutboxEvent.delete_all
    Event.delete_all
    Organization.delete_all
    User.delete_all
  end

  it "lets only one registration through when two users race for the last spot" do
    organization = Organization.create!(name: "Harbor", slug: "harbor-race")
    event = Event.create!(
      organization: organization,
      title: "Last seat",
      description: "Capacity one",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Lisbon",
      kind: "in_person",
      capacity: 1,
      status: "published"
    )
    users = 2.times.map do |index|
      User.create!(email: "racer#{index}@example.com", name: "Racer #{index}", password: "password")
    end

    results = users.map do |user|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Events::Register.new(user: User.find(user.id), event: Event.find(event.id)).call
          :created
        end
      rescue Events::Register::EventFull, Events::Register::AlreadyRegistered
        :rejected
      end
    end.map(&:value)

    expect(results).to contain_exactly(:created, :rejected)
    expect(Registration.where(event_id: event.id).count).to eq(1)
    expect(event.reload.reserved_spots).to eq(1)
  end
end
