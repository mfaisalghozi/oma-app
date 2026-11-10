package api

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/masterdata"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/profile"
)

func New(db *sql.DB, verifier auth.Verifier) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { httpapi.Write(w, 200, map[string]string{"status": "ok"}) })
	consents := &profile.Consents{DB: db}
	accounts := &account.Handler{DB: db, Consents: consents.Required}
	mux.Handle("POST /v1/me/initialize", auth.Middleware(verifier, http.HandlerFunc(accounts.Initialize)))
	master := &masterdata.Handler{DB: db}
	mux.Handle("GET /v1/profile-data", auth.Middleware(verifier, accounts.Active(http.HandlerFunc(master.List))))
	mux.HandleFunc("GET /v1/consents/documents", consents.Documents)
	mux.Handle("GET /v1/me/consents", auth.Middleware(verifier, accounts.Active(http.HandlerFunc(consents.Read))))
	mux.Handle("POST /v1/me/consents", auth.Middleware(verifier, accounts.Active(http.HandlerFunc(consents.Accept))))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
		defer cancel()
		mux.ServeHTTP(w, r.WithContext(ctx))
	})
}
