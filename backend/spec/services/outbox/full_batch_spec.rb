require "rails_helper"

RSpec.describe "Outbox::Publisher#full_batch?" do
  def pending_row(key)
    OutboxEvent.create!(event_type: "TopicFollowed", aggregate_type: "TopicFollow", aggregate_id: 1,
                        idempotency_key: key, payload: { "user_id" => 1, "topic_id" => 1, "user_location" => "Berlin" })
  end

  before { stub_const("Outbox::Publisher::BATCH_SIZE", 2) }

  it "is true when a pass read a whole batch, and the next pass carries on with the rest" do
    3.times { |i| pending_row("topic_followed:test:#{i}") }
    publisher = Outbox::Publisher.new

    expect(publisher.call).to eq(2)
    expect(publisher.full_batch?).to be(true)
    expect(publisher.call).to eq(1)
    expect(publisher.full_batch?).to be(false)
    expect(OutboxEvent.pending.count).to eq(0)
  end

  it "is false before any pass" do
    expect(Outbox::Publisher.new.full_batch?).to be(false)
  end
end
