namespace :bench do
  desc "Create my_forum_benchmark and load discovery data. BENCH_SCALE=full|smoke|tiny"
  task prepare: :environment do
    scale = ENV.fetch("BENCH_SCALE", "full")
    Bench::Database.prepare!
    manifest = Bench::Dataset.generate!(scale: scale)
    Bench::Dataset.print_summary(manifest)
  end

  desc "Time GET /api/events against my_forum_benchmark"
  task discover: :environment do
    Bench::Database.establish!
    report = Bench::Discovery.run!
    path = Bench::Discovery.write(report)
    Bench::Discovery.print_report(report)
    puts
    puts "wrote #{path}"
    abort("Visibility checks failed") unless report["checks_passed"]
  end

  desc "Offer 300 requests/sec to production-mode Puma. BENCH_RATE BENCH_DURATION"
  task traffic: :environment do
    report = Bench::Traffic.run!
    path = Bench::Traffic.write(report)
    Bench::Traffic.print_report(report)
    puts
    puts "wrote #{path}"
  end

  desc "Load the benchmark dataset and time discovery"
  task run: :environment do
    Rake::Task["bench:prepare"].invoke
    Rake::Task["bench:discover"].invoke
  end
end
