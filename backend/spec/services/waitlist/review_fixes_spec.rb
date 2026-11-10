require "rails_helper"

# Cases found in the MF-202 code review.
RSpec.describe "waitlist edge cases" do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Popular session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 1, status: "published"
    )
  end
  let(:holder) { person("holder") }
  let(:ana) { person("ana") }
  let(:ben) { person("ben") }

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")
  def registration_of(user) = Registration.find_by!(user: user, event: event)

  def offer_to_ana
    Events::Register.new(user: holder, event: event).call
    Waitlist::Join.new(user: ana, event: event).call
    Registrations::Cancel.new(user: holder, event: event).call
    registration_of(ana)
  end

  describe "accepting" do
    it "is refused once the organizer has cancelled the event, before the cascade reaches the offer" do
      offer_to_ana
      Events::Cancel.new(event: event).call

      expect { Waitlist::AcceptOffer.new(user: ana, event: event).call }.to raise_error(Waitlist::AcceptOffer::NoOffer)
      expect(OutboxEvent.where(event_type: "RegistrationCreated", aggregate_id: registration_of(ana).id)).to be_empty
    end

    it "is refused once the event has started" do
      offer_to_ana
      event.update_columns(starts_at: 1.minute.ago)

      expect { Waitlist::AcceptOffer.new(user: ana, event: event).call }.to raise_error(Waitlist::AcceptOffer::NoOffer)
    end
  end

  describe "expiring an offer on a cancelled event" do
    it "leaves it to the cancellation cascade, so the person hears the event was cancelled" do
      offer = offer_to_ana
      Events::Cancel.new(event: event).call

      travel_to(offer.offer_expires_at + 1.second) { Waitlist::ExpireOffer.call(offer.id, offer.lifecycle_version) }
      expect(offer.reload.status).to eq("offered")
      expect(OutboxEvent.where(event_type: "WaitlistOfferExpired")).to be_empty

      CancelEventRegistrationsJob.perform_now(event.id)
      expect(offer.reload.cancelled_by).to eq("organizer")
      expect(Notification.find_by!(user: ana).kind).to eq("event_cancelled")
    end
  end

  describe "moving the start" do
    it "offers a seat left free in the closed last hour once the start moves later" do
      soon = Event.create!(
        organization: organization, title: "Soon", description: "Talk", starts_at: 50.minutes.from_now,
        ends_at: 2.hours.from_now, location: "Geneva", kind: "in_person", capacity: 1, status: "published"
      )
      travel_to(2.hours.ago) do
        Events::Register.new(user: holder, event: soon).call
        Waitlist::Join.new(user: ana, event: soon).call
      end
      Registrations::Cancel.new(user: holder, event: soon).call
      expect(Registration.find_by!(user: ana, event: soon).status).to eq("waitlisted")

      Events::Update.new(event: soon, attributes: { "starts_at" => 1.day.from_now, "ends_at" => 1.day.from_now + 1.hour }).call

      expect(Registration.find_by!(user: ana, event: soon).status).to eq("offered")
    end

    it "shortens an open offer that would end after the new start, and schedules the new deadline" do
      offer = offer_to_ana
      clear_enqueued_jobs

      freeze_time do
        Events::Update.new(event: event, attributes: { "starts_at" => 4.hours.from_now, "ends_at" => 5.hours.from_now }).call

        expect(offer.reload.offer_expires_at).to eq(2.hours.from_now)
        expect(ExpireWaitlistOfferJob).to have_been_enqueued.with(offer.id, offer.lifecycle_version).at(2.hours.from_now)
      end
    end
  end

  describe "the overdue sweep" do
    it "expires the rest when one offer fails, then reports the failure" do
      second = Event.create!(
        organization: organization, title: "Second", description: "Talk", starts_at: 3.days.from_now,
        ends_at: 3.days.from_now + 1.hour, location: "Geneva", kind: "in_person", capacity: 1, status: "published"
      )
      first_offer = offer_to_ana
      Events::Register.new(user: holder, event: second).call
      Waitlist::Join.new(user: ben, event: second).call
      Registrations::Cancel.new(user: holder, event: second).call
      second_offer = Registration.find_by!(user: ben, event: second)

      allow(Waitlist::ExpireOffer).to receive(:call).and_call_original
      allow(Waitlist::ExpireOffer).to receive(:call).with(first_offer.id, any_args).and_raise(ActiveRecord::LockWaitTimeout)

      travel_to(1.day.from_now + 1.hour) do
        expect { Waitlist::ExpireOverdue.call }.to raise_error(Waitlist::ExpireOverdue::IncompleteSweep, /#{first_offer.id}/)
      end
      expect(second_offer.reload.cancelled_by).to eq("offer_expired")
      expect(first_offer.reload.status).to eq("offered")
    end
  end
end
