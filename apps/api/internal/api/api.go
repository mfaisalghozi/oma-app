package api

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

func New(db *sql.DB, verifier auth.Verifier) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { httpapi.Write(w, 200, map[string]string{"status": "ok"}) })
	accounts := &account.Handler{DB: db}
	mux.Handle("POST /v1/me/initialize", auth.Middleware(verifier, http.HandlerFunc(accounts.Initialize)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		mux.ServeHTTP(w, r.WithContext(ctx))
	})
}
