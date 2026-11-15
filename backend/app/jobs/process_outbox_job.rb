class ProcessOutboxJob < ApplicationJob
  queue_as :default

  def perform
    publisher = Outbox::Publisher.new
    published = publisher.call
    return if Rails.env.test?

    wait = self.class.wait_after(published: published, full_batch: publisher.full_batch?)
    wait ? self.class.set(wait: wait).perform_later : self.class.perform_later
  end

  # nil = go again at once. A pass that published a full batch leaves rows waiting, so idling would only grow the
  # backlog (MF-302). Enqueued directly, not with wait: 0, because Sidekiq polls scheduled jobs only every few
  # seconds. A full batch with nothing published (every row waiting behind failures) does not spin.
  def self.wait_after(published:, full_batch:)
    return nil if full_batch && published.positive?

    published.positive? ? 1.second : 5.seconds
  end
end
