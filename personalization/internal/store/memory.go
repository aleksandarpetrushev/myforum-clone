package store

import (
	"context"
	"sync"
	"time"
)

type Memory struct {
	mu        sync.Mutex
	events    map[int64]Event
	topics    map[int64]map[int64]struct{}
	userTopic map[int64]map[int64]struct{}
	location  map[int64]string
	seen      map[string]struct{}
}

func NewMemory() *Memory {
	return &Memory{
		events:    map[int64]Event{},
		topics:    map[int64]map[int64]struct{}{},
		userTopic: map[int64]map[int64]struct{}{},
		location:  map[int64]string{},
		seen:      map[string]struct{}{},
	}
}

func (m *Memory) Ping(context.Context) error { return nil }

func (m *Memory) Apply(_ context.Context, incoming Incoming) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if incoming.IdempotencyKey != "" {
		if _, ok := m.seen[incoming.IdempotencyKey]; ok {
			return nil
		}
	}

	switch incoming.EventType {
	case "EventUpdated", "RegistrationCreated":
		snapshot, _ := incoming.Payload["event"].(map[string]any)
		if snapshot == nil {
			break
		}
		event := eventFromSnapshot(snapshot)
		m.events[event.ID] = event
		m.topics[event.ID] = idSet(event.TopicIDs)
		if location, _ := incoming.Payload["user_location"].(string); location != "" {
			if userID, ok := int64From(incoming.Payload["user_id"]); ok {
				m.location[userID] = location
			}
		}
	case "TopicFollowed":
		userID, userOK := int64From(incoming.Payload["user_id"])
		topicID, topicOK := int64From(incoming.Payload["topic_id"])
		if userOK && topicOK {
			set := m.userTopic[userID]
			if set == nil {
				set = map[int64]struct{}{}
				m.userTopic[userID] = set
			}
			set[topicID] = struct{}{}
		}
		if location, _ := incoming.Payload["user_location"].(string); location != "" {
			if userID, ok := int64From(incoming.Payload["user_id"]); ok {
				m.location[userID] = location
			}
		}
	case "TopicUnfollowed":
		userID, userOK := int64From(incoming.Payload["user_id"])
		topicID, topicOK := int64From(incoming.Payload["topic_id"])
		if userOK && topicOK {
			delete(m.userTopic[userID], topicID)
		}
	}

	if incoming.IdempotencyKey != "" {
		m.seen[incoming.IdempotencyKey] = struct{}{}
	}
	return nil
}

func (m *Memory) Candidates(_ context.Context, userID int64, now time.Time) ([]Event, Profile, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	profile := Profile{Location: m.location[userID]}
	for topicID := range m.userTopic[userID] {
		profile.TopicIDs = append(profile.TopicIDs, topicID)
	}

	var events []Event
	for _, event := range m.events {
		if event.Status != "published" || !event.StartsAt.After(now) {
			continue
		}
		event.TopicIDs = keys(m.topics[event.ID])
		events = append(events, event)
	}
	return events, profile, nil
}

func eventFromSnapshot(snapshot map[string]any) Event {
	id, _ := int64From(snapshot["id"])
	startsAt, _ := time.Parse(time.RFC3339, stringFrom(snapshot["starts_at"]))
	return Event{
		ID:            id,
		Title:         stringFrom(snapshot["title"]),
		Location:      stringFrom(snapshot["location"]),
		StartsAt:      startsAt,
		Status:        stringFrom(snapshot["status"]),
		ReservedSpots: intFrom(snapshot["reserved_spots"]),
		Capacity:      intFrom(snapshot["capacity"]),
		TopicIDs:      int64Slice(snapshot["topic_ids"]),
	}
}

func int64From(value any) (int64, bool) {
	switch typed := value.(type) {
	case float64:
		return int64(typed), true
	case int64:
		return typed, true
	case int:
		return int64(typed), true
	default:
		return 0, false
	}
}

func intFrom(value any) int {
	number, _ := int64From(value)
	return int(number)
}

func stringFrom(value any) string {
	text, _ := value.(string)
	return text
}

func int64Slice(value any) []int64 {
	raw, _ := value.([]any)
	ids := make([]int64, 0, len(raw))
	for _, item := range raw {
		if id, ok := int64From(item); ok {
			ids = append(ids, id)
		}
	}
	return ids
}

func idSet(ids []int64) map[int64]struct{} {
	set := make(map[int64]struct{}, len(ids))
	for _, id := range ids {
		set[id] = struct{}{}
	}
	return set
}

func keys(set map[int64]struct{}) []int64 {
	ids := make([]int64, 0, len(set))
	for id := range set {
		ids = append(ids, id)
	}
	return ids
}
