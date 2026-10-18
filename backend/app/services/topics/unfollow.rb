module Topics
  class Unfollow
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      follow = TopicFollow.find_by(user: @user, topic: @topic)
      return false unless follow

      ApplicationRecord.transaction do
        follow.destroy!
        OutboxEvent.record!(
          event_type: "TopicUnfollowed",
          aggregate_type: "TopicFollow",
          aggregate_id: follow.id,
          idempotency_key: "topic_unfollowed:#{@user.id}:#{@topic.id}:#{follow.id}",
          payload: {
            "user_id" => @user.id,
            "topic_id" => @topic.id
          }
        )
      end

      true
    end
  end
end
