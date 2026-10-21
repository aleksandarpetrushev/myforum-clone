module Api
  module Me
    class NotificationsController < BaseController
      PAGE_SIZE = 20

      rescue_from Notifications::Cursor::Invalid, with: :render_invalid_cursor

      def index
        before = Notifications::Cursor.decode(params[:cursor])
        scope = current_user.notifications.newest_first
        if before
          created_at, id = before
          scope = scope.where("(notifications.created_at, notifications.id) < (?, ?)", created_at, id)
        end
        rows = scope.limit(PAGE_SIZE + 1).to_a
        page = rows.first(PAGE_SIZE)
        render json: {
          "data" => page.map(&:as_json_api),
          "unread_count" => current_user.notifications.unread.count,
          "next_cursor" => rows.size > PAGE_SIZE ? Notifications::Cursor.encode(page.last) : nil
        }
      end

      def read
        notification = current_user.notifications.find(params[:id])
        current_user.notifications.unread.where(id: notification.id).update_all(read_at: Time.current)
        notification.reload
        render json: notification.as_json_api.merge("unread_count" => current_user.notifications.unread.count)
      end

      def read_all
        current_user.notifications.unread.update_all(read_at: Time.current)
        render json: { "unread_count" => current_user.notifications.unread.count }
      end

      private

      def render_invalid_cursor
        render_error(code: "invalid_cursor", message: "Cursor is invalid", status: :bad_request)
      end
    end
  end
end
