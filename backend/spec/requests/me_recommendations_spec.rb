require "rails_helper"

RSpec.describe "My recommendations", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous
  end

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:user) { User.create!(email: "reader@example.com", name: "Reader", password: "password") }

  def event(title, visibility: "public")
    created = Event.create!(
      organization: organization, title: title, description: "Session",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 10, status: "published", visibility: visibility
    )
    created.allowed_organizations << partner if visibility == "organization_restricted"
    created
  end

  def fetch
    get "/api/me/recommendations", headers: auth_headers(user)
  end

  it "returns recommended events shaped like discovery rows" do
    recommended = event("Climate clinic")
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([recommended.id])

    fetch

    expect(response).to have_http_status(:ok)
    row = json_body.fetch("data").sole
    expect(row.keys).to match_array(recommended.as_list_json.keys)
    expect(row).to include("id" => recommended.id, "title" => "Climate clinic")
  end

  it "returns an empty list when there is nothing to recommend" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([])

    fetch

    expect(response).to have_http_status(:ok)
    expect(json_body).to eq("data" => [])
  end

  it "returns 503 when Go fails and nothing is cached" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_raise(Personalization::Unavailable, "timeout")

    fetch

    expect(response).to have_http_status(:service_unavailable)
    expect(json_body.dig("error", "code")).to eq("recommendations_unavailable")
  end

  it "serves the last list, filtered, when Go fails after the cache has expired" do
    kept = event("Kept")
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([kept.id])
    fetch
    travel 10.minutes
    allow(Personalization::Client).to receive(:recommended_event_ids).and_raise(Personalization::Unavailable, "timeout")

    fetch

    expect(response).to have_http_status(:ok)
    expect(json_body["data"].map { |row| row["id"] }).to eq([kept.id])
  end

  it "drops a restricted event as soon as the user leaves the organization, even while the list is cached" do
    OrganizationMembership.create!(user: user, organization: partner, role: "member")
    restricted = event("Partners only", visibility: "organization_restricted")
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([restricted.id])
    fetch
    expect(json_body["data"].map { |row| row["id"] }).to eq([restricted.id])

    OrganizationMembership.where(user: user, organization: partner).delete_all
    fetch

    expect(json_body["data"]).to eq([])
    expect(Personalization::Client).to have_received(:recommended_event_ids).once
  end

  it "rejects an unauthenticated request" do
    get "/api/me/recommendations"

    expect(response).to have_http_status(:unauthorized)
  end
end
