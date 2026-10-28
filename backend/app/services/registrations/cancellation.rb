module Registrations
  # The registration state change shared by a participant's own cancel and the organizer's event cancellation.
  # Runs inside the caller's transaction, with the registration row locked. Seat counting is the caller's job:
  # Registrations::Cancel lowers it per registration, CancelEventRegistrationsJob recounts once at the end.
  class Cancellation
    def self.apply!(registration, by:)
      registration.lifecycle_version += 1
      registration.cancelled_by = by
      registration.cancel!
    end
  end
end
