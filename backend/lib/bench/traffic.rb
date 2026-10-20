require "net/http"
require "openssl"
require "socket"
require "timeout"
require "uri"

module Bench
  # Offers a fixed arrival rate at a production-mode Puma process.
  #
  # The server uses the benchmark database, Redis cache, force_ssl, and the
  # production Puma defaults (WEB_CONCURRENCY workers, five threads). Arrivals
  # follow the same discovery mix as Bench::Discovery. Latency above the
  # client timeout is an error.
  #
  # Throughput counts only HTTP 200 responses that finish inside the
  # measurement window. The generator then keeps serving for one second.
  # Completions in that drain, and work still queued or in flight at the
  # deadline, are reported separately and are not part of completed_rps.
  class Traffic
    PORT = 3999
    THREADS = 5
    TIMEOUT = 2
    DRAIN = 1
    SECRET = "bench-traffic-secret"

    def self.worker_count
      count = Integer(ENV.fetch("WEB_CONCURRENCY", "1"))
      raise ArgumentError, "WEB_CONCURRENCY must be positive" unless count.positive?

      count
    end

    def self.run!(rate: nil, duration: nil, warmup: nil)
      rate = (rate || ENV.fetch("BENCH_RATE", 300)).to_i
      duration = (duration || ENV.fetch("BENCH_DURATION", 20)).to_i
      warmup = (warmup || ENV.fetch("BENCH_WARMUP", 5)).to_i
      raise ArgumentError, "rate must be positive" unless rate.positive?
      raise ArgumentError, "duration must be positive" unless duration.positive?
      raise ArgumentError, "warmup must be zero or positive" if warmup.negative?

      manifest = Dataset.read_manifest
      Database.establish!
      expected = manifest.dig("counts", "events").to_i
      actual = Event.count
      raise "Manifest says #{expected} events but the benchmark database has #{actual}. Run bin/rails bench:prepare." unless actual == expected

      templates = templates(manifest)
      tokens = mint_tokens(manifest)
      database_url = benchmark_url
      ActiveRecord::Base.connection_pool.disconnect!
      certs = ensure_certs
      server = Server.start(database_url: database_url, certs: certs)
      drive(server, templates, tokens, rate: rate, duration: duration, warmup: warmup, manifest: manifest)
    ensure
      server&.stop
    end

    def self.templates(manifest)
      probes = manifest.fetch("probes")
      page = deep_page_number
      {
        "upcoming_page_1" => request_template("/api/events", "outsider"),
        "keyword_common" => request_template("/api/events", "outsider", q: probes.fetch("common_token")),
        "keyword_selective" => request_template("/api/events", "outsider", q: probes.fetch("selective_token")),
        "location" => request_template("/api/events", "outsider", location: probes.fetch("location")),
        "topic" => request_template("/api/events", "outsider", topic_id: probes.fetch("topic_id")),
        "combined" => request_template(
          "/api/events",
          "outsider",
          q: probes.fetch("common_token"),
          location: probes.fetch("location"),
          topic_id: probes.fetch("topic_id")
        ),
        "deep_page" => request_template("/api/events", "outsider", page: page)
      }
    end

    def self.schedule(templates, count, rng)
      Array.new(count) do
        name = pick(rng)
        templates.fetch(name).merge("scenario" => name)
      end
    end

    def self.write(report)
      path = Rails.root.join("tmp/bench/traffic.json")
      FileUtils.mkdir_p(path.dirname)
      path.write(JSON.pretty_generate(report))
      path
    end

    def self.print_report(report)
      puts
      puts report.fetch("note")
      puts "target #{report["target_rps"]} rps for #{report["duration_s"]}s after #{report["warmup_s"]}s warmup"
      puts "server #{report.dig("server", "environment")}  #{report.dig("server", "bind")}  workers #{report.dig("server", "workers")}  threads #{report.dig("server", "threads")}"
      puts "database #{report.dig("dataset", "database")}  scale #{report.dig("dataset", "scale")}  events #{report.dig("dataset", "events")}"
      puts
      puts format(
        "offered %6.1f rps    in-window %6.1f rps    success %5.1f%%    drain %d    deadline queued %d in flight %d    abandoned %d    errors %d",
        report["offered_rps"], report["completed_rps"], report["success_percent"],
        report["completed_during_drain"], report.dig("at_deadline", "queued"), report.dig("at_deadline", "in_flight"),
        report["abandoned"], report["errors"]
      )
      puts format("end-to-end  p50 %s ms   p95 %s ms   p99 %s ms", ms(report.dig("e2e_ms", "p50")), ms(report.dig("e2e_ms", "p95")), ms(report.dig("e2e_ms", "p99")))
      puts format("service     p50 %s ms   p95 %s ms   p99 %s ms", ms(report.dig("service_ms", "p50")), ms(report.dig("service_ms", "p95")), ms(report.dig("service_ms", "p99")))
      puts "statuses #{report["statuses"].inspect}"
      puts
      puts format("%-22s %7s %8s %8s %8s", "scenario", "n", "p50", "p95", "errors")
      report.fetch("scenarios").each do |scenario|
        puts format("%-22s %7d %8s %8s %8d", scenario["name"], scenario["samples"], ms(scenario["p50_ms"]), ms(scenario["p95_ms"]), scenario["errors"])
      end
    end

    def self.ms(value)
      value.nil? ? "    n/a" : format("%7.1f", value)
    end
    private_class_method :ms

    def self.request_template(path, user, params = {})
      query = URI.encode_www_form(params)
      full = query.empty? ? path : "#{path}?#{query}"
      { "path" => full, "user" => user }
    end
    private_class_method :request_template

    def self.deep_page_number
      rough = Event.published.upcoming.count
      pages = [(rough.to_f / Discovery::PAGE_SIZE).ceil, 1].max
      return 1 if pages < 2

      [[pages, 250].min, 2].max
    end
    private_class_method :deep_page_number

    def self.pick(rng)
      roll = rng.rand(100)
      cursor = 0
      Discovery::MIX.each do |name, weight|
        cursor += weight
        return name if roll < cursor
      end
      Discovery::MIX.last.first
    end
    private_class_method :pick

    def self.mint_tokens(manifest)
      manifest.fetch("personas").to_h do |role, persona|
        payload = { "sub" => persona.fetch("id"), "exp" => 2.hours.from_now.to_i }
        [role, JWT.encode(payload, SECRET, "HS256")]
      end
    end
    private_class_method :mint_tokens

    def self.benchmark_url
      config = Database.benchmark_config
      name = config.fetch(:database)
      if config[:host]
        user = ActiveRecord::Base.connection.select_value("SELECT current_user")
        password = config[:password]
        auth = password.nil? || password == "" ? user.to_s : "#{user}:#{password}"
        port = config[:port] ? ":#{config[:port]}" : ""
        "postgres://#{auth}@#{config[:host]}#{port}/#{name}"
      else
        # Socket connections have no host. URI rejects "user@/" so the database
        # name is the path and the server process uses the OS user.
        "postgres:///#{name}"
      end
    end
    private_class_method :benchmark_url

    def self.ensure_certs
      dir = Rails.root.join("tmp/bench")
      FileUtils.mkdir_p(dir)
      key = dir.join("localhost.key")
      cert = dir.join("localhost.crt")
      return { key: key.to_s, cert: cert.to_s } if key.exist? && cert.exist?

      system(
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
        "-keyout", key.to_s, "-out", cert.to_s, "-subj", "/CN=localhost",
        out: File::NULL, err: File::NULL
      ) || raise("openssl could not create the local certificate")
      { key: key.to_s, cert: cert.to_s }
    end
    private_class_method :ensure_certs

    def self.drive(server, templates, tokens, rate:, duration:, warmup:, manifest:)
      rng = Random.new(Dataset::SEED)
      queue = Queue.new
      offered = []
      mutex = Mutex.new
      stop = { "abandon" => false }
      concurrency = rate
      workers = Array.new(concurrency) do
        Thread.new do
          client = Client.new(tokens)
          loop do
            item = queue.pop
            break if item == :stop

            run = false
            mutex.synchronize do
              if stop["abandon"]
                item["unserved"] = true
              else
                item["started_at"] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                run = true
              end
            end
            next unless run

            result = client.perform(item)
            finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            mutex.synchronize do
              item["finished_at"] = finished
              item.merge!(result)
            end
          end
        end
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      measure_at = started + warmup
      finish_at = measure_at + duration
      interval = 1.0 / rate
      next_at = started
      next_report = started + 5
      while next_at < finish_at
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sleep(next_at - now) if next_at > now
        if next_at >= next_report
          $stdout.puts "  t=#{(next_at - started).round}s queue=#{queue.size}"
          next_report += 5
        end
        name = pick(rng)
        item = templates.fetch(name).merge("scheduled" => next_at, "scenario" => name)
        mutex.synchronize { offered << item }
        queue << item
        next_at += interval
      end

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(finish_at - now) if finish_at > now
      mutex.synchronize { mark_deadline!(offered, measure_at: measure_at, finish_at: finish_at) }

      sleep DRAIN
      stop["abandon"] = true
      concurrency.times { queue << :stop }
      workers.each(&:join)

      report(offered, manifest, rate: rate, duration: duration, warmup: warmup, measure_at: measure_at)
    end
    private_class_method :drive

    def self.mark_deadline!(offered, measure_at:, finish_at:)
      offered.each do |item|
        next if item["scheduled"] < measure_at

        item["at_deadline"] =
          if item["finished_at"] && item["finished_at"] <= finish_at
            "completed"
          elsif item["started_at"] && item["started_at"] <= finish_at
            "in_flight"
          else
            "queued"
          end
      end
    end
    private_class_method :mark_deadline!

    def self.summarize(samples, duration:, warmup:, measure_at:)
      measured = samples.select { |sample| sample["scheduled"] >= measure_at }
      window = measured.select { |sample| sample["at_deadline"] == "completed" }
      successes = window.select { |sample| sample["status"] == 200 }
      errors = window.reject { |sample| sample["status"] == 200 }
      drain = measured.select { |sample| sample["finished_at"] && sample["at_deadline"] != "completed" && !sample["unserved"] }
      {
        "warmup_s" => warmup,
        "duration_s" => duration,
        "drain_s" => DRAIN,
        "offered" => measured.size,
        "offered_rps" => (measured.size / duration.to_f).round(2),
        "completed_in_window" => successes.size,
        "completed_rps" => (successes.size / duration.to_f).round(2),
        "success_percent" => measured.empty? ? 0.0 : (100.0 * successes.size / measured.size).round(2),
        "errors" => errors.size,
        "completed_during_drain" => drain.size,
        "at_deadline" => {
          "queued" => measured.count { |sample| sample["at_deadline"] == "queued" },
          "in_flight" => measured.count { |sample| sample["at_deadline"] == "in_flight" }
        },
        "abandoned" => measured.count { |sample| sample["unserved"] },
        "statuses" => window.group_by { |sample| sample["status"] }.transform_values(&:size),
        "e2e_ms" => percentile_summary(successes.map { |sample| sample["e2e_ms"] }.compact.sort),
        "service_ms" => percentile_summary(successes.map { |sample| sample["service_ms"] }.compact.sort),
        "scenarios" => scenario_rows(measured)
      }
    end

    def self.report(recorded, manifest, rate:, duration:, warmup:, measure_at:)
      summarize(recorded, duration: duration, warmup: warmup, measure_at: measure_at).merge(
        "generated_at" => Time.current.iso8601,
        "note" => "Local production-mode Puma. TLS is terminated by Puma so force_ssl accepts the request. #{worker_count} #{worker_count == 1 ? "process" : "processes"} and #{THREADS} threads each. Redis cache is enabled. completed_rps counts HTTP 200 responses that finish inside the measurement window. service_ms for those responses includes waiting for a free Puma thread. Completions during the following #{DRAIN}s drain are excluded. This is not a deployed production environment.",
        "target_rps" => rate,
        "server" => {
          "environment" => "production",
          "bind" => "https://127.0.0.1:#{PORT}",
          "workers" => worker_count,
          "threads" => THREADS,
          "timeout_s" => TIMEOUT
        },
        "dataset" => {
          "database" => manifest["database"],
          "scale" => manifest["scale"],
          "events" => manifest.dig("counts", "events")
        }
      )
    end
    private_class_method :report

    def self.scenario_rows(measured)
      names = Discovery::MIX.map(&:first)
      names.map do |name|
        rows = measured.select { |sample| sample["scenario"] == name }
        successes = rows.select { |sample| sample["at_deadline"] == "completed" && sample["status"] == 200 }
        errors = rows.select { |sample| sample["at_deadline"] == "completed" && sample["status"] != 200 }
        times = successes.map { |sample| sample["service_ms"] }.compact.sort
        {
          "name" => name,
          "samples" => successes.size,
          "p50_ms" => percentile(times, 0.50),
          "p95_ms" => percentile(times, 0.95),
          "errors" => errors.size
        }
      end
    end
    private_class_method :scenario_rows

    def self.percentile_summary(sorted)
      {
        "p50" => percentile(sorted, 0.50),
        "p95" => percentile(sorted, 0.95),
        "p99" => percentile(sorted, 0.99)
      }
    end
    private_class_method :percentile_summary

    def self.percentile(sorted, fraction)
      return nil if sorted.empty?

      sorted[[(fraction * sorted.length).ceil, 1].max - 1].round(2)
    end
    private_class_method :percentile

    class Client
      def initialize(tokens)
        @tokens = tokens
        @http = nil
      end

      def perform(item)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = request(item)
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        {
          "scenario" => item["scenario"],
          "status" => response.code.to_i,
          "service_ms" => ((finished - started) * 1000),
          "e2e_ms" => ((finished - item["scheduled"]) * 1000)
        }
      rescue StandardError => error
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        close
        {
          "scenario" => item["scenario"],
          "status" => 0,
          "error" => error.class.name,
          "service_ms" => ((finished - started) * 1000),
          "e2e_ms" => ((finished - item["scheduled"]) * 1000)
        }
      end

      def request(item)
        http = connection
        req = Net::HTTP::Get.new(item.fetch("path"))
        token = @tokens[item["user"]]
        req["Authorization"] = "Bearer #{token}" if token
        req["Accept"] = "application/json"
        response = http.request(req)
        response.body
        response
      end

      def connection
        return @http if @http&.started?

        http = Net::HTTP.new("127.0.0.1", PORT)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.open_timeout = 1
        http.read_timeout = TIMEOUT
        http.write_timeout = TIMEOUT
        http.keep_alive_timeout = 30
        http.start
        @http = http
      end

      def close
        @http&.finish
      rescue StandardError
        nil
      ensure
        @http = nil
      end
    end

    class Server
      def self.start(database_url:, certs:)
        log = Rails.root.join("tmp/bench/puma.log")
        FileUtils.mkdir_p(log.dirname)
        pidfile = Rails.root.join("tmp/bench/puma.pid")
        raise "port #{PORT} is already in use" if port_open?

        env = {
          "RAILS_ENV" => "production",
          "DATABASE_URL" => database_url,
          "JWT_SECRET" => SECRET,
          "CACHE_REDIS_URL" => ENV.fetch("CACHE_REDIS_URL", "redis://localhost:6379/1"),
          "REDIS_URL" => ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
          "PORT" => PORT.to_s,
          "PIDFILE" => pidfile.to_s,
          "RAILS_MAX_THREADS" => THREADS.to_s,
          "WEB_CONCURRENCY" => Traffic.worker_count.to_s,
          "RAILS_LOG_LEVEL" => "info",
          "BENCH_SSL_KEY" => certs.fetch(:key),
          "BENCH_SSL_CERT" => certs.fetch(:cert),
          "BUNDLE_PATH" => nil,
          "BUNDLE_USER_HOME" => nil
        }
        pid = Process.spawn(
          env,
          "bundle", "exec", "puma", "-C", "config/puma_traffic.rb",
          chdir: Rails.root.to_s,
          pgroup: true,
          out: [log.to_s, "w"],
          err: [:child, :out]
        )
        server = new(pid, log)
        server.wait_until_ready
        server
      rescue StandardError
        server&.stop
        raise
      end

      def initialize(pid, log)
        @pid = pid
        @log = log
      end

      def wait_until_ready
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
        until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          return if healthy?
          raise "Puma exited during boot. #{log_tail}" unless alive?

          sleep 0.2
        end
        raise "Puma did not become ready. #{log_tail}"
      end

      def stop
        Process.kill("TERM", -@pid)
        Timeout.timeout(10) { Process.wait(@pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        Process.kill("KILL", -@pid)
        Process.wait(@pid)
      rescue StandardError
        nil
      end

      def healthy?
        client = Client.new({})
        response = client.request("path" => "/health")
        response.code.to_i == 200
      rescue StandardError
        false
      ensure
        client&.close
      end

      def alive?
        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH
        false
      end

      def log_tail
        return "" unless @log.exist?

        lines = @log.readlines
        cause = lines.find { |line| line.include?("Unable to load") || line.include?("Error") }
        [cause, *lines.last(12)].compact.join
      end

      def self.port_open?
        socket = Socket.tcp("127.0.0.1", PORT, connect_timeout: 0.2)
        socket.close
        true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError
        false
      end
    end
  end
end
