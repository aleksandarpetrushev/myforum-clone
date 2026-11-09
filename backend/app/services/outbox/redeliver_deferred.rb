module Outbox
  # Sends deferred rows to the personalization service again, oldest first. Run after deploying a service that
  # reads a new schema_version (personalization/contract/README.md). Only the personalization delivery is
  # retried: notifications and analytics were dispatched when the row was first published.
  class RedeliverDeferred
    Result = Struct.new(:delivered, :still_deferred, keyword_init: true)

    def call
      delivered = 0
      still_deferred = 0

      OutboxEvent.deferred.order(:id).find_each do |event|
        event.with_lock do
          next unless event.status == "deferred"

          if Personalization::DeliverEvent.call(event) == :deferred
            still_deferred += 1
          else
            event.update!(status: "published", published_at: Time.current)
            delivered += 1
          end
        end
      end

      Result.new(delivered: delivered, still_deferred: still_deferred)
    end
  end
end
