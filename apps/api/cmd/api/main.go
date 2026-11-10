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
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	server := &http.Server{Addr: addr, Handler: api.New(db, verifier), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second}
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
