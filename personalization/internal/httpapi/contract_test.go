package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
	"time"

	"myforum/personalization/contract"
	"myforum/personalization/internal/store"
)

func mustValidator(t *testing.T) *contract.Validator {
	t.Helper()
	validator, err := contract.NewValidator()
	if err != nil {
		t.Fatalf("contract schema did not compile: %v", err)
	}
	return validator
}

// contractServer is a service with an empty memory store whose log lines can be read back.
type contractServer struct {
	memory  *store.Memory
	handler http.Handler
	logs    *bytes.Buffer
	now     time.Time
}

func newContractServer(t *testing.T) *contractServer {
	t.Helper()
	logs := &bytes.Buffer{}
	memory := store.NewMemory()
	now := time.Date(2026, 11, 1, 12, 0, 0, 0, time.UTC) // before every example's starts_at
	server := &Server{
		Store: memory, Log: slog.New(slog.NewJSONHandler(logs, nil)),
		Now: func() time.Time { return now }, Contract: mustValidator(t),
	}
	return &contractServer{memory: memory, handler: server.Handler(), logs: logs, now: now}
}

func (c *contractServer) post(body []byte) *httptest.ResponseRecorder {
	response := httptest.NewRecorder()
	c.handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/internal/events", bytes.NewReader(body)))
	return response
}

func (c *contractServer) ingest(t *testing.T, body []byte) {
	t.Helper()
	if response := c.post(body); response.Code != http.StatusNoContent {
		t.Fatalf("ingest status %d body %s", response.Code, response.Body.String())
	}
}

func decode(t *testing.T, raw []byte) any {
	t.Helper()
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatal(err)
	}
	return value
}

func (c *contractServer) candidates(t *testing.T, userID int64) ([]store.Event, store.Profile) {
	t.Helper()
	events, profile, err := c.memory.Candidates(context.Background(), userID, c.now)
	if err != nil {
		t.Fatal(err)
	}
	return events, profile
}

func example(t *testing.T, eventType string) []byte {
	t.Helper()
	raw, err := contract.Files.ReadFile("v1/examples/" + eventType + ".json")
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// edit decodes an example, lets the caller change it, and encodes it again.
func edit(t *testing.T, raw []byte, change func(body map[string]any)) []byte {
	t.Helper()
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatal(err)
	}
	change(body)
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func TestEveryExampleIsValidAndUnderstood(t *testing.T) {
	entries, err := contract.Files.ReadDir("v1/examples")
	if err != nil {
		t.Fatal(err)
	}
	validator := mustValidator(t)
	seen := map[string]bool{}
	for _, entry := range entries {
		eventType := strings.TrimSuffix(entry.Name(), ".json")
		seen[eventType] = true
		if err := validator.Validate(1, decode(t, example(t, eventType))); err != nil {
			t.Errorf("%s example is not valid: %v", eventType, err)
		}
	}
	for _, eventType := range validator.EventTypes(1) {
		if !seen[eventType] {
			t.Errorf("no example for %s", eventType)
		}
	}

	// Each example, applied, must change the read model the way its values say.
	t.Run("EventPublished", func(t *testing.T) {
		c := newContractServer(t)
		c.ingest(t, example(t, "EventPublished"))
		events, _ := c.candidates(t, 55)
		if len(events) != 1 || events[0].Title != "Financing the energy transition" || events[0].Capacity != 80 {
			t.Fatalf("event not stored as sent: %+v", events)
		}
	})
	t.Run("EventUpdated", func(t *testing.T) {
		c := newContractServer(t)
		c.ingest(t, example(t, "EventUpdated"))
		if events, _ := c.candidates(t, 55); len(events) != 0 {
			t.Fatalf("restricted event visible to a non-member: %+v", events)
		}
		c.memory.SetMemberships(55, []store.Membership{{OrganizationID: 12, Role: "member"}})
		if events, _ := c.candidates(t, 55); len(events) != 1 || events[0].Revision != 4 {
			t.Fatalf("allowed organizations or revision not read: %+v", events)
		}
	})
	t.Run("EventCancelled", func(t *testing.T) {
		c := newContractServer(t)
		c.ingest(t, example(t, "EventPublished"))
		c.ingest(t, example(t, "EventCancelled"))
		if events, _ := c.candidates(t, 55); len(events) != 0 {
			t.Fatalf("cancelled event is still a candidate: %+v", events)
		}
	})
	t.Run("RegistrationCreated and RegistrationCancelled", func(t *testing.T) {
		c := newContractServer(t)
		c.ingest(t, example(t, "RegistrationCreated"))
		if events, profile := c.candidates(t, 55); len(events) != 1 || events[0].ReservedSpots != 4 || profile.Location != "Berlin" {
			t.Fatalf("registration not read: %+v %+v", events, profile)
		}
		c.ingest(t, example(t, "RegistrationCancelled"))
		if events, _ := c.candidates(t, 55); len(events) != 1 || events[0].ReservedSpots != 3 {
			t.Fatalf("cancelled registration not read: %+v", events)
		}
	})
	t.Run("TopicFollowed and TopicUnfollowed", func(t *testing.T) {
		c := newContractServer(t)
		c.ingest(t, example(t, "TopicFollowed"))
		if _, profile := c.candidates(t, 55); !slices.Contains(profile.TopicIDs, 6) {
			t.Fatalf("follow not read: %+v", profile)
		}
		c.ingest(t, example(t, "TopicUnfollowed"))
		if _, profile := c.candidates(t, 55); slices.Contains(profile.TopicIDs, 6) {
			t.Fatalf("unfollow not read: %+v", profile)
		}
	})
}

func TestEveryExampleIngestsWithoutContractWarnings(t *testing.T) {
	for _, eventType := range mustValidator(t).EventTypes(1) {
		c := newContractServer(t)
		c.ingest(t, example(t, eventType))
		if strings.Contains(c.logs.String(), "contract.") {
			t.Errorf("%s example logged a contract problem: %s", eventType, c.logs.String())
		}
	}
}

func TestUnknownFieldsAreAllowed(t *testing.T) {
	c := newContractServer(t)
	c.ingest(t, edit(t, example(t, "EventPublished"), func(body map[string]any) {
		body["sent_by"] = "rails"
		body["payload"].(map[string]any)["event"].(map[string]any)["room"] = "Congress hall"
	}))

	if strings.Contains(c.logs.String(), "contract.") {
		t.Fatalf("an added field was reported: %s", c.logs.String())
	}
	if events, _ := c.candidates(t, 55); len(events) != 1 {
		t.Fatalf("not applied: %+v", events)
	}
}

func TestInvalidPayloadIsLoggedAndStillApplied(t *testing.T) {
	c := newContractServer(t)
	c.ingest(t, edit(t, example(t, "EventPublished"), func(body map[string]any) {
		delete(body["payload"].(map[string]any)["event"].(map[string]any), "title")
	}))

	if !strings.Contains(c.logs.String(), `"msg":"contract.invalid"`) || !strings.Contains(c.logs.String(), "title") {
		t.Fatalf("missing title not logged: %s", c.logs.String())
	}
	if events, _ := c.candidates(t, 55); len(events) != 1 {
		t.Fatalf("invalid payload was not applied: %+v", events)
	}
}

// Unsupported means "not yet": 422 unsupported_contract, so Rails keeps the row as deferred instead of
// marking it published, and the event is not applied.
func TestUnsupportedVersionOrEventTypeIsRefusedAsDeferred(t *testing.T) {
	cases := map[string]func(body map[string]any){
		"schema_version 2":        func(body map[string]any) { body["schema_version"] = 2 },
		"schema_version a string": func(body map[string]any) { body["schema_version"] = "1" },
		"unknown event_type":      func(body map[string]any) { body["event_type"] = "EventArchived" },
		"no event_type":           func(body map[string]any) { delete(body, "event_type") },
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			c := newContractServer(t)
			response := c.post(edit(t, example(t, "EventPublished"), change))

			if response.Code != http.StatusUnprocessableEntity || !strings.Contains(response.Body.String(), "unsupported_contract") {
				t.Fatalf("status %d body %s, want 422 unsupported_contract", response.Code, response.Body.String())
			}
			if !strings.Contains(c.logs.String(), `"msg":"contract.unsupported"`) {
				t.Fatalf("not logged as unsupported: %s", c.logs.String())
			}
			if events, _ := c.candidates(t, 55); len(events) != 0 {
				t.Fatalf("applied anyway: %+v", events)
			}
		})
	}
}

func TestMissingSchemaVersionIsReadAsVersion1(t *testing.T) {
	c := newContractServer(t)
	c.ingest(t, edit(t, example(t, "EventPublished"), func(body map[string]any) { delete(body, "schema_version") }))

	if strings.Contains(c.logs.String(), "contract.") {
		t.Fatalf("a pre-contract body was reported: %s", c.logs.String())
	}
	if events, _ := c.candidates(t, 55); len(events) != 1 {
		t.Fatalf("not applied: %+v", events)
	}
}

// A field of the wrong type is a contract problem to log, never a 422 that would stop Rails' poller.
func TestWrongFieldTypesAreLoggedNotRefused(t *testing.T) {
	cases := map[string]func(body map[string]any){
		"schema_version 1.0":       func(body map[string]any) { body["schema_version"] = 1.0 },
		"payload an array":         func(body map[string]any) { body["payload"] = []any{} },
		"idempotency_key a number": func(body map[string]any) { body["idempotency_key"] = 42 },
		"capacity a string": func(body map[string]any) {
			body["payload"].(map[string]any)["event"].(map[string]any)["capacity"] = "80"
		},
	}
	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			c := newContractServer(t)
			c.ingest(t, edit(t, example(t, "EventPublished"), change))
			if name != "schema_version 1.0" && !strings.Contains(c.logs.String(), `"msg":"contract.invalid"`) {
				t.Fatalf("not logged: %s", c.logs.String())
			}
		})
	}
}

func TestBodyOverTheLimitGets413(t *testing.T) {
	c := newContractServer(t)
	big := edit(t, example(t, "EventPublished"), func(body map[string]any) {
		body["padding"] = strings.Repeat("x", maxIngestBody)
	})

	response := c.post(big)

	if response.Code != http.StatusRequestEntityTooLarge || !strings.Contains(response.Body.String(), "payload_too_large") {
		t.Fatalf("status %d body %s, want 413 payload_too_large", response.Code, response.Body.String())
	}
}

func TestMissingValidatorAppliesWithoutChecking(t *testing.T) {
	logs := &bytes.Buffer{}
	memory := store.NewMemory()
	now := time.Date(2026, 11, 1, 12, 0, 0, 0, time.UTC)
	handler := (&Server{Store: memory, Log: slog.New(slog.NewJSONHandler(logs, nil)), Now: func() time.Time { return now }}).Handler()

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/internal/events", bytes.NewReader(example(t, "EventPublished"))))

	if response.Code != http.StatusNoContent || !strings.Contains(logs.String(), "contract.validator_missing") {
		t.Fatalf("status %d logs %s", response.Code, logs.String())
	}
	if events, _, _ := memory.Candidates(context.Background(), 55, now); len(events) != 1 {
		t.Fatalf("not applied: %+v", events)
	}
}
