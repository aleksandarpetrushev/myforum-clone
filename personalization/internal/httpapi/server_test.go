package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"myforum/personalization/internal/store"
)

func TestRecommendationsAndIngest(t *testing.T) {
	memory := store.NewMemory()
	now := time.Date(2026, 10, 18, 12, 0, 0, 0, time.UTC)
	server := &Server{Store: memory, Log: slog.New(slog.DiscardHandler), Now: func() time.Time { return now }}
	handler := server.Handler()

	body := map[string]any{
		"idempotency_key": "evt-1",
		"event_type":      "EventUpdated",
		"payload": map[string]any{
			"event": map[string]any{
				"id":             float64(9),
				"title":          "Climate clinic",
				"location":       "Berlin",
				"starts_at":      now.Add(48 * time.Hour).Format(time.RFC3339),
				"status":         "published",
				"reserved_spots": float64(4),
				"capacity":       float64(10),
				"topic_ids":      []any{float64(2)},
			},
		},
	}
	encoded, _ := json.Marshal(body)
	ingest := httptest.NewRequest(http.MethodPost, "/internal/events", bytes.NewReader(encoded))
	ingestResponse := httptest.NewRecorder()
	handler.ServeHTTP(ingestResponse, ingest)
	if ingestResponse.Code != http.StatusNoContent {
		t.Fatalf("ingest status %d", ingestResponse.Code)
	}

	follow, _ := json.Marshal(map[string]any{
		"idempotency_key": "follow-1",
		"event_type":      "TopicFollowed",
		"payload": map[string]any{
			"user_id":       float64(3),
			"topic_id":      float64(2),
			"user_location": "Berlin",
		},
	})
	followResponse := httptest.NewRecorder()
	handler.ServeHTTP(followResponse, httptest.NewRequest(http.MethodPost, "/internal/events", bytes.NewReader(follow)))
	if followResponse.Code != http.StatusNoContent {
		t.Fatalf("follow status %d", followResponse.Code)
	}

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/recommendations?user_id=3", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("recommendations status %d body %s", response.Code, response.Body.String())
	}
	var payload struct {
		Data []struct {
			EventID int64 `json:"event_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Data) != 1 || payload.Data[0].EventID != 9 {
		t.Fatalf("unexpected recommendations: %+v", payload.Data)
	}

	health := httptest.NewRecorder()
	handler.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/health", nil).WithContext(context.Background()))
	if health.Code != http.StatusOK {
		t.Fatalf("health status %d", health.Code)
	}
}
