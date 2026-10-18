class EventAllowedOrganization < ApplicationRecord
  belongs_to :event
  belongs_to :organization

  validates :organization_id, uniqueness: { scope: :event_id }

  after_commit :invalidate_event_list_cache, on: %i[create destroy]

  private

  def invalidate_event_list_cache
    Events::Cache.invalidate(event_id)
  end
end
