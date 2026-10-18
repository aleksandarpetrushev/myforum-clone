require "rails_helper"

RSpec.describe Topics::Follow do
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password") }
  let(:topic) { Topic.create!(name: "Cities", slug: "cities") }

  it "creates one follow and one outbox event" do
    created = described_class.new(user: user, topic: topic).call

    expect(created).to be(true)
    expect(TopicFollow.where(user: user, topic: topic).count).to eq(1)
    expect(OutboxEvent.where(event_type: "TopicFollowed").count).to eq(1)
  end

  it "is idempotent when the user already follows the topic" do
    described_class.new(user: user, topic: topic).call

    expect {
      created = described_class.new(user: user, topic: topic).call
      expect(created).to be(false)
    }.not_to raise_error

    expect(TopicFollow.count).to eq(1)
    expect(OutboxEvent.where(event_type: "TopicFollowed").count).to eq(1)
  end
end
