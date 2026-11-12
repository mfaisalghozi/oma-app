package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"oma/apps/api/internal/api"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/database"
	"oma/apps/api/internal/platform/storage"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	boot, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	db, err := database.Open(boot, os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Onboarding fails closed when no consent document is active, and the
	// symptom (every account stuck at accept_consents) is hard to trace back
	// to a missing registry row. Say it once, loudly, at startup.
	var activeDocuments int
	if err = db.QueryRowContext(boot, `SELECT count(*) FROM consent_documents WHERE active`).Scan(&activeDocuments); err != nil {
		log.Printf("warning: cannot read consent_documents: %v", err)
	} else if activeDocuments == 0 {
		log.Printf("warning: no active consent documents; every account will stop at accept_consents. Apply catalogs/dev-consent-documents.sql for local work, or insert the approved legal documents.")
	}

	issuer := strings.TrimRight(os.Getenv("SUPABASE_URL"), "/") + "/auth/v1"
	if os.Getenv("SUPABASE_URL") == "" {
		log.Fatal("SUPABASE_URL is required")
	}
	verifier := auth.NewJWKS(issuer+"/.well-known/jwks.json", issuer, "authenticated")
	store, err := storage.NewSupabase(os.Getenv("SUPABASE_URL"), os.Getenv("SUPABASE_SERVICE_ROLE_KEY"))
	if err != nil {
		log.Fatal(err)
	}
	if err = store.CheckBucket(boot); err != nil {
		log.Fatal("profile storage bucket unavailable or incorrectly configured")
	}
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	server := &http.Server{Addr: addr, Handler: api.NewWithStorage(db, verifier, store), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second}
	drained := make(chan struct{})
	go func() {
		defer close(drained)
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	log.Printf("API listening on %s", addr)
	if err = server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal("HTTP server failed")
	}
	<-drained
}
