class Registration < ApplicationRecord
  STATUSES = %w[pending confirmed cancelled failed].freeze

  belongs_to :user
  belongs_to :event

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :event_id }

  def as_json_api
    {
      "id" => id,
      "status" => status,
      "event_id" => event_id,
      "user_id" => user_id,
      "created_at" => created_at,
      "event" => event && {
        "id" => event.id,
        "title" => event.title,
        "starts_at" => event.starts_at,
        "location" => event.location
      }
    }
  end
end
