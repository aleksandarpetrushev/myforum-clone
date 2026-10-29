module Api
  module Me
    class RegistrationsController < BaseController
      # Upcoming: confirmed, for a published event that has not ended, soonest first.
      # Past: everything else, most recent first, with cancelled and failed registrations after the ones that took
      # place, so a cancelled event months away does not sit above yesterday's session. The split happens here, not in the client, because rows for
      # events the caller can no longer see carry no dates, so only the server can place them.
      def index
        now = Time.current
        base = current_user.registrations.joins(:event).includes(:event)

        upcoming = base
          .where(status: "confirmed")
          .where("events.ends_at > :now AND events.status = 'published'", now: now)
          .order("events.starts_at ASC, events.id ASC")
          .load
        # The negation of Upcoming, written out rather than as a NOT IN subquery. Change both together: the
        # "exactly one section" spec fails if they drift.
        past = base
          .where("registrations.status <> 'confirmed' OR events.ends_at <= :now OR events.status <> 'published'", now: now)
          .order(Arel.sql(<<~SQL.squish))
            CASE WHEN registrations.status = 'confirmed' AND events.status = 'published' THEN 0 ELSE 1 END,
            events.starts_at DESC, events.id DESC
          SQL
          .load

        visible_event_ids = visible_event_ids_for(upcoming + past)
        render json: {
          "upcoming" => upcoming.map { |registration| json_for(registration, visible_event_ids) },
          "past" => past.map { |registration| json_for(registration, visible_event_ids) }
        }
      end

      private

      def visible_event_ids_for(registrations)
        event_ids = registrations.map(&:event_id)
        return Set.new if event_ids.empty?

        policy_scope(Event).where(id: event_ids).ids.to_set
      end

      def json_for(registration, visible_event_ids)
        registration.as_json_api(event_visible: visible_event_ids.include?(registration.event_id))
      end
    end
  end
end
