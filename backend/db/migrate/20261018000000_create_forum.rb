class CreateForum < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.string :location
      t.timestamps
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"

    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :organizations, :slug, unique: true

    create_table :organization_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :organization_memberships, [:user_id, :organization_id],
              unique: true, name: "index_memberships_on_user_and_organization"
    add_check_constraint :organization_memberships, "role IN ('member', 'admin')", name: "memberships_role_valid"

    create_table :topics do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :topics, :slug, unique: true

    create_table :topic_follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.timestamps
    end
    add_index :topic_follows, [:user_id, :topic_id], unique: true

    create_table :speakers do |t|
      t.string :name, null: false
      t.string :title
      t.timestamps
    end

    create_table :events do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :location, null: false
      t.string :kind, null: false
      t.integer :capacity, null: false
      t.integer :reserved_spots, null: false, default: 0
      t.string :status, null: false, default: "published"
      t.timestamps
    end
    add_index :events, :starts_at
    add_index :events, :location
    add_index :events, :status
    add_check_constraint :events, "kind IN ('online', 'in_person')", name: "events_kind_valid"
    add_check_constraint :events, "status IN ('draft', 'published', 'cancelled')", name: "events_status_valid"
    add_check_constraint :events, "capacity > 0", name: "events_capacity_positive"
    add_check_constraint :events, "reserved_spots >= 0 AND reserved_spots <= capacity", name: "events_reserved_within_capacity"
    add_check_constraint :events, "ends_at > starts_at", name: "events_ends_after_start"

    create_table :event_topics do |t|
      t.references :event, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.timestamps
    end
    add_index :event_topics, [:event_id, :topic_id], unique: true

    create_table :event_speakers do |t|
      t.references :event, null: false, foreign_key: true
      t.references :speaker, null: false, foreign_key: true
      t.timestamps
    end
    add_index :event_speakers, [:event_id, :speaker_id], unique: true

    create_table :registrations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.string :status, null: false, default: "confirmed"
      t.timestamps
    end
    add_index :registrations, [:user_id, :event_id], unique: true
    add_check_constraint :registrations,
                         "status IN ('pending', 'confirmed', 'cancelled', 'failed')",
                         name: "registrations_status_valid"

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :idempotency_key, null: false
      t.datetime :read_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :notifications, :idempotency_key, unique: true
    add_index :notifications, [:user_id, :created_at]

    create_table :outbox_events do |t|
      t.string :event_type, null: false
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false
      t.string :idempotency_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :published_at
      t.timestamps
    end
    add_index :outbox_events, :idempotency_key, unique: true
    add_index :outbox_events, [:status, :created_at]
    add_check_constraint :outbox_events, "status IN ('pending', 'published')", name: "outbox_status_valid"

    create_table :analytics_events do |t|
      t.references :outbox_event, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.bigint :user_id
      t.jsonb :properties, null: false, default: {}
      t.timestamps
    end
  end
end
