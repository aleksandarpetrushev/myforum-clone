require "rails_helper"

RSpec.describe Registration do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 1, status: "published"
    )
  end

  def user(name)
    User.create!(email: "#{name}@example.com", name: name, password: "password")
  end

  def waitlist(name, at:)
    described_class.create!(user: user(name), event: event, status: "waitlisted", waitlisted_at: at, lifecycle_version: 1)
  end

  describe "waitlist states" do
    it "moves waitlisted to offered to confirmed" do
      registration = waitlist("ana", at: 1.hour.ago)
      registration.update!(offered_at: Time.current, offer_expires_at: 1.day.from_now)
      registration.offer!
      registration.accept_offer!

      expect(registration.reload.status).to eq("confirmed")
    end

    it "cancels from confirmed, waitlisted and offered" do
      %w[confirmed waitlisted offered].each_with_index do |status, index|
        registration = described_class.create!(
          user: user("u#{index}"), event: event, status: status, lifecycle_version: 1,
          waitlisted_at: Time.current, offered_at: Time.current, offer_expires_at: 1.day.from_now
        )
        registration.cancel!
        expect(registration.status).to eq("cancelled"), status
      end
    end

    it "rejoins the line from a cancelled registration, but not from a confirmed one" do
      registration = described_class.create!(user: user("ana"), event: event, status: "cancelled", lifecycle_version: 1)
      registration.waitlisted_at = Time.current
      expect(registration.join_waitlist).to be(true)

      confirmed = described_class.create!(user: user("ben"), event: event, status: "confirmed", lifecycle_version: 1)
      expect(confirmed.join_waitlist).to be(false)
    end

    it "is refused by the database without the times the states need" do
      expect { described_class.create!(user: user("ana"), event: event, status: "waitlisted", lifecycle_version: 1) }
        .to raise_error(ActiveRecord::StatementInvalid, /registrations_waitlisted_has_join_time/)
      expect {
        described_class.create!(user: user("ben"), event: event, status: "offered", lifecycle_version: 1, waitlisted_at: Time.current)
      }.to raise_error(ActiveRecord::StatementInvalid, /registrations_offered_has_deadline/)
    end
  end

  describe "#waitlist_position" do
    it "counts from join order, and closes up when someone leaves" do
      first = waitlist("ana", at: 3.minutes.ago)
      second = waitlist("ben", at: 2.minutes.ago)
      third = waitlist("cyd", at: 1.minute.ago)

      expect([first, second, third].map(&:waitlist_position)).to eq([1, 2, 3])

      second.cancel!
      expect([first.waitlist_position, third.waitlist_position]).to eq([1, 2])
      expect(second.reload.waitlist_position).to be_nil
    end

    it "orders joins in the same instant by id" do
      now = Time.current
      first = waitlist("ana", at: now)
      second = waitlist("ben", at: now)

      expect([first.waitlist_position, second.waitlist_position]).to eq([1, 2])
    end

    it "is only in the API for a waitlisted registration, when the caller passes it in" do
      registration = waitlist("ana", at: 1.minute.ago)
      expect(registration.as_json_api(event_visible: false, waitlist_position: 1)).to include("waitlist_position" => 1)
      expect(registration.as_json_api(event_visible: false)).not_to have_key("waitlist_position")
      expect(registration.as_json_api(event_visible: false)).not_to have_key("offer_expires_at")
    end

    it "computes many positions in one query" do
      other_event = Event.create!(
        organization: organization, title: "Other", description: "Talk", starts_at: 4.days.from_now,
        ends_at: 4.days.from_now + 1.hour, location: "Geneva", kind: "in_person", capacity: 1, status: "published"
      )
      first = waitlist("ana", at: 3.minutes.ago)
      second = waitlist("ben", at: 2.minutes.ago)
      elsewhere = described_class.create!(user: user("cyd"), event: other_event, status: "waitlisted",
                                          waitlisted_at: 1.minute.ago, lifecycle_version: 1)

      queries = 0
      counter = ->(*) { queries += 1 }
      positions = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.waitlist_positions([first, second, elsewhere])
      end

      expect(positions).to eq(first.id => 1, second.id => 2, elsewhere.id => 1)
      expect(queries).to eq(1)
    end
  end
end
