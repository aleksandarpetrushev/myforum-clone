class ProcessOutboxJob < ApplicationJob
  queue_as :default

  def perform
    processed = Outbox::Publisher.new.call
    return if Rails.env.test?

    wait = processed.positive? ? 1.second : 5.seconds
    self.class.set(wait: wait).perform_later
  end
end
