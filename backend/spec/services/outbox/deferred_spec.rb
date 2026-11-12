require "rails_helper"

# MF-203: a row the personalization service cannot read yet is kept as deferred, not marked published and not
# left pending, and is sent again once the service understands it.
RSpec.describe "deferred outbox rows" do
  let(:organization) { Organization.create!(name: "Lumen", slug: "lumen") }
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password", location: "Berlin") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Health forum", description: "Public session",
      starts_at: 4.days.from_now, ends_at: 4.days.from_now + 2.hours, location: "Berlin",
      kind: "in_person", capacity: 5, status: "published"
    )
  end

  def go_answers(*answers)
    allow(Rails.application.config.x).to receive(:personalization_delivery).and_return("http")
    allow(Personalization::Http).to receive(:post_json).and_return(*answers.map { |answer| response(*answer) })
  end

  def response(code, error_code = nil)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    response = klass.new("1.1", code.to_s, "")
    body = error_code ? { error: { code: error_code, message: "…" } }.to_json : ""
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  it "keeps a row Go cannot read as deferred, still runs its notification, and moves on to the next row" do
    registration = Events::Register.new(user: user, event: event).call
    Topics::Follow.new(user: user, topic: Topic.create!(name: "Climate", slug: "climate")).call
    go_answers([422, "unsupported_contract"], [204])

    perform_enqueued_jobs { Outbox::Publisher.new.call }

    created = OutboxEvent.find_by!(event_type: "RegistrationCreated", aggregate_id: registration.id)
    expect(created).to have_attributes(status: "deferred", published_at: nil)
    expect(OutboxEvent.find_by!(event_type: "TopicFollowed").status).to eq("published")
    expect(Notification.where(user: user, kind: "registration_confirmed").count).to eq(1)
    expect(Metrics.outbox_deferred_count).to eq(1)
  end

  it "keeps a row that fails with any other error pending, to retry, without raising (MF-204)" do
    Events::Register.new(user: user, event: event).call
    go_answers([422, "invalid_json"])

    expect { Outbox::Publisher.new.call }.not_to raise_error
    expect(OutboxEvent.last).to have_attributes(status: "pending", attempts: 1)
    expect(OutboxEvent.last.last_error).to include("DeliveryError")
  end

  it "publishes deferred rows once Go can read them, and leaves the others deferred" do
    Events::Register.new(user: user, event: event).call
    Registrations::Cancel.new(user: user, event: event).call
    go_answers([422, "unsupported_contract"], [422, "unsupported_contract"])
    Outbox::Publisher.new.call
    expect(OutboxEvent.deferred.count).to eq(2)

    go_answers([204], [422, "unsupported_contract"])
    result = Outbox::RedeliverDeferred.new.call

    expect(result.to_h).to eq(delivered: 1, still_deferred: 1)
    expect(OutboxEvent.order(:id).pluck(:status)).to eq(%w[published deferred])
    expect(OutboxEvent.order(:id).first.published_at).to be_present
  end
end
