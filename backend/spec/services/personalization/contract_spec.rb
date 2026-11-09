require "rails_helper"

RSpec.describe Personalization::Contract do
  let(:organization) { Organization.create!(name: "Atlas", slug: "atlas") }
  let(:user) { User.create!(email: "contract@example.com", name: "Contract", password: "password") }
  let(:topic) { Topic.create!(name: "Climate", slug: "climate") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Session", description: "Talk",
      starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour, location: "Geneva",
      kind: "in_person", capacity: 10, status: "draft"
    )
  end

  it "produces a valid envelope for each of the seven event types" do
    event.topics << topic
    Events::Update.new(event: event, attributes: { "status" => "published" }).call
    Events::Register.new(user: user, event: event).call
    Registrations::Cancel.new(user: user, event: event).call
    Topics::Follow.new(user: user, topic: topic).call
    Topics::Unfollow.new(user: user, topic: topic).call
    Events::Cancel.new(event: event).call

    rows = OutboxEvent.order(:id).to_a
    expect(rows.map(&:event_type)).to match_array(
      %w[EventUpdated EventPublished RegistrationCreated RegistrationCancelled TopicFollowed TopicUnfollowed EventCancelled]
    )
    rows.each { |row| expect(PersonalizationContract.errors_for(row)).to eq([]), row.event_type }
  end

  it "reports a payload that breaks the contract" do
    row = OutboxEvent.new(
      event_type: "EventUpdated", aggregate_type: "Event", aggregate_id: event.id, idempotency_key: "event_updated:x",
      payload: { "event" => event.snapshot.except("starts_at") }
    )

    expect(PersonalizationContract.errors_for(row).join).to include("starts_at")
  end

  it "stores the version when the row is written, and sends that version" do
    old_row = OutboxEvent.create!(
      event_type: "TopicUnfollowed", aggregate_type: "TopicFollow", aggregate_id: 1, idempotency_key: "old",
      payload: { "user_id" => user.id, "topic_id" => topic.id }
    )
    stub_const("Personalization::Contract::VERSION", 2)
    new_row = OutboxEvent.create!(
      event_type: "TopicUnfollowed", aggregate_type: "TopicFollow", aggregate_id: 2, idempotency_key: "new",
      payload: { "user_id" => user.id, "topic_id" => topic.id }
    )

    expect([old_row.reload.schema_version, new_row.reload.schema_version]).to eq([1, 2])

    sent = []
    allow(Rails.application.config.x).to receive(:personalization_delivery).and_return("http")
    allow(Personalization::Http).to receive(:post_json) do |_path, body:, **|
      sent << body
      Net::HTTPNoContent.new("1.1", "204", "No Content")
    end
    Personalization::DeliverEvent.call(old_row)

    expect(sent.sole).to include("schema_version" => 1, "idempotency_key" => "old", "event_type" => "TopicUnfollowed")
    # Row "new" was written as version 2 only to test storage; the hook must not judge it against version 1.
    new_row.destroy!
  end
end
