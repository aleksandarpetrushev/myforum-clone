require "rails_helper"

# MF-202: the paths that free a seat offer it to the line in the same transaction.
RSpec.describe "freeing seats for the waitlist" do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 2, status: "published"
    )
  end

  def person(name)
    User.create!(email: "#{name}@example.com", name: name, password: "password", location: "Davos")
  end

  def register(user) = Events::Register.new(user: user, event: event).call

  def wait(user, minutes_ago)
    Registration.create!(user: user, event: event, status: "waitlisted", waitlisted_at: minutes_ago.minutes.ago,
                         lifecycle_version: 1)
  end

  def cancel(user) = Registrations::Cancel.new(user: user, event: event)

  let(:ana) { person("ana") }
  let(:ben) { person("ben") }
  let!(:first_in_line) { wait(person("cyd"), 10) }
  let!(:second_in_line) { wait(person("dee"), 5) }

  before do
    register(ana)
    register(ben)
  end

  it "offers a cancelled seat to the first in line and tells the canceller as before" do
    service = cancel(ana)
    service.call

    expect(service.offers).to eq([first_in_line])
    expect(first_in_line.reload.status).to eq("offered")
    expect(second_in_line.reload.status).to eq("waitlisted")
    expect(event.reload.reserved_spots).to eq(2)
    expect(OutboxEvent.where(event_type: "RegistrationCancelled").count).to eq(1)
  end

  it "passes a declined offer to the next in line without telling the decliner" do
    cancel(ana).call
    expect { cancel(first_in_line.user).call }.not_to change { OutboxEvent.where(event_type: "RegistrationCancelled").count }

    expect(first_in_line.reload).to have_attributes(status: "cancelled", cancelled_by: "participant")
    expect(second_in_line.reload.status).to eq("offered")
    expect(event.reload.reserved_spots).to eq(2)
  end

  it "lets someone leave the line without touching seats or writing anything" do
    expect { cancel(second_in_line.user).call }.not_to change(OutboxEvent, :count)

    expect(second_in_line.reload.status).to eq("cancelled")
    expect(event.reload.reserved_spots).to eq(2)
  end

  it "offers new seats when the organizer raises the capacity" do
    service = Events::Update.new(event: event, attributes: { "capacity" => 5 })
    service.call

    expect(service.offers).to eq([first_in_line, second_in_line])
    expect(event.reload.reserved_spots).to eq(4)
  end

  it "offers nothing when the capacity goes down or another field changes" do
    Events::Update.new(event: event, attributes: { "title" => "Renamed" }).call
    expect(first_in_line.reload.status).to eq("waitlisted")
  end
end
