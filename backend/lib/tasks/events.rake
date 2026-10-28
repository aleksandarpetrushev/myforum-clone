namespace :events do
  desc "Re-enqueue the registration cascade for cancelled events that still have confirmed registrations"
  task resume_cancellations: :environment do
    ids = Events::StuckCancellations.scope.ids
    ids.each { |event_id| CancelEventRegistrationsJob.perform_later(event_id) }
    puts "Re-enqueued #{ids.size} cancelled event(s): #{ids.join(", ")}"
  end
end
