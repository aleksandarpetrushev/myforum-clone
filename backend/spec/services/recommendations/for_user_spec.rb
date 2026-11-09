require "rails_helper"

RSpec.describe Recommendations::ForUser do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:partner) { Organization.create!(name: "Partner", slug: "partner") }
  let(:user) { User.create!(email: "reader@example.com", name: "Reader", password: "password") }

  def event(title, starts_at: 3.days.from_now, status: "published", visibility: "public")
    created = Event.create!(
      organization: organization, title: title, description: "Session",
      starts_at: starts_at, ends_at: starts_at + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 10, status: status, visibility: visibility
    )
    created.allowed_organizations << partner if visibility == "organization_restricted"
    created
  end

  def go_ranks(*events)
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return(events.map(&:id))
  end

  def recommended
    described_class.new(user: user).call
  end

  it "keeps Go's order" do
    third = event("Third")
    first = event("First")
    second = event("Second")
    go_ranks(first, second, third)

    expect(recommended).to eq([first, second, third])
  end

  it "asks Go for more than it shows, so filtering still leaves five" do
    go_ranks
    recommended

    expect(Personalization::Client).to have_received(:recommended_event_ids).with(user_id: user.id, limit: 20)
  end

  it "leaves out an event the user cannot see" do
    hidden = event("Partners only", visibility: "organization_restricted")
    open = event("Open")
    go_ranks(hidden, open)

    expect(recommended).to eq([open])
  end

  it "leaves out cancelled, draft and past events, even when the user can still see them" do
    cancelled = event("Called off")
    Events::Cancel.new(event: cancelled).call
    draft = event("Draft", status: "draft")
    past = event("Over", starts_at: 2.days.ago)
    open = event("Open")
    go_ranks(cancelled, draft, past, open)

    expect(recommended).to eq([open])
  end

  it "leaves out a draft even for an admin of its organization, who can see it" do
    OrganizationMembership.create!(user: user, organization: organization, role: "admin")
    draft = event("Our draft", status: "draft")
    open = event("Open")
    go_ranks(draft, open)

    expect(Pundit.policy_scope!(user, Event)).to include(draft)
    expect(recommended).to eq([open])
  end

  it "leaves out events the user is registered for, but not ones they cancelled" do
    booked = event("Booked")
    changed_mind = event("Changed my mind")
    Events::Register.new(user: user, event: booked).call
    Events::Register.new(user: user, event: changed_mind).call
    Registrations::Cancel.new(user: user, event: changed_mind).call
    go_ranks(booked, changed_mind)

    expect(recommended).to eq([changed_mind.reload])
  end

  it "leaves out a full event" do
    full = event("Sold out")
    full.update!(capacity: 1, reserved_spots: 1)
    open = event("Open")
    go_ranks(full, open)

    expect(recommended).to eq([open])
  end

  it "returns at most five" do
    go_ranks(*Array.new(7) { |index| event("Session #{index}") })

    expect(recommended.size).to eq(5)
  end

  it "returns nothing when Go has nothing" do
    go_ranks

    expect(recommended).to eq([])
  end
end
