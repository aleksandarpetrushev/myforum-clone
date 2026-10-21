class AddNotificationOutcomeToOutboxEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :outbox_events, :notification_outcome, :string
    add_check_constraint :outbox_events,
                         "notification_outcome IS NULL OR notification_outcome IN ('delivered', 'suppressed')",
                         name: "outbox_events_notification_outcome_valid"
  end
end