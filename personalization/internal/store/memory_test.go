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
