namespace :outbox do
  desc "Send deferred outbox rows to the personalization service again (after it learns a new schema_version)"
  task redeliver_deferred: :environment do
    result = Outbox::RedeliverDeferred.new.call
    puts "Delivered #{result.delivered} deferred row(s); #{result.still_deferred} still deferred."
  end
end
