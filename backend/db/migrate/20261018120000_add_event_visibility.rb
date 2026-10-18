class AddEventVisibility < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :visibility, :string, null: false, default: "public"
    add_check_constraint :events,
                         "visibility IN ('public', 'organization_restricted')",
                         name: "events_visibility_valid"

    create_table :event_allowed_organizations do |t|
      t.references :event, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.timestamps
    end
    add_index :event_allowed_organizations, [:event_id, :organization_id],
              unique: true,
              name: "index_event_allowed_organizations_on_event_and_org"
  end
end