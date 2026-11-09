package store

import (
	"context"
	"os"
	"testing"
	"time"
)

// Runs against a real database only when PERSONALIZATION_TEST_DATABASE_URL is set. Every change is rolled back.
func TestPostgresSnapshotRevisions(t *testing.T) {
	url := os.Getenv("PERSONALIZATION_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("PERSONALIZATION_TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	store, err := OpenPostgres(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	tx, err := store.db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()

	const id = int64(-106) // never a real event id
	startsAt := time.Now().Add(48 * time.Hour).UTC().Format(time.RFC3339)
	apply := func(key, title string, spots float64, revision any, topicIDs []any) {
		t.Helper()
		event := map[string]any{
			"id": float64(id), "title": title, "location": "Berlin", "starts_at": startsAt, "status": "published",
			"reserved_spots": spots, "capacity": float64(10), "visibility": "public", "topic_ids": topicIDs,
		}
		if revision != nil {
			event["revision"] = revision
		}
		err := store.applyTx(ctx, tx, Incoming{IdempotencyKey: key, EventType: "EventUpdated", Payload: map[string]any{"event": event}})
		if err != nil {
			t.Fatal(err)
		}
	}
	read := func() (title string, spots, revision, topics int) {
		t.Helper()
		if err := tx.QueryRowContext(ctx, `SELECT title, reserved_spots, revision FROM personalization.events WHERE id = $1`, id).Scan(&title, &spots, &revision); err != nil {
			t.Fatal(err)
		}
		if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM personalization.event_topics WHERE event_id = $1`, id).Scan(&topics); err != nil {
			t.Fatal(err)
		}
		return
	}

	apply("t:2", "Second edit", 0, float64(2), []any{float64(1), float64(2)})
	apply("t:1", "First edit", 0, float64(1), []any{float64(3)})
	if title, _, revision, topics := read(); title != "Second edit" || revision != 2 || topics != 2 {
		t.Fatalf("older snapshot was applied: %q revision %d topics %d", title, revision, topics)
	}

	apply("t:legacy", "Second edit", 4, nil, []any{float64(1), float64(2)})
	if _, spots, revision, _ := read(); spots != 4 || revision != 2 {
		t.Fatalf("snapshot without a revision: spots %d revision %d, want 4 at revision 2", spots, revision)
	}

	apply("t:1b", "First edit", 0, float64(1), []any{float64(3)})
	if title, _, _, _ := read(); title != "Second edit" {
		t.Fatalf("an older revision was applied after a legacy snapshot: %q", title)
	}
}
