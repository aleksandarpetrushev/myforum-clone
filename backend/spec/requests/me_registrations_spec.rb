require "rails_helper"

RSpec.describe "My registrations", type: :request do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:user) { User.create!(email: "participant@example.com", name: "Participant", password: "password") }

  def event(title, starts_at:, ends_at: starts_at + 1.hour, visibility: "public")
    created = Event.create!(
      organization: organization,
      title: title,
      description: "Session",
      starts_at: starts_at,
      ends_at: ends_at,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "published",
      visibility: visibility
    )
    created.allowed_organizations << partner if visibility == "organization_restricted"
    created
  end

  def register(event)
    Events::Register.new(user: user, event: event).call
  end

  def fetch
    get "/api/me/registrations", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    json_body
  end

  def event_ids(section)
    fetch.fetch(section).map { |row| row["event_id"] }
  end

  it "lists upcoming registrations soonest first, whatever order they were made in" do
    later = event("Later", starts_at: 5.days.from_now)
    sooner = event("Sooner", starts_at: 2.days.from_now)
    register(later)
    register(sooner)

    expect(event_ids("upcoming")).to eq([sooner.id, later.id])
  end

  it "lists past registrations most recent first" do
    older = event("Older", starts_at: 10.days.ago)
    recent = event("Recent", starts_at: 2.days.ago)
    register(recent)
    register(older)

    expect(event_ids("past")).to eq([recent.id, older.id])
  end

  it "lists cancelled and failed registrations after the past events that took place" do
    attended = event("Attended", starts_at: 2.days.ago)
    older = event("Older", starts_at: 10.days.ago)
    self_cancelled = event("Self-cancelled", starts_at: 6.months.from_now)
    called_off = event("Called off", starts_at: 3.days.from_now)
    failed = event("Failed", starts_at: 1.day.ago)
    [older, attended, self_cancelled, called_off].each { |created| register(created) }
    Registrations::Cancel.new(user: user, event: self_cancelled).call
    Events::Cancel.new(event: called_off).call
    Registration.create!(user: user, event: failed, status: "failed")

    expect(event_ids("past")).to eq([attended.id, older.id, self_cancelled.id, called_off.id, failed.id])
  end

  it "breaks ties on the same start time by event id in both sections" do
    start = 3.days.from_now.change(usec: 0)
    first = event("First", starts_at: start)
    second = event("Second", starts_at: start)
    past_start = 3.days.ago.change(usec: 0)
    old_first = event("Old first", starts_at: past_start)
    old_second = event("Old second", starts_at: past_start)
    [second, first, old_first, old_second].each { |created| register(created) }

    body = fetch
    expect(body["upcoming"].map { |row| row["event_id"] }).to eq([first.id, second.id])
    expect(body["past"].map { |row| row["event_id"] }).to eq([old_second.id, old_first.id])
  end

  it "keeps an event in Upcoming until it ends, and moves it to Past once it has" do
    in_progress = event("In progress", starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
    finished = event("Finished", starts_at: 3.hours.ago, ends_at: 1.hour.ago)
    register(in_progress)
    register(finished)

    body = fetch
    expect(body["upcoming"].map { |row| row["event_id"] }).to eq([in_progress.id])
    expect(body["past"].map { |row| row["event_id"] }).to eq([finished.id])
  end

  it "puts a registration the participant cancelled under Past" do
    future = event("Changed my mind", starts_at: 4.days.from_now)
    register(future)
    Registrations::Cancel.new(user: user, event: future).call

    body = fetch
    expect(body["upcoming"]).to be_empty
    expect(body["past"].first).to include("event_id" => future.id, "status" => "cancelled", "cancelled_by" => "participant")
  end

  it "puts a registration for an organizer-cancelled event under Past before the cascade job runs" do
    future = event("Called off", starts_at: 4.days.from_now)
    register(future)
    Events::Cancel.new(event: future).call

    body = fetch
    expect(body["upcoming"]).to be_empty
    row = body["past"].first
    expect(row).to include("event_id" => future.id, "status" => "confirmed")
    expect(row["event"]).to include("status" => "cancelled")
  end

  it "puts a failed registration under Past" do
    future = event("Never confirmed", starts_at: 4.days.from_now)
    Registration.create!(user: user, event: future, status: "failed")

    body = fetch
    expect(body["upcoming"]).to be_empty
    expect(body["past"].first).to include("event_id" => future.id, "status" => "failed")
  end

  it "places a registration for an event the user can no longer see at its date, without its details" do
    OrganizationMembership.create!(user: user, organization: partner, role: "member")
    hidden = event("Partners only", starts_at: 3.days.from_now, visibility: "organization_restricted")
    before_it = event("Before", starts_at: 2.days.from_now)
    after_it = event("After", starts_at: 4.days.from_now)
    [after_it, hidden, before_it].each { |created| register(created) }
    OrganizationMembership.where(user: user, organization: partner).delete_all

    body = fetch
    expect(body["upcoming"].map { |row| row["event_id"] }).to eq([before_it.id, hidden.id, after_it.id])
    expect(body["upcoming"][1]).not_to have_key("event")
    expect(response.body).not_to include("Partners only")
  end

  it "includes the event's end time in the summary" do
    future = event("With an end", starts_at: 2.days.from_now)
    register(future)

    summary = fetch["upcoming"].first["event"]
    expect(Time.zone.parse(summary["ends_at"])).to be_within(1.second).of(future.ends_at)
  end

  it "rejects an unauthenticated request" do
    get "/api/me/registrations"

    expect(response).to have_http_status(:unauthorized)
  end

  it "puts every registration in exactly one section" do
    register(event("Upcoming", starts_at: 2.days.from_now))
    register(event("Happening", starts_at: 10.minutes.ago, ends_at: 50.minutes.from_now))
    register(event("Ended", starts_at: 2.days.ago))
    cancelled = event("Self-cancelled", starts_at: 3.days.from_now)
    register(cancelled)
    Registrations::Cancel.new(user: user, event: cancelled).call
    called_off = event("Organizer cancelled", starts_at: 5.days.from_now)
    register(called_off)
    Events::Cancel.new(event: called_off).call
    Registration.create!(user: user, event: event("Failed", starts_at: 6.days.from_now), status: "failed")

    body = fetch
    ids = body["upcoming"].map { |row| row["id"] } + body["past"].map { |row| row["id"] }
    expect(ids).to match_array(user.registrations.ids)
    expect(ids.uniq.size).to eq(ids.size)
    expect(body["upcoming"].size).to eq(2)
  end
end
