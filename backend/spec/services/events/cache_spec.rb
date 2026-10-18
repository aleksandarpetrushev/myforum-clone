require "rails_helper"

RSpec.describe Events::Cache do
  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous
  end

  let(:organization) { Organization.create!(name: "Cache Org", slug: "cache-org") }
  let(:partner) { Organization.create!(name: "Cache Partner", slug: "cache-partner") }
  let(:user) { User.create!(email: "cache-user@example.com", name: "Cache User", password: "password") }
  let(:outsider) { User.create!(email: "cache-out@example.com", name: "Out", password: "password") }
  let!(:restricted) do
    event = Event.create!(
      organization: organization,
      title: "Cached restricted",
      description: "Members",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Berlin",
      kind: "in_person",
      capacity: 10,
      status: "published",
      visibility: "organization_restricted"
    )
    event.allowed_organizations << partner
    event
  end

  def upcoming_ids(viewer)
    get "/api/events", headers: auth_headers(viewer)
    expect(response).to have_http_status(:ok)
    json_body["data"].map { |row| row["id"] }
  end

  it "keeps per-user upcoming lists and refreshes after membership delete_all", type: :request do
    OrganizationMembership.create!(user: user, organization: partner, role: "member")

    expect(upcoming_ids(user)).to include(restricted.id)
    expect(upcoming_ids(outsider)).not_to include(restricted.id)

    cached_key = described_class.upcoming_list_key(user)
    expect(Rails.cache.read(cached_key)).to be_present

    OrganizationMembership.where(user: user, organization: partner).delete_all
    expect(described_class.upcoming_list_key(user)).not_to eq(cached_key)
    expect(upcoming_ids(user)).not_to include(restricted.id)
  end

  it "refreshes upcoming lists when allowed organizations change", type: :request do
    OrganizationMembership.create!(user: user, organization: partner, role: "member")
    expect(upcoming_ids(user)).to include(restricted.id)

    before_epoch = described_class.list_epoch
    Events::Update.new(event: restricted, attributes: { "allowed_organization_ids" => [] }).call
    expect(described_class.list_epoch).to be > before_epoch
    expect(upcoming_ids(user)).not_to include(restricted.id)
  end

  it "bumps the list epoch when registration changes reserved spots" do
    public_event = Event.create!(
      organization: organization,
      title: "Open clinic",
      description: "Public",
      starts_at: 4.days.from_now,
      ends_at: 4.days.from_now + 1.hour,
      location: "Berlin",
      kind: "in_person",
      capacity: 5,
      status: "published"
    )
    before_epoch = described_class.list_epoch
    Events::Register.new(user: user, event: public_event).call
    expect(described_class.list_epoch).to be > before_epoch
  end
end
