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
