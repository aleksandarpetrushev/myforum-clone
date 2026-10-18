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

  validates :title, :description, :location, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :reserved_spots, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ends_after_start
  validate :spots_within_capacity

  after_commit :invalidate_event_caches, on: %i[create update destroy]

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
    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end

  def spots_within_capacity
    return if reserved_spots.blank? || capacity.blank?
    errors.add(:reserved_spots, "cannot exceed capacity") if reserved_spots > capacity
  end
end

