class Registration < ApplicationRecord
  STATUSES = %w[confirmed cancelled failed].freeze

  belongs_to :user
  belongs_to :event

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :event_id }
  validates :lifecycle_version, numericality: { only_integer: true, greater_than: 0 }

  state_machine :status, initial: :confirmed do
    state :confirmed
    state :cancelled
    state :failed

    event :cancel do
      transition confirmed: :cancelled
    end

    event :reconfirm do
      transition cancelled: :confirmed
    end
  end

  def as_json_api(event_visible: true)
    payload = {
      "id" => id,
      "status" => status,
      "event_id" => event_id,
      "user_id" => user_id,
      "created_at" => created_at
    }
    payload["event"] = event_summary if event_visible && event
    payload
  end

  def event_summary
    {
      "id" => event.id,
      "title" => event.title,
      "starts_at" => event.starts_at,
      "location" => event.location
    }
  end
end
