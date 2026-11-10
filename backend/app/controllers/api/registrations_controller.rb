module Api
  class RegistrationsController < BaseController
    def create
      event = policy_scope(Event).find(params[:event_id])
      authorize event, :show?
      @registration = Events::Register.new(user: current_user, event: event).call
      Metrics.increment("registration_success_total")
      render json: @registration.as_json_api, status: :created
    rescue Events::Register::AlreadyRegistered
      Metrics.increment("registration_failure_total")
      render_error(
        code: "duplicate_registration",
        message: "You are already registered for this event.",
        status: :conflict
      )
    end

    def cancel
      event = event_for_cancel
      @registration = Registrations::Cancel.new(user: current_user, event: event).call
      Metrics.increment("registration_cancel_success_total")
      render json: @registration.as_json_api(
        event_visible: EventPolicy.new(current_user, @registration.event).show?
      )
    rescue Registrations::Cancel::UserNotRegistered
      Metrics.increment("registration_cancel_failure_total")
      render_error(
        code: "user_not_registered",
        message: "You are not registered for this event.",
        status: :not_found
      )
    rescue Registrations::Cancel::InvalidState
      Metrics.increment("registration_cancel_failure_total")
      render_error(
        code: "invalid_registration_state",
        message: "This registration cannot be cancelled.",
        status: :unprocessable_entity
      )
    rescue Registrations::Cancel::EventStarted
      Metrics.increment("registration_cancel_failure_total")
      render_error(
        code: "event_started",
        message: "Cancellation is allowed only before the event starts.",
        status: :unprocessable_entity
      )
    end

    # MF-202: joins the line for a full event. 201 for a new place in line, 200 when already in it.
    def waitlist
      event = policy_scope(Event).find(params[:event_id])
      authorize event, :show?
      result = Waitlist::Join.new(user: current_user, event: event).call
      render json: result.registration.as_json_api, status: result.created ? :created : :ok
    rescue Waitlist::Join::AlreadyRegistered
      render_error(code: "duplicate_registration", message: "You are already registered for this event.", status: :conflict)
    rescue Waitlist::Join::SeatsAvailable
      render_error(code: "seats_available", message: "This event has free seats; register instead.", status: :conflict)
    rescue Waitlist::Join::Closed
      render_error(code: "waitlist_closed", message: "The waitlist closes one hour before the event starts.",
                   status: :unprocessable_entity)
    end

    # Confirms a seat offered from the waitlist. Like cancel, it works on the caller's own row even if they can no
    # longer see the event.
    def accept_offer
      registration = Waitlist::AcceptOffer.new(user: current_user, event: event_for_cancel).call
      render json: registration.as_json_api(event_visible: EventPolicy.new(current_user, registration.event).show?)
    rescue Waitlist::AcceptOffer::NoOffer
      render_error(code: "no_offer", message: "You have no open seat offer for this event.", status: :unprocessable_entity)
    end

    private

    # A caller who can no longer see the event can still cancel their own row.
    # Someone with no registration only reaches a visible event, so a hidden id stays not_found.
    def event_for_cancel
      registration = current_user.registrations.find_by(event_id: params[:event_id])
      return registration.event if registration

      policy_scope(Event).find(params[:event_id])
    end
  end
end
