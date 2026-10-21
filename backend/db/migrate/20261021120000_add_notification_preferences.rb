class AddNotificationPreferences < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    create_table :notification_preferences, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :registration_confirmed_enabled, null: false, default: true
      t.boolean :registration_cancelled_enabled, null: false, default: true
      t.timestamps
    end

    # Build replacements before dropping the indexes that still serve list and
    # unread-count queries. A failed concurrent build can leave an INVALID index;
    # if_not_exists will not replace it. Drop that index concurrently and run again.
    add_index :notifications, [:user_id, :created_at, :id],
              order: { created_at: :desc, id: :desc },
              name: "index_notifications_on_user_id_and_created_at_and_id",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :notifications, :user_id,
              where: "read_at IS NULL",
              name: "index_notifications_on_user_id_unread",
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :notifications,
                 name: "index_notifications_on_user_id_and_created_at",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :notifications,
                 name: "index_notifications_on_user_id",
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :notifications, :user_id,
              name: "index_notifications_on_user_id",
              algorithm: :concurrently,
              if_not_exists: true
    add_index :notifications, [:user_id, :created_at],
              name: "index_notifications_on_user_id_and_created_at",
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :notifications,
                 name: "index_notifications_on_user_id_unread",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :notifications,
                 name: "index_notifications_on_user_id_and_created_at_and_id",
                 algorithm: :concurrently,
                 if_exists: true

    drop_table :notification_preferences, if_exists: true
  end
end
