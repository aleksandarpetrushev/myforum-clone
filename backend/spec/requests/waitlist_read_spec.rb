require "rails_helper"

RSpec.describe "Waitlist on the read side", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:admin) { person("admin") }
  let(:holder) { person("holder") }
  let(:ana) { person("ana") }
  let(:ben) { person("ben") }

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")

  def make_event(title, starts_in: 3.days)
    Event.create!(
      organization: organization, title: title, description: "Talk", starts_at: Time.current + starts_in,
      ends_at: Time.current + starts_in + 1.hour, location: "Geneva", kind: "in_person", capacity: 1, status: "published"
    )
  end

  let(:event) { make_event("Popular session") }

  before do
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    Events::Register.new(user: holder, event: event).call
    Waitlist::Join.new(user: ana, event: event).call
    Waitlist::Join.new(user: ben, event: event).call
  end

  describe "event detail" do
    it "shows the viewer's own place in line, and nothing about anyone else's" do
      get "/api/events/#{event.id}", headers: auth_headers(ben)

      expect(json_body["my_registration"]).to include("status" => "waitlisted", "waitlist_position" => 2)
      expect(json_body).not_to have_key("waitlist_count")
    end

    it "shows the organizer's admins how many are waiting, without caching it for others" do
      get "/api/events/#{event.id}", headers: auth_headers(admin)
      expect(json_body["waitlist_count"]).to eq(2)
      expect(json_body["my_registration"]).to be_nil

      get "/api/events/#{event.id}", headers: auth_headers(ana)
      expect(json_body).not_to have_key("waitlist_count")
      expect(json_body["my_registration"]).to include("waitlist_position" => 1)
    end
  end

  describe "My registrations" do
    def sections(user)
      get "/api/me/registrations", headers: auth_headers(user)
      json_body.transform_values { |rows| rows.map { |row| row.slice("event_id", "status", "waitlist_position") } }
    end

    it "lists a place in line under Upcoming with its position" do
      expect(sections(ben)["upcoming"]).to eq([{ "event_id" => event.id, "status" => "waitlisted", "waitlist_position" => 2 }])
    end

    it "lists an offer under Upcoming" do
      Registrations::Cancel.new(user: holder, event: event).call

      expect(sections(ana)["upcoming"].sole).to include("status" => "offered")
    end

    it "moves an expired offer to Past" do
      Registrations::Cancel.new(user: holder, event: event).call
      offer = Registration.find_by!(user: ana, event: event)
      travel_to(offer.offer_expires_at + 1.second) { Waitlist::ExpireOffer.call(offer.id, offer.lifecycle_version) }

      expect(sections(ana)["upcoming"]).to be_empty
      expect(sections(ana)["past"].sole).to include("status" => "cancelled")
    end

    it "moves a place in line, and an offer whose expiry has not run yet, to Past once the event has started" do
      Registrations::Cancel.new(user: holder, event: event).call # ana offered, ben still waiting

      travel_to(event.starts_at + 1.minute) do
        expect(sections(ana)).to eq("upcoming" => [], "past" => [{ "event_id" => event.id, "status" => "offered" }])
        expect(sections(ben)["upcoming"]).to be_empty
        expect(sections(ben)["past"].sole).to include("status" => "waitlisted")
      end
    end

  end
end
