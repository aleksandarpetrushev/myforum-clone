class User < ApplicationRecord
  has_secure_password

  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  has_many :topic_follows, dependent: :destroy
  has_many :followed_topics, through: :topic_follows, source: :topic
  has_many :registrations, dependent: :destroy
  has_many :notifications, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
