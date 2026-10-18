module Api
  class EventsController < BaseController
    def index
      render json: { "data" => list_payload }
    end

    def show
      event = policy_scope(Event).find(params[:id])
      authorize event
      render json: Events::Cache.fetch_detail(event.id)
    end

    def update
      event = policy_scope(Event).find(params[:id])
      authorize event
      updated = Events::Update.new(event: event, attributes: event_params).call
      render json: updated.as_detail_json
    end

    def destroy
      event = policy_scope(Event).find(params[:id])
      authorize event
      event.destroy!
      Events::Cache.invalidate(event.id)
      head :no_content
    end

    def register
      event = policy_scope(Event).find(params[:id])
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

    private

    def list_payload
      if cacheable_list?
        Rails.cache.fetch(Events::Cache::UPCOMING_KEY, expires_in: Events::Cache::UPCOMING_TTL) do
          serialize(filtered_events)
        end
      else
        serialize(filtered_events)
      end
    end

    def filtered_events
      events = policy_scope(Event).published.includes(:organization, :topics).order(:starts_at)
      events = events.upcoming if upcoming?
      events = events.matching_text(params[:q]) if params[:q].present?
      events = events.in_location(params[:location]) if params[:location].present?
      events = events.with_topic(params[:topic_id]) if params[:topic_id].present?
      events.offset(offset).limit(per_page)
    end

    def serialize(events)
      events.map(&:as_list_json)
    end

    def cacheable_list?
      upcoming? && params[:q].blank? && params[:location].blank? && params[:topic_id].blank? && page == 1
    end

    def upcoming?
      ActiveModel::Type::Boolean.new.cast(params.fetch(:upcoming, true))
    end

    def page
      [params.fetch(:page, 1).to_i, 1].max
    end

    def per_page
      20
    end

    def offset
      (page - 1) * per_page
    end

    def event_params
      params.require(:event).permit(:title, :description, :starts_at, :ends_at, :location, :kind, :capacity, :status)
    end
  end
end
