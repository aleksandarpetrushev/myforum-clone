class EventPolicy
  attr_reader :user, :event

  def initialize(user, event)
    @user = user
    @event = event
  end

  def show?
    user.present?
  end

  def update?
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

      scope.all
    end

    private

    attr_reader :user, :scope
  end

  private

  def admin_of_organizer?
    return false unless user && event.respond_to?(:organization_id)

    OrganizationMembership.exists?(user_id: user.id, organization_id: event.organization_id, role: "admin")
  end
end
