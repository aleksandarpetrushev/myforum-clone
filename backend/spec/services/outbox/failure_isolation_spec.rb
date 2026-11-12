require "rails_helper"

# MF-204: on 12 November the personalization service was down for 30 minutes and the whole outbox stopped for 63,
# because one failed delivery failed the poller and Sidekiq's backoff kept it off. A failure must now stay with its
# row, and with the rows that must follow it.
RSpec.describe "outbox failure isolation" do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { Organization.create!(name: "Lumen", slug: "lumen") }

  def event(title)
    Event.create!(
      organization: organization, title: title, description: "Talk", starts_at: 4.days.from_now,
      ends_at: 4.days.from_now + 1.hour, location: "Berlin", kind: "in_person", capacity: 5, status: "published"
    )
  end

  def person(name) = User.create!(email: "#{name}@example.com", name: name, password: "password", location: "Berlin")

  # Go refuses connections for rows about the given event ids, and accepts everything else.
  def go_down_for(*event_ids)
    allow(Rails.application.config.x).to receive(:personalization_delivery).and_return("http")
    allow(Personalization::Http).to receive(:post_json) do |_path, body:, **|
      if event_ids.include?(body.dig("payload", "event_id") || body.dig("payload", "event", "id"))
        raise Errno::ECONNREFUSED
      end
      Net::HTTPNoContent.new("1.1", "204", "No Content")
    end
  end

  def publish = perform_enqueued_jobs(only: [SendNotificationJob, RecordAnalyticsJob]) { Outbox::Publisher.new.call }

  let(:broken) { event("Broken") }
  let(:healthy) { event("Healthy") }
  let(:ana) { person("ana") }
  let(:ben) { person("ben") }

  it "keeps delivering other rows, and their notifications, while one event's rows fail" do
    Events::Register.new(user: ana, event: broken).call
    Events::Register.new(user: ben, event: healthy).call
    go_down_for(broken.id)

    expect { publish }.not_to raise_error

    failed = OutboxEvent.find_by!(aggregate_id: Registration.find_by!(user: ana).id)
    expect(failed).to have_attributes(status: "pending", attempts: 1)
    expect(failed.next_attempt_at).to be > Time.current
    expect(OutboxEvent.find_by!(aggregate_id: Registration.find_by!(user: ben).id).status).to eq("published")
    expect(Notification.where(user: ben).count).to eq(1)
  end

  it "holds later rows for the same event behind the failed one, and delivers them in order once it recovers" do
    Events::Register.new(user: ana, event: broken).call
    go_down_for(broken.id)
    publish
    Events::Register.new(user: ben, event: broken).call

    publish
    rows = OutboxEvent.where(event_type: "RegistrationCreated").order(:id)
    expect(rows.pluck(:status)).to eq(%w[pending pending])
    expect(rows.last.attempts).to eq(0)

    go_down_for
    travel(Outbox::Publisher.backoff(1) + 1.second) { publish }
    expect(rows.reload.pluck(:status)).to eq(%w[published published])
    expect(rows.first.published_at).to be <= rows.last.published_at
  end

  it "keeps a user's topic follow and unfollow in order" do
    topic = Topic.create!(name: "Climate", slug: "climate")
    allow(Rails.application.config.x).to receive(:personalization_delivery).and_return("http")
    calls = 0
    allow(Personalization::Http).to receive(:post_json) do
      calls += 1
      raise Errno::ECONNREFUSED if calls == 1 # the follow fails once

      Net::HTTPNoContent.new("1.1", "204", "No Content")
    end
    Topics::Follow.new(user: ana, topic: topic).call
    Topics::Unfollow.new(user: ana, topic: topic).call

    publish
    expect(OutboxEvent.order(:id).pluck(:event_type, :status)).to eq([%w[TopicFollowed pending], %w[TopicUnfollowed pending]])

    travel(Outbox::Publisher.backoff(1) + 1.second) { publish }
    delivered = OutboxEvent.order(:published_at, :id).pluck(:event_type)
    expect(delivered).to eq(%w[TopicFollowed TopicUnfollowed])
  end

  it "backs off each row on its own, up to five minutes" do
    expect((1..10).map { |n| Outbox::Publisher.backoff(n).to_i }).to eq([2, 4, 8, 16, 32, 64, 128, 256, 300, 300])
  end

  describe "stall alerts" do
    it "measures how long pending rows have waited with nothing published" do
      Events::Register.new(user: ana, event: broken).call
      go_down_for(broken.id)

      travel(3.minutes) do
        publish
        expect(Metrics.outbox_stall_seconds).to be_within(2).of(180)
      end
    end

    it "is 0 while the outbox flows or is empty" do
      expect(Metrics.outbox_stall_seconds).to eq(0)
      Events::Register.new(user: ben, event: healthy).call
      go_down_for
      publish
      expect(Metrics.outbox_stall_seconds).to eq(0)
    end

    it "counts rows that have failed five times or more" do
      Events::Register.new(user: ana, event: broken).call
      OutboxEvent.last.update_columns(attempts: 5)

      expect(Metrics.outbox_rows_failing).to eq(1)
    end
  end
end
