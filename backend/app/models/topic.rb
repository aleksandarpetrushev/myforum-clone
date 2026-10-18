class Topic < ApplicationRecord
  has_many :topic_follows, dependent: :destroy
  has_many :followers, through: :topic_follows, source: :user
  has_many :event_topics, dependent: :destroy
  has_many :events, through: :event_topics

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
