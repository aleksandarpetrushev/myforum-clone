class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :events, dependent: :destroy
  has_many :event_allowed_organizations, dependent: :destroy
  has_many :permitted_events, through: :event_allowed_organizations, source: :event

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
