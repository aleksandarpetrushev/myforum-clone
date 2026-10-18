module Api
  class TopicsController < BaseController
    def index
      topics = Topic.order(:name)
      followed_ids = current_user.topic_follows.where(topic_id: topics.select(:id)).pluck(:topic_id).to_set

      render json: {
        "data" => topics.map { |topic|
          { "id" => topic.id, "name" => topic.name, "slug" => topic.slug, "followed" => followed_ids.include?(topic.id) }
        }
      }
    end

    def follow
      topic = Topic.find(params[:id])
      Topics::Follow.new(user: current_user, topic: topic).call
      head :no_content
    end

    def unfollow
      topic = Topic.find(params[:id])
      Topics::Unfollow.new(user: current_user, topic: topic).call
      head :no_content
    end
  end
end
