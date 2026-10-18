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
	Candidates(ctx context.Context, userID int64, now time.Time) ([]Event, Profile, error)
	Ping(ctx context.Context) error
}
