require "rails_helper"

RSpec.describe "Waitlist", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:starts_in) { 3.days }
  let(:event) do
    Event.create!(
      organization: organization, title: "Popular session", description: "Talk",
      starts_at: Time.current + starts_in, ends_at: Time.current + starts_in + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 1, status: "published"
    )
  end
  let(:holder) { person("holder") }
  let(:ana) { person("ana") }
  let(:ben) { person("ben") }

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")

  def join(user, event_id: event.id) = post("/api/registrations/waitlist", params: { event_id: event_id }, headers: auth_headers(user))
  def accept(user) = post("/api/registrations/accept_offer", params: { event_id: event.id }, headers: auth_headers(user))
  def register(user) = post("/api/registrations", params: { event_id: event.id }, headers: auth_headers(user))
  def cancel(user) = post("/api/registrations/cancel", params: { event_id: event.id }, headers: auth_headers(user))

  def fill_event = Events::Register.new(user: holder, event: event).call

  it "joins once, answers the same place in line on a second join, and shows the position" do
    fill_event
    join(ana)
    expect(response).to have_http_status(:created)
    expect(json_body).to include("status" => "waitlisted", "waitlist_position" => 1)

    join(ben)
    join(ana)
    expect(response).to have_http_status(:ok)
    expect(json_body).to include("status" => "waitlisted", "waitlist_position" => 1)
    expect(Registration.where(event: event, status: "waitlisted").count).to eq(2)
  end

  it "refuses to queue for a seat that is free" do
    join(ana)

    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("seats_available")
  end

  it "refuses someone already registered" do
    fill_event
    join(holder)

    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("duplicate_registration")
  end

  context "in the last hour before the start" do
    let(:starts_in) { 50.minutes }

    it "closes the line" do
      fill_event
      join(ana)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body.dig("error", "code")).to eq("waitlist_closed")
    end

    it "gives a freed seat to whoever registers first, including someone still in line" do
      event # created now, starting in 50 minutes; the line filled up two hours earlier, while it was open
      travel_to(Time.current - 2.hours) do
        fill_event
        join(ana)
        join(ben)
      end
      cancel(holder)
      expect(event.reload.reserved_spots).to eq(0)

      register(ben)

      expect(response).to have_http_status(:created)
      expect(Registration.find_by(user: ben, event: event).status).to eq("confirmed")
      expect(Registration.find_by(user: ana, event: event).status).to eq("waitlisted")
    end
  end

  it "does not show an event the user cannot see" do
    hidden = Event.create!(
      organization: organization, title: "Partners only", description: "Talk", starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour, location: "Geneva", kind: "in_person", capacity: 1, status: "published",
      visibility: "organization_restricted"
    )
    hidden.allowed_organizations << partner
    join(ana, event_id: hidden.id)

    expect(response).to have_http_status(:not_found)
  end

  describe "an offered seat" do
    before do
      fill_event
      join(ana)
      join(ben)
      cancel(holder)
    end

    it "is held: a direct registration finds the event full" do
      register(person("cyd"))

      expect(response).to have_http_status(:conflict)
      expect(json_body.dig("error", "code")).to eq("event_full")
    end

    it "is confirmed by accepting it, without changing the seat count" do
      expect(Registration.find_by(user: ana, event: event)).to be_offered

      expect { accept(ana) }.not_to(change { event.reload.reserved_spots })

      expect(response).to have_http_status(:ok)
      expect(json_body["status"]).to eq("confirmed")
      expect(OutboxEvent.where(event_type: "RegistrationCreated", aggregate_id: json_body["id"]).count).to eq(1)
    end

    it "cannot be accepted by someone without an offer, or after it lapsed" do
      accept(ben)
      expect(json_body.dig("error", "code")).to eq("no_offer")

      travel_to(Registration.find_by(user: ana, event: event).offer_expires_at + 1.second) { accept(ana) }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body.dig("error", "code")).to eq("no_offer")
    end

    it "shows the offer deadline to the person offered" do
      get "/api/me/registrations", headers: auth_headers(ana)
      row = (json_body["upcoming"] + json_body["past"]).find { |r| r["event_id"] == event.id }

      expect(row).to include("status" => "offered")
      expect(row["offer_expires_at"]).to be_present
    end
  end
end
