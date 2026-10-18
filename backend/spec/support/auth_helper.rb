module AuthHelper
  def auth_headers(user)
    { "Authorization" => "Bearer #{AuthToken.encode(user)}" }
  end

  def json_body
    JSON.parse(response.body)
  end
end
