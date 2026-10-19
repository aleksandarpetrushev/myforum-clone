module Outbox
  class Dispatcher
    def self.call(event)
      case event.event_type
      when "RegistrationCreated", "RegistrationCancelled"
        SendNotificationJob.perform_later(event.id)
        RecordAnalyticsJob.perform_later(event.id)
      when "EventUpdated", "TopicFollowed", "TopicUnfollowed"
        RecordAnalyticsJob.perform_later(event.id)
      end

      Personalization::DeliverEvent.call(event)
    end
  end
end
