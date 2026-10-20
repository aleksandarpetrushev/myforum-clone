module Bench
  # Deterministic discovery dataset.
  #
  # Full scale matches the performance ticket: 100_000 events, 50_000 users,
  # 5_000 organizations, and 150_000 memberships. Starts are relative to the
  # moment of the load, so upcoming rows stay in the future. The same scale
  # keeps the same ids, tokens, and visibility relationships.
  #
  # Registrations, speakers, follows, and outbox rows are left out. Event
  # discovery does not read them.
  class Dataset
    SEED = 42
    PASSWORD = "password"
    SELECTIVE_TOKEN = "lumenforge"
    COMMON_TOKEN = "practitioners"
    ADMIN_TOKEN = "privatebrief"
    OUTSIDER_ID = 1
    MEMBER_ID = 2
    ADMIN_ID = 3
    HOME_ORG_ID = 1
    PARTNER_ORG_ID = 2
    ORGANIZER_ORG_ID = 3
    OTHER_PARTNER_ORG_ID = 4
    BATCH = 2_000

    SCALES = {
      tiny: { organizations: 40, users: 120, memberships: 240, events: 400 },
      smoke: { organizations: 200, users: 1_000, memberships: 3_000, events: 2_000 },
      full: { organizations: 5_000, users: 50_000, memberships: 150_000, events: 100_000 }
    }.freeze

    PROBE_FULL = {
      public_selective: 40,
      restricted_selective: 5,
      admin_only: 15,
      combined: 300
    }.freeze

    PROBE_FLOOR = {
      public_selective: 4,
      restricted_selective: 2,
      admin_only: 2,
      combined: 12
    }.freeze

    PROBE_ORDER = %i[public_selective restricted_selective admin_only combined].freeze

    TOPIC_NAMES = [
      "Climate", "Public health", "AI policy", "Cities", "Education", "Energy",
      "Labor", "Democracy", "Food systems", "Mobility", "Housing", "Science",
      "Design", "Security", "Economy", "Oceans", "Trade", "Migration",
      "Agriculture", "Biodiversity", "Water", "Digital rights", "Infrastructure", "Youth"
    ].freeze

    ANGLES = [
      "what programs can change this year",
      "a briefing for members",
      "notes from the field",
      "choices for the next budget",
      "lessons from last season",
      "a working agenda"
    ].freeze

    CAPACITIES = [24, 40, 80, 120, 250].freeze

    LOCATIONS = [
      ["Berlin", 18], ["London", 10], ["New York", 10], ["Paris", 6], ["Lisbon", 5],
      ["Toronto", 5], ["Nairobi", 4], ["Singapore", 4], ["Mexico City", 4], ["Seoul", 4],
      ["Chicago", 4], ["Sydney", 3], ["Amsterdam", 3], ["Cape Town", 3], ["Online", 17]
    ].freeze

    ORG_PREFIXES = %w[Northwind Harbor Lumen Fieldnote Atlas Kindred Civic Meridian Copper Bramble].freeze
    ORG_SUFFIXES = %w[Collective Institute Labs Guild Foundation Network Workshop Council].freeze

    def self.generate!(scale: :full)
      assert_safe_database!
      config = scale_config(scale)
      silence_logs do
        reset!
        now = Time.current
        rng = Random.new(SEED)
        puts "loading organizations (#{config[:organizations]})"
        insert_organizations(config, now)
        puts "loading users (#{config[:users]})"
        insert_users(config, now, password_digest, rng)
        insert_topics(now)
        puts "loading memberships (#{config[:memberships]})"
        insert_memberships(build_memberships(config, rng), now)
        puts "loading events (#{config[:events]})"
        probe_ranges = insert_events(config, rng, now)
        puts "analyzing tables"
        analyze!
        manifest = build_manifest(scale, config, probe_ranges, now)
        validate!(manifest)
        write_manifest(manifest)
        manifest
      end
    end

    def self.manifest_path
      Rails.root.join("tmp/bench/manifest.json")
    end

    def self.read_manifest
      path = manifest_path
      raise "Missing #{path}. Run bin/rails bench:prepare." unless path.exist?

      JSON.parse(path.read)
    end

    def self.print_summary(manifest)
      counts = manifest.fetch("counts")
      profile = manifest.fetch("profile")
      puts
      puts "Benchmark database #{manifest.fetch("database")} (#{manifest.fetch("scale")})"
      puts "events #{counts["events"]}  users #{counts["users"]}  organizations #{counts["organizations"]}  memberships #{counts["memberships"]}"
      puts "published upcoming #{profile["published_upcoming"]}  largest shared start #{profile["largest_start_tie"]}"
      profile["status_visibility"].each do |row|
        puts "  #{row["status"]} #{row["visibility"]} #{row["n"]}"
      end
      personas = manifest.fetch("personas")
      puts "password #{PASSWORD}"
      puts "outsider #{personas.dig("outsider", "email")}  member #{personas.dig("member", "email")}  admin #{personas.dig("admin", "email")}"
      puts "selective token #{SELECTIVE_TOKEN}  common token #{COMMON_TOKEN}  admin token #{ADMIN_TOKEN}"
      puts "manifest #{manifest_path}"
    end

    def self.scale_config(scale)
      config = SCALES.fetch(scale.to_sym) do
        raise ArgumentError, "Unknown scale #{scale}. Use #{SCALES.keys.join(", ")}."
      end
      users = config.fetch(:users)
      orgs = config.fetch(:organizations)
      memberships = config.fetch(:memberships)
      events = config.fetch(:events)
      raise "users must leave room for persona accounts" unless users >= orgs + 3
      raise "memberships must cover every user and an admin for every organization" unless memberships >= users && memberships >= orgs + 2
      raise "memberships exceed 12 per user" unless memberships <= ((users - 3) * 12) + 3
      raise "not enough events for probe rows" if probe_counts(events).values.sum >= events

      config
    end

    def self.probe_counts(event_count)
      PROBE_FULL.to_h do |key, full|
        scaled = (full * event_count / 100_000.0).ceil
        value = [[scaled, PROBE_FLOOR.fetch(key)].max, full].min
        [key, value]
      end
    end

    def self.assert_safe_database!
      raise "Refusing to load benchmark data in production" if Rails.env.production?
      return if Rails.env.test?

      name = ActiveRecord::Base.connection.current_database
      return if name == Database::NAME

      raise "Refusing to replace database #{name}. Run bin/rails bench:prepare to load #{Database::NAME}."
    end

    def self.silence_logs
      rails_logger = Rails.logger
      ar_logger = ActiveRecord::Base.logger
      rails_level = rails_logger&.level
      ar_level = ar_logger&.level
      rails_logger.level = Logger::ERROR if rails_logger
      ar_logger.level = Logger::ERROR if ar_logger
      yield
    ensure
      rails_logger.level = rails_level if rails_logger
      ar_logger.level = ar_level if ar_logger
    end

    def self.reset!
      if Rails.env.test?
        [
          AnalyticsEvent, Notification, OutboxEvent, Registration, EventSpeaker, EventTopic,
          TopicFollow, OrganizationMembership, EventAllowedOrganization, Event, Speaker,
          Topic, Organization, User
        ].each(&:delete_all)
      else
        ActiveRecord::Base.connection.execute(<<~SQL)
          TRUNCATE TABLE
            analytics_events,
            notifications,
            outbox_events,
            registrations,
            event_speakers,
            event_topics,
            topic_follows,
            organization_memberships,
            event_allowed_organizations,
            events,
            speakers,
            topics,
            organizations,
            users
          RESTART IDENTITY CASCADE
        SQL
      end
    end

    def self.password_digest
      BCrypt::Password.create(PASSWORD)
    end

    def self.insert_organizations(config, now)
      rows = config.fetch(:organizations).times.map { |offset|
        id = offset + 1
        prefix = ORG_PREFIXES[id % ORG_PREFIXES.length]
        suffix = ORG_SUFFIXES[id % ORG_SUFFIXES.length]
        {
          id: id,
          name: "#{prefix} #{suffix} #{id}",
          slug: "#{prefix}-#{suffix}-#{id}".downcase,
          created_at: now,
          updated_at: now
        }
      }
      Organization.insert_all(rows, returning: false)
      reset_pk!("organizations")
    end

    def self.insert_users(config, now, digest, rng)
      location_weights = cumulative_weights(LOCATIONS.length)
      rows = []
      config.fetch(:users).times do |offset|
        id = offset + 1
        email, name, location = persona_identity(id) || [
          format("bench-user-%06d@example.com", id),
          "Bench User #{id}",
          LOCATIONS[weighted_index(location_weights, rng) - 1].first
        ]
        rows << {
          id: id,
          email: email,
          name: name,
          password_digest: digest,
          location: location,
          created_at: now,
          updated_at: now
        }
        flush(User, rows)
      end
      flush(User, rows, force: true)
      reset_pk!("users")
    end

    def self.persona_identity(id)
      case id
      when OUTSIDER_ID then ["bench-outsider@example.com", "Bench Outsider", "Berlin"]
      when MEMBER_ID then ["bench-member@example.com", "Bench Member", "Berlin"]
      when ADMIN_ID then ["bench-admin@example.com", "Bench Admin", "Lisbon"]
      end
    end

    def self.insert_topics(now)
      rows = TOPIC_NAMES.each_with_index.map { |name, index|
        {
          id: index + 1,
          name: name,
          slug: name.downcase.gsub(" ", "-"),
          created_at: now,
          updated_at: now
        }
      }
      Topic.insert_all(rows, returning: false)
      reset_pk!("topics")
    end

    def self.build_memberships(config, rng)
      user_count = config.fetch(:users)
      org_count = config.fetch(:organizations)
      target = config.fetch(:memberships)
      pairs = {}
      per_user = Hash.new(0)
      admin_orgs = {}

      add = lambda do |user_id, org_id, role|
        key = [user_id, org_id]
        return false if pairs.key?(key)

        pairs[key] = role
        per_user[user_id] += 1
        admin_orgs[org_id] = true if role == "admin"
        true
      end

      add.call(OUTSIDER_ID, HOME_ORG_ID, "member")
      add.call(MEMBER_ID, PARTNER_ORG_ID, "member")
      add.call(ADMIN_ID, ORGANIZER_ORG_ID, "admin")

      org_count.times do |offset|
        org_id = offset + 1
        next if admin_orgs[org_id]

        user_id = case org_id
        when HOME_ORG_ID then user_count
        when PARTNER_ORG_ID then user_count - 1
        else org_id + 3
        end
        raise "admin user #{user_id} is outside the user range" unless user_id.between?(4, user_count)
        raise "could not anchor organization #{org_id}" unless add.call(user_id, org_id, "admin")
      end

      raise "anchor memberships exceed the target" if pairs.size > target

      cumulative = cumulative_weights(org_count)
      remaining = target - pairs.size
      pool = (4..user_count).to_a
      misses = 0
      while remaining.positive?
        misses += 1
        raise "could not place #{remaining} memberships" if misses > user_count * 50

        user_id = pool[rng.rand(pool.length)]
        next if per_user[user_id] >= 12

        if add.call(user_id, weighted_index(cumulative, rng), "member")
          remaining -= 1
          misses = 0
        end
      end

      pairs
    end

    def self.insert_memberships(pairs, now)
      rows = []
      pairs.each do |(user_id, organization_id), role|
        rows << {
          user_id: user_id,
          organization_id: organization_id,
          role: role,
          created_at: now,
          updated_at: now
        }
        flush(OrganizationMembership, rows)
      end
      flush(OrganizationMembership, rows, force: true)
    end

    def self.insert_events(config, rng, now)
      event_count = config.fetch(:events)
      org_count = config.fetch(:organizations)
      counts = probe_counts(event_count)
      ranges = {}
      cursor = 0
      PROBE_ORDER.each do |key|
        first_id = cursor + 1
        cursor += counts.fetch(key)
        ranges[key] = [first_id, cursor]
      end

      cumulative = cumulative_weights(org_count)
      location_weights = cumulative_weights(LOCATIONS.length)
      tie_at = now.beginning_of_hour + 60.days + 9.hours
      events = []
      topics = []
      allowed = []
      loaded = 0

      flush_events = lambda do |force: false|
        next if events.empty? || (events.size < BATCH && !force)

        Event.insert_all(events, returning: false)
        EventTopic.insert_all(topics, returning: false) if topics.any?
        EventAllowedOrganization.insert_all(allowed, returning: false) if allowed.any?
        loaded += events.size
        puts "  events #{loaded} / #{event_count}" if loaded == event_count || (loaded % 10_000).zero?
        events.clear
        topics.clear
        allowed.clear
      end

      ranges.each do |kind, (first_id, last_id)|
        (first_id..last_id).each do |id|
          attributes = probe_attributes(kind, id, now)
          events << event_row(id, attributes, now)
          attributes.fetch(:topic_ids).each { |topic_id| topics << topic_row(id, topic_id, now) }
          attributes.fetch(:allowed_organization_ids).each { |organization_id| allowed << allowed_row(id, organization_id, now) }
          flush_events.call
        end
      end

      ((cursor + 1)..event_count).each do |id|
        attributes = random_attributes(id, rng, now, tie_at, cumulative, location_weights)
        events << event_row(id, attributes, now)
        attributes.fetch(:topic_ids).each { |topic_id| topics << topic_row(id, topic_id, now) }
        attributes.fetch(:allowed_organization_ids).each { |organization_id| allowed << allowed_row(id, organization_id, now) }
        flush_events.call
      end
      flush_events.call(force: true)
      reset_pk!("events")
      ranges
    end

    def self.probe_attributes(kind, id, now)
      starts_at = now.beginning_of_hour + 40.days + id.hours
      case kind
      when :public_selective
        {
          organization_id: HOME_ORG_ID,
          title: "Climate forum #{id}: #{SELECTIVE_TOKEN} briefing",
          description: "Session #{id} shares a climate briefing for a public audience in Berlin.",
          starts_at: starts_at,
          location: "Berlin",
          status: "published",
          visibility: "public",
          topic_ids: [1],
          allowed_organization_ids: []
        }
      when :restricted_selective
        {
          organization_id: ORGANIZER_ORG_ID,
          title: "Climate forum #{id}: #{SELECTIVE_TOKEN} members briefing",
          description: "Session #{id} shares a climate briefing with invited organizations in Berlin.",
          starts_at: starts_at,
          location: "Berlin",
          status: "published",
          visibility: "organization_restricted",
          topic_ids: [1],
          allowed_organization_ids: [PARTNER_ORG_ID]
        }
      when :admin_only
        {
          organization_id: ORGANIZER_ORG_ID,
          title: "Closed forum #{id}: #{ADMIN_TOKEN} for partners",
          description: "Session #{id} is a closed Lisbon discussion for one invited organization.",
          starts_at: starts_at,
          location: "Lisbon",
          status: "published",
          visibility: "organization_restricted",
          topic_ids: [1],
          allowed_organization_ids: [OTHER_PARTNER_ORG_ID]
        }
      when :combined
        {
          organization_id: 5,
          title: "Climate forum #{id}: city climate notes",
          description: description_for(id, "Climate", "Berlin", common: true),
          starts_at: starts_at,
          location: "Berlin",
          status: "published",
          visibility: "public",
          topic_ids: [1],
          allowed_organization_ids: []
        }
      else
        raise "unknown probe #{kind}"
      end
    end

    def self.random_attributes(id, rng, now, tie_at, org_weights, location_weights)
      status_roll = rng.rand
      status = if status_roll < 0.85
        "published"
      elsif status_roll < 0.93
        "draft"
      else
        "cancelled"
      end

      time_roll = rng.rand
      upcoming = (status == "published" && time_roll < 0.72) || (status == "draft" && time_roll < 0.40)
      starts_at = if upcoming && rng.rand < 0.08
        tie_at
      elsif upcoming
        now.beginning_of_hour + (1 + rng.rand(180)).days + (8 + rng.rand(10)).hours
      else
        now.beginning_of_hour - (2 + rng.rand(500)).days + (8 + rng.rand(10)).hours
      end

      location = LOCATIONS[weighted_index(location_weights, rng) - 1].first
      primary_topic = 1 + rng.rand(TOPIC_NAMES.length)
      topic_roll = rng.rand
      extras = if topic_roll < 0.10
        2
      elsif topic_roll < 0.45
        1
      else
        0
      end
      topic_ids = [primary_topic]
      extras.times do
        candidate = nil
        8.times do
          candidate = 1 + rng.rand(TOPIC_NAMES.length)
          break unless topic_ids.include?(candidate)
        end
        topic_ids << candidate unless topic_ids.include?(candidate)
      end

      organizer_id = weighted_index(org_weights, rng)
      visibility = status == "published" && rng.rand < 0.10 ? "organization_restricted" : "public"
      allowed_organization_ids = visibility == "organization_restricted" ? allow_list(rng, organizer_id, org_weights) : []

      {
        organization_id: organizer_id,
        title: "#{TOPIC_NAMES[primary_topic - 1]} forum #{id}: #{ANGLES[id % ANGLES.length]}",
        description: description_for(id, TOPIC_NAMES[primary_topic - 1], location, common: rng.rand < 0.18),
        starts_at: starts_at,
        location: location,
        status: status,
        visibility: visibility,
        topic_ids: topic_ids,
        allowed_organization_ids: allowed_organization_ids
      }
    end

    def self.allow_list(rng, organizer_id, org_weights)
      picked = []
      picked << PARTNER_ORG_ID if organizer_id != PARTNER_ORG_ID && rng.rand < 0.50
      wanted = 1 + rng.rand(3)
      guard = 0
      while picked.size < wanted && guard < 30
        guard += 1
        org_id = weighted_index(org_weights, rng)
        next if org_id == organizer_id || org_id == HOME_ORG_ID || picked.include?(org_id)

        picked << org_id
      end
      if picked.empty?
        picked << (organizer_id == OTHER_PARTNER_ORG_ID ? PARTNER_ORG_ID : OTHER_PARTNER_ORG_ID)
      end
      picked
    end

    def self.description_for(id, topic_name, location, common:)
      topic = topic_name.downcase
      sentences = [
        "Session #{id} compares what changed in #{topic} this season and which constraints still bind.",
        "The hour in #{location} stays on budgets, delivery partners, and decisions a program can make this year.",
        "Speakers bring one concrete case, including case #{id}, and leave with a short list of next steps.",
        "Materials assume the audience already runs a #{topic} effort and wants a sharper brief."
      ]
      body = sentences.first(2 + (id % 3)).join(" ")
      body = "#{body} The discussion is for practitioners who compare notes across organizations." if common
      body
    end

    def self.event_row(id, attributes, now)
      starts_at = attributes.fetch(:starts_at)
      location = attributes.fetch(:location)
      {
        id: id,
        organization_id: attributes.fetch(:organization_id),
        title: attributes.fetch(:title),
        description: attributes.fetch(:description),
        starts_at: starts_at,
        ends_at: starts_at + 2.hours,
        location: location,
        kind: location == "Online" ? "online" : "in_person",
        capacity: CAPACITIES[id % CAPACITIES.length],
        reserved_spots: 0,
        status: attributes.fetch(:status),
        visibility: attributes.fetch(:visibility),
        created_at: now,
        updated_at: now
      }
    end

    def self.topic_row(event_id, topic_id, now)
      { event_id: event_id, topic_id: topic_id, created_at: now, updated_at: now }
    end

    def self.allowed_row(event_id, organization_id, now)
      { event_id: event_id, organization_id: organization_id, created_at: now, updated_at: now }
    end

    def self.flush(model, rows, force: false)
      return if rows.empty? || (rows.size < BATCH && !force)

      model.insert_all(rows, returning: false)
      rows.clear
    end

    def self.reset_pk!(table)
      connection = ActiveRecord::Base.connection
      quoted = connection.quote(table)
      connection.select_value(<<~SQL)
        SELECT setval(
          pg_get_serial_sequence(#{quoted}, 'id'),
          COALESCE((SELECT MAX(id) FROM #{connection.quote_table_name(table)}), 1),
          true
        )
      SQL
    end

    def self.cumulative_weights(count)
      total = 0.0
      Array.new(count) { |index|
        total += 1.0 / ((index + 1)**0.85)
        total
      }
    end

    def self.weighted_index(cumulative, rng)
      target = rng.rand * cumulative.last
      low = 0
      high = cumulative.length - 1
      while low < high
        mid = (low + high) / 2
        if cumulative[mid] < target
          low = mid + 1
        else
          high = mid
        end
      end
      low + 1
    end

    def self.analyze!
      ActiveRecord::Base.connection.execute(<<~SQL)
        ANALYZE events, event_topics, event_allowed_organizations,
          organization_memberships, organizations, topics, users
      SQL
    end

    def self.build_manifest(scale, config, probe_ranges, now)
      connection = ActiveRecord::Base.connection
      tie = connection.select_one(<<~SQL)
        SELECT starts_at, COUNT(*) AS tie_count
        FROM events
        WHERE status = 'published'
        GROUP BY starts_at
        ORDER BY COUNT(*) DESC
        LIMIT 1
      SQL
      {
        "scale" => scale.to_s,
        "seed" => SEED,
        "generated_at" => now.iso8601,
        "database" => connection.current_database,
        "password" => PASSWORD,
        "counts" => {
          "events" => config.fetch(:events),
          "users" => config.fetch(:users),
          "organizations" => config.fetch(:organizations),
          "memberships" => config.fetch(:memberships),
          "event_topics" => EventTopic.count,
          "allowed_organizations" => EventAllowedOrganization.count
        },
        "personas" => {
          "outsider" => { "id" => OUTSIDER_ID, "email" => "bench-outsider@example.com" },
          "member" => { "id" => MEMBER_ID, "email" => "bench-member@example.com" },
          "admin" => { "id" => ADMIN_ID, "email" => "bench-admin@example.com" }
        },
        "probes" => {
          "selective_token" => SELECTIVE_TOKEN,
          "common_token" => COMMON_TOKEN,
          "admin_token" => ADMIN_TOKEN,
          "location" => "Berlin",
          "topic_id" => 1,
          "topic_slug" => "climate",
          "ranges" => probe_ranges.transform_keys(&:to_s).transform_values { |first_id, last_id| [first_id, last_id] }
        },
        "profile" => {
          "published_upcoming" => Event.published.upcoming.count,
          "largest_start_tie" => tie ? tie["tie_count"].to_i : 0,
          "status_visibility" => connection.select_all(
            "SELECT status, visibility, COUNT(*) AS n FROM events GROUP BY 1, 2 ORDER BY 1, 2"
          ).to_a.map { |row| row.merge("n" => row["n"].to_i) }
        }
      }
    end

    def self.validate!(manifest)
      counts = manifest.fetch("counts")
      raise "event count drifted" unless Event.count == counts.fetch("events")
      raise "user count drifted" unless User.count == counts.fetch("users")
      raise "organization count drifted" unless Organization.count == counts.fetch("organizations")
      raise "membership count drifted" unless OrganizationMembership.count == counts.fetch("memberships")

      expectations = {
        OUTSIDER_ID => { HOME_ORG_ID => "member" },
        MEMBER_ID => { PARTNER_ORG_ID => "member" },
        ADMIN_ID => { ORGANIZER_ORG_ID => "admin" }
      }
      expectations.each do |user_id, expected|
        actual = OrganizationMembership.where(user_id: user_id).pluck(:organization_id, :role).to_h
        raise "persona #{user_id} memberships #{actual.inspect}" unless actual == expected
      end

      connection = ActiveRecord::Base.connection
      orphan_restricted = connection.select_value(<<~SQL)
        SELECT COUNT(*) FROM events e
        WHERE e.visibility = 'organization_restricted'
          AND NOT EXISTS (
            SELECT 1 FROM event_allowed_organizations a WHERE a.event_id = e.id
          )
      SQL
      raise "restricted events without an allow list" unless orphan_restricted.to_i.zero?

      organizer_allowed = connection.select_value(<<~SQL)
        SELECT COUNT(*) FROM event_allowed_organizations a
        INNER JOIN events e ON e.id = a.event_id
        WHERE a.organization_id = e.organization_id
      SQL
      raise "organizer was added to its own allow list" unless organizer_allowed.to_i.zero?

      home_allowed = connection.select_value(
        "SELECT COUNT(*) FROM event_allowed_organizations WHERE organization_id = #{HOME_ORG_ID.to_i}"
      )
      raise "home organization is on an allow list" unless home_allowed.to_i.zero?

      ranges = manifest.dig("probes", "ranges")
      selective_ids = ids_for(ranges, "public_selective") + ids_for(ranges, "restricted_selective")
      admin_ids = ids_for(ranges, "admin_only")
      selective_matches = Event.where("title ILIKE :term OR description ILIKE :term", term: "%#{SELECTIVE_TOKEN}%").count
      admin_matches = Event.where("title ILIKE :term OR description ILIKE :term", term: "%#{ADMIN_TOKEN}%").count
      raise "selective token leaked into other rows" unless selective_matches == selective_ids.size
      raise "admin token leaked into other rows" unless admin_matches == admin_ids.size

      outsider = User.find(OUTSIDER_ID)
      member = User.find(MEMBER_ID)
      admin = User.find(ADMIN_ID)
      raise "outsider can see restricted probe events" unless visible_count(outsider, ids_for(ranges, "restricted_selective")).zero?
      raise "member missed restricted probe events" unless visible_count(member, ids_for(ranges, "restricted_selective")) == ids_for(ranges, "restricted_selective").size
      raise "outsider can see admin-only events" unless visible_count(outsider, admin_ids).zero?
      raise "member can see admin-only events" unless visible_count(member, admin_ids).zero?
      raise "admin missed admin-only events" unless visible_count(admin, admin_ids) == admin_ids.size
    end

    def self.visible_count(user, ids)
      EventPolicy::Scope.new(user, Event.where(id: ids)).resolve.count
    end

    def self.ids_for(ranges, key)
      first_id, last_id = ranges.fetch(key)
      (first_id..last_id).to_a
    end

    def self.write_manifest(manifest)
      return if Rails.env.test?

      path = manifest_path
      FileUtils.mkdir_p(path.dirname)
      path.write(JSON.pretty_generate(manifest))
    end

    private_class_method :scale_config, :probe_counts, :assert_safe_database!, :silence_logs, :reset!,
      :password_digest, :insert_organizations, :insert_users, :persona_identity, :insert_topics,
      :build_memberships, :insert_memberships, :insert_events, :probe_attributes, :random_attributes,
      :allow_list, :description_for, :event_row, :topic_row, :allowed_row, :flush, :reset_pk!,
      :cumulative_weights, :weighted_index, :analyze!, :build_manifest, :validate!, :visible_count,
      :ids_for, :write_manifest
  end
end
