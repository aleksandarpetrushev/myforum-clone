module Recommendations
  # Go ranks; Rails decides what this user may be shown (MF-201, D2 to D4).
  class ForUser
    LIMIT = 5

    def initialize(user:)
      @user = user
    end

    # Raises Personalization::Unavailable when Go fails and there is no cached list to fall back on.
    def call
      ids = Personalization::Recommendations.ids_for(@user)
      return [] if ids.empty?

      registered = @user.registrations.where(status: "confirmed", event_id: ids).pluck(:event_id)
      # policy_scope alone also returns cancelled events, and Go's projection can lag a cancellation.
      events = Pundit.policy_scope!(@user, Event)
        .published
        .upcoming
        .where(id: ids - registered)
        .includes(:organization, :topics)
        .index_by(&:id)
      ids.filter_map { |id| events[id] }.first(LIMIT)
    end
  end
end
