require "rails_helper"

RSpec.describe "Event creation", type: :request do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:other_organization) { Organization.create!(name: "Borealis", slug: "borealis") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:topic) { Topic.create!(name: "Climate", slug: "climate") }
  let(:admin) { User.create!(email: "admin@example.com", name: "Admin", password: "password") }
  let(:member) { User.create!(email: "member@example.com", name: "Member", password: "password") }
  let(:partner_member) { User.create!(email: "partner@example.com", name: "Partner", password: "password") }
  let(:outsider) { User.create!(email: "outsider@example.com", name: "Outsider", password: "password") }

  let(:starts_at) { 3.days.from_now.change(usec: 0) }
  let(:attributes) do
    {
      organization_id: organization.id,
      title: "Financing the energy transition",
      description: "A working session",
      starts_at: starts_at.iso8601,
      ends_at: (starts_at + 90.minutes).iso8601,
      location: "Geneva",
      kind: "in_person",
      capacity: 80,
      status: "published",
      topic_ids: [topic.id]
    }
  end

  before do
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    OrganizationMembership.create!(user: member, organization: organization, role: "member")
    OrganizationMembership.create!(user: partner_member, organization: partner, role: "member")
  end

  def create_event(user, overrides = {})
    headers = user ? auth_headers(user) : {}
    post "/api/events", params: { event: attributes.merge(overrides) }, headers: headers, as: :json
  end

  def discovery_ids(user)
    get "/api/events", headers: auth_headers(user)
    json_body["data"].map { |row| row["id"] }
  end

  def draft_event
    Event.create!(
      organization: organization,
      title: "Embargoed session",
      description: "Speakers not announced",
      starts_at: starts_at,
      ends_at: starts_at + 1.hour,
      location: "Geneva",
      kind: "in_person",
      capacity: 10,
      status: "draft"
    )
  end

  it "rejects an unauthenticated user" do
    expect { create_event(nil) }.not_to change(Event, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("unauthenticated")
  end

  it "rejects a member who is not an admin of the organization" do
    expect { create_event(member) }.not_to change(Event, :count)
    expect(response).to have_http_status(:forbidden)
    expect(json_body.dig("error", "code")).to eq("forbidden")
  end

  it "rejects an admin creating an event for an organization they do not administer" do
    expect { create_event(admin, organization_id: other_organization.id) }.not_to change(Event, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "creates a published event and returns its details" do
    create_event(admin)

    expect(response).to have_http_status(:created)
    expect(json_body).to include(
      "title" => "Financing the energy transition",
      "status" => "published",
      "visibility" => "public",
      "kind" => "in_person",
      "capacity" => 80,
      "description" => "A working session",
      "allowed_organization_ids" => []
    )
    expect(json_body["topics"].map { |row| row["id"] }).to eq([topic.id])
    expect(Time.zone.parse(json_body["starts_at"])).to eq(starts_at)
  end

  it "ignores allowed organizations on a public event" do
    create_event(admin, visibility: "public", allowed_organization_ids: [partner.id])

    expect(response).to have_http_status(:created)
    expect(json_body["allowed_organization_ids"]).to eq([])
    expect(EventAllowedOrganization.where(event_id: json_body["id"])).to be_empty
  end

  it "keeps a draft out of discovery" do
    create_event(admin, status: "draft")
    event_id = json_body["id"]

    expect(response).to have_http_status(:created)
    expect(discovery_ids(outsider)).not_to include(event_id)
    expect(discovery_ids(admin)).not_to include(event_id)
  end

  it "defaults to a draft when no status is sent" do
    create_event(admin, status: nil)

    expect(response).to have_http_status(:created)
    expect(json_body["status"]).to eq("draft")
  end

  it "shows a new published event in discovery" do
    create_event(admin)
    event_id = json_body["id"]

    expect(discovery_ids(outsider)).to include(event_id)
  end

  it "rejects an end time that is not after the start time" do
    expect { create_event(admin, ends_at: starts_at.iso8601) }.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "code")).to eq("validation_failed")
    expect(json_body.dig("error", "details", "ends_at")).to eq(["must be after starts_at"])
    expect(json_body.dig("error", "reasons", "ends_at")).to eq([{ "error" => "ends_before_start" }])
  end

  it "rejects a status other than draft or published" do
    expect { create_event(admin, status: "cancelled") }.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("status")
  end

  it "rejects a restricted event with no allowed organizations" do
    expect {
      create_event(admin, visibility: "organization_restricted", allowed_organization_ids: [])
    }.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("allowed_organization_ids")
  end

  it "rejects an allowed organization that does not exist" do
    expect {
      create_event(admin, visibility: "organization_restricted", allowed_organization_ids: [Organization.maximum(:id).to_i + 1])
    }.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("allowed_organization_ids")
  end

  it "rejects a topic that does not exist" do
    expect { create_event(admin, topic_ids: [Topic.maximum(:id).to_i + 1]) }.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("topic_ids")
  end

  it "shows a restricted event to allowed organizations and hides it from the organizer's members" do
    create_event(admin, visibility: "organization_restricted", allowed_organization_ids: [partner.id])

    expect(response).to have_http_status(:created)
    expect(json_body["allowed_organization_ids"]).to eq([partner.id])
    event_id = json_body["id"]
    expect(discovery_ids(partner_member)).to include(event_id)
    expect(discovery_ids(member)).not_to include(event_id)
    expect(discovery_ids(admin)).to include(event_id)
  end

  describe "draft visibility" do
    it "returns not found when a non-admin opens a draft by id" do
      draft = draft_event

      get "/api/events/#{draft.id}", headers: auth_headers(member)
      expect(response).to have_http_status(:not_found)

      get "/api/events/#{draft.id}", headers: auth_headers(outsider)
      expect(response).to have_http_status(:not_found)
    end

    it "lets the organizer's admin open a draft by id" do
      draft = draft_event

      get "/api/events/#{draft.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json_body["status"]).to eq("draft")
    end

    it "refuses a registration for a draft" do
      draft = draft_event

      expect {
        post "/api/registrations", params: { event_id: draft.id }, headers: auth_headers(outsider), as: :json
      }.not_to change(Registration, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not let a published event reach draft through cancelled" do
    create_event(admin)
    event_id = json_body["id"]

    post "/api/events/#{event_id}/cancel", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)

    patch "/api/events/#{event_id}", params: { event: { status: "draft" } }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Event.find(event_id).status).to eq("cancelled")
  end

  it "rejects a missing or unparseable start time with 422" do
    expect { create_event(admin, starts_at: "") }.not_to change(Event, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("starts_at")

    expect { create_event(admin, starts_at: "not-a-date") }.not_to change(Event, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "does not let a published event go back to draft" do
    create_event(admin)
    event_id = json_body["id"]

    patch "/api/events/#{event_id}", params: { event: { status: "draft" } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "details")).to have_key("status")
    expect(Event.find(event_id).status).to eq("published")
  end
end
