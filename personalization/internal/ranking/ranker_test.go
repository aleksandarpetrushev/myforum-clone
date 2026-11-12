package ranking

import (
	"math/rand"
	"sort"
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

// TopK must give exactly what a full sort gives, while holding only limit events (MF-204).
func TestTopKMatchesAFullSort(t *testing.T) {
	now := time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC)
	random := rand.New(rand.NewSource(204))
	profile := store.Profile{Location: "Geneva", TopicIDs: []int64{1, 3, 5}}
	locations := []string{"Geneva", "Davos", "Berlin"}

	for round := 0; round < 50; round++ {
		events := make([]store.Event, 300)
		for index := range events {
			capacity := 1 + random.Intn(50)
			events[index] = store.Event{
				ID:            int64(index + 1),
				Status:        []string{"published", "published", "published", "cancelled"}[random.Intn(4)],
				StartsAt:      now.Add(time.Duration(random.Intn(60*24)-24) * time.Hour),
				Location:      locations[random.Intn(len(locations))],
				Capacity:      capacity,
				ReservedSpots: random.Intn(capacity + 1),
				TopicIDs:      []int64{int64(random.Intn(6)), int64(random.Intn(6))},
			}
		}
		limit := 1 + random.Intn(25)

		top := NewTopK(limit, profile, now)
		for _, event := range events {
			top.Offer(event)
			if top.worst.Len() > limit {
				t.Fatalf("round %d: held %d events, limit %d", round, top.worst.Len(), limit)
			}
		}
		got := top.Results()

		all := NewTopK(0, profile, now)
		for _, event := range events {
			all.Offer(event)
		}
		want := all.Results()
		sort.SliceStable(want, func(i, j int) bool { return better(want[i], want[j]) })
		if len(want) > limit {
			want = want[:limit]
		}

		if len(got) != len(want) {
			t.Fatalf("round %d: %d results, want %d", round, len(got), len(want))
		}
		for index := range want {
			if got[index].Event.ID != want[index].Event.ID || got[index].Score != want[index].Score {
				t.Fatalf("round %d, position %d: got event %d (score %d), want %d (score %d)", round, index,
					got[index].Event.ID, got[index].Score, want[index].Event.ID, want[index].Score)
			}
		}
	}
}
