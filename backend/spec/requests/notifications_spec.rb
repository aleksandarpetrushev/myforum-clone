require "rails_helper"

RSpec.describe "notification center", type: :request do
  let(:user) { User.create!(email: "alex@example.com", name: "Alex", password: "password") }
  let(:other) { User.create!(email: "other@example.com", name: "Other", password: "password") }

  def notify(owner, key, created_at:, read_at: nil)
    Notification.create!(
      user: owner,
      kind: "registration_confirmed",
      title: "Registration confirmed",
      body: "You are registered for Forum #{key}.",
      idempotency_key: "notification:#{key}",
      created_at: created_at,
      updated_at: created_at,
      read_at: read_at
    )
  end

  it "pages the caller's notifications newest first and reports the unread count" do
    base = Time.zone.parse("2026-01-01 00:00:00")
    created = 21.times.map { |index| notify(user, "page-#{index}", created_at: base + index.minutes) }
    notify(other, "someone-else", created_at: base + 1.day)

    get "/api/me/notifications", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    ids = json_body["data"].map { |row| row["id"] }
    expect(ids).to eq(created.reverse.first(20).map(&:id))
    expect(json_body["unread_count"]).to eq(21)
    expect(json_body["next_cursor"]).to be_present
    expect(ids).not_to include(Notification.find_by!(idempotency_key: "notification:someone-else").id)

    get "/api/me/notifications", params: { cursor: json_body["next_cursor"] }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json_body["data"].map { |row| row["id"] }).to eq([created.first.id])
    expect(json_body["next_cursor"]).to be_nil
  end

  it "pages notifications that share a timestamp by id" do
    stamp = Time.zone.parse("2026-03-01 12:00:00")
    created = 21.times.map { |index| notify(user, "tie-#{index}", created_at: stamp) }

    get "/api/me/notifications", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    ids = json_body["data"].map { |row| row["id"] }
    expect(ids).to eq(created.reverse.first(20).map(&:id))

    get "/api/me/notifications", params: { cursor: json_body["next_cursor"] }, headers: auth_headers(user)

    second = json_body["data"].map { |row| row["id"] }
    expect(second).to eq([created.first.id])
    expect(ids & second).to be_empty
    expect(json_body["next_cursor"]).to be_nil
  end

  it "rejects a cursor that does not decode" do
    get "/api/me/notifications", params: { cursor: "not-a-cursor" }, headers: auth_headers(user)

    expect(response).to have_http_status(:bad_request)
    expect(json_body.dig("error", "code")).to eq("invalid_cursor")
  end

  it "marks one notification read once and hides another user's row" do
    notification = notify(user, "one", created_at: Time.current)
    foreign = notify(other, "foreign", created_at: Time.current)

    post "/api/me/notifications/#{foreign.id}/read", headers: auth_headers(user)
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.read_at).to be_nil

    post "/api/me/notifications/#{notification.id}/read", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    read_at = Time.zone.parse(json_body["read_at"])
    expect(json_body["unread_count"]).to eq(0)

    post "/api/me/notifications/#{notification.id}/read", headers: auth_headers(user)
    expect(Time.zone.parse(json_body["read_at"])).to eq(read_at)
  end

  it "marks every unread notification read without moving an existing timestamp" do
    already = notify(user, "read", created_at: 2.days.ago, read_at: Time.zone.parse("2026-02-01 12:00:00"))
    pending = notify(user, "unread", created_at: 1.day.ago)
    stored = already.reload.read_at

    post "/api/me/notifications/read_all", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json_body["unread_count"]).to eq(0)
    expect(already.reload.read_at).to eq(stored)
    expect(pending.reload.read_at).to be_present
    marked = pending.read_at

    post "/api/me/notifications/read_all", headers: auth_headers(user)
    expect(pending.reload.read_at).to eq(marked)
    expect(already.reload.read_at).to eq(stored)
  end

  it "keeps preferences enabled until the user stores a change" do
    get "/api/me/notification_preferences", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json_body).to eq(
      "registration_confirmed_enabled" => true,
      "registration_cancelled_enabled" => true
    )
    expect(NotificationPreference.count).to eq(0)

    patch "/api/me/notification_preferences",
          params: { notification_preference: { registration_confirmed_enabled: false } },
          headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(json_body["registration_confirmed_enabled"]).to be(false)
    expect(json_body["registration_cancelled_enabled"]).to be(true)
    expect(user.reload.notification_preference.registration_confirmed_enabled).to be(false)
  end
end
