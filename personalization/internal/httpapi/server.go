package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"myforum/personalization/internal/ranking"
	"myforum/personalization/internal/store"
)

type Server struct {
	Store store.Store
	Log   *slog.Logger
	Now   func() time.Time
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

	now := s.now()
	events, profile, err := s.Store.Candidates(r.Context(), userID, now)
	if err != nil {
		s.Log.Error("recommendations failed", "error", err.Error(), "user_id", userID)
		writeError(w, http.StatusInternalServerError, "recommendations_failed", "Could not load recommendations")
		return
	}

	ranked := ranking.Rank(events, profile, now, 10)
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

func (s *Server) ingest(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IdempotencyKey string         `json:"idempotency_key"`
		EventType      string         `json:"event_type"`
		Payload        map[string]any `json:"payload"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_json", "Request body must be JSON")
		return
	}
	if body.EventType == "" {
		writeError(w, http.StatusUnprocessableEntity, "invalid_event", "event_type is required")
		return
	}

	err := s.Store.Apply(r.Context(), store.Incoming{
		IdempotencyKey: body.IdempotencyKey,
		EventType:      body.EventType,
		Payload:        body.Payload,
	})
	if err != nil {
		s.Log.Error("ingest failed", "error", err.Error(), "event_type", body.EventType)
		writeError(w, http.StatusInternalServerError, "ingest_failed", "Could not store the event")
		return
	}
	w.WriteHeader(http.StatusNoContent)
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
