class RebuildEventCacheJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.includes(:organization, :topics, :speakers).find_by(id: event_id)
    if event
      Events::Cache.write_detail(event)
    else
      Rails.cache.delete(Events::Cache.detail_key(event_id))
    end
  end
end
