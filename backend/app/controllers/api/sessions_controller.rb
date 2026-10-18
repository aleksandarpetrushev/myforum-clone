module Api
  class SessionsController < ActionController::API
    def create
      user = User.find_by(email: params[:email].to_s.strip.downcase)
      unless user&.authenticate(params[:password])
        return render json: {
          "error" => { "code" => "unauthenticated", "message" => "Invalid email or password" }
        }, status: :unauthorized
      end

      render json: {
        "token" => AuthToken.encode(user),
        "user" => { "id" => user.id, "email" => user.email, "name" => user.name, "location" => user.location }
      }
    end
  end
end
