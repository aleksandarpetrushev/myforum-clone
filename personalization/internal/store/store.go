package store

import (
	"context"
	"time"
)

type Event struct {
	ID                     int64
	Title                  string
	Location               string
	StartsAt               time.Time
	Status                 string
	ReservedSpots          int
	Capacity               int
	TopicIDs               []int64
	Visibility             string
	OrganizerID            int64
	AllowedOrganizationIDs []int64
	// Revision counts every change to the event row in Rails. A snapshot older than the stored one is ignored.
	Revision int
	// HasRevision is false for snapshots written before Rails sent revisions. They are applied as they were
	// before (last to arrive wins) and never lower the stored revision.
	HasRevision bool
}

type Membership struct {
	OrganizationID int64
	Role           string
}

type Profile struct {
	Location string
	TopicIDs []int64
}

type Incoming struct {
	IdempotencyKey string
	EventType      string
	Payload        map[string]any
}

type Store interface {
	Apply(ctx context.Context, incoming Incoming) error
	// Profile is what ranking needs to know about the user.
	Profile(ctx context.Context, userID int64) (Profile, error)
	// EachCandidate calls visit once for every event the user may be recommended. It streams instead of returning
	// a list, so a caller keeps only what it needs: holding every eligible event per request ran the service out
	// of memory on 12 November (MF-204).
	EachCandidate(ctx context.Context, userID int64, now time.Time, visit func(Event)) error
	Ping(ctx context.Context) error
}
