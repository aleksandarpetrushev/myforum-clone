require "rails_helper"

RSpec.describe "Drafts (MF-105)", type: :request do
  let(:atlas) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:borealis) { Organization.create!(name: "Borealis", slug: "borealis") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:admin) { person("admin") }
  let(:member) { person("member") }
  let(:other_admin) { person("other-admin") }
  let(:outsider) { person("outsider") }

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")

  def make_event(organization, title, status: "draft", starts_in: 3.days, visibility: "public")
    Event.create!(
      organization: organization, title: title, description: "Talk", starts_at: Time.current + starts_in,
      ends_at: Time.current + starts_in + 1.hour, location: "Geneva", kind: "in_person", capacity: 10,
      status: status, visibility: visibility
    )
  end

  before do
    OrganizationMembership.create!(user: admin, organization: atlas, role: "admin")
    OrganizationMembership.create!(user: admin, organization: borealis, role: "admin")
    OrganizationMembership.create!(user: member, organization: atlas, role: "member")
    OrganizationMembership.create!(user: other_admin, organization: partner, role: "admin")
  end

  def drafts_for(user)
    get "/api/me/drafts", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    json_body["data"]
  end

  def publish(user, event)
    post "/api/events/#{event.id}/publish", headers: auth_headers(user)
  end

  describe "GET /api/me/drafts" do
    it "lists the drafts of every organization the user administers, soonest first, and nothing published" do
      later = make_event(atlas, "Atlas later", starts_in: 5.days)
      sooner = make_event(borealis, "Borealis sooner", starts_in: 2.days)
      make_event(atlas, "Atlas published", status: "published")

      rows = drafts_for(admin)

      expect(rows.map { |row| row["id"] }).to eq([sooner.id, later.id])
      expect(rows.map { |row| row.dig("organization", "name") }).to eq(%w[Borealis Atlas])
      expect(rows.map { |row| row["status"] }.uniq).to eq(["draft"])
    end

    it "shows no one else's drafts" do
      make_event(atlas, "Atlas draft")

      expect(drafts_for(member)).to eq([])
      expect(drafts_for(other_admin)).to eq([])
      expect(drafts_for(outsider)).to eq([])
    end
  end

  describe "POST /api/events/:id/publish" do
    it "publishes a future draft once, and it appears in discovery" do
      draft = make_event(atlas, "Ready")

      publish(admin, draft)

      expect(response).to have_http_status(:ok)
      expect(json_body["status"]).to eq("published")
      expect(OutboxEvent.where(event_type: "EventPublished", aggregate_id: draft.id).count).to eq(1)
      get "/api/events", headers: auth_headers(outsider)
      expect(json_body["data"].map { |row| row["id"] }).to include(draft.id)
    end

    it "refuses a draft whose start has passed, and says why" do
      draft = make_event(atlas, "Too late", starts_in: 1.day)
      draft.update_columns(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      publish(admin, draft)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body.dig("error", "details", "starts_at")).to include("has already passed, so the event cannot be published")
      expect(draft.reload.status).to eq("draft")
    end

    it "refuses a restricted draft with no allowed organizations" do
      draft = make_event(atlas, "Restricted", visibility: "organization_restricted")

      publish(admin, draft)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body.dig("error", "details")).to have_key("allowed_organization_ids")
      expect(draft.reload.status).to eq("draft")
    end

    it "treats publishing twice as one publish, like any repeated save (MF-106)" do
      draft = make_event(atlas, "Double click")

      2.times { publish(admin, draft) }

      expect(response).to have_http_status(:ok)
      expect(OutboxEvent.where(event_type: "EventPublished", aggregate_id: draft.id).count).to eq(1)
    end

    it "refuses a cancelled event" do
      cancelled = make_event(atlas, "Called off", status: "published")
      Events::Cancel.new(event: cancelled).call

      publish(admin, cancelled)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(cancelled.reload.status).to eq("cancelled")
    end

    it "is not found for someone who cannot see the draft" do
      draft = make_event(atlas, "Secret")

      publish(member, draft)

      expect(response).to have_http_status(:not_found)
      expect(draft.reload.status).to eq("draft")
    end
  end

  describe "publishing after the start through the older paths" do
    it "refuses PATCH to published" do
      draft = make_event(atlas, "Patch me")
      draft.update_columns(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      patch "/api/events/#{draft.id}", params: { event: { status: "published" } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(draft.reload.status).to eq("draft")
    end

    it "refuses creating an event as published with a start in the past, but allows a past draft" do
      attributes = { organization_id: atlas.id, title: "Old", description: "Talk", starts_at: 2.hours.ago.iso8601,
                     ends_at: 1.hour.ago.iso8601, location: "Geneva", kind: "in_person", capacity: 10 }

      post "/api/events", params: { event: attributes.merge(status: "published") }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "/api/events", params: { event: attributes.merge(status: "draft") }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:created)
    end
  end
end
