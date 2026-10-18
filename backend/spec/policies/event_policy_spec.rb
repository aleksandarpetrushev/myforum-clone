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

  describe "organization_restricted events" do
    let(:other) { Organization.create!(name: "Other", slug: "other-policy") }
    let(:third) { Organization.create!(name: "Third", slug: "third-policy") }
    let(:outsider) { User.create!(email: "outsider@example.com", name: "Outsider", password: "password") }
    let(:restricted) do
      created = Event.create!(
        organization: organization,
        title: "Closed session",
        description: "Members",
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        location: "Berlin",
        kind: "in_person",
        capacity: 10,
        status: "published",
        visibility: "organization_restricted"
      )
      created.allowed_organizations << other
      created.allowed_organizations << third
      created
    end

    it "hides the event from users outside the allowed organizations" do
      expect(described_class.new(outsider, restricted).show?).to be(false)
      expect(EventPolicy::Scope.new(outsider, Event.all).resolve).not_to include(restricted)
    end

    it "shows the event when the user belongs to any allowed organization" do
      OrganizationMembership.create!(user: outsider, organization: third, role: "member")

      expect(described_class.new(outsider, restricted).show?).to be(true)
      expect(EventPolicy::Scope.new(outsider, Event.all).resolve).to include(restricted)
    end

    it "keeps access through a remaining organization after one membership ends" do
      OrganizationMembership.create!(user: outsider, organization: other, role: "member")
      kept = OrganizationMembership.create!(user: outsider, organization: third, role: "member")
      OrganizationMembership.where(user: outsider, organization: other).delete_all

      expect(described_class.new(outsider, restricted).show?).to be(true)
      kept.destroy!
      expect(described_class.new(outsider, restricted).show?).to be(false)
    end

    it "lets an organizer admin view a restricted event that does not list their organization" do
      expect(described_class.new(admin, restricted).show?).to be(true)
      expect(described_class.new(member, restricted).show?).to be(false)
      expect(EventPolicy::Scope.new(admin, Event.all).resolve).to include(restricted)
    end

    it "hides a newly restricted event from a user who is not in an allowed organization" do
      event.update!(visibility: "organization_restricted")

      expect(described_class.new(member, event).show?).to be(false)
      expect(EventPolicy::Scope.new(member, Event.all).resolve).not_to include(event)
    end
  end
end
