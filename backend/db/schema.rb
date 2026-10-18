# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_18_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "analytics_events", force: :cascade do |t|
    t.bigint "outbox_event_id", null: false
    t.string "name", null: false
    t.bigint "user_id"
    t.jsonb "properties", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["outbox_event_id"], name: "index_analytics_events_on_outbox_event_id", unique: true
  end

  create_table "event_speakers", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "speaker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "speaker_id"], name: "index_event_speakers_on_event_id_and_speaker_id", unique: true
    t.index ["event_id"], name: "index_event_speakers_on_event_id"
    t.index ["speaker_id"], name: "index_event_speakers_on_speaker_id"
  end

  create_table "event_topics", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "topic_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "topic_id"], name: "index_event_topics_on_event_id_and_topic_id", unique: true
    t.index ["event_id"], name: "index_event_topics_on_event_id"
    t.index ["topic_id"], name: "index_event_topics_on_topic_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "location", null: false
    t.string "kind", null: false
    t.integer "capacity", null: false
    t.integer "reserved_spots", default: 0, null: false
    t.string "status", default: "published", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location"], name: "index_events_on_location"
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.index ["starts_at"], name: "index_events_on_starts_at"
    t.index ["status"], name: "index_events_on_status"
    t.check_constraint "capacity > 0", name: "events_capacity_positive"
    t.check_constraint "ends_at > starts_at", name: "events_ends_after_start"
    t.check_constraint "kind::text = ANY (ARRAY['online'::character varying, 'in_person'::character varying]::text[])", name: "events_kind_valid"
    t.check_constraint "reserved_spots >= 0 AND reserved_spots <= capacity", name: "events_reserved_within_capacity"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'cancelled'::character varying]::text[])", name: "events_status_valid"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "idempotency_key", null: false
    t.datetime "read_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_notifications_on_idempotency_key", unique: true
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "organization_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "organization_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_memberships_on_user_and_organization", unique: true
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['member'::character varying, 'admin'::character varying]::text[])", name: "memberships_role_valid"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "outbox_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "aggregate_type", null: false
    t.bigint "aggregate_id", null: false
    t.string "idempotency_key", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_outbox_events_on_idempotency_key", unique: true
    t.index ["status", "created_at"], name: "index_outbox_events_on_status_and_created_at"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'published'::character varying]::text[])", name: "outbox_status_valid"
  end

  create_table "registrations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "event_id", null: false
    t.string "status", default: "confirmed", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_registrations_on_event_id"
    t.index ["user_id", "event_id"], name: "index_registrations_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_registrations_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'confirmed'::character varying, 'cancelled'::character varying, 'failed'::character varying]::text[])", name: "registrations_status_valid"
  end

  create_table "speakers", force: :cascade do |t|
    t.string "name", null: false
    t.string "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "topic_follows", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "topic_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["topic_id"], name: "index_topic_follows_on_topic_id"
    t.index ["user_id", "topic_id"], name: "index_topic_follows_on_user_id_and_topic_id", unique: true
    t.index ["user_id"], name: "index_topic_follows_on_user_id"
  end

  create_table "topics", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_topics_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "location"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
  end

  add_foreign_key "analytics_events", "outbox_events"
  add_foreign_key "event_speakers", "events"
  add_foreign_key "event_speakers", "speakers"
  add_foreign_key "event_topics", "events"
  add_foreign_key "event_topics", "topics"
  add_foreign_key "events", "organizations"
  add_foreign_key "notifications", "users"
  add_foreign_key "organization_memberships", "organizations"
  add_foreign_key "organization_memberships", "users"
  add_foreign_key "registrations", "events"
  add_foreign_key "registrations", "users"
  add_foreign_key "topic_follows", "topics"
  add_foreign_key "topic_follows", "users"
end
