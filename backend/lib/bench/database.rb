module Bench
  class Database
    NAME = "my_forum_benchmark"

    def self.prepare!
      raise "Refusing to build benchmark data in production" if Rails.env.production?

      config = benchmark_config
      create_fresh!(config)
      ActiveRecord::Base.establish_connection(config)
      load Rails.root.join("db/schema.rb")
    end

    def self.establish!
      ActiveRecord::Base.establish_connection(benchmark_config)
      ActiveRecord::Base.connection.select_value("SELECT 1")
    rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad => error
      raise "Could not open #{NAME} (#{error.message}). Run bin/rails bench:prepare."
    end

    def self.benchmark_config
      app_config.merge(database: NAME)
    end

    def self.app_config
      @app_config ||= begin
        raw = ActiveRecord::Base.connection_db_config.configuration_hash.symbolize_keys
        {
          adapter: raw[:adapter] || "postgresql",
          host: raw[:host],
          port: raw[:port],
          username: raw[:username],
          password: raw[:password],
          encoding: raw[:encoding] || "unicode",
          pool: raw[:pool] || 5,
          sslmode: raw[:sslmode]
        }.compact
      end
    end

    def self.create_fresh!(config)
      admin = config.merge(database: "postgres")
      ActiveRecord::Base.establish_connection(admin)
      quoted_name = ActiveRecord::Base.connection.quote(NAME)
      identifier = ActiveRecord::Base.connection.quote_table_name(NAME)
      exists = ActiveRecord::Base.connection.select_value("SELECT 1 FROM pg_database WHERE datname = #{quoted_name}")
      if exists
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          SELECT pg_terminate_backend(pid)
          FROM pg_stat_activity
          WHERE datname = #{quoted_name} AND pid <> pg_backend_pid()
        SQL
        ActiveRecord::Base.connection.execute("DROP DATABASE #{identifier}")
      end
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{identifier}")
    end
    private_class_method :create_fresh!
  end
end
