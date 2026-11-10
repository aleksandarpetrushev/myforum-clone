require "rails_helper"

RSpec.describe "cancelling an event with a waitlist" do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Popular session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 2, status: "published"
    )
  end

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")

  it "cancels registrants, the person offered a seat and everyone waiting, and tells each once" do
    keeper = person("keeper")
    leaver = person("leaver")
    offered = person("offered")
    waiting = person("waiting")
    [keeper, leaver].each { |user| Events::Register.new(user: user, event: event).call }
    [offered, waiting].each { |user| Waitlist::Join.new(user: user, event: event).call }
    Registrations::Cancel.new(user: leaver, event: event).call
    expect(Registration.find_by(user: offered).status).to eq("offered")

    Events::Cancel.new(event: event).call
    expect(Events::StuckCancellations.scope).to include(event)
    2.times { CancelEventRegistrationsJob.perform_now(event.id) }

    statuses = Registration.where(user: [keeper, offered, waiting]).pluck(:status, :cancelled_by).uniq
    expect(statuses).to eq([%w[cancelled organizer]])
    expect(event.reload.reserved_spots).to eq(0)
    expect(Events::StuckCancellations.scope).not_to include(event)

    bodies = Notification.where(kind: "event_cancelled").order(:user_id).pluck(:user_id, :body).to_h
    expect(bodies.keys).to contain_exactly(keeper.id, offered.id, waiting.id)
    expect(bodies[keeper.id]).to include("Your registration has been cancelled")
    expect(bodies[waiting.id]).to include("taken off its waitlist")
  end
end
