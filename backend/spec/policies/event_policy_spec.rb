require "rails_helper"

RSpec.describe EventPolicy do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Open session",
      description: "Public",
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      location: "Berlin",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
  end
  let(:member) { User.create!(email: "member@example.com", name: "Member", password: "password") }
  let(:admin) { User.create!(email: "admin@example.com", name: "Admin", password: "password") }

  before do
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    OrganizationMembership.create!(user: member, organization: organization, role: "member")
  end

  it "denies an anonymous user" do
    expect(described_class.new(nil, event).show?).to be(false)
    expect(EventPolicy::Scope.new(nil, Event.all).resolve).to be_empty
  end

  it "allows any authenticated user to view" do
    expect(described_class.new(member, event).show?).to be(true)
    expect(EventPolicy::Scope.new(member, Event.all).resolve).to include(event)
  end

  it "allows only an organizer admin to update" do
    expect(described_class.new(admin, event).update?).to be(true)
    expect(described_class.new(member, event).update?).to be(false)
  end
end
