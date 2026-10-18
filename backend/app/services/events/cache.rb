module Events
  class Cache
    DETAIL_TTL = 10.minutes
    UPCOMING_TTL = 1.minute
    UPCOMING_KEY = "events/upcoming/v1"

    def self.detail_key(event_id)
      "events/#{event_id}/detail"
    end

    def self.fetch_detail(event_id)
      cached = Rails.cache.read(detail_key(event_id))
      return cached if cached

      event = Event.includes(:organization, :topics, :speakers).find(event_id)
      payload = event.as_detail_json
      Rails.cache.write(detail_key(event_id), payload, expires_in: DETAIL_TTL)
      payload
    end

    def self.write_detail(event)
      Rails.cache.write(detail_key(event.id), event.as_detail_json, expires_in: DETAIL_TTL)
    end

    def self.invalidate(event_id)
      Rails.cache.delete(detail_key(event_id))
      Rails.cache.delete(UPCOMING_KEY)
    end
  end
end
