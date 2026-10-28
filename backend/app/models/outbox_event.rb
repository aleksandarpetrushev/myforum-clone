class OutboxEvent < ApplicationRecord
  STATUSES = %w[pending published].freeze
  NOTIFICATION_OUTCOMES = %w[delivered suppressed].freeze

  validates :event_type, :aggregate_type, :aggregate_id, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :notification_outcome, inclusion: { in: NOTIFICATION_OUTCOMES }, allow_nil: true
  validates :idempotency_key, uniqueness: true

  scope :pending, -> { where(status: "pending") }

  def self.record!(attrs)
    create!(attrs)
  rescue ActiveRecord::RecordNotUnique
    find_by!(idempotency_key: attrs[:idempotency_key] || attrs["idempotency_key"])
  end

  # For facts that happen once per aggregate, such as EventPublished: a repeated key returns the existing row.
  # Keys that must be unique per change keep using record!, so a collision fails loudly instead of dropping data.
  def self.record_once!(attrs)
    find_by(idempotency_key: attrs[:idempotency_key] || attrs["idempotency_key"]) || record!(attrs)
  end
end
