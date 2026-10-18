class EventSpeaker < ApplicationRecord
  belongs_to :event
  belongs_to :speaker

  validates :event_id, uniqueness: { scope: :speaker_id }
end
