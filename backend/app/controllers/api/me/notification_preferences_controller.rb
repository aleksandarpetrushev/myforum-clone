module Api
  module Me
    class NotificationPreferencesController < BaseController
      def show
        render json: NotificationPreference.api_json(current_user.notification_preference)
      end

      def update
        record = NotificationPreference.update_for(current_user, preference_params)
        render json: NotificationPreference.api_json(record)
      end

      private

      def preference_params
        params.require(:notification_preference).permit(:registration_confirmed_enabled, :registration_cancelled_enabled, :event_cancelled_enabled)
      end
    end
  end
end
