require "rails_helper"

RSpec.describe "waitlist offer expiry" do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 1, status: "published"
    )
  end
  let(:holder) { person("holder") }
  let(:ana) { person("ana") }
  let(:ben) { person("ben") }

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password")
  def registration_of(user) = Registration.find_by!(user: user, event: event)

  # The holder cancels, so ana (first in line) is offered the seat and ben waits.
  before do
    Events::Register.new(user: holder, event: event).call
    travel(-2.minutes) { Waitlist::Join.new(user: ana, event: event).call }
    travel(-1.minute) { Waitlist::Join.new(user: ben, event: event).call }
    Registrations::Cancel.new(user: holder, event: event).call
  end

  it "schedules the expiry at the offer's deadline" do
    offer = registration_of(ana)

    expect(ExpireWaitlistOfferJob).to have_been_enqueued
      .with(offer.id, offer.lifecycle_version).at(offer.offer_expires_at)
  end

  it "expires a lapsed offer, tells the person, and offers the seat to the next in line" do
    offer = registration_of(ana)

    travel_to(offer.offer_expires_at + 1.second) do
      ExpireWaitlistOfferJob.perform_now(offer.id, offer.lifecycle_version)
    end

    expect(offer.reload).to have_attributes(status: "cancelled", cancelled_by: "offer_expired")
    expect(registration_of(ben).status).to eq("offered")
    expect(event.reload.reserved_spots).to eq(1)
    expect(OutboxEvent.where(event_type: "WaitlistOfferExpired", aggregate_id: offer.id).count).to eq(1)
    expect(ExpireWaitlistOfferJob).to have_been_enqueued.with(registration_of(ben).id, registration_of(ben).lifecycle_version)
  end

  it "does nothing for an offer that was accepted before its job ran" do
    offer = registration_of(ana)
    Waitlist::AcceptOffer.new(user: ana, event: event).call

    travel_to(offer.offer_expires_at + 1.second) do
      expect { ExpireWaitlistOfferJob.perform_now(offer.id, offer.lifecycle_version) }.not_to change(OutboxEvent, :count)
    end
    expect(offer.reload.status).to eq("confirmed")
  end

  it "reschedules itself when it runs before the deadline" do
    offer = registration_of(ana)
    clear_enqueued_jobs

    ExpireWaitlistOfferJob.perform_now(offer.id, offer.lifecycle_version)

    expect(offer.reload.status).to eq("offered")
    expect(ExpireWaitlistOfferJob).to have_been_enqueued.with(offer.id, offer.lifecycle_version).at(offer.offer_expires_at)
  end

  it "catches an offer whose job was lost, and the metric shows it until then" do
    offer = registration_of(ana)
    clear_enqueued_jobs

    travel_to(offer.offer_expires_at + 2.minutes) do
      expect(Metrics.overdue_waitlist_offers).to eq(1)
      expect(Waitlist::ExpireOverdue.call).to eq(1)
      expect(Metrics.overdue_waitlist_offers).to eq(0)
    end
    expect(offer.reload.cancelled_by).to eq("offer_expired")
    expect(registration_of(ben).status).to eq("offered")
  end
end
