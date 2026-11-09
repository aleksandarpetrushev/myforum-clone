class AllowDeferredOutboxEvents < ActiveRecord::Migration[7.1]
  # deferred: dispatched to the in-process handlers, but the personalization service cannot read the row's
  # schema_version or event_type yet. Sent again by bin/rails outbox:redeliver_deferred (MF-203).
  def up
    remove_check_constraint :outbox_events, name: "outbox_status_valid"
    add_check_constraint :outbox_events, "status IN ('pending', 'published', 'deferred')", name: "outbox_status_valid"
  end

  def down
    remove_check_constraint :outbox_events, name: "outbox_status_valid"
    add_check_constraint :outbox_events, "status IN ('pending', 'published')", name: "outbox_status_valid"
  end
end
