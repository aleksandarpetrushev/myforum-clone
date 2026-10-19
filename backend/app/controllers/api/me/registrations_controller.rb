module Api
  module Me
    class RegistrationsController < BaseController
      def index
        registrations = current_user.registrations.includes(:event).order(created_at: :desc).load
        visible_event_ids = visible_event_ids_for(registrations)
        render json: {
          "data" => registrations.map { |registration| json_for(registration, visible_event_ids) }
        }
      end

      private

      def visible_event_ids_for(registrations)
        event_ids = registrations.map(&:event_id)
        return [] if event_ids.empty?

        policy_scope(Event).where(id: event_ids).ids
      end

      def json_for(registration, visible_event_ids)
        registration.as_json_api(event_visible: visible_event_ids.include?(registration.event_id))
      end
    end
  end
end
