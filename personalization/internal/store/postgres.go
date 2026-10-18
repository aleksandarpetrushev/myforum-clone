package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type Postgres struct {
	db *sql.DB
}

func OpenPostgres(ctx context.Context, databaseURL string) (*Postgres, error) {
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open postgres: %w", err)
	}
	store := &Postgres{db: db}
	if err := store.migrate(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

func (p *Postgres) Close() error {
	return p.db.Close()
}

func (p *Postgres) Ping(ctx context.Context) error {
	if err := p.db.PingContext(ctx); err != nil {
		return fmt.Errorf("ping postgres: %w", err)
	}
	return nil
}

func (p *Postgres) migrate(ctx context.Context) error {
	_, err := p.db.ExecContext(ctx, `
		CREATE SCHEMA IF NOT EXISTS personalization;
		CREATE TABLE IF NOT EXISTS personalization.events (
			id bigint PRIMARY KEY,
			title text NOT NULL,
			location text NOT NULL,
			starts_at timestamptz NOT NULL,
			status text NOT NULL,
			reserved_spots integer NOT NULL,
			capacity integer NOT NULL
		);
		CREATE TABLE IF NOT EXISTS personalization.event_topics (
			event_id bigint NOT NULL,
			topic_id bigint NOT NULL,
			PRIMARY KEY (event_id, topic_id)
		);
		CREATE TABLE IF NOT EXISTS personalization.user_topics (
			user_id bigint NOT NULL,
			topic_id bigint NOT NULL,
			PRIMARY KEY (user_id, topic_id)
		);
		CREATE TABLE IF NOT EXISTS personalization.user_locations (
			user_id bigint PRIMARY KEY,
			location text NOT NULL
		);
		CREATE TABLE IF NOT EXISTS personalization.processed_events (
			idempotency_key text PRIMARY KEY,
			processed_at timestamptz NOT NULL
		);
	`)
	if err != nil {
		return fmt.Errorf("migrate personalization schema: %w", err)
	}
	return nil
}

func (p *Postgres) Apply(ctx context.Context, incoming Incoming) error {
	tx, err := p.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin apply: %w", err)
	}
	defer tx.Rollback()

	if incoming.IdempotencyKey != "" {
		result, err := tx.ExecContext(ctx, `
			INSERT INTO personalization.processed_events (idempotency_key, processed_at)
			VALUES ($1, $2)
			ON CONFLICT (idempotency_key) DO NOTHING
		`, incoming.IdempotencyKey, time.Now().UTC())
		if err != nil {
			return fmt.Errorf("record idempotency key: %w", err)
		}
		affected, err := result.RowsAffected()
		if err != nil {
			return fmt.Errorf("rows affected: %w", err)
		}
		if affected == 0 {
			return nil
		}
	}

	if err := p.applyTx(ctx, tx, incoming); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit apply: %w", err)
	}
	return nil
}

func (p *Postgres) applyTx(ctx context.Context, tx *sql.Tx, incoming Incoming) error {
	switch incoming.EventType {
	case "EventUpdated", "RegistrationCreated":
		snapshot, _ := incoming.Payload["event"].(map[string]any)
		if snapshot == nil {
			return nil
		}
		event := eventFromSnapshot(snapshot)
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO personalization.events (id, title, location, starts_at, status, reserved_spots, capacity)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (id) DO UPDATE SET
				title = EXCLUDED.title,
				location = EXCLUDED.location,
				starts_at = EXCLUDED.starts_at,
				status = EXCLUDED.status,
				reserved_spots = EXCLUDED.reserved_spots,
				capacity = EXCLUDED.capacity
		`, event.ID, event.Title, event.Location, event.StartsAt, event.Status, event.ReservedSpots, event.Capacity); err != nil {
			return fmt.Errorf("upsert event: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM personalization.event_topics WHERE event_id = $1`, event.ID); err != nil {
			return fmt.Errorf("clear event topics: %w", err)
		}
		for _, topicID := range event.TopicIDs {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO personalization.event_topics (event_id, topic_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING
			`, event.ID, topicID); err != nil {
				return fmt.Errorf("insert event topic: %w", err)
			}
		}
		if location, _ := incoming.Payload["user_location"].(string); location != "" {
			if userID, ok := int64From(incoming.Payload["user_id"]); ok {
				if err := upsertLocation(ctx, tx, userID, location); err != nil {
					return err
				}
			}
		}
	case "TopicFollowed":
		userID, userOK := int64From(incoming.Payload["user_id"])
		topicID, topicOK := int64From(incoming.Payload["topic_id"])
		if userOK && topicOK {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO personalization.user_topics (user_id, topic_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING
			`, userID, topicID); err != nil {
				return fmt.Errorf("follow topic: %w", err)
			}
		}
		if location, _ := incoming.Payload["user_location"].(string); location != "" && userOK {
			if err := upsertLocation(ctx, tx, userID, location); err != nil {
				return err
			}
		}
	case "TopicUnfollowed":
		userID, userOK := int64From(incoming.Payload["user_id"])
		topicID, topicOK := int64From(incoming.Payload["topic_id"])
		if userOK && topicOK {
			if _, err := tx.ExecContext(ctx, `DELETE FROM personalization.user_topics WHERE user_id = $1 AND topic_id = $2`, userID, topicID); err != nil {
				return fmt.Errorf("unfollow topic: %w", err)
			}
		}
	}
	return nil
}

func upsertLocation(ctx context.Context, tx *sql.Tx, userID int64, location string) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO personalization.user_locations (user_id, location) VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE SET location = EXCLUDED.location
	`, userID, location)
	if err != nil {
		return fmt.Errorf("upsert location: %w", err)
	}
	return nil
}

func (p *Postgres) Candidates(ctx context.Context, userID int64, now time.Time) ([]Event, Profile, error) {
	rows, err := p.db.QueryContext(ctx, `
		SELECT id, title, location, starts_at, status, reserved_spots, capacity
		FROM personalization.events
		WHERE status = 'published' AND starts_at > $1
	`, now)
	if err != nil {
		return nil, Profile{}, fmt.Errorf("query events: %w", err)
	}
	defer rows.Close()

	events := []Event{}
	ids := []int64{}
	for rows.Next() {
		var event Event
		if err := rows.Scan(&event.ID, &event.Title, &event.Location, &event.StartsAt, &event.Status, &event.ReservedSpots, &event.Capacity); err != nil {
			return nil, Profile{}, fmt.Errorf("scan event: %w", err)
		}
		events = append(events, event)
		ids = append(ids, event.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, Profile{}, fmt.Errorf("events rows: %w", err)
	}

	topicsByEvent := map[int64][]int64{}
	topicRows, err := p.db.QueryContext(ctx, `SELECT event_id, topic_id FROM personalization.event_topics`)
	if err != nil {
		return nil, Profile{}, fmt.Errorf("query event topics: %w", err)
	}
	defer topicRows.Close()
	for topicRows.Next() {
		var eventID, topicID int64
		if err := topicRows.Scan(&eventID, &topicID); err != nil {
			return nil, Profile{}, fmt.Errorf("scan event topic: %w", err)
		}
		topicsByEvent[eventID] = append(topicsByEvent[eventID], topicID)
	}
	for index := range events {
		events[index].TopicIDs = topicsByEvent[events[index].ID]
	}

	profile := Profile{}
	userTopics, err := p.db.QueryContext(ctx, `SELECT topic_id FROM personalization.user_topics WHERE user_id = $1`, userID)
	if err != nil {
		return nil, Profile{}, fmt.Errorf("query user topics: %w", err)
	}
	defer userTopics.Close()
	for userTopics.Next() {
		var topicID int64
		if err := userTopics.Scan(&topicID); err != nil {
			return nil, Profile{}, fmt.Errorf("scan user topic: %w", err)
		}
		profile.TopicIDs = append(profile.TopicIDs, topicID)
	}
	_ = p.db.QueryRowContext(ctx, `SELECT location FROM personalization.user_locations WHERE user_id = $1`, userID).Scan(&profile.Location)
	_ = ids
	return events, profile, nil
}
