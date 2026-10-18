module Api
  module Me
    class NotificationsController < BaseController
      def index
        notifications = current_user.notifications.order(created_at: :desc).limit(50)
        render json: { "data" => notifications.map(&:as_json_api) }
      end
    end
  end
end
