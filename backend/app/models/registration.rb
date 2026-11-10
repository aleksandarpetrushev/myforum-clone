class Registration < ApplicationRecord
  # waitlisted and offered are the waitlist (MF-202, ADR 0008). An offered registration holds a seat.
  STATUSES = %w[confirmed cancelled failed waitlisted offered].freeze
  CANCELLERS = %w[participant organizer offer_expired].freeze
  # Registrations that hold a seat or a place in line, so the user counts as taking part.
  ACTIVE_STATUSES = %w[confirmed waitlisted offered].freeze
  SEAT_HOLDING_STATUSES = %w[confirmed offered].freeze

  belongs_to :user
  belongs_to :event

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :event_id }
  validates :lifecycle_version, numericality: { only_integer: true, greater_than: 0 }
  validates :cancelled_by, inclusion: { in: CANCELLERS }, allow_nil: true

  # The line for one event, first in line first. id breaks ties between joins in the same instant.
  scope :waitlisted_in_order, -> { where(status: "waitlisted").order(:waitlisted_at, :id) }

  state_machine :status, initial: :confirmed do
    state :confirmed
    state :cancelled
    state :failed
    state :waitlisted
    state :offered

    event :cancel do
      transition %i[confirmed waitlisted offered] => :cancelled
    end

    event :reconfirm do
      transition cancelled: :confirmed
    end

    event :join_waitlist do
      transition cancelled: :waitlisted
    end

    event :offer do
      transition waitlisted: :offered
    end

    event :accept_offer do
      transition offered: :confirmed
    end

    # A seat freed in the last hour, when the line is closed, goes to whoever registers first, including
    # someone still waiting in line.
    event :confirm_from_waitlist do
      transition waitlisted: :confirmed
    end
  end

  # 1 for the first in line. Computed from join order on each read rather than stored, so leaving the line
  # is one write and the number is never stale (ADR 0008).
  def waitlist_position
    return unless waitlisted?

    Registration.where(event_id: event_id, status: "waitlisted")
                .where("(waitlisted_at, id) < (?, ?)", waitlisted_at, id)
                .count + 1
  end

  # Positions for many waitlisted registrations in one query, keyed by id: one row per registration asked
  # about, each counting the earlier joiners of its own line through the waitlist index.
  def self.waitlist_positions(registrations)
    ids = registrations.select(&:waitlisted?).map(&:id)
    return {} if ids.empty?

    sql = sanitize_sql_array([<<~SQL.squish, ids])
      SELECT r.id,
             (SELECT COUNT(*) FROM registrations o
               WHERE o.event_id = r.event_id AND o.status = 'waitlisted'
                 AND (o.waitlisted_at, o.id) < (r.waitlisted_at, r.id)) + 1
        FROM registrations r
       WHERE r.id IN (?)
    SQL
    connection.select_rows(sql).to_h { |id, position| [id.to_i, position.to_i] }
  end

  # waitlist_position is passed in rather than computed here, so a list never runs one query per row.
  def as_json_api(event_visible: true, waitlist_position: nil)
    payload = {
      "id" => id,
      "status" => status,
      "cancelled_by" => cancelled_by,
      "event_id" => event_id,
      "user_id" => user_id,
      "created_at" => created_at
    }
    payload["waitlist_position"] = waitlist_position if waitlisted? && waitlist_position
    payload["offer_expires_at"] = offer_expires_at if offered?
    payload["event"] = event_summary if event_visible && event
    payload
  end

  def event_summary
    {
      "id" => event.id,
      "title" => event.title,
      "starts_at" => event.starts_at,
      "ends_at" => event.ends_at,
      "location" => event.location,
      # Lets the client show "Event cancelled" before the cancellation job reaches this registration.
      "status" => event.status
    }
  end
end
