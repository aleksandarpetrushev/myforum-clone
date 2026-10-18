package store

func CanSee(event Event, memberships []Membership) bool {
	if event.Visibility == "" || event.Visibility == "public" {
		return true
	}
	if event.Visibility != "organization_restricted" {
		return false
	}
	for _, membership := range memberships {
		if membership.Role == "admin" && membership.OrganizationID == event.OrganizerID {
			return true
		}
		for _, organizationID := range event.AllowedOrganizationIDs {
			if membership.OrganizationID == organizationID {
				return true
			}
		}
	}
	return false
}
