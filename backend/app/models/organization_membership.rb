class OrganizationMembership < ApplicationRecord
  ROLES = %w[member admin].freeze

  belongs_to :user
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
end
