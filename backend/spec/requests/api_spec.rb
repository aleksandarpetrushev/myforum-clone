require "rails_helper"

RSpec.describe "API", type: :request do
  let(:organization) { Organization.create!(name: "Civic Hall", slug: "civic-hall") }
  let(:topic) { Topic.create!(name: "Housing", slug: "housing") }
  let(:user) { User.create!(email: "alex@example.com", name: "Alex Morgan", password: "password", location: "Berlin") }
  let(:admin) { User.create!(email: "admin@example.com", name: "Admin", password: "password") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Housing clinic",
      description: "How cities fund housing",
      starts_at: 5.days.from_now,
      ends_at: 5.days.from_now + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 3,
      status: "published",
      topics: [topic]
    )
  end

  before do
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
  end

  it "rejects unauthenticated event access" do
    get "/api/events"
    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("unauthenticated")
  end

  it "lists upcoming events for a signed-in user" do
    event
    get "/api/events", params: { q: "housing", topic_id: topic.id, location: "Berlin" }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json_body["data"].map { |row| row["id"] }).to include(event.id)
  end

  it "registers the user and reports a duplicate as a conflict" do
    post "/api/events/#{event.id}/register", headers: auth_headers(user)
    expect(response).to have_http_status(:created)
    expect(json_body["status"]).to eq("confirmed")

    post "/api/events/#{event.id}/register", headers: auth_headers(user)
    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("duplicate_registration")
  end

  it "returns event_full when capacity is exhausted" do
    event.update!(capacity: 1, reserved_spots: 1)
    post "/api/events/#{event.id}/register", headers: auth_headers(user)

    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("event_full")
  end

  it "forbids a member from updating an event and allows an organizer admin" do
    patch "/api/events/#{event.id}", params: { event: { title: "Nope" } }, headers: auth_headers(user)
    expect(response).to have_http_status(:forbidden)

    patch "/api/events/#{event.id}", params: { event: { title: "Updated clinic" } }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(event.reload.title).to eq("Updated clinic")
  end

  it "follows a topic idempotently and lists it" do
    post "/api/topics/#{topic.id}/follow", headers: auth_headers(user)
    post "/api/topics/#{topic.id}/follow", headers: auth_headers(user)
    expect(response).to have_http_status(:no_content)
    expect(TopicFollow.where(user: user, topic: topic).count).to eq(1)

    get "/api/topics", headers: auth_headers(user)
    followed = json_body["data"].find { |row| row["id"] == topic.id }
    expect(followed["followed"]).to be(true)

    delete "/api/topics/#{topic.id}/follow", headers: auth_headers(user)
    expect(response).to have_http_status(:no_content)
    expect(TopicFollow.where(user: user, topic: topic)).to be_empty
  end

  it "signs in with the seeded-style password" do
    post "/api/session", params: { email: user.email, password: "password" }
    expect(response).to have_http_status(:ok)
    expect(json_body["token"]).to be_present
  end
end
