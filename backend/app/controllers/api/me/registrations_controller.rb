module Api
  module Me
    class RegistrationsController < BaseController
      def index
        registrations = current_user.registrations.includes(:event).order(created_at: :desc)
        render json: { "data" => registrations.map(&:as_json_api) }
      end
    end
  end
end
