module Api
  # Feeds the allowed-organizations picker, so only organization admins may list every organization.
  class OrganizationsController < BaseController
    def index
      return render_forbidden(nil) unless current_user.organization_memberships.exists?(role: "admin")

      organizations = Organization.order(:name)
      render json: { "data" => organizations.map(&:as_option_json) }
    end
  end
end
