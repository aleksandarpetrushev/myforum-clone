require "digest"

module Events
  class Cache
    DETAIL_TTL = 10.minutes
    LIST_TTL = 1.minute
    LIST_EPOCH_KEY = "events/list_epoch"

    def self.detail_key(event_id)
      "events/#{event_id}/detail"
    end

    def self.upcoming_list_key(user)
      "events/upcoming/v2/u#{user.id}/m#{membership_fingerprint(user)}/e#{list_epoch}"
    end

    def self.membership_fingerprint(user)
      rows = OrganizationMembership
        .where(user_id: user.id)
        .order(:organization_id, :role)
        .pluck(:organization_id, :role)
      Digest::SHA256.hexdigest(rows.map { |organization_id, role| "#{organization_id}:#{role}" }.join("|"))[0, 16]
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

    def self.fetch_upcoming_list(user)
      Rails.cache.fetch(upcoming_list_key(user), expires_in: LIST_TTL) { yield }
    end

    def self.invalidate(event_id)
      Rails.cache.delete(detail_key(event_id))
      bump_list_epoch!
    end

    def self.bump_list_epoch!
      bump_epoch(LIST_EPOCH_KEY)
    end

    def self.list_epoch
      Rails.cache.read(LIST_EPOCH_KEY).to_i
    end

    def self.bump_epoch(key)
      value = Rails.cache.increment(key)
      return value if value

      Rails.cache.write(key, 1)
      1
    end
    private_class_method :bump_epoch
  end
end
