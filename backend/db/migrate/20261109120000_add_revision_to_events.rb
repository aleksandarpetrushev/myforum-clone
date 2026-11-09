class AddRevisionToEvents < ActiveRecord::Migration[7.1]
  def change
    # Incremented by every change to the event row (edits, cancellation, seat counts). Keys EventUpdated and
    # lets Go keep the newest snapshot when outbox rows arrive out of order.
    add_column :events, :revision, :integer, null: false, default: 0
  end
end
