class AddEventCancelledEnabledToNotificationPreferences < ActiveRecord::Migration[7.1]
  def change
    add_column :notification_preferences, :event_cancelled_enabled, :boolean, default: true, null: false
  end
end
