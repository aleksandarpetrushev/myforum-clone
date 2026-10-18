class EventTopic < ApplicationRecord
  belongs_to :event
  belongs_to :topic

  validates :event_id, uniqueness: { scope: :topic_id }
end
