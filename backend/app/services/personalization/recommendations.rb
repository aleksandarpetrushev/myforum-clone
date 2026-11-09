module Personalization
  # Go's ranked event ids for a user, cached briefly. Says nothing about whether the user may see
  # them: Recommendations::ForUser decides that on every request.
  class Recommendations
    FRESH_FOR = 30.seconds
    KEEP_STALE_FOR = 1.day
    REQUEST_LIMIT = 20

    def self.cache_key(user)
      "recommendations/v1/u#{user.id}"
    end

    # Fresh for 30 s, so a new topic follow shows within a minute (outbox lag plus this).
    # The entry is not deleted on follow: Go updates asynchronously, so an early refetch could
    # cache the old list again. Past 30 s the entry is used only when Go fails.
    def self.ids_for(user)
      cached = read_cache(user)
      return cached["ids"] if cached && Time.current.to_f - cached["fetched_at"] < FRESH_FOR

      ids = Client.recommended_event_ids(user_id: user.id, limit: REQUEST_LIMIT)
      write_cache(user, { "ids" => ids, "fetched_at" => Time.current.to_f })
      Metrics.increment("recommendations_fetched_total")
      ids
    rescue Unavailable => error
      raise unless cached

      # Treat the old list as fresh for another 30 s, so that while Go is down each user waits for a
      # timeout at most once per window instead of on every request.
      write_cache(user, cached.merge("fetched_at" => Time.current.to_f))
      Metrics.increment("recommendations_stale_total")
      Rails.logger.warn({ event: "recommendations.stale", user_id: user.id, error: error.message }.to_json)
      cached["ids"]
    end

    # A cache failure, or an entry this code did not write, means calling Go, never failing the request.
    def self.read_cache(user)
      entry = Rails.cache.read(cache_key(user))
      entry if valid_entry?(entry)
    rescue StandardError => error
      Rails.logger.warn({ event: "recommendations.cache_failed", user_id: user.id, error: error.message }.to_json)
      nil
    end

    def self.write_cache(user, entry)
      Rails.cache.write(cache_key(user), entry, expires_in: KEEP_STALE_FOR)
    rescue StandardError => error
      Rails.logger.warn({ event: "recommendations.cache_failed", user_id: user.id, error: error.message }.to_json)
    end

    def self.valid_entry?(entry)
      entry.is_a?(Hash) &&
        entry["ids"].is_a?(Array) && entry["ids"].all?(Integer) &&
        entry["fetched_at"].is_a?(Numeric)
    end
    private_class_method :read_cache, :write_cache, :valid_entry?
  end
end
