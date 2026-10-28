class Event < ApplicationRecord
  KINDS = %w[online in_person].freeze
  STATUSES = %w[draft published cancelled].freeze
  VISIBILITIES = %w[public organization_restricted].freeze

  belongs_to :organization
  has_many :event_topics, dependent: :destroy
  has_many :topics, through: :event_topics
  has_many :event_speakers, dependent: :destroy
  has_many :speakers, through: :event_speakers
  has_many :registrations, dependent: :destroy
  has_many :event_allowed_organizations, dependent: :destroy
  has_many :allowed_organizations, through: :event_allowed_organizations, source: :organization

  validates :title, :description, :location, :starts_at, :ends_at, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :reserved_spots, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ends_after_start
  validate :spots_within_capacity
  validate :status_follows_machine

  after_commit :invalidate_event_caches, on: %i[create update destroy]

  # The only status changes a saved event may make. initial matches the column default, which seeds and
  # insert_all rely on; the API defaults new events to draft in Events::Create.
  state_machine :status, initial: :published do
    state :draft
    state :published
    state :cancelled

    event :publish do
      transition draft: :published
    end

    event :cancel do
      transition published: :cancelled
    end

    # Only Events::Cancel fires this event; it also writes EventCancelled, which starts the registration cascade.
    before_transition on: :cancel do |event|
      event.cancelled_at = Time.current
      event.cancelling_through_event = true
    end

    after_transition on: :cancel do |event|
      event.cancelling_through_event = false
    end
  end

  attr_accessor :cancelling_through_event

  # starts_at is not unique. id keeps offset pages stable when several events share a start.
  scope :in_start_order, -> { order(starts_at: :asc, id: :asc) }
  scope :published, -> { where(status: "published") }
  scope :upcoming, -> { where("starts_at >= ?", Time.current) }
  scope :in_location, ->(location) { where(location: location) }
  scope :with_topic, ->(topic_id) { joins(:event_topics).where(event_topics: { topic_id: topic_id }) }
  scope :matching_text, ->(query) {
    term = "%#{sanitize_sql_like(query.to_s.strip)}%"
    where("events.title ILIKE :term OR events.description ILIKE :term", term: term)
  }

  def snapshot
    {
      "id" => id,
      "title" => title,
      "location" => location,
      "starts_at" => starts_at&.iso8601,
      "status" => status,
      "reserved_spots" => reserved_spots,
      "capacity" => capacity,
      "topic_ids" => topic_ids,
      "visibility" => visibility,
      "organization_id" => organization_id,
      "allowed_organization_ids" => allowed_organization_ids
    }
  end

  def as_list_json
    {
      "id" => id,
      "title" => title,
      "starts_at" => starts_at,
      "ends_at" => ends_at,
      "location" => location,
      "kind" => kind,
      "capacity" => capacity,
      "reserved_spots" => reserved_spots,
      "status" => status,
      "cancelled_at" => cancelled_at,
      "visibility" => visibility,
      "organization" => { "id" => organization_id, "name" => organization.name },
      "topics" => topics.map { |topic| { "id" => topic.id, "name" => topic.name, "slug" => topic.slug } }
    }
  end

  def as_detail_json
    as_list_json.merge(
      "description" => description,
      "speakers" => speakers.map { |speaker| { "id" => speaker.id, "name" => speaker.name, "title" => speaker.title } }
    )
  end

  private

  def invalidate_event_caches
    Events::Cache.invalidate(id)
  end

  def ends_after_start
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, :ends_before_start) if ends_at <= starts_at
  end

  # Plain writes such as update!(status: ...) skip the machine's events, so check them against the machine too.
  # Cancelling is stricter: it must come through the cancel event (Events::Cancel), never a plain write, or the
  # event would end up cancelled with no cancelled_at, no EventCancelled row and registrations never cancelled.
  # A new record has no transition: Events::Create decides its starting status.
  def status_follows_machine
    return if new_record? || !status_changed? || !STATUSES.include?(status)

    allowed = status_transitions(from: status_was.to_sym, to: status.to_sym).any?
    allowed &&= cancelling_through_event if status == "cancelled"
    errors.add(:status, :invalid_transition) unless allowed
  end

  def spots_within_capacity
    return if reserved_spots.blank? || capacity.blank?
    errors.add(:reserved_spots, "cannot exceed capacity") if reserved_spots > capacity
  end
end

