# Local production-shaped Puma for bench:traffic.
# WEB_CONCURRENCY selects the worker count. Puma reads that variable itself.
# The default is one worker and five threads, matching config/puma.rb.
# TLS is terminated here so config.force_ssl accepts the request.

threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", "5"))
threads threads_count, threads_count
environment ENV.fetch("RAILS_ENV", "production")
preload_app!
pidfile ENV.fetch("PIDFILE", "tmp/bench/puma.pid")
ssl_bind "127.0.0.1", ENV.fetch("PORT", "3999"),
  key: ENV.fetch("BENCH_SSL_KEY"),
  cert: ENV.fetch("BENCH_SSL_CERT")

before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
end

before_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
end
