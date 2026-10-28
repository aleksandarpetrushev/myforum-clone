class EventPolicy
  attr_reader :user, :event

  def initialize(user, event)
    @user = user
    @event = event
  end

  # A draft is visible only to the organizing organization's admins, including by direct link.
  # A cancelled event stays visible under the same rules as a published one, so registrants can see it.
  def show?
    return false unless user
    return true if admin_of_organizer?
    return false if draft?
    return true if public_event?

    member_of_allowed_organization?
  end

  def create?
    admin_of_organizer?
  end

  def update?
    admin_of_organizer?
  end

  def cancel?
    admin_of_organizer?
  end

  def destroy?
    update?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      return scope.none unless user

      scope.where(<<~SQL.squish, user.id, user.id)
        (
          events.status IN ('published', 'cancelled')
          AND (
            events.visibility = 'public'
            OR (
              events.visibility = 'organization_restricted'
              AND EXISTS (
                SELECT 1
                FROM event_allowed_organizations eao
                INNER JOIN organization_memberships om
                  ON om.organization_id = eao.organization_id
                 AND om.user_id = ?
                WHERE eao.event_id = events.id
              )
            )
          )
        )
        OR EXISTS (
          SELECT 1
          FROM organization_memberships om
          WHERE om.user_id = ?
            AND om.organization_id = events.organization_id
            AND om.role = 'admin'
        )
      SQL
    end

    private

    attr_reader :user, :scope
  end

  private

  def draft?
    event.status == "draft"
  end

  def public_event?
    event.visibility.blank? || event.visibility == "public"
  end

  def member_of_allowed_organization?
    return false unless event.visibility == "organization_restricted"

    OrganizationMembership
      .where(user_id: user.id)
      .where(organization_id: event.event_allowed_organizations.select(:organization_id))
      .exists?
  end

  def admin_of_organizer?
    return false unless user && event.respond_to?(:organization_id)

    OrganizationMembership.exists?(user_id: user.id, organization_id: event.organization_id, role: "admin")
  end
end
