require "rails_helper"

RSpec.describe SendNotificationJob do
  let(:organization) { Organization.create!(name: "Lumen", slug: "lumen") }
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password", location: "Berlin") }
  let(:event) do
    Event.create!(
      organization: organization,
      title: "Health forum",
      description: "Public session",
      starts_at: 4.days.from_now,
      ends_at: 4.days.from_now + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 5,
      status: "published"
    )
  end

  it "skips a notification disabled before the job runs and still records analytics" do
    Events::Register.new(user: user, event: event).call
    NotificationPreference.update_for(user, registration_confirmed_enabled: false)

    perform_enqueued_jobs { Outbox::Publisher.new.call }

    expect(Notification.where(user: user)).to be_empty
    expect(OutboxEvent.find_by!(event_type: "RegistrationCreated").notification_outcome).to eq("suppressed")
    expect(AnalyticsEvent.where(user_id: user.id, name: "RegistrationCreated").count).to eq(1)
  end

  it "does not deliver a suppressed event after the preference is enabled again" do
    Events::Register.new(user: user, event: event).call
    NotificationPreference.update_for(user, registration_confirmed_enabled: false)
    outbox = OutboxEvent.find_by!(event_type: "RegistrationCreated")

    perform_enqueued_jobs { Outbox::Publisher.new.call }
    NotificationPreference.update_for(user, registration_confirmed_enabled: true)
    described_class.perform_now(outbox.id)

    expect(Notification.where(user: user)).to be_empty
    expect(outbox.reload.notification_outcome).to eq("suppressed")
  end

  it "creates one notification when the job is performed twice" do
    Events::Register.new(user: user, event: event).call
    outbox = OutboxEvent.find_by!(event_type: "RegistrationCreated")

    2.times { described_class.perform_now(outbox.id) }

    expect(Notification.where(user: user, kind: "registration_confirmed").count).to eq(1)
    expect(outbox.reload.notification_outcome).to eq("delivered")
  end

  it "records delivery when a retry finds the notification already stored" do
    Events::Register.new(user: user, event: event).call
    outbox = OutboxEvent.find_by!(event_type: "RegistrationCreated")
    Notification.create!(
      user: user,
      kind: "registration_confirmed",
      title: "Registration confirmed",
      body: "You are registered for Health forum.",
      idempotency_key: "notification:#{outbox.idempotency_key}"
    )

    described_class.perform_now(outbox.id)

    expect(Notification.where(user: user).count).to eq(1)
    expect(outbox.reload.notification_outcome).to eq("delivered")
  end
end

RSpec.describe "notification preference lock" do
  self.use_transactional_tests = false

  after do
    Notification.delete_all
    NotificationPreference.delete_all
    OutboxEvent.delete_all
    Event.delete_all
    Organization.delete_all
    User.delete_all
  end

  it "does not create a notification when a preference update holds the user lock" do
    organization = Organization.create!(name: "Lumen", slug: "lumen-race")
    user = User.create!(email: "racer@example.com", name: "Racer", password: "password")
    event = Event.create!(
      organization: organization,
      title: "Health forum",
      description: "Public session",
      starts_at: 4.days.from_now,
      ends_at: 4.days.from_now + 2.hours,
      location: "Berlin",
      kind: "in_person",
      capacity: 5,
      status: "published"
    )
    outbox = OutboxEvent.create!(
      event_type: "RegistrationCreated",
      aggregate_type: "Registration",
      aggregate_id: 1,
      idempotency_key: "registration_created:race:1",
      payload: { "user_id" => user.id, "event_id" => event.id, "event" => { "title" => event.title } },
      status: "published"
    )
    ready = Queue.new
    release = Queue.new

    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        User.transaction do
          User.lock.find(user.id)
          ready << :locked
          release.pop
          NotificationPreference.find_or_initialize_by(user_id: user.id).update!(registration_confirmed_enabled: false)
        end
      end
    end
    ready.pop

    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        SendNotificationJob.perform_now(outbox.id)
      end
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      waiting = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT COUNT(*)
        FROM pg_stat_activity
        WHERE datname = current_database()
          AND pid <> pg_backend_pid()
          AND wait_event_type = 'Lock'
          AND query LIKE '%FOR UPDATE%'
      SQL
      break if waiting.to_i.positive?

      raise "notification job did not wait for the user lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end

    release << :go
    holder.value
    worker.value

    expect(Notification.where(user: user)).to be_empty
    expect(outbox.reload.notification_outcome).to eq("suppressed")
    expect(NotificationPreference.find_by!(user: user).registration_confirmed_enabled).to be(false)
  end
end
