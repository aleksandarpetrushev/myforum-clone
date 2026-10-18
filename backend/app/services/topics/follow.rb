module Topics
  class Follow
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      created = false

      ApplicationRecord.transaction do
        follow = TopicFollow.find_by(user: @user, topic: @topic)
        if follow
          created = false
        else
          follow = TopicFollow.create!(user: @user, topic: @topic)
          created = true
          OutboxEvent.record!(
            event_type: "TopicFollowed",
            aggregate_type: "TopicFollow",
            aggregate_id: follow.id,
            idempotency_key: "topic_followed:#{@user.id}:#{@topic.id}",
            payload: {
              "user_id" => @user.id,
              "topic_id" => @topic.id,
              "user_location" => @user.location
            }
          )
        end
      end

      created
    rescue ActiveRecord::RecordNotUnique
      false
    end
  end
end
