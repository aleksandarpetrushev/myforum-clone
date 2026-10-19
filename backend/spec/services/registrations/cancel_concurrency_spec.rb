require "rails_helper"

RSpec.describe "registration cancel under concurrency" do
  self.use_transactional_tests = false

  after do
    Registration.delete_all
    OutboxEvent.delete_all
    Event.delete_all
    Organization.delete_all
    User.delete_all
  end

  it "frees only one spot when two cancels race" do
    organization = Organization.create!(name: "Harbor", slug: "harbor-cancel")
    event = Event.create!(
      organization: organization,
      title: "Last seat",
      description: "Capacity one",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Lisbon",
      kind: "in_person",
      capacity: 2,
      reserved_spots: 1,
      status: "published"
    )
    user = User.create!(email: "racer-cancel@example.com", name: "Racer", password: "password")
    Registration.create!(user: user, event: event, status: "confirmed", lifecycle_version: 1)

    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Registrations::Cancel.new(user: User.find(user.id), event: Event.find(event.id)).call
          :cancelled
        end
      rescue StandardError
        :failed
      end
    end.map(&:value)

    expect(results).to contain_exactly(:cancelled, :cancelled)
    expect(event.reload.reserved_spots).to eq(0)
    expect(Registration.find_by!(user: user, event: event).status).to eq("cancelled")
    expect(OutboxEvent.where(event_type: "RegistrationCancelled").count).to eq(1)
  end
end
