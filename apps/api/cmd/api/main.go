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
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/config"
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
	policy, err := config.LoadDiscovery(os.Getenv("DISCOVERY_POLICY_FILE"))
	if err != nil {
		log.Fatal(err)
	}
	limitService, err := limits.NewService(limits.ConfigFromEnvironment(os.Getenv))
	if err != nil {
		log.Fatal(err)
	}
	var provider describe.JSONProvider
	if key := os.Getenv("BEDROCK_API_KEY"); key != "" {
		provider, err = describe.NewBedrock(describe.BedrockConfig{APIKey: key})
		if err != nil {
			log.Fatal("invalid Describe provider configuration")
		}
	}
	searches, err := describe.NewService(boot, db, store, policy, limitService, provider)
	if err != nil {
		log.Fatal("invalid Describe configuration")
	}
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	server := &http.Server{Addr: addr, Handler: api.NewWithDescribeServices(db, verifier, store, policy, limitService, searches), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second}
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
