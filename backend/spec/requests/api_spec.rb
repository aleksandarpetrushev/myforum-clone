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

  it "pages events that share a start time by id" do
    shared = Time.zone.parse("2030-06-01 15:00:00")
    base = Event.maximum(:id).to_i
    now = Time.current
    tie_ids = (1..21).map { |offset| base + offset }
    Event.insert_all(tie_ids.reverse.map { |id|
      {
        id: id,
        organization_id: organization.id,
        title: "Tied #{id}",
        description: "Same start",
        starts_at: shared,
        ends_at: shared + 2.hours,
        location: "Berlin",
        kind: "in_person",
        capacity: 10,
        created_at: now,
        updated_at: now
      }
    })
    Event.connection.execute("SELECT setval(pg_get_serial_sequence('events', 'id'), (SELECT MAX(id) FROM events))")
    early = Event.create!(
      organization: organization,
      title: "Earlier",
      description: "Starts first",
      starts_at: shared - 1.day,
      ends_at: shared - 1.day + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )

    pages = lambda do |page|
      get "/api/events", params: { page: page }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json_body["data"].map { |row| row["id"] }
    end

    expected = [early.id] + tie_ids.sort
    page1 = pages.call(1)
    page2 = pages.call(2)

    expect(page1).to eq(expected.first(20))
    expect(pages.call(1)).to eq(page1)
    expect(page2).to eq(expected.drop(20))
    expect(page1 & page2).to be_empty
  end

  it "returns user_not_registered when cancelling without a registration" do
    post "/api/registrations/cancel", params: { event_id: event.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
    expect(json_body.dig("error", "code")).to eq("user_not_registered")
  end

  it "registers the user and reports a duplicate as a conflict" do
    post "/api/registrations", params: { event_id: event.id }, headers: auth_headers(user)
    expect(response).to have_http_status(:created)
    expect(json_body["status"]).to eq("confirmed")

    post "/api/registrations", params: { event_id: event.id }, headers: auth_headers(user)
    expect(response).to have_http_status(:conflict)
    expect(json_body.dig("error", "code")).to eq("duplicate_registration")
  end

  it "rejects cancellation once the event has started" do
    post "/api/registrations", params: { event_id: event.id }, headers: auth_headers(user)
    event.update!(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

    post "/api/registrations/cancel", params: { event_id: event.id }, headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.dig("error", "code")).to eq("event_started")
    expect(event.reload.reserved_spots).to eq(1)
  end

  it "returns event_full when capacity is exhausted" do
    event.update!(capacity: 1, reserved_spots: 1)
    post "/api/registrations", params: { event_id: event.id }, headers: auth_headers(user)

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

  describe "organization-restricted events" do
    let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
    let(:second) { Organization.create!(name: "Second", slug: "second") }
    let(:member) { User.create!(email: "member@example.com", name: "Member", password: "password") }
    let(:restricted) do
      created = Event.create!(
        organization: organization,
        title: "Private clinic",
        description: "Invite only",
        starts_at: 6.days.from_now,
        ends_at: 6.days.from_now + 1.hour,
        location: "Berlin",
        kind: "in_person",
        capacity: 5,
        status: "published",
        visibility: "organization_restricted"
      )
      created.allowed_organizations << partner
      created.allowed_organizations << second
      created
    end

    it "omits restricted events from search and returns 404 for a direct request" do
      restricted
      get "/api/events", params: { q: "Private" }, headers: auth_headers(user)
      expect(json_body["data"].map { |row| row["id"] }).not_to include(restricted.id)

      expect(Events::Cache).not_to receive(:fetch_detail)
      get "/api/events/#{restricted.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Private clinic")

      post "/api/registrations", params: { event_id: restricted.id }, headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end

    it "lets a member of one allowed organization discover, view, and register" do
      OrganizationMembership.create!(user: member, organization: second, role: "member")
      restricted

      get "/api/events", params: { q: "Private" }, headers: auth_headers(member)
      expect(json_body["data"].map { |row| row["id"] }).to include(restricted.id)

      get "/api/events/#{restricted.id}", headers: auth_headers(member)
      expect(response).to have_http_status(:ok)
      expect(json_body["visibility"]).to eq("organization_restricted")

      post "/api/registrations", params: { event_id: restricted.id }, headers: auth_headers(member)
      expect(response).to have_http_status(:created)
    end

    it "authorizes registration history with one event scope query" do
      OrganizationMembership.create!(user: member, organization: partner, role: "member")
      visible = restricted
      hidden = Array.new(3) do |index|
        Event.create!(
          organization: organization,
          title: "Hidden session #{index}",
          description: "Invite only",
          starts_at: (7 + index).days.from_now,
          ends_at: (7 + index).days.from_now + 1.hour,
          location: "Berlin",
          kind: "in_person",
          capacity: 5,
          status: "published",
          visibility: "organization_restricted"
        )
      end
      ([visible] + hidden).each do |created|
        Registration.create!(user: member, event: created, status: "confirmed")
      end

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql]
        next if payload[:name] == "SCHEMA" || sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

        queries << sql
      end
      get "/api/me/registrations", headers: auth_headers(member)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(queries.count { |sql| sql.include?("organization_memberships") }).to eq(1)
      rows = json_body["data"].index_by { |row| row["event_id"] }
      expect(rows[visible.id]).to have_key("event")
      expect(rows[visible.id]["event"]["title"]).to eq(visible.title)
      hidden.each do |created|
        expect(rows[created.id]).not_to have_key("event")
        expect(response.body).not_to include(created.title)
      end
    end

    it "drops access immediately when the last permitted membership is removed" do
      first = OrganizationMembership.create!(user: member, organization: partner, role: "member")
      second_membership = OrganizationMembership.create!(user: member, organization: second, role: "member")
      Registration.create!(user: member, event: restricted, status: "confirmed")
      restricted.update!(reserved_spots: 1)

      first.destroy!
      get "/api/events/#{restricted.id}", headers: auth_headers(member)
      expect(response).to have_http_status(:ok)

      second_membership.destroy!
      get "/api/events/#{restricted.id}", headers: auth_headers(member)
      expect(response).to have_http_status(:not_found)

      get "/api/me/registrations", headers: auth_headers(member)
      expect(json_body["data"].map { |row| row["event_id"] }).to eq([restricted.id])
      expect(json_body.dig("data", 0, "status")).to eq("confirmed")
      expect(json_body.dig("data", 0)).not_to have_key("event")
      expect(response.body).not_to include(restricted.title)
      expect(response.body).not_to include(restricted.location)

      post "/api/registrations/cancel", params: { event_id: restricted.id }, headers: auth_headers(member)
      expect(response).to have_http_status(:ok)
      expect(json_body["status"]).to eq("cancelled")
      expect(json_body).not_to have_key("event")
      expect(response.body).not_to include(restricted.title)
      expect(response.body).not_to include(restricted.location)
      expect(restricted.reload.reserved_spots).to eq(0)

      get "/api/events/#{restricted.id}", headers: auth_headers(member)
      expect(response).to have_http_status(:not_found)

      post "/api/registrations/cancel", params: { event_id: restricted.id }, headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
      expect(json_body.dig("error", "code")).to eq("not_found")
    end

    it "hides an event after it becomes organization restricted" do
      get "/api/events/#{event.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      patch "/api/events/#{event.id}",
            params: { event: { visibility: "organization_restricted", allowed_organization_ids: [partner.id] } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(event.reload.visibility).to eq("organization_restricted")
      expect(event.allowed_organization_ids).to eq([partner.id])

      get "/api/events/#{event.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end

    it "lets the organizer admin open a restricted event that does not list their organization" do
      get "/api/events/#{restricted.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      patch "/api/events/#{restricted.id}", params: { event: { title: "Admin title" } }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(restricted.reload.title).to eq("Admin title")
    end
  end
end
