require "rails_helper"

RSpec.describe Waitlist::OfferFreedSeats do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }

  def event(capacity:, reserved:, starts_in: 3.days, status: "published")
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: Time.current + starts_in, ends_at: Time.current + starts_in + 1.hour, location: "Geneva",
      kind: "in_person", capacity: capacity, reserved_spots: reserved, status: status
    )
  end

  def line(event, size)
    Array.new(size) do |index|
      user = User.create!(email: "w#{index}@example.com", name: "W#{index}", password: "password", location: "Davos")
      Registration.create!(user: user, event: event, status: "waitlisted", waitlisted_at: (size - index).minutes.ago,
                           lifecycle_version: 1)
    end
  end

  def offer(event)
    ApplicationRecord.transaction { described_class.call(Event.lock.find(event.id)) }
  end

  it "offers each free seat to the first in line, holds it, and bumps the revision once" do
    session = event(capacity: 5, reserved: 2)
    waiting = line(session, 5)

    offered = offer(session)

    expect(offered).to eq(waiting.first(3))
    expect(waiting.map { |r| r.reload.status }).to eq(%w[offered offered offered waitlisted waitlisted])
    expect(session.reload).to have_attributes(reserved_spots: 5, revision: 1)
    expect(OutboxEvent.where(event_type: "WaitlistOffered").pluck(:aggregate_id)).to match_array(waiting.first(3).map(&:id))
  end

  it "gives a day to confirm when the event is far off" do
    freeze_time do
      session = event(capacity: 1, reserved: 0, starts_in: 10.days)
      line(session, 1)

      offered = offer(session).sole
      expect(offered.offer_expires_at).to eq(Time.current + 24.hours)
      expect(offered.offered_at).to eq(Time.current)
    end
  end

  it "gives half the time to the start when that is shorter than a day" do
    freeze_time do
      session = event(capacity: 1, reserved: 0, starts_in: 6.hours)
      line(session, 1)

      expect(offer(session).sole.offer_expires_at).to eq(Time.current + 3.hours)
    end
  end

  it "offers nothing in the last hour, leaving the seat free" do
    session = event(capacity: 1, reserved: 0, starts_in: 59.minutes)
    waiting = line(session, 1)

    expect(offer(session)).to eq([])
    expect(waiting.first.reload.status).to eq("waitlisted")
    expect(session.reload.reserved_spots).to eq(0)
  end

  it "offers nothing for an event that is not published" do
    session = event(capacity: 1, reserved: 0, status: "draft")
    line(session, 1)

    expect(offer(session)).to eq([])
  end

  it "offers nothing when no seat is free or nobody is waiting" do
    full = event(capacity: 1, reserved: 1)
    line(full, 1)
    empty_line = event(capacity: 3, reserved: 0)

    expect(offer(full)).to eq([])
    expect(offer(empty_line)).to eq([])
    expect(empty_line.reload.revision).to eq(0)
  end
end
