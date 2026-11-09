package store

import (
	"context"
	"testing"
	"time"
)

func TestMemoryApplyIsIdempotent(t *testing.T) {
	memory := NewMemory()
	incoming := Incoming{
		IdempotencyKey: "event-1",
		EventType:      "EventUpdated",
		Payload: map[string]any{
			"event": map[string]any{
				"id":             float64(4),
				"title":          "Cities",
				"location":       "Berlin",
				"starts_at":      time.Now().Add(24 * time.Hour).UTC().Format(time.RFC3339),
				"status":         "published",
				"reserved_spots": float64(2),
				"capacity":       float64(20),
				"topic_ids":      []any{float64(3)},
			},
		},
	}

	if err := memory.Apply(context.Background(), incoming); err != nil {
		t.Fatal(err)
	}
	if err := memory.Apply(context.Background(), incoming); err != nil {
		t.Fatal(err)
	}

	events, _, err := memory.Candidates(context.Background(), 1, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
}

func TestEventPublishedAddsTheEventToCandidates(t *testing.T) {
	memory := NewMemory()
	incoming := Incoming{
		IdempotencyKey: "event_published:7",
		EventType:      "EventPublished",
		Payload: map[string]any{
			"event": map[string]any{
				"id":             float64(7),
				"title":          "Financing the energy transition",
				"location":       "Geneva",
				"starts_at":      time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339),
				"status":         "published",
				"reserved_spots": float64(0),
				"capacity":       float64(80),
				"topic_ids":      []any{float64(5)},
				"visibility":     "public",
			},
		},
	}

	if err := memory.Apply(context.Background(), incoming); err != nil {
		t.Fatal(err)
	}

	events, _, err := memory.Candidates(context.Background(), 1, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].ID != 7 {
		t.Fatalf("expected event 7 as the only candidate, got %+v", events)
	}
}

func TestEventCancelledRemovesTheEventFromCandidates(t *testing.T) {
	memory := NewMemory()
	snapshot := func(status string) map[string]any {
		return map[string]any{
			"id":             float64(8),
			"title":          "Called off",
			"location":       "Geneva",
			"starts_at":      time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339),
			"status":         status,
			"reserved_spots": float64(3),
			"capacity":       float64(80),
			"topic_ids":      []any{float64(5)},
			"visibility":     "public",
		}
	}

	published := Incoming{IdempotencyKey: "event_published:8", EventType: "EventPublished", Payload: map[string]any{"event": snapshot("published")}}
	cancelled := Incoming{IdempotencyKey: "event_cancelled:8", EventType: "EventCancelled", Payload: map[string]any{"event": snapshot("cancelled")}}
	for _, incoming := range []Incoming{published, cancelled} {
		if err := memory.Apply(context.Background(), incoming); err != nil {
			t.Fatal(err)
		}
	}

	events, _, err := memory.Candidates(context.Background(), 1, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 0 {
		t.Fatalf("expected no candidates after cancellation, got %+v", events)
	}
}

func TestRegistrationCancelledUpdatesReservedSpots(t *testing.T) {
	memory := NewMemory()
	startsAt := time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339)
	snapshot := func(spots float64) map[string]any {
		return map[string]any{
			"event": map[string]any{
				"id":             float64(9),
				"title":          "Clinic",
				"location":       "Berlin",
				"starts_at":      startsAt,
				"status":         "published",
				"reserved_spots": spots,
				"capacity":       float64(10),
				"visibility":     "public",
			},
		}
	}

	if err := memory.Apply(context.Background(), Incoming{
		IdempotencyKey: "registration_created:1:1",
		EventType:      "RegistrationCreated",
		Payload:        snapshot(1),
	}); err != nil {
		t.Fatal(err)
	}
	cancel := Incoming{
		IdempotencyKey: "registration_cancelled:1:2",
		EventType:      "RegistrationCancelled",
		Payload:        snapshot(0),
	}
	if err := memory.Apply(context.Background(), cancel); err != nil {
		t.Fatal(err)
	}
	if err := memory.Apply(context.Background(), cancel); err != nil {
		t.Fatal(err)
	}

	events, _, err := memory.Candidates(context.Background(), 1, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].ReservedSpots != 0 {
		t.Fatalf("expected reserved spots 0, got %+v", events)
	}
}

func TestSnapshotRevisions(t *testing.T) {
	startsAt := time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339)
	snapshot := func(title string, spots float64, revision any) map[string]any {
		event := map[string]any{
			"id":             float64(9),
			"title":          title,
			"location":       "Berlin",
			"starts_at":      startsAt,
			"status":         "published",
			"reserved_spots": spots,
			"capacity":       float64(10),
			"visibility":     "public",
		}
		if revision != nil {
			event["revision"] = revision
		}
		return map[string]any{"event": event}
	}
	apply := func(memory *Memory, key, eventType string, payload map[string]any) {
		t.Helper()
		if err := memory.Apply(context.Background(), Incoming{IdempotencyKey: key, EventType: eventType, Payload: payload}); err != nil {
			t.Fatal(err)
		}
	}
	stored := func(memory *Memory) Event {
		t.Helper()
		events, _, err := memory.Candidates(context.Background(), 1, time.Now())
		if err != nil || len(events) != 1 {
			t.Fatalf("candidates: %v %+v", err, events)
		}
		return events[0]
	}

	t.Run("an older revision arriving late is ignored", func(t *testing.T) {
		memory := NewMemory()
		apply(memory, "event_updated:9:2", "EventUpdated", snapshot("Second edit", 0, float64(2)))
		apply(memory, "event_updated:9:1", "EventUpdated", snapshot("First edit", 0, float64(1)))

		if got := stored(memory); got.Title != "Second edit" || got.Revision != 2 {
			t.Fatalf("stored %q revision %d", got.Title, got.Revision)
		}
	})

	t.Run("a late edit does not undo a cancellation", func(t *testing.T) {
		memory := NewMemory()
		cancelled := snapshot("Edit", 0, float64(3))
		cancelled["event"].(map[string]any)["status"] = "cancelled"
		apply(memory, "event_cancelled:9", "EventCancelled", cancelled)
		apply(memory, "event_updated:9:2", "EventUpdated", snapshot("Edit", 0, float64(2)))

		if got := memory.events[9]; got.Status != "cancelled" || got.Revision != 3 {
			t.Fatalf("status %q revision %d, want cancelled at 3", got.Status, got.Revision)
		}
		if events, _, _ := memory.Candidates(context.Background(), 1, time.Now()); len(events) != 0 {
			t.Fatalf("cancelled event is still a candidate: %+v", events)
		}
	})

	t.Run("seat counts arriving out of order keep the newest", func(t *testing.T) {
		memory := NewMemory()
		apply(memory, "registration_created:2:1", "RegistrationCreated", snapshot("Edit", 6, float64(5)))
		apply(memory, "registration_created:1:1", "RegistrationCreated", snapshot("Edit", 5, float64(4)))

		if got := stored(memory); got.ReservedSpots != 6 {
			t.Fatalf("reserved spots %d, want 6", got.ReservedSpots)
		}
	})

	t.Run("a snapshot without a revision applies and keeps the stored revision", func(t *testing.T) {
		memory := NewMemory()
		apply(memory, "event_updated:9:1", "EventUpdated", snapshot("Edited", 5, float64(1)))
		apply(memory, "registration_created:7:1", "RegistrationCreated", snapshot("Edited", 6, nil))

		if got := stored(memory); got.ReservedSpots != 6 || got.Revision != 1 {
			t.Fatalf("reserved spots %d revision %d, want 6 at revision 1", got.ReservedSpots, got.Revision)
		}
		apply(memory, "event_updated:9:0", "EventUpdated", snapshot("Older edit", 6, float64(0)))
		if got := stored(memory); got.Title != "Edited" {
			t.Fatalf("an older revision was applied after a legacy snapshot: %q", got.Title)
		}
	})
}
