require "digest"

module Bench
  # Times GET /api/events through the Rails stack.
  #
  # Samples are steady-state cache misses: warmup requests are discarded and
  # the response cache is a null store, which is how keyword, topic, location,
  # and later pages already behave. Postgres can still serve pages from its
  # own cache. The run is one request at a time, so it does not stand in for
  # 300 requests/sec.
  class Discovery
    PAGE_SIZE = 20
    MIX = [
      ["upcoming_page_1", 40],
      ["keyword_common", 18],
      ["keyword_selective", 7],
      ["location", 15],
      ["topic", 10],
      ["combined", 8],
      ["deep_page", 2]
    ].freeze

    class CheckFailed < StandardError; end

    def self.run!(manifest: nil, iterations: nil, warmup: nil, mix: nil, explain: true)
      manifest ||= Dataset.read_manifest
      iterations = (iterations || ENV.fetch("BENCH_ITERATIONS", 20)).to_i
      warmup = (warmup || ENV.fetch("BENCH_WARMUP", 2)).to_i
      mix_requests = (mix || ENV.fetch("BENCH_MIX", 80)).to_i
      raise ArgumentError, "iterations must be positive" unless iterations.positive?
      raise ArgumentError, "warmup must be zero or positive" if warmup.negative?

      assert_database!
      assert_manifest!(manifest)
      previous_cache = Rails.cache
      rails_logger = Rails.logger
      ar_logger = ActiveRecord::Base.logger
      rails_level = rails_logger&.level
      ar_level = ar_logger&.level
      Rails.cache = ActiveSupport::Cache::NullStore.new
      rails_logger.level = Logger::ERROR if rails_logger
      ar_logger.level = Logger::ERROR if ar_logger

      execute(manifest, iterations: iterations, warmup: warmup, mix_requests: mix_requests, explain: explain)
    ensure
      Rails.cache = previous_cache if defined?(previous_cache) && previous_cache
      rails_logger.level = rails_level if rails_logger
      ar_logger.level = ar_level if ar_logger
    end

    def self.write(report)
      path = Rails.root.join("tmp/bench/discovery.json")
      FileUtils.mkdir_p(path.dirname)
      path.write(JSON.pretty_generate(report))
      path
    end

    def self.print_report(report)
      puts
      puts report.fetch("note")
      puts "database #{report.dig("dataset", "database")}  scale #{report.dig("dataset", "scale")}  events #{report.dig("dataset", "events")}"
      puts "iterations #{report["iterations"]}  warmup #{report["warmup"]}  cache #{report["cache"]}"
      puts "postgres #{report["postgres"]}  ruby #{report["ruby"]}  sha #{report["git_sha"] || "unknown"}"
      puts
      puts format("%-26s %6s %8s %8s %8s %8s %8s %6s %5s", "scenario", "n", "min", "p50", "p95", "p99", "max", "rows", "sql")
      report.fetch("scenarios").each do |scenario|
        puts format(
          "%-26s %6d %8.1f %8.1f %8.1f %8.1f %8.1f %6d %5d",
          scenario["name"], scenario["samples"], scenario["min_ms"], scenario["p50_ms"],
          scenario["p95_ms"], scenario["p99_ms"], scenario["max_ms"], scenario["rows"], scenario["sql_count"]
        )
      end

      mix = report["mix"]
      if mix && mix["samples"].to_i.positive?
        puts
        puts format("mix %-21s %6d %8.1f %8.1f %8.1f %8.1f %8.1f", "", mix["samples"], mix["min_ms"], mix["p50_ms"], mix["p95_ms"], mix["p99_ms"], mix["max_ms"])
      end

      cache_hit = report["cache_hit"]
      if cache_hit
        puts
        if cache_hit["status"] == "measured"
          puts "upcoming_page_1 cache hit  p50 #{format("%.1f", cache_hit["p50_ms"])} ms  p95 #{format("%.1f", cache_hit["p95_ms"])} ms  (membership fingerprint still reads Postgres)"
        else
          puts "upcoming_page_1 cache hit  skipped (#{cache_hit["reason"]})"
        end
      end

      puts
      puts "List-query plans:"
      report.fetch("scenarios").each do |scenario|
        plan = scenario["explain"]
        next unless plan

        if plan["error"]
          puts format("  %-26s  explain failed: %s", scenario["name"], plan["error"])
          next
        end

        access = plan["event_access"] || "unknown access"
        filter = plan["event_filter"] ? ", #{plan["event_filter"]} filter" : ""
        puts format("  %-26s %8.1f ms  %s on events%s", scenario["name"], plan["execution_ms"].to_f, access, filter)
      end

      checks = report.fetch("checks")
      puts
      if checks["passed"]
        puts "visibility checks passed"
      else
        puts "visibility checks failed:"
        checks["failures"].each { |failure| puts "  #{failure}" }
      end
      pagination = checks["pagination"] || {}
      puts "page 1 stable across two reads: #{pagination["page_1_stable"]}"
      puts "ids shared by page 1 and page 2: #{pagination["page_1_and_2_overlap"]}"
      puts "largest published start tie: #{report.dig("dataset", "largest_start_tie")}"
    end

    def self.execute(manifest, iterations:, warmup:, mix_requests:, explain:)
      tokens = persona_tokens(manifest)
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.host = "localhost"
      deep_page = deep_page_number
      scenarios = scenario_definitions(manifest, deep_page)
      checks = visibility_checks(session, tokens, manifest)
      scenarios_report = []

      if checks["passed"]
        scenarios.each_value do |scenario|
          $stdout.puts "timing #{scenario[:name]}"
          scenarios_report << time_scenario(session, tokens, scenario, iterations: iterations, warmup: warmup, explain: explain)
        end
        mix_report = time_mix(session, tokens, scenarios, mix_requests)
        cache_hit = cache_hit_sample(session, tokens.fetch("outsider"), scenarios.fetch(:upcoming_page_1))
      end

      {
        "generated_at" => Time.current.iso8601,
        "note" => "Single-request baseline after warmup, run in #{Rails.env}. Response cache disabled. This does not generate peak traffic and does not prove a production latency target.",
        "database" => ActiveRecord::Base.connection.current_database,
        "postgres" => ActiveRecord::Base.connection.select_value("SHOW server_version"),
        "ruby" => RUBY_VERSION,
        "git_sha" => git_sha,
        "iterations" => iterations,
        "warmup" => warmup,
        "cache" => "null_store",
        "page_size" => PAGE_SIZE,
        "deep_page" => deep_page,
        "dataset" => {
          "database" => manifest["database"],
          "scale" => manifest["scale"],
          "events" => manifest.dig("counts", "events"),
          "users" => manifest.dig("counts", "users"),
          "organizations" => manifest.dig("counts", "organizations"),
          "memberships" => manifest.dig("counts", "memberships"),
          "published_upcoming" => manifest.dig("profile", "published_upcoming"),
          "largest_start_tie" => manifest.dig("profile", "largest_start_tie")
        },
        "checks" => checks,
        "checks_passed" => checks["passed"],
        "scenarios" => scenarios_report,
        "mix" => mix_report,
        "cache_hit" => cache_hit
      }
    end
    private_class_method :execute

    def self.assert_manifest!(manifest)
      expected = manifest.dig("counts", "events").to_i
      actual = Event.count
      return if actual == expected

      database = ActiveRecord::Base.connection.current_database
      raise "Manifest says #{expected} events but #{database} has #{actual}. Run bin/rails bench:prepare."
    end
    private_class_method :assert_manifest!

    def self.assert_database!
      name = ActiveRecord::Base.connection.current_database
      return if Rails.env.test? || name == Database::NAME

      raise "Connected to #{name}. Run bin/rails bench:discover to use #{Database::NAME}."
    end
    private_class_method :assert_database!

    def self.persona_tokens(manifest)
      manifest.fetch("personas").to_h do |role, persona|
        user = User.find(persona.fetch("id"))
        [role, AuthToken.encode(user)]
      end
    end
    private_class_method :persona_tokens

    def self.scenario_definitions(manifest, deep_page)
      probes = manifest.fetch("probes")
      {
        upcoming_page_1: { name: "upcoming_page_1", user: "outsider", params: {} },
        keyword_selective: { name: "keyword_selective", user: "outsider", params: { q: probes["selective_token"] } },
        keyword_common: { name: "keyword_common", user: "outsider", params: { q: probes["common_token"] } },
        keyword_miss: { name: "keyword_miss", user: "outsider", params: { q: "zzznomatchtoken" } },
        location: { name: "location", user: "outsider", params: { location: probes["location"] } },
        topic: { name: "topic", user: "outsider", params: { topic_id: probes["topic_id"] } },
        combined: {
          name: "combined",
          user: "outsider",
          params: { q: probes["common_token"], location: probes["location"], topic_id: probes["topic_id"] }
        },
        deep_page: { name: "deep_page", user: "outsider", params: { page: deep_page } },
        all_dates_page_1: { name: "all_dates_page_1", user: "outsider", params: { upcoming: false } },
        restricted_as_member: { name: "restricted_as_member", user: "member", params: { q: probes["selective_token"] } },
        restricted_as_admin: { name: "restricted_as_admin", user: "admin", params: { q: probes["admin_token"] } },
        restricted_as_outsider: { name: "restricted_as_outsider", user: "outsider", params: { q: probes["admin_token"] } }
      }
    end
    private_class_method :scenario_definitions

    def self.deep_page_number
      rough = Event.published.upcoming.count
      pages = [(rough.to_f / PAGE_SIZE).ceil, 1].max
      return 1 if pages < 2

      [[pages, 250].min, 2].max
    end
    private_class_method :deep_page_number

    def self.visibility_checks(session, tokens, manifest)
      ranges = manifest.dig("probes", "ranges")
      probes = manifest.fetch("probes")
      failures = []
      public_ids = id_range(ranges, "public_selective")
      restricted_ids = id_range(ranges, "restricted_selective")
      admin_ids = id_range(ranges, "admin_only")
      selective = { q: probes["selective_token"] }
      admin_only = { q: probes["admin_token"] }

      outsider_selective = walk_ids(session, tokens.fetch("outsider"), selective)
      member_selective = walk_ids(session, tokens.fetch("member"), selective)
      admin_hits = walk_ids(session, tokens.fetch("admin"), admin_only)
      outsider_admin = walk_ids(session, tokens.fetch("outsider"), admin_only)
      member_admin = walk_ids(session, tokens.fetch("member"), admin_only)

      expect_set(failures, "outsider selective search", outsider_selective, public_ids)
      expect_set(failures, "member selective search", member_selective, public_ids + restricted_ids)
      expect_set(failures, "admin token search", admin_hits, admin_ids)
      expect_set(failures, "outsider admin-token search", outsider_admin, [])
      expect_set(failures, "member admin-token search", member_admin, [])

      pagination = pagination_notes(session, tokens.fetch("outsider"))
      {
        "passed" => failures.empty?,
        "failures" => failures,
        "pagination" => pagination
      }
    end
    private_class_method :visibility_checks

    def self.expect_set(failures, label, pages, expected)
      flat = pages.flatten
      duplicates = pages.sum { |page| page.size - page.uniq.size }
      overlap = pages.each_cons(2).sum { |left, right| (left & right).size }
      failures << "#{label} returned duplicate ids inside a page" if duplicates.positive?
      failures << "#{label} repeated ids across adjacent pages" if overlap.positive?
      return if flat.sort == expected.sort

      failures << "#{label} returned #{flat.size} ids, expected #{expected.size}. Re-run bench:prepare if this dataset is old."
    end
    private_class_method :expect_set

    def self.walk_ids(session, token, params)
      pages = []
      10.times do |index|
        _elapsed, status, body = fetch(session, token, params.merge(page: index + 1))
        raise CheckFailed, "GET /api/events failed with #{status}: #{error_text(body)}" unless status == 200

        ids = Array(body["data"]).map { |row| row.fetch("id") }
        pages << ids
        break if ids.size < PAGE_SIZE
      end
      pages
    end
    private_class_method :walk_ids

    def self.pagination_notes(session, token)
      first = fetch(session, token, {})
      second = fetch(session, token, {})
      third = fetch(session, token, { page: 2 })
      [first, second, third].each do |elapsed, status, body|
        raise CheckFailed, "upcoming list failed with #{status}" unless status == 200
        raise CheckFailed, "timing placeholder #{elapsed}" if elapsed.nil?
      end
      page_a = Array(first[2]["data"]).map { |row| row.fetch("id") }
      page_b = Array(second[2]["data"]).map { |row| row.fetch("id") }
      page_2 = Array(third[2]["data"]).map { |row| row.fetch("id") }
      {
        "page_1_stable" => page_a == page_b,
        "page_1_and_2_overlap" => (page_a & page_2).size,
        "duplicate_ids_on_page_1" => page_a.size - page_a.uniq.size
      }
    end
    private_class_method :pagination_notes

    def self.time_scenario(session, tokens, scenario, iterations:, warmup:, explain:)
      token = tokens.fetch(scenario.fetch(:user))
      params = scenario.fetch(:params)
      warmup.times { fetch(session, token, params) }
      samples = []
      rows = nil
      digest = nil
      queries = []
      iterations.times do |index|
        if index.zero?
          elapsed, status, body, queries = fetch_with_sql(session, token, params)
        else
          elapsed, status, body = fetch(session, token, params)
        end
        raise CheckFailed, "#{scenario[:name]} failed with #{status}: #{error_text(body)}" unless status == 200

        ids = Array(body["data"]).map { |row| row.fetch("id") }
        rows = ids.size
        digest = Digest::SHA256.hexdigest(ids.join(","))
        samples << elapsed
      end

      summary(samples).merge(
        "name" => scenario.fetch(:name),
        "user" => scenario.fetch(:user),
        "params" => scenario.fetch(:params).transform_keys(&:to_s),
        "rows" => rows,
        "ids_sha256" => digest,
        "sql_count" => queries.size,
        "sql_ms" => queries.sum { |query| query["ms"] }.round(2),
        "queries" => queries,
        "explain" => explain ? explain_scenario(scenario) : nil
      )
    end
    private_class_method :time_scenario

    def self.time_mix(session, tokens, scenarios, mix_requests)
      return { "samples" => 0 } unless mix_requests.positive?

      rng = Random.new(Dataset::SEED)
      samples = Array.new(mix_requests) do
        name = pick_mix(rng)
        scenario = scenarios.fetch(name.to_sym)
        elapsed, status, = fetch(session, tokens.fetch(scenario.fetch(:user)), scenario.fetch(:params))
        raise CheckFailed, "mix request #{name} failed with #{status}" unless status == 200

        elapsed
      end
      summary(samples).merge("samples" => mix_requests, "weights" => MIX.to_h)
    end
    private_class_method :time_mix

    def self.pick_mix(rng)
      roll = rng.rand(100)
      cursor = 0
      MIX.each do |name, weight|
        cursor += weight
        return name if roll < cursor
      end
      MIX.last.first
    end
    private_class_method :pick_mix

    def self.summary(samples)
      sorted = samples.sort
      {
        "samples" => samples.size,
        "min_ms" => sorted.first.round(2),
        "mean_ms" => (samples.sum / samples.size.to_f).round(2),
        "p50_ms" => percentile(sorted, 0.50).round(2),
        "p95_ms" => percentile(sorted, 0.95).round(2),
        "p99_ms" => percentile(sorted, 0.99).round(2),
        "max_ms" => sorted.last.round(2)
      }
    end
    private_class_method :summary

    def self.percentile(sorted, fraction)
      index = [(fraction * sorted.length).ceil, 1].max - 1
      sorted[index]
    end
    private_class_method :percentile

    def self.fetch(session, token, params)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      session.get("/api/events", params: params, headers: { "Authorization" => "Bearer #{token}" })
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
      status = session.response.status
      body = parse_body(session)
      [elapsed, status, body]
    end
    private_class_method :fetch

    def self.fetch_with_sql(session, token, params)
      queries = []
      callback = lambda do |_name, _started, _finished, _id, payload|
        sql = payload[:sql].to_s
        return if payload[:name] == "SCHEMA" || payload[:name] == "CACHE"
        return if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)\b/i)

        queries << { "name" => payload[:name], "ms" => payload[:duration].to_f.round(2), "sql" => sql }
      end
      elapsed = status = body = nil
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        elapsed, status, body = fetch(session, token, params)
      end
      [elapsed, status, body, queries]
    end
    private_class_method :fetch_with_sql

    def self.parse_body(session)
      JSON.parse(session.response.body)
    rescue JSON::ParserError
      { "_invalid" => session.response.body.to_s }
    end

    def self.error_text(body)
      return body.dig("error", "message") if body["error"].is_a?(Hash)

      body["_invalid"].to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip.byteslice(0, 400)
    end
    private_class_method :error_text
    private_class_method :parse_body

    def self.explain_scenario(scenario)
      user = User.find_by!(email: persona_email(scenario.fetch(:user)))
      relation = list_relation(user, scenario.fetch(:params))
      sql = ActiveRecord::Base.connection.unprepared_statement { relation.except(:includes).to_sql }
      rows = ActiveRecord::Base.connection.exec_query("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{sql}")
      parsed = JSON.parse(rows.rows.first.first).first
      access = []
      walk_plan(parsed["Plan"], access)
      event_node = access.find { |node| node["relation"] == "events" }
      filter = event_node && event_node["filter"].to_s.include?("~~*") ? "ILIKE" : nil
      {
        "execution_ms" => parsed["Execution Time"].to_f.round(2),
        "planning_ms" => parsed["Planning Time"].to_f.round(2),
        "seq_scans" => access.select { |node| node["type"].to_s.include?("Seq Scan") }.map { |node| node["relation"] }.compact.uniq,
        "event_access" => event_node ? event_node["type"] : parsed.dig("Plan", "Node Type"),
        "event_filter" => filter
      }
    rescue StandardError => error
      { "error" => error.message }
    end
    private_class_method :explain_scenario

    def self.walk_plan(node, access)
      return unless node.is_a?(Hash)

      access << {
        "type" => node["Node Type"],
        "relation" => node["Relation Name"],
        "filter" => node["Filter"]
      }
      Array(node["Plans"]).each { |child| walk_plan(child, access) }
    end
    private_class_method :walk_plan

    def self.list_relation(user, params)
      events = EventPolicy::Scope.new(user, Event.all).resolve.published.includes(:organization, :topics).order(:starts_at)
      events = events.upcoming if upcoming_param?(params)
      events = events.matching_text(params[:q]) if params[:q].present?
      events = events.in_location(params[:location]) if params[:location].present?
      events = events.with_topic(params[:topic_id]) if params[:topic_id].present?
      page = [params.fetch(:page, 1).to_i, 1].max
      events.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
    end
    private_class_method :list_relation

    def self.upcoming_param?(params)
      ActiveModel::Type::Boolean.new.cast(params.fetch(:upcoming, true))
    end
    private_class_method :upcoming_param?

    def self.persona_email(role)
      {
        "outsider" => "bench-outsider@example.com",
        "member" => "bench-member@example.com",
        "admin" => "bench-admin@example.com"
      }.fetch(role)
    end
    private_class_method :persona_email

    def self.cache_hit_sample(session, token, scenario)
      previous = Rails.cache
      url = ENV.fetch("CACHE_REDIS_URL", "redis://localhost:6379/1")
      redis = Redis.new(url: url, connect_timeout: 0.3, read_timeout: 0.3, write_timeout: 0.3)
      return { "status" => "skipped", "reason" => "redis unavailable" } unless redis.ping == "PONG"

      Rails.cache = ActiveSupport::Cache.lookup_store(:redis_cache_store, url: url)
      2.times { fetch(session, token, scenario.fetch(:params)) }
      samples = Array.new(5) do
        elapsed, status, = fetch(session, token, scenario.fetch(:params))
        raise CheckFailed, "cache-hit sample failed with #{status}" unless status == 200

        elapsed
      end
      summary(samples).merge(
        "status" => "measured",
        "note" => "Unfiltered first page only. The cache key still reads memberships from Postgres."
      )
    rescue StandardError => error
      { "status" => "skipped", "reason" => error.message }
    ensure
      Rails.cache = previous if previous
      redis&.close
    end
    private_class_method :cache_hit_sample

    def self.git_sha
      root = Rails.root.join("..").to_s
      sha = IO.popen(["git", "-C", root, "rev-parse", "--short", "HEAD"], err: File::NULL, &:read).to_s.strip
      sha.empty? ? nil : sha
    rescue StandardError
      nil
    end
    private_class_method :git_sha

    def self.id_range(ranges, key)
      first_id, last_id = ranges.fetch(key)
      (first_id..last_id).to_a
    end
    private_class_method :id_range
  end
end
