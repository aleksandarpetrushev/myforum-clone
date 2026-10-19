module Api
  module Me
    class RegistrationsController < BaseController
      def index
        registrations = current_user.registrations.includes(:event).order(created_at: :desc)
        render json: { "data" => registrations.map { |registration| json_for(registration) } }
      end

      private

      def json_for(registration)
        registration.as_json_api(event_visible: EventPolicy.new(current_user, registration.event).show?)
      end
    end
  end
end
