require "rails_helper"

RSpec.describe "Event cancellation", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:admin) { User.create!(email: "admin@example.com", name: "Admin", password: "password") }
  let(:member) { User.create!(email: "member@example.com", name: "Member", password: "password") }
  let(:registrant) { User.create!(email: "registrant@example.com", name: "Registrant", password: "password") }
  let(:outsider) { User.create!(email: "outsider@example.com", name: "Outsider", password: "password") }

  before do
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    OrganizationMembership.create!(user: member, organization: organization, role: "member")
  end

  def create_event(status: "published", visibility: "public", starts_at: 3.days.from_now)
    event = Event.create!(
      organization: organization,
      title: "Climate finance session",
      description: "A working session",
      starts_at: starts_at,
      ends_at: starts_at + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: status,
      visibility: visibility
    )
    event.allowed_organizations << partner if visibility == "organization_restricted"
    event
  end

  def cancel(event, as:)
    post "/api/events/#{event.id}/cancel", headers: auth_headers(as), as: :json
  end

  def discovery_ids(user)
    get "/api/events", headers: auth_headers(user)
    json_body["data"].map { |row| row["id"] }
  end

  it "cancels a published event, records when, and writes one EventCancelled row" do
    event = create_event
    Events::Register.new(user: registrant, event: event).call

    cancel(event, as: admin)

    expect(response).to have_http_status(:ok)
    expect(json_body["status"]).to eq("cancelled")
    expect(json_body["cancelled_at"]).to be_present
    expect(OutboxEvent.where(event_type: "EventCancelled", aggregate_id: event.id).count).to eq(1)
  end

  it "returns 200 with no further effect when the event is already cancelled" do
    event = create_event
    cancel(event, as: admin)
    first_cancelled_at = event.reload.cancelled_at

    travel 1.minute do
      cancel(event, as: admin)
    end

    expect(response).to have_http_status(:ok)
    expect(json_body["status"]).to eq("cancelled")
    expect(event.reload.cancelled_at).to eq(first_cancelled_at)
    expect(OutboxEvent.where(event_type: "EventCancelled", aggregate_id: event.id).count).to eq(1)
  end

  it "forbids a member who is not an admin of the organizer" do
    event = create_event

    cancel(event, as: member)

    expect(response).to have_http_status(:forbidden)
    expect(event.reload.status).to eq("published")
  end

  it "refuses to cancel an event that has started" do
    event = create_event(starts_at: 1.hour.ago)

    cancel(event, as: admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "code")).to eq("event_started")
    expect(event.reload.status).to eq("published")
  end

  it "refuses to cancel a draft" do
    event = create_event(status: "draft")

    cancel(event, as: admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "reasons", "status")).to include(include("error" => "invalid_transition"))
    expect(event.reload.status).to eq("draft")
  end

  describe "who sees a cancelled event" do
    it "keeps it out of discovery" do
      event = create_event
      cancel(event, as: admin)

      expect(discovery_ids(outsider)).not_to include(event.id)
    end

    it "shows it to registrants and other allowed users with its cancellation date" do
      event = create_event
      Events::Register.new(user: registrant, event: event).call
      cancel(event, as: admin)

      [registrant, outsider].each do |viewer|
        get "/api/events/#{event.id}", headers: auth_headers(viewer)
        expect(response).to have_http_status(:ok)
        expect(json_body).to include("status" => "cancelled")
        expect(json_body["cancelled_at"]).to be_present
      end
    end

    it "keeps a restricted cancelled event hidden from users outside the allowed organizations" do
      event = create_event(visibility: "organization_restricted")
      cancel(event, as: admin)

      get "/api/events/#{event.id}", headers: auth_headers(outsider)

      expect(response).to have_http_status(:not_found)
    end

    it "keeps drafts hidden from non-admins" do
      draft = create_event(status: "draft")

      get "/api/events/#{draft.id}", headers: auth_headers(outsider)

      expect(response).to have_http_status(:not_found)
    end

    it "keeps the event's title on My registrations, marked cancelled by the organizer" do
      event = create_event
      Events::Register.new(user: registrant, event: event).call
      cancel(event, as: admin)
      perform_enqueued_jobs { Outbox::Publisher.new.call }

      get "/api/me/registrations", headers: auth_headers(registrant)

      row = json_body["past"].find { |registration| registration["event_id"] == event.id }
      expect(row).to include("status" => "cancelled", "cancelled_by" => "organizer")
      expect(row["event"]).to include("title" => "Climate finance session", "status" => "cancelled")
    end

    it "refuses a new registration for a cancelled event" do
      event = create_event
      cancel(event, as: admin)

      post "/api/registrations", params: { event_id: event.id }, headers: auth_headers(outsider), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH and status" do
    it "refuses status cancelled, even with other fields, and changes nothing" do
      event = create_event

      patch "/api/events/#{event.id}",
            params: { event: { status: "cancelled", title: "Renamed" } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body.dig("error", "reasons", "status")).to include(include("error" => "invalid_transition"))
      expect(event.reload).to have_attributes(status: "published", title: "Climate finance session", cancelled_at: nil)
      expect(OutboxEvent.where(event_type: "EventCancelled", aggregate_id: event.id)).to be_empty
    end

    it "still publishes a draft with one EventPublished row" do
      draft = create_event(status: "draft")

      patch "/api/events/#{draft.id}", params: { event: { status: "published" } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(OutboxEvent.where(event_type: "EventPublished", aggregate_id: draft.id).count).to eq(1)
    end

    it "refuses any status change out of cancelled" do
      event = create_event
      cancel(event, as: admin)

      %w[published draft].each do |status|
        patch "/api/events/#{event.id}", params: { event: { status: status } }, headers: auth_headers(admin), as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(event.reload.status).to eq("cancelled")
    end
  end
end
