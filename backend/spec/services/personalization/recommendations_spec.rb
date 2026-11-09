require "rails_helper"

RSpec.describe Personalization::Recommendations do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous
  end

  let(:user) { User.create!(email: "cached@example.com", name: "Cached", password: "password") }

  it "calls Go once within 30 seconds" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([1, 2])

    expect(described_class.ids_for(user)).to eq([1, 2])
    travel 29.seconds
    expect(described_class.ids_for(user)).to eq([1, 2])
    expect(Personalization::Client).to have_received(:recommended_event_ids).once
  end

  it "asks Go again after 30 seconds" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([1], [2])

    described_class.ids_for(user)
    travel 31.seconds
    expect(described_class.ids_for(user)).to eq([2])
  end

  it "serves the expired list when Go fails" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([1, 2])
    described_class.ids_for(user)
    travel 5.minutes
    allow(Personalization::Client).to receive(:recommended_event_ids).and_raise(Personalization::Unavailable, "timeout")

    expect(described_class.ids_for(user)).to eq([1, 2])
  end

  it "waits another 30 seconds before asking a failing Go again" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([1, 2])
    described_class.ids_for(user)
    travel 5.minutes
    allow(Personalization::Client).to receive(:recommended_event_ids).and_raise(Personalization::Unavailable, "timeout")

    described_class.ids_for(user)
    travel 29.seconds
    expect(described_class.ids_for(user)).to eq([1, 2])
    travel 2.seconds
    described_class.ids_for(user)

    # Once at 0 s (succeeded), once at 5 min (failed), not at 5 min 29 s, again at 5 min 31 s.
    expect(Personalization::Client).to have_received(:recommended_event_ids).exactly(3).times
  end

  it "ignores a cache entry it did not write and asks Go" do
    Rails.cache.write(described_class.cache_key(user), { "ids" => [9] })
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([4])

    expect(described_class.ids_for(user)).to eq([4])
  end

  it "raises when Go fails and nothing is cached" do
    allow(Personalization::Client).to receive(:recommended_event_ids).and_raise(Personalization::Unavailable, "timeout")

    expect { described_class.ids_for(user) }.to raise_error(Personalization::Unavailable)
  end

  it "calls Go instead of failing when the cache raises" do
    allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError)
    allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError)
    allow(Personalization::Client).to receive(:recommended_event_ids).and_return([3])

    expect(described_class.ids_for(user)).to eq([3])
  end
end
