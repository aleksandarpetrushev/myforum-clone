namespace :waitlist do
  desc "Expire waitlist offers past their deadline whose expiry job never ran, and offer the seats on"
  task expire_overdue: :environment do
    count = Waitlist::ExpireOverdue.call
    puts "Expired #{count} overdue waitlist offer(s)."
  end
end
