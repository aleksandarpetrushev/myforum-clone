module Events
  # Cancelled events whose cascade has not finished: someone is still registered, waiting or offered a seat.
  class StuckCancellations
    def self.scope
      Event.where(status: "cancelled")
           .where(id: Registration.where(status: Registration::ACTIVE_STATUSES).select(:event_id))
    end
  end
end
