module Events
  # Cancelled events whose cascade has not finished: they still have confirmed registrations.
  class StuckCancellations
    def self.scope
      Event.where(status: "cancelled")
           .where(id: Registration.where(status: "confirmed").select(:event_id))
    end
  end
end
