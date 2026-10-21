class NotificationPreference < ApplicationRecord
  belongs_to :user

  COLUMNS = {
    "registration_confirmed" => :registration_confirmed_enabled,
    "registration_cancelled" => :registration_cancelled_enabled
  }.freeze

  validates :registration_confirmed_enabled, inclusion: { in: [true, false] }
  validates :registration_cancelled_enabled, inclusion: { in: [true, false] }

  def self.api_json(record)
    {
      "registration_confirmed_enabled" => record.nil? || record.registration_confirmed_enabled,
      "registration_cancelled_enabled" => record.nil? || record.registration_cancelled_enabled
    }
  end

  # Caller holds the user row lock inside the current transaction.
  def self.allows?(user_id, kind)
    column = COLUMNS[kind]
    return true unless column

    value = where(user_id: user_id).pick(column)
    value.nil? || value
  end

  def self.update_for(user, attributes)
    User.transaction do
      User.lock.find(user.id)
      record = find_or_initialize_by(user_id: user.id)
      record.update!(attributes)
      record
    end
  end
end
