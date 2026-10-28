class AddCancelledByToRegistrations < ActiveRecord::Migration[7.1]
  def up
    add_column :registrations, :cancelled_by, :string
    add_check_constraint :registrations,
                         "cancelled_by IS NULL OR cancelled_by IN ('participant', 'organizer')",
                         name: "registrations_cancelled_by_valid"
    # Every cancellation before this column existed was made by the participant.
    execute "UPDATE registrations SET cancelled_by = 'participant' WHERE status = 'cancelled'"
  end

  def down
    remove_check_constraint :registrations, name: "registrations_cancelled_by_valid"
    remove_column :registrations, :cancelled_by
  end
end
