module Bench
  # MF-302: one Annual Meeting programme day on top of the benchmark dataset.
  #
  # Sessions and topic follows are created through Events::Create and Topics::Follow, so they write the same
  # outbox rows as production and reach the personalization service through the outbox, not by a side door.
  # Each run starts clean: the previous run's programme, registrations, notifications, outbox rows and the
  # personalization read model are removed first. That is only safe in my_forum_benchmark, which nothing else uses.
  class Programme
    TITLE_PREFIX = "Annual Meeting: "
    KEYNOTES = 5
    KEYNOTE_CAPACITY = 1_000
    POPULAR = 15
    POPULAR_CAPACITY = 200
    SESSIONS = 200
    FIRST_PARTICIPANT_ID = 4 # ids 1-3 are the bench personas
    SEED = 302

    def self.prepare!(participants:)
      assert_benchmark_database!
      rng = Random.new(SEED)
      reset!
      organization = Organization.order(:id).first
      topics = Topic.order(:id).to_a
      raise "The benchmark dataset has no topics" if topics.empty?

      sessions = create_sessions(organization, topics, rng)
      participant_ids = User.where("id >= ?", FIRST_PARTICIPANT_ID).order(:id).limit(participants).pluck(:id)
      raise "The benchmark dataset has only #{participant_ids.size} users; #{participants} needed" if participant_ids.size < participants

      follow_topics(participant_ids, topics, rng)
      {
        "keynote_ids" => sessions.first(KEYNOTES).map(&:id),
        "popular_ids" => sessions[KEYNOTES, POPULAR].map(&:id),
        "regular_ids" => sessions.drop(KEYNOTES + POPULAR).map(&:id),
        "participant_ids" => participant_ids,
        "topic_ids" => topics.map(&:id),
        "search_token" => "summit"
      }
    end

    def self.assert_benchmark_database!
      name = ActiveRecord::Base.connection.current_database
      raise "Refusing to reset #{name}: the rush only runs against #{Database::NAME}" unless name == Database::NAME
    end

    def self.reset!
      connection = ActiveRecord::Base.connection
      connection.transaction do
        connection.execute("DELETE FROM analytics_events")
        connection.execute("DELETE FROM notifications")
        connection.execute("DELETE FROM outbox_events")
        connection.execute("DELETE FROM registrations")
        connection.execute("DELETE FROM topic_follows")
        programme = Event.where("title LIKE ?", "#{TITLE_PREFIX}%").select(:id)
        EventTopic.where(event_id: programme).delete_all
        Event.where(id: programme).delete_all
      end
      # The Go service creates these tables at start-up; on the first run they do not exist yet.
      if connection.select_value("SELECT to_regclass('personalization.events')")
        connection.execute(<<~SQL.squish)
          TRUNCATE personalization.events, personalization.event_topics, personalization.user_topics,
                   personalization.user_locations, personalization.processed_events,
                   personalization.event_allowed_organizations
        SQL
      end
    end
    private_class_method :reset!

    def self.create_sessions(organization, topics, rng)
      day = (Time.current + 2.days).beginning_of_day + 8.hours # two days out: waitlist offers stay possible
      Array.new(SESSIONS) do |index|
        capacity =
          if index < KEYNOTES then KEYNOTE_CAPACITY
          elsif index < KEYNOTES + POPULAR then POPULAR_CAPACITY
          else rng.rand(50..200)
          end
        starts_at = day + (index % 10).hours
        Events::Create.new(
          organization: organization,
          attributes: {
            "title" => "#{TITLE_PREFIX}summit session #{index + 1}",
            "description" => "Programme session #{index + 1} of the Annual Meeting summit.",
            "starts_at" => starts_at,
            "ends_at" => starts_at + 1.hour,
            "location" => "Davos",
            "kind" => "in_person",
            "capacity" => capacity,
            "visibility" => "public",
            "status" => "published",
            "topic_ids" => topics.sample(2, random: rng).map(&:id)
          }
        ).call
      end
    end
    private_class_method :create_sessions

    def self.follow_topics(participant_ids, topics, rng)
      User.where(id: participant_ids).find_each do |user|
        topics.sample(rng.rand(2..3), random: rng).each do |topic|
          Topics::Follow.new(user: user, topic: topic).call
        end
      end
    end
    private_class_method :follow_topics
  end
end
