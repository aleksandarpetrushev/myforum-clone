package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"time"

	"myforum/personalization/contract"
	"myforum/personalization/internal/ranking"
	"myforum/personalization/internal/store"
)

type Server struct {
	Store    store.Store
	Log      *slog.Logger
	Now      func() time.Time
	Contract *contract.Validator
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /ready", s.ready)
	mux.HandleFunc("GET /recommendations", s.recommendations)
	mux.HandleFunc("POST /internal/events", s.ingest)
	return mux
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.Ping(r.Context()); err != nil {
		s.Log.Error("readiness failed", "error", err.Error())
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) recommendations(w http.ResponseWriter, r *http.Request) {
	userID, err := strconv.ParseInt(r.URL.Query().Get("user_id"), 10, 64)
	if err != nil || userID <= 0 {
		writeError(w, http.StatusUnprocessableEntity, "invalid_user", "user_id is required")
		return
	}

	limit, ok := recommendationLimit(r.URL.Query().Get("limit"))
	if !ok {
		writeError(w, http.StatusUnprocessableEntity, "invalid_limit", "limit must be a positive integer")
		return
	}

	now := s.now()
	events, profile, err := s.Store.Candidates(r.Context(), userID, now)
	if err != nil {
		s.Log.Error("recommendations failed", "error", err.Error(), "user_id", userID)
		writeError(w, http.StatusInternalServerError, "recommendations_failed", "Could not load recommendations")
		return
	}

	ranked := ranking.Rank(events, profile, now, limit)
	data := make([]map[string]any, 0, len(ranked))
	for _, item := range ranked {
		data = append(data, map[string]any{
			"event_id":  item.Event.ID,
			"title":     item.Event.Title,
			"location":  item.Event.Location,
			"starts_at": item.Event.StartsAt.UTC().Format(time.RFC3339),
			"score":     item.Score,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"data": data})
}

const (
	defaultRecommendationLimit = 10
	maxRecommendationLimit     = 50
)

// recommendationLimit reads ?limit=. Absent means the default; above the maximum is capped.
// Rails asks for more than it shows because it drops events the user cannot see or has booked.
func recommendationLimit(raw string) (int, bool) {
	if raw == "" {
		return defaultRecommendationLimit, true
	}
	limit, err := strconv.Atoi(raw)
	if err != nil || limit < 1 {
		return 0, false
	}
	return min(limit, maxRecommendationLimit), true
}

// maxIngestBody bounds one event. The largest real payload is a few kilobytes; a bigger body gets 413 with
// a code that says so, rather than being cut off and reported as bad JSON.
const maxIngestBody = 10 << 20

// ingest answers 204 to every envelope it can apply, valid against the contract or not: a non-2xx stops Rails'
// outbox poller, and with it notifications and analytics (MF-203). Schema problems are logged instead. A
// schema_version or event_type this service cannot read gets 422 unsupported_contract, so Rails keeps the row
// as deferred and sends it again once this service understands it.
func (s *Server) ingest(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, maxIngestBody+1))
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_body", "Could not read the request body")
		return
	}
	if len(raw) > maxIngestBody {
		s.Log.Error("contract.too_large", "bytes_read", len(raw), "limit", maxIngestBody)
		writeError(w, http.StatusRequestEntityTooLarge, "payload_too_large", "The event body is larger than 10 MiB")
		return
	}

	// Decoded once, loosely: a field of the wrong type is a contract problem to log, not a reason to refuse.
	var decoded any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_json", "Request body must be JSON")
		return
	}
	body, ok := decoded.(map[string]any)
	if !ok {
		writeError(w, http.StatusUnprocessableEntity, "invalid_json", "Request body must be a JSON object")
		return
	}
	version, versionOK := schemaVersion(body)
	eventType, _ := body["event_type"].(string)
	idempotencyKey, _ := body["idempotency_key"].(string)
	logFields := []any{"event_type", eventType, "schema_version", body["schema_version"], "idempotency_key", idempotencyKey}

	if s.Contract == nil {
		s.Log.Error("contract.validator_missing", logFields...)
	} else {
		if !versionOK || !s.Contract.Supports(version) || !s.Contract.Knows(version, eventType) {
			s.Log.Error("contract.unsupported", logFields...)
			writeError(w, http.StatusUnprocessableEntity, "unsupported_contract",
				"This service cannot read this schema_version or event_type yet")
			return
		}
		if _, present := body["schema_version"]; !present {
			body["schema_version"] = float64(version)
		}
		if err := s.Contract.Validate(version, body); err != nil {
			s.Log.Warn("contract.invalid", append(logFields, "errors", err.Error())...)
		}
	}

	payload, _ := body["payload"].(map[string]any)
	err = s.Store.Apply(r.Context(), store.Incoming{
		IdempotencyKey: idempotencyKey,
		EventType:      eventType,
		Payload:        payload,
	})
	if err != nil {
		s.Log.Error("ingest failed", "error", err.Error(), "event_type", eventType)
		writeError(w, http.StatusInternalServerError, "ingest_failed", "Could not store the event")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// schemaVersion reads schema_version. Rails sent none before MF-203, so a missing one is version 1. A value
// that is not a whole number cannot name a version.
func schemaVersion(body map[string]any) (int, bool) {
	value, present := body["schema_version"]
	if !present {
		return 1, true
	}
	number, ok := value.(float64)
	if !ok || number != math.Trunc(number) {
		return 0, false
	}
	return int(number), true
}

func (s *Server) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]string{"code": code, "message": message},
	})
}

func Serve(ctx context.Context, addr string, handler http.Handler, log *slog.Logger) error {
	server := &http.Server{Addr: addr, Handler: handler}
	errCh := make(chan error, 1)
	go func() {
		errCh <- server.ListenAndServe()
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			return err
		}
		err := <-errCh
		if errors.Is(err, http.ErrServerClosed) {
			log.Info("server stopped")
			return nil
		}
		return err
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}
