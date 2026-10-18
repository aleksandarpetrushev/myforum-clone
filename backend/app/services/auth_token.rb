class AuthToken
  ALGORITHM = "HS256"

  def self.encode(user)
    JWT.encode({ "sub" => user.id, "exp" => 7.days.from_now.to_i }, secret, ALGORITHM)
  end

  def self.decode(token)
    payload, = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
    payload
  rescue JWT::DecodeError
    nil
  end

  def self.secret
    if Rails.env.production?
      ENV.fetch("JWT_SECRET")
    else
      ENV.fetch("JWT_SECRET", "dev-only-change-me")
    end
  end
end
