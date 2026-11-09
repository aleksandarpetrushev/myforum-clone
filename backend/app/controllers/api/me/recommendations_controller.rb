module Api
  module Me
    class RecommendationsController < BaseController
      def index
        events = Recommendations::ForUser.new(user: current_user).call
        render json: { "data" => events.map(&:as_list_json) }
      rescue Personalization::Unavailable => error
        Metrics.increment("recommendations_unavailable_total")
        Rails.logger.warn({ event: "recommendations.unavailable", user_id: current_user.id, error: error.message }.to_json)
        render_error(
          code: "recommendations_unavailable",
          message: "Recommendations are not available right now.",
          status: :service_unavailable
        )
      end
    end
  end
end
