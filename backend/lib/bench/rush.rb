require "json"
require "net/http"
require "openssl"
require "timeout"

module Bench
  # MF-302: the programme-publish rush, against the targets agreed with the programme manager
  # (docs/design/MF-302.md).
  #
  # Runs production-mode Puma (Bench::Traffic::Server), Sidekiq and the Go personalization service against
  # my_forum_benchmark, on their own Redis databases so nothing reaches the development queue or cache.
  # Participants arrive on the agreed curve (two thirds in the first fifth of the window, the rest spread over
  # the remaining four fifths). Each browses, checks recommendations, books 4 to 6 sessions (70% of bookings on
  # the 20 hot sessions; joins the waitlist when one is full) and checks My registrations and notifications:
  # about 25 requests, with 1 to 4 seconds between them. Afterwards the database is checked for wrong outcomes.
  class Rush
    PARTICIPANTS = 3_000
    MINUTES = 10
    PERSONALIZATION_PORT = 8099
    QUEUE_REDIS = "redis://localhost:6379/5"
    CACHE_REDIS = "redis://localhost:6379/6"
    TIMEOUT = 10
    THINK = (1.0..4.0)
    HOT_SHARE = 0.7
    KEYNOTE_WEIGHT = 3
    EXPECTED_CODES = %w[event_full duplicate_registration seats_available waitlist_closed].freeze
    GO_MEMORY_LIMIT_MB = 512

    TARGETS = {
      "registration_p95_ms" => 1_200, "registration_p99_ms" => 3_500,
      "page_p95_ms" => 500, "page_p99_ms" => 1_500,
      "error_percent" => 0.1, "wrong_outcomes" => 0,
      "notification_lag_p95_s" => 60, "notification_lag_max_s" => 120,
      "go_memory_percent_of_limit" => 70
    }.freeze

    def self.run!(scale: 1.0, minutes: MINUTES)
      new(scale: scale, minutes: minutes).run!
    end

    def initialize(scale:, minutes:)
      @scale = scale
      @minutes = minutes
      @participants = (PARTICIPANTS * scale).round
      @dir = Rails.root.join("tmp/bench")
      FileUtils.mkdir_p(@dir)
    end

    def run!
      Database.establish!
      isolate_from_development!
      log "building the programme for #{@participants} participants"
      @programme = Programme.prepare!(participants: @participants)
      raise "Setting up the programme enqueued jobs; they would have gone to the wrong queue" if ActiveJob::Base.queue_adapter.enqueued_jobs.any?

      @tokens = @programme["participant_ids"].to_h { |id| [id, JWT.encode({ "sub" => id, "exp" => 3.hours.from_now.to_i }, Traffic::SECRET, "HS256")] }
      database_url = Traffic.send(:benchmark_url)
      start_go
      start_sidekiq(database_url)
      @puma = Traffic::Server.start(database_url: database_url, certs: Traffic.send(:ensure_certs), extra_env: app_env(database_url).except("RAILS_ENV", "DATABASE_URL", "JWT_SECRET"))
      start_outbox_chain(database_url)
      log "delivering the setup rows (sessions, topic follows) to personalization"
      wait_for_outbox(timeout: 900) || raise("The setup outbox rows did not drain in 15 minutes")

      @memory = MemorySampler.new(@go_pid)
      run_started_at = Time.current
      samples, lateness = drive
      log "rush finished; waiting for notifications to drain"
      drained = wait_for_outbox(timeout: 300)
      @memory.stop
      report(samples, lateness, run_started_at, drained)
    ensure
      @memory&.stop
      @puma&.stop
      stop_process(@sidekiq_pid, "sidekiq")
      stop_process(@go_pid, "personalization")
    end

    def self.write(report)
      path = Rails.root.join("tmp/bench/rush-#{report["scale"]}x.json")
      path.write(JSON.pretty_generate(report))
      path
    end

    def self.print_report(report)
      puts
      puts "Programme rush at #{report["scale"]}x: #{report["participants"]} participants over #{report["minutes"]} min"
      puts format("requests %d   peak %d/s (busiest second)   generator late at start p99 %.0f ms", report["requests"], report["peak_rps"], report.dig("generator", "start_lateness_p99_ms"))
      report.fetch("checks").each do |check|
        puts format("  %-4s %-34s %12s   target %s", check["pass"] ? "PASS" : "FAIL", check["name"], check["actual"].inspect, check["target"])
      end
      puts "statuses #{report["statuses"].inspect}"
      puts "outcomes #{report["outcomes"].inspect}"
    end

    private

    # The rake process builds the programme with the app's own services. Their cache writes go to the bench cache,
    # and any job they enqueued would fail the run instead of reaching the development Sidekiq.
    def isolate_from_development!
      [QUEUE_REDIS, CACHE_REDIS].each do |url|
        db = url.split("/").last
        system("redis-cli", "-n", db, "flushdb", out: File::NULL) || raise("Could not flush Redis db #{db}")
      end
      Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(url: CACHE_REDIS)
      ActiveJob::Base.queue_adapter = :test
    end

    def app_env(database_url)
      {
        "RAILS_ENV" => "production",
        "DATABASE_URL" => database_url,
        "JWT_SECRET" => Traffic::SECRET,
        "REDIS_URL" => QUEUE_REDIS,
        "CACHE_REDIS_URL" => CACHE_REDIS,
        "PERSONALIZATION_URL" => "http://127.0.0.1:#{PERSONALIZATION_PORT}",
        "RAILS_MAX_THREADS" => "5",
        "RAILS_LOG_LEVEL" => "warn",
        "BUNDLE_PATH" => nil,
        "BUNDLE_USER_HOME" => nil
      }
    end

    def start_go
      binary = @dir.join("personalization-bench").to_s
      go_dir = Rails.root.join("../personalization").to_s
      system("go", "build", "-o", binary, "./cmd/personalization", chdir: go_dir) || raise("go build failed")
      config = Database.benchmark_config
      url = "postgres://#{config[:host] || "localhost"}:#{config[:port] || 5432}/#{Database::NAME}?sslmode=disable"
      @go_pid = Process.spawn({ "DATABASE_URL" => url, "PORT" => PERSONALIZATION_PORT.to_s }, binary,
        out: [@dir.join("personalization.log").to_s, "w"], err: [:child, :out], pgroup: true)
      wait_until("personalization to answer /health") do
        Net::HTTP.get_response(URI("http://127.0.0.1:#{PERSONALIZATION_PORT}/health")).is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end
    end

    def start_sidekiq(database_url)
      log_path = @dir.join("sidekiq.log")
      @sidekiq_pid = Process.spawn(app_env(database_url), "bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml",
        chdir: Rails.root.to_s, out: [log_path.to_s, "w"], err: [:child, :out], pgroup: true)
      wait_until("Sidekiq to boot") { File.exist?(log_path) && File.read(log_path).include?("Booted Rails") }
    end

    # One polling chain in the bench Redis (db 5), which nothing else uses: the development chain is untouched.
    def start_outbox_chain(database_url)
      system(app_env(database_url), "bin/rails", "runner", "ProcessOutboxJob.perform_later", chdir: Rails.root.to_s) ||
        raise("Could not start the outbox chain")
    end

    def wait_for_outbox(timeout:)
      deadline = monotonic + timeout
      quiet_since = nil
      while monotonic < deadline
        waiting = OutboxEvent.where(status: %w[pending deferred]).count
        unanswered = OutboxEvent.where(event_type: notifying_types, notification_outcome: nil).count
        if waiting.zero? && unanswered.zero?
          quiet_since ||= monotonic
          return true if monotonic - quiet_since >= 3
        else
          quiet_since = nil
        end
        sleep 1
      end
      false
    end

    def notifying_types
      %w[RegistrationCreated RegistrationCancelled EventCancelled WaitlistOffered WaitlistOfferExpired]
    end

    # --- the load ---

    def drive
      plans = Array.new(@participants) { |index| plan_for(index) }
      samples = Queue.new
      lateness = Queue.new
      window = @minutes * 60.0
      first_group = (@participants * 2 / 3.0).round
      started = monotonic
      threads = []
      next_report = started + 15
      plans.each_with_index do |plan, index|
        offset = index < first_group ? window * 0.2 * index / first_group : window * (0.2 + 0.8 * (index - first_group) / [@participants - first_group, 1].max)
        due = started + offset
        now = monotonic
        sleep(due - now) if due > now
        lateness << ((monotonic - due) * 1000)
        threads << Thread.new(plan) { |p| run_participant(p, samples, started) }
        if monotonic >= next_report
          log format("t=%3ds arrived %d/%d samples %d", monotonic - started, index + 1, @participants, samples.size)
          next_report += 15
        end
      end
      threads.each(&:join)
      [drain(samples), drain(lateness)]
    end

    def plan_for(index)
      rng = Random.new(Programme::SEED + index)
      user_id = @programme["participant_ids"].fetch(index)
      hot = @programme["keynote_ids"].flat_map { |id| [id] * KEYNOTE_WEIGHT } + @programme["popular_ids"]
      regular = @programme["regular_ids"]
      bookings = []
      wanted = rng.rand(4..6)
      while bookings.size < wanted
        pool = rng.rand < HOT_SHARE ? hot : regular
        id = pool.sample(random: rng)
        bookings << id unless bookings.include?(id)
      end
      browse = (regular - bookings).sample(5, random: rng)
      steps = [
        [:get, "/api/events", "discovery"],
        [:get, "/api/me/recommendations", "recommendations"],
        [:get, "/api/events?topic_id=#{@programme["topic_ids"].sample(random: rng)}", "discovery_topic"],
        [:get, "/api/events?q=#{@programme["search_token"]}", "discovery_search"]
      ]
      browse.zip(bookings).each do |viewed, booked|
        steps << [:get, "/api/events/#{viewed}", "session_page"] if viewed
        steps << [:book, booked] if booked
      end
      bookings.drop(browse.size).each { |booked| steps << [:book, booked] }
      steps << [:get, "/api/me/registrations", "my_registrations"]
      steps << [:get, "/api/me/notifications", "notifications"]
      { "user_id" => user_id, "steps" => steps, "rng" => rng }
    end

    def run_participant(plan, samples, started)
      client = Client.new(@tokens.fetch(plan["user_id"]))
      plan["steps"].each do |step|
        if step.first == :book
          event_id = step[1]
          record(samples, started, plan, client.get("/api/events/#{event_id}"), "session_page", "page")
          created = client.post("/api/registrations", event_id: event_id)
          record(samples, started, plan, created, "register", "registration", event_id)
          if created[:status] == 409 && created[:code] == "event_full"
            record(samples, started, plan, client.post("/api/registrations/waitlist", event_id: event_id), "join_waitlist", "registration", event_id)
          end
          record(samples, started, plan, client.get("/api/events/#{event_id}"), "session_page", "page")
        else
          record(samples, started, plan, client.get(step[1]), step[2], "page")
        end
        sleep plan["rng"].rand(THINK)
      end
    ensure
      client&.close
    end

    def record(samples, started, plan, result, name, kind, event_id = nil)
      samples << result.merge(name: name, kind: kind, user_id: plan["user_id"], event_id: event_id, at: result[:sent_at] - started)
    end

    def drain(queue)
      items = []
      items << queue.pop until queue.empty?
      items
    end

    # --- the report ---

    def report(samples, lateness, run_started_at, drained)
      registration = samples.select { |s| s[:kind] == "registration" }
      pages = samples.select { |s| s[:kind] == "page" }
      errors = samples.count { |s| s[:status].zero? || s[:status] >= 500 }
      unexpected = samples.select { |s| unexpected?(s) }
      outcomes = outcomes(samples)
      lag = notification_lag(run_started_at)
      memory_peak = @memory.peak_mb
      per_second = samples.group_by { |s| s[:at].floor }.transform_values(&:size)
      actual = {
        "registration_p95_ms" => pct(registration, 0.95), "registration_p99_ms" => pct(registration, 0.99),
        "page_p95_ms" => pct(pages, 0.95), "page_p99_ms" => pct(pages, 0.99),
        "error_percent" => (100.0 * errors / [samples.size, 1].max).round(3),
        "wrong_outcomes" => outcomes.values_at("over_capacity", "counter_drift", "duplicate_rows", "lost_bookings", "lost_waitlist_places").sum,
        "notification_lag_p95_s" => lag["p95_s"], "notification_lag_max_s" => lag["max_s"],
        "go_memory_percent_of_limit" => (100.0 * memory_peak / GO_MEMORY_LIMIT_MB).round(1)
      }
      checks = TARGETS.map do |name, target|
        value = actual[name]
        { "name" => name, "actual" => value, "target" => "<= #{target}", "pass" => !value.nil? && value <= target }
      end
      checks << { "name" => "outbox drained after the rush", "actual" => drained, "target" => "true", "pass" => drained }
      checks << { "name" => "unexpected responses (test bugs)", "actual" => unexpected.size, "target" => "0", "pass" => unexpected.empty? }
      {
        "generated_at" => Time.current.iso8601,
        "scale" => @scale, "participants" => @participants, "minutes" => @minutes,
        "note" => "One local machine runs the generator, Puma (#{Traffic.worker_count} workers x #{Traffic::THREADS} threads), Sidekiq (#{sidekiq_concurrency} threads), the Go service and Postgres. Not a deployed environment.",
        "requests" => samples.size,
        "peak_rps" => per_second.values.max.to_i,
        "rps_by_10s" => samples.group_by { |s| (s[:at] / 10).floor * 10 }.sort.to_h.transform_values { |v| (v.size / 10.0).round(1) },
        "checks" => checks,
        "statuses" => samples.group_by { |s| [s[:status], s[:code]].compact.join(" ") }.transform_values(&:size),
        "by_request" => samples.group_by { |s| s[:name] }.to_h { |name, rows| [name, { "n" => rows.size, "p50_ms" => pct(rows, 0.5), "p95_ms" => pct(rows, 0.95), "p99_ms" => pct(rows, 0.99), "errors" => rows.count { |s| s[:status].zero? || s[:status] >= 500 } }] },
        "hot_sessions" => hot_session_rows(registration),
        "outcomes" => outcomes,
        "notification_lag" => lag,
        "go_memory_peak_mb" => memory_peak,
        "generator" => { "start_lateness_p99_ms" => percentile(lateness.sort, 0.99), "start_lateness_max_ms" => lateness.max&.round },
        "unexpected_examples" => unexpected.first(10).map { |s| s.slice(:name, :status, :code, :event_id) }
      }
    end

    def unexpected?(sample)
      status = sample[:status]
      return false if status.zero? || status >= 500 || status < 400
      !EXPECTED_CODES.include?(sample[:code])
    end

    # Wrong outcomes, from the database. A 201 the participant saw must be a row; a seat count must match its rows.
    def outcomes(samples)
      programme_ids = @programme.values_at("keynote_ids", "popular_ids", "regular_ids").flatten
      events = Event.where(id: programme_ids)
      counts = Registration.where(event_id: programme_ids, status: %w[confirmed offered]).group(:event_id).count
      rows = Registration.where(event_id: programme_ids).pluck(:user_id, :event_id, :status).group_by { |u, e, _| [u, e] }
      confirmed_told = samples.select { |s| s[:name] == "register" && s[:status] == 201 }
      waitlist_told = samples.select { |s| s[:name] == "join_waitlist" && [200, 201].include?(s[:status]) }
      timed_out = samples.select { |s| s[:name] == "register" && s[:status].zero? }
      {
        "over_capacity" => events.count { |e| e.reserved_spots > e.capacity },
        "counter_drift" => events.count { |e| e.reserved_spots != counts.fetch(e.id, 0) },
        "duplicate_rows" => rows.count { |_, list| list.size > 1 },
        "lost_bookings" => confirmed_told.count { |s| rows.dig([s[:user_id], s[:event_id]], 0, 2) != "confirmed" },
        "lost_waitlist_places" => waitlist_told.count { |s| rows.dig([s[:user_id], s[:event_id]], 0, 2) != "waitlisted" },
        "booked_but_told_timeout" => timed_out.count { |s| rows.dig([s[:user_id], s[:event_id]], 0, 2) == "confirmed" },
        "confirmed" => Registration.where(event_id: programme_ids, status: "confirmed").count,
        "waitlisted" => Registration.where(event_id: programme_ids, status: "waitlisted").count,
        "full_sessions" => events.count { |e| e.reserved_spots >= e.capacity }
      }
    end

    # From the booking's outbox row to the participant's notification row.
    def notification_lag(since)
      lags = ActiveRecord::Base.connection.select_values(<<~SQL.squish).map(&:to_f).sort
        SELECT EXTRACT(EPOCH FROM (n.created_at - o.created_at))
        FROM outbox_events o
        JOIN notifications n ON n.idempotency_key = 'notification:' || o.idempotency_key
        WHERE o.created_at >= #{ActiveRecord::Base.connection.quote(since)}
      SQL
      dispatch = OutboxEvent.where("created_at >= ?", since).where.not(published_at: nil)
        .pluck(Arel.sql("EXTRACT(EPOCH FROM (published_at - created_at))")).map(&:to_f).sort
      {
        "notifications" => lags.size,
        "p50_s" => percentile(lags, 0.5), "p95_s" => percentile(lags, 0.95), "max_s" => lags.last&.round(1),
        "outbox_dispatch_p95_s" => percentile(dispatch, 0.95), "outbox_dispatch_max_s" => dispatch.last&.round(1),
        "still_pending" => OutboxEvent.where(status: "pending").count, "deferred" => OutboxEvent.where(status: "deferred").count,
        "failing" => OutboxEvent.where("attempts > 0").count
      }
    end

    def hot_session_rows(registration)
      (@programme["keynote_ids"] + @programme["popular_ids"]).map do |id|
        rows = registration.select { |s| s[:event_id] == id && s[:name] == "register" }
        { "event_id" => id, "keynote" => @programme["keynote_ids"].include?(id), "attempts" => rows.size, "p95_ms" => pct(rows, 0.95), "p99_ms" => pct(rows, 0.99) }
      end
    end

    def pct(samples, fraction)
      percentile(samples.reject { |s| s[:status].zero? }.map { |s| s[:ms] }.sort, fraction)
    end

    def percentile(sorted, fraction)
      return nil if sorted.empty?

      sorted[[(fraction * sorted.length).ceil, 1].max - 1].round(1)
    end

    def sidekiq_concurrency
      Rails.root.join("config/sidekiq.yml").read[/concurrency:\s*(\d+)/, 1]&.to_i || 5
    end

    def wait_until(what, timeout: 120)
      deadline = monotonic + timeout
      until yield
        raise "Timed out waiting for #{what}" if monotonic > deadline

        sleep 0.5
      end
    end

    def stop_process(pid, name)
      return unless pid

      Process.kill("-TERM", Process.getpgid(pid))
      Timeout.timeout(20) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill("-KILL", Process.getpgid(pid))
      log "#{name} did not stop in 20 s and was killed"
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def log(message)
      $stdout.puts "[rush] #{message}"
    end

    class Client
      def initialize(token)
        @token = token
      end

      def get(path)
        perform(Net::HTTP::Get.new(path))
      end

      def post(path, body)
        request = Net::HTTP::Post.new(path)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
        perform(request)
      end

      def perform(request)
        request["Authorization"] = "Bearer #{@token}"
        request["Accept"] = "application/json"
        sent = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = connection.request(request)
        ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - sent) * 1000
        status = response.code.to_i
        code = status >= 400 ? (JSON.parse(response.body).dig("error", "code") rescue nil) : nil
        { status: status, code: code, ms: ms, sent_at: sent }
      rescue StandardError => error
        close
        { status: 0, code: error.class.name, ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - sent) * 1000, sent_at: sent }
      end

      def connection
        return @http if @http&.started?

        @http = Net::HTTP.new("127.0.0.1", Traffic::PORT).tap do |http|
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http.open_timeout = 5
          http.read_timeout = TIMEOUT
          http.write_timeout = TIMEOUT
          http.keep_alive_timeout = 30
          http.max_retries = 0 # a retried POST would book twice; a timeout is reported, never repeated
          http.start
        end
      end

      def close
        @http&.finish
      rescue StandardError
        nil
      ensure
        @http = nil
      end
    end

    # Samples the Go service's resident memory once a second.
    class MemorySampler
      attr_reader :peak_mb

      def initialize(pid)
        @peak_mb = 0.0
        @running = true
        @thread = Thread.new do
          while @running
            rss_kb = `ps -o rss= -p #{pid}`.to_i
            @peak_mb = [@peak_mb, rss_kb / 1024.0].max.round(1)
            sleep 1
          end
        end
      end

      def stop
        @running = false
        @thread&.join
      end
    end
  end
end
