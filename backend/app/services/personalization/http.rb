require "net/http"

module Personalization
  # The one way Rails reaches the Go service. Callers choose timeouts; retries are always off, so a
  # timeout means exactly that long (Net::HTTP otherwise retries an idempotent GET once after a
  # read timeout, doubling the wait).
  class Http
    def self.get(path, query:, open_timeout:, read_timeout:)
      uri = uri_for(path)
      uri.query = URI.encode_www_form(query)
      perform(uri, Net::HTTP::Get.new(uri), open_timeout: open_timeout, read_timeout: read_timeout)
    end

    def self.post_json(path, body:, open_timeout:, read_timeout:)
      uri = uri_for(path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      perform(uri, request, open_timeout: open_timeout, read_timeout: read_timeout)
    end

    def self.base_url
      Rails.application.config.x.personalization_url
    end

    def self.uri_for(path)
      URI.join("#{base_url}/", path)
    end

    def self.perform(uri, request, open_timeout:, read_timeout:)
      Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https", open_timeout: open_timeout, read_timeout: read_timeout, max_retries: 0
      ) { |http| http.request(request) }
    end
    private_class_method :uri_for, :perform
  end
end
