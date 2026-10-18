class Notification < ApplicationRecord
  belongs_to :user

  validates :kind, :title, :body, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true

  def as_json_api
    {
      "id" => id,
      "kind" => kind,
      "title" => title,
      "body" => body,
      "read_at" => read_at,
      "created_at" => created_at
    }
  end
end
