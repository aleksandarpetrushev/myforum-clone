class OutboxEvent < ApplicationRecord
  STATUSES = %w[pending published].freeze

  validates :event_type, :aggregate_type, :aggregate_id, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true

  scope :pending, -> { where(status: "pending") }

  def self.record!(attrs)
    create!(attrs)
  rescue ActiveRecord::RecordNotUnique
    find_by!(idempotency_key: attrs[:idempotency_key] || attrs["idempotency_key"])
  end
end
