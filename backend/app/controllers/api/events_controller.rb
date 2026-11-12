module Api
  class EventsController < BaseController
    def index
      render json: { "data" => list_payload }
    end

    def show
      event = policy_scope(Event).find(params[:id])
      authorize event
      render json: Events::Cache.fetch_detail(event.id).merge(viewer_details(event))
    end

    def create
      event = Event.new(organization_id: create_params[:organization_id])
      authorize event
      created = Events::Create.new(organization: event.organization, attributes: create_params.except(:organization_id)).call
      render json: created.as_detail_json.merge("allowed_organization_ids" => created.allowed_organization_ids),
             status: :created
    end

    def update
      event = policy_scope(Event).find(params[:id])
      authorize event
      updated = Events::Update.new(event: event, attributes: event_params).call
      render json: updated.as_detail_json
    end

    # MF-105: publishes a draft. Events::Update checks and publishes in one transaction under the row lock, so a
    # refusal (start passed, restricted with no allowed organizations, not a draft) is 422 with its reasons.
    def publish
      event = policy_scope(Event).find(params[:id])
      authorize event, :update?
      published = Events::Update.new(event: event, attributes: { "status" => "published" }).call
      render json: published.as_detail_json.merge(viewer_details(published))
    end

    def cancel
      event = policy_scope(Event).find(params[:id])
      authorize event
      cancelled = Events::Cancel.new(event: event).call
      render json: cancelled.as_detail_json
    rescue Events::Cancel::EventStarted
      render_event_started
    end

    def destroy
      event = policy_scope(Event).find(params[:id])
      authorize event
      event.destroy!
      Events::Cache.invalidate(event.id)
      head :no_content
    end

    private

    # Per-viewer additions to the shared cached detail (MF-202): never cached, because they differ by user.
    def viewer_details(event)
      registration = current_user.registrations.find_by(event_id: event.id)
      details = {
        "my_registration" => registration&.as_json_api(event_visible: false, waitlist_position: registration.waitlist_position)
          &.slice("id", "status", "cancelled_by", "waitlist_position", "offer_expires_at")
      }
      details["waitlist_count"] = event.registrations.where(status: "waitlisted").count if EventPolicy.new(current_user, event).update?
      details
    end

    def render_event_started
      render_error(code: "event_started", message: "An event cannot be cancelled after it starts.", status: :unprocessable_entity)
    end

    def list_payload
      if cacheable_list?
        Events::Cache.fetch_upcoming_list(current_user) { serialize(filtered_events) }
      else
        serialize(filtered_events)
      end
    end

    def filtered_events
      events = policy_scope(Event).published.includes(:organization, :topics).in_start_order
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
      params.require(:event).permit(:title, :description, :starts_at, :ends_at, :location, :kind, :capacity, :status, :visibility, allowed_organization_ids: [])
    end

    # Separate from event_params: create also takes the organization and topics, and its status rules differ.
    def create_params
      params.require(:event).permit(
        :organization_id, :title, :description, :starts_at, :ends_at, :location, :kind, :capacity, :status, :visibility,
        allowed_organization_ids: [], topic_ids: []
      )
    end
  end
end
