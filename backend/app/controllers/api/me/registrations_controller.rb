module Api
  module Me
    class RegistrationsController < BaseController
      def index
        registrations = current_user.registrations.includes(:event).order(created_at: :desc).select do |registration|
          EventPolicy.new(current_user, registration.event).show?
        end
        render json: { "data" => registrations.map(&:as_json_api) }
      end
    end
  end
end
