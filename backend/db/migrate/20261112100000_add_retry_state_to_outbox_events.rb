class AddRetryStateToOutboxEvents < ActiveRecord::Migration[7.1]
  # MF-204: a row whose delivery fails backs off on its own instead of stopping the poller for every row.
  def change
    add_column :outbox_events, :attempts, :integer, null: false, default: 0
    add_column :outbox_events, :next_attempt_at, :datetime
    add_column :outbox_events, :last_error, :string
  end
end
