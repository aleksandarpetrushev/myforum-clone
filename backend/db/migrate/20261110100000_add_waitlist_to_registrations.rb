class AddWaitlistToRegistrations < ActiveRecord::Migration[7.1]
  # MF-202: the waitlist is two registration states. waitlisted_at orders the line (positions are computed from
  # it when read); an offer holds a seat until offer_expires_at.
  def up
    add_column :registrations, :waitlisted_at, :datetime
    add_column :registrations, :offered_at, :datetime
    add_column :registrations, :offer_expires_at, :datetime
    add_index :registrations, %i[event_id status waitlisted_at id], name: "index_registrations_on_waitlist_order"

    remove_check_constraint :registrations, name: "registrations_status_valid"
    add_check_constraint :registrations, "status IN ('confirmed', 'cancelled', 'failed', 'waitlisted', 'offered')",
                         name: "registrations_status_valid"
    remove_check_constraint :registrations, name: "registrations_cancelled_by_valid"
    add_check_constraint :registrations,
                         "cancelled_by IS NULL OR cancelled_by IN ('participant', 'organizer', 'offer_expired')",
                         name: "registrations_cancelled_by_valid"
    add_check_constraint :registrations, "status <> 'waitlisted' OR waitlisted_at IS NOT NULL",
                         name: "registrations_waitlisted_has_join_time"
    add_check_constraint :registrations, "status <> 'offered' OR (offered_at IS NOT NULL AND offer_expires_at IS NOT NULL)",
                         name: "registrations_offered_has_deadline"
  end

  def down
    remove_check_constraint :registrations, name: "registrations_offered_has_deadline"
    remove_check_constraint :registrations, name: "registrations_waitlisted_has_join_time"
    remove_check_constraint :registrations, name: "registrations_cancelled_by_valid"
    add_check_constraint :registrations, "cancelled_by IS NULL OR cancelled_by IN ('participant', 'organizer')",
                         name: "registrations_cancelled_by_valid"
    remove_check_constraint :registrations, name: "registrations_status_valid"
    add_check_constraint :registrations, "status IN ('confirmed', 'cancelled', 'failed')", name: "registrations_status_valid"
    remove_index :registrations, name: "index_registrations_on_waitlist_order"
    remove_column :registrations, :offer_expires_at
    remove_column :registrations, :offered_at
    remove_column :registrations, :waitlisted_at
  end
end
