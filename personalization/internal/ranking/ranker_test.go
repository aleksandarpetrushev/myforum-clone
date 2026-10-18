package ranking

import (
	"testing"
	"time"

	"myforum/personalization/internal/store"
)

func TestRankPrefersFollowedTopicAndLocation(t *testing.T) {
	now := time.Date(2026, 10, 18, 12, 0, 0, 0, time.UTC)
	events := []store.Event{
		{ID: 1, Title: "Elsewhere", Location: "Lisbon", StartsAt: now.Add(48 * time.Hour), Status: "published", Capacity: 10, ReservedSpots: 1},
		{ID: 2, Title: "Local climate", Location: "Berlin", StartsAt: now.Add(48 * time.Hour), Status: "published", TopicIDs: []int64{7}, Capacity: 10, ReservedSpots: 8},
		{ID: 3, Title: "Past", Location: "Berlin", StartsAt: now.Add(-time.Hour), Status: "published", TopicIDs: []int64{7}},
	}
	profile := store.Profile{Location: "Berlin", TopicIDs: []int64{7}}

	ranked := Rank(events, profile, now, 10)
	if len(ranked) != 2 {
		t.Fatalf("expected 2 upcoming events, got %d", len(ranked))
	}
	if ranked[0].Event.ID != 2 {
		t.Fatalf("expected topic and location match first, got %d", ranked[0].Event.ID)
	}
	if ranked[0].Score <= ranked[1].Score {
		t.Fatalf("expected a higher score for the matching event")
	}
}
