class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :events, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
