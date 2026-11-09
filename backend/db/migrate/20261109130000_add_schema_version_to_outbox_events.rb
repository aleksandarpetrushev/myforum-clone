class AddSchemaVersionToOutboxEvents < ActiveRecord::Migration[7.1]
  def change
    # The Rails-Go contract version the payload was written in (MF-203). Rows that already exist are version 1.
    add_column :outbox_events, :schema_version, :integer, null: false, default: 1
  end
end
