class AnalyticsEvent < ApplicationRecord
  belongs_to :outbox_event

  validates :name, presence: true
  validates :outbox_event_id, uniqueness: true
end
