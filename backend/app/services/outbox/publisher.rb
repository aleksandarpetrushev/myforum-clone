module Outbox
  class Publisher
    BATCH_SIZE = 100

    def call
      published = 0

      OutboxEvent.pending.order(:id).limit(BATCH_SIZE).each do |event|
        event.with_lock do
          if event.status == "pending"
            Dispatcher.call(event)
            event.update!(status: "published", published_at: Time.current)
            published += 1
          end
        end
      end

      published
    end
  end
end
