class AddRegistrationLifecycleVersion < ActiveRecord::Migration[7.1]
  def up
    execute "UPDATE registrations SET status = 'confirmed' WHERE status = 'pending'"
    remove_check_constraint :registrations, name: "registrations_status_valid"
    add_check_constraint :registrations,
                         "status IN ('confirmed', 'cancelled', 'failed')",
                         name: "registrations_status_valid"
    add_column :registrations, :lifecycle_version, :integer, null: false, default: 1
  end

  def down
    remove_column :registrations, :lifecycle_version
    remove_check_constraint :registrations, name: "registrations_status_valid"
    add_check_constraint :registrations,
                         "status IN ('pending', 'confirmed', 'cancelled', 'failed')",
                         name: "registrations_status_valid"
  end
end
