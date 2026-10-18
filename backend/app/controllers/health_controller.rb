class HealthController < ActionController::API
  def show
    render json: { "status" => "ok" }
  end

  def ready
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { "status" => "ready" }
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::Error
    render json: { "status" => "not_ready" }, status: :service_unavailable
  end
end
