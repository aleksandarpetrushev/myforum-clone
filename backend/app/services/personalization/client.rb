module Personalization
  class Client
    OPEN_TIMEOUT = 0.25
    READ_TIMEOUT = 1

    # A Puma thread waits for this call, so the timeouts stay short: a hung Go service must not
    # hold every thread and slow discovery itself (MF-201, D6).
    def self.recommended_event_ids(user_id:, limit:)
      response = Http.get(
        "recommendations",
        query: { user_id: user_id, limit: limit },
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      )
      raise Unavailable, "personalization returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("data").map { |row| Integer(row.fetch("event_id")) }
    rescue Unavailable
      raise
    rescue StandardError => error
      raise Unavailable, "#{error.class}: #{error.message}"
    end
  end
end
