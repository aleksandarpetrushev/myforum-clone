module Api
  class BaseController < ActionController::API
    include Pundit::Authorization

    before_action :authenticate_user!
    around_action :track_request

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
    rescue_from ActiveRecord::RecordInvalid, with: :render_validation_failed
    rescue_from StateMachines::InvalidTransition, with: :render_validation_failed
    rescue_from Events::Register::EventFull, with: :render_event_full

    private

    attr_reader :current_user

    def authenticate_user!
      token = request.authorization.to_s.delete_prefix("Bearer ").presence
      payload = token && AuthToken.decode(token)
      @current_user = User.find_by(id: payload["sub"]) if payload

      return if @current_user

      render_error(code: "unauthenticated", message: "Authentication required", status: :unauthorized)
    end

    def render_not_found(_exception)
      render_error(code: "not_found", message: "Resource not found", status: :not_found)
    end

    def render_forbidden(_exception)
      render_error(code: "forbidden", message: "You are not allowed to perform this action", status: :forbidden)
    end

    # ActiveRecord::RecordInvalid carries the model as record; StateMachines::InvalidTransition as object.
    def render_validation_failed(exception)
      model = exception.respond_to?(:record) ? exception.record : exception.object
      render_error(
        code: "validation_failed",
        message: "Validation failed",
        status: :unprocessable_entity,
        details: model.errors.to_hash,
        reasons: model.errors.details
      )
    end

    def render_event_full(_exception)
      Metrics.increment("registration_failure_total")
      render_error(code: "event_full", message: "This event has reached capacity.", status: :conflict)
    end

    # details carries human-readable messages per field; reasons carries the stable error types clients can match on.
    def render_error(code:, message:, status:, details: nil, reasons: nil)
      body = { "code" => code, "message" => message }
      body["details"] = details if details
      body["reasons"] = reasons if reasons
      render json: { "error" => body }, status: status
    end

    def track_request
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      Metrics.increment("http_requests_total")
      Metrics.observe_duration(duration_ms)
      Rails.logger.info({
        event: "http.request",
        request_id: request.request_id,
        user_id: current_user&.id,
        method: request.request_method,
        path: request.path,
        status: response.status,
        duration_ms: duration_ms,
        event_id: params[:event_id] || (controller_name == "events" ? params[:id] : nil),
        registration_id: @registration&.id
      }.compact.to_json)
    end
  end
end
