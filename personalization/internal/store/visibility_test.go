package store

import "testing"

func TestCanSee(t *testing.T) {
	publicEvent := Event{ID: 1, Visibility: "public", OrganizerID: 10}
	restricted := Event{ID: 2, Visibility: "organization_restricted", OrganizerID: 10, AllowedOrganizationIDs: []int64{20, 30}}
	closed := Event{ID: 3, Visibility: "organization_restricted", OrganizerID: 10}

	if !CanSee(publicEvent, nil) {
		t.Fatal("public events are visible without a membership")
	}
	if CanSee(restricted, nil) {
		t.Fatal("outsiders cannot see restricted events")
	}
	if !CanSee(restricted, []Membership{{OrganizationID: 30, Role: "member"}}) {
		t.Fatal("a membership in any allowed organization is enough")
	}
	if CanSee(restricted, []Membership{{OrganizationID: 99, Role: "member"}}) {
		t.Fatal("an unrelated membership does not grant access")
	}
	if !CanSee(closed, []Membership{{OrganizationID: 10, Role: "admin"}}) {
		t.Fatal("the organizer admin can see a restricted event with no allowed organizations")
	}
	if CanSee(closed, []Membership{{OrganizationID: 10, Role: "member"}}) {
		t.Fatal("an organizer member is not on the allow list")
	}
}
