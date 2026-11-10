# Scheduled at an offer's deadline (MF-202). Safe to run late, early or twice: Waitlist::ExpireOffer checks the
# registration is still offered at the same lifecycle_version and past its deadline.
class ExpireWaitlistOfferJob < ApplicationJob
  queue_as :default

  def perform(registration_id, lifecycle_version)
    Waitlist::ExpireOffer.call(registration_id, lifecycle_version)
  end
end
