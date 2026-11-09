module Personalization
  # Go timed out, refused the connection, answered non-2xx, or sent something we cannot read.
  class Unavailable < StandardError; end
end
