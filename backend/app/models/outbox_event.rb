class OutboxEvent < ApplicationRecord
  # deferred: handled in-process, but the personalization service cannot read it yet (MF-203).
  STATUSES = %w[pending published deferred].freeze
  NOTIFICATION_OUTCOMES = %w[delivered suppressed].freeze

  # The contract version the payload is written in, fixed when the row is written (MF-203).
  attribute :schema_version, :integer, default: -> { Personalization::Contract::VERSION }

  validates :event_type, :aggregate_type, :aggregate_id, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :notification_outcome, inclusion: { in: NOTIFICATION_OUTCOMES }, allow_nil: true
  validates :idempotency_key, uniqueness: true

  scope :pending, -> { where(status: "pending") }
  scope :deferred, -> { where(status: "deferred") }

  # Rows with the same key must reach their consumers in order: a user's topic follows and unfollows, and an event's
  # changes. When one row is waiting to retry, later rows with its key wait too (MF-204).
  def ordering_key
    case event_type
    when "TopicFollowed", "TopicUnfollowed" then "user:#{payload["user_id"]}"
    else "event:#{payload["event_id"] || payload.dig("event", "id") || aggregate_id}"
    end
  end

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
