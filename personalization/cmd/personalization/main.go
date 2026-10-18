package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"myforum/personalization/internal/httpapi"
	"myforum/personalization/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		databaseURL = "postgres://localhost/my_forum_development?sslmode=disable"
	}

	db, err := store.OpenPostgres(ctx, databaseURL)
	if err != nil {
		log.Error("database setup failed", "error", err.Error())
		os.Exit(1)
	}
	defer db.Close()

	addr := os.Getenv("PORT")
	if addr == "" {
		addr = "8080"
	}
	server := &httpapi.Server{Store: db, Log: log}
	log.Info("listening", "addr", addr)
	if err := httpapi.Serve(ctx, ":"+addr, server.Handler(), log); err != nil {
		log.Error("server exited", "error", err.Error())
		os.Exit(1)
	}
}
