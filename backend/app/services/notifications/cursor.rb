require "base64"
require "json"

module Notifications
  class Cursor
    class Invalid < StandardError; end

    def self.encode(notification)
      payload = JSON.generate(
        "created_at" => notification.created_at.iso8601(6),
        "id" => notification.id
      )
      Base64.urlsafe_encode64(payload, padding: false)
    end

    def self.decode(value)
      return nil if value.nil? || value == ""

      padded = value.to_s
      padded += "=" * ((4 - padded.length % 4) % 4)
      data = JSON.parse(Base64.urlsafe_decode64(padded))
      created_at = Time.zone.iso8601(data.fetch("created_at"))
      id = Integer(data.fetch("id"))
      raise Invalid if id <= 0

      [created_at, id]
    rescue ArgumentError, JSON::ParserError, KeyError, TypeError
      raise Invalid
    end
  end
end
