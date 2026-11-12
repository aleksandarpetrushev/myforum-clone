module Api
  module Me
    # MF-105: the drafts of every organization the user administers, soonest first. Drafts never appear in
    # discovery, so this is how an admin finds them. policy_scope stays the single gate on who may see a draft.
    class DraftsController < BaseController
      def index
        administered = current_user.organizations.where(organization_memberships: { role: "admin" }).select(:id)
        drafts = policy_scope(Event).where(status: "draft", organization_id: administered)
                                    .includes(:organization, :topics).in_start_order
        render json: { "data" => drafts.map(&:as_list_json) }
      end
    end
  end
end
