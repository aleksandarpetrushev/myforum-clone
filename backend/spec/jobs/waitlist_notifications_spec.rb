require "rails_helper"

RSpec.describe "waitlist notifications" do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Popular session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 1, status: "published"
    )
  end
  let(:holder) { User.create!(email: "holder@example.com", name: "Holder", password: "password") }
  let(:ana) { User.create!(email: "ana@example.com", name: "Ana", password: "password") }

  def publish = perform_enqueued_jobs(only: [SendNotificationJob, RecordAnalyticsJob]) { Outbox::Publisher.new.call }

  before do
    Events::Register.new(user: holder, event: event).call
    Waitlist::Join.new(user: ana, event: event).call
    Registrations::Cancel.new(user: holder, event: event).call
  end

  it "tells the person offered a seat, even with registration notifications switched off" do
    NotificationPreference.update_for(ana, "registration_confirmed_enabled" => false, "registration_cancelled_enabled" => false)
    publish

    notification = Notification.find_by!(user: ana, kind: "waitlist_offered")
    expect(notification.body).to include("Popular session")
    expect(AnalyticsEvent.where(name: "WaitlistOffered").count).to eq(1)
  end

  it "tells the person whose offer expired" do
    offer = Registration.find_by!(user: ana, event: event)
    travel_to(offer.offer_expires_at + 1.second) { Waitlist::ExpireOffer.call(offer.id, offer.lifecycle_version) }
    publish

    expect(Notification.where(user: ana).pluck(:kind)).to contain_exactly("waitlist_offered", "waitlist_offer_expired")
  end

  it "tells only the person offered, not the canceller about the offer nor anyone still waiting" do
    ben = User.create!(email: "ben@example.com", name: "Ben", password: "password")
    Waitlist::Join.new(user: ben, event: event).call
    publish

    expect(Notification.where(user: ben)).to be_empty
    expect(Notification.where(user: holder).pluck(:kind)).to eq(%w[registration_confirmed registration_cancelled])
  end
end
