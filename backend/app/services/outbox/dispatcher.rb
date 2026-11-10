module Outbox
  class Dispatcher
    # Returns what the personalization service did with the row: :delivered, :deferred or :skipped.
    def self.call(event)
      case event.event_type
      when "RegistrationCreated", "RegistrationCancelled", "WaitlistOffered", "WaitlistOfferExpired"
        SendNotificationJob.perform_later(event.id)
        RecordAnalyticsJob.perform_later(event.id)
      when "EventCancelled"
        CancelEventRegistrationsJob.perform_later(event.aggregate_id)
        RecordAnalyticsJob.perform_later(event.id)
      when "EventUpdated", "TopicFollowed", "TopicUnfollowed"
        RecordAnalyticsJob.perform_later(event.id)
      end

      Personalization::DeliverEvent.call(event)
    end
  end
end
