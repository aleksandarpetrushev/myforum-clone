module Api
  module Me
    class OrganizationsController < BaseController
      def index
        organizations = current_user.organizations.where(organization_memberships: { role: "admin" }).order(:name)
        render json: { "data" => organizations.map(&:as_option_json) }
      end
    end
  end
end
