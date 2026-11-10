package api

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/masterdata"
	"oma/apps/api/internal/media"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
	"oma/apps/api/internal/profile"
)

func New(db *sql.DB, verifier auth.Verifier) http.Handler {
	return NewWithStorage(db, verifier, storage.Unavailable{})
}

func NewWithStorage(db *sql.DB, verifier auth.Verifier, store storage.Store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) { httpapi.Write(w, 200, map[string]string{"status": "ok"}) })
	photos := &media.Handler{DB: db, Store: store}
	profiles := &profile.Handler{DB: db, Store: store}
	consents := &profile.Consents{DB: db}
	accounts := &account.Handler{DB: db, Consents: consents.Required}
	mux.Handle("POST /v1/me/initialize", auth.Middleware(verifier, http.HandlerFunc(accounts.Initialize)))
	guard := func(h http.HandlerFunc) http.Handler { return auth.Middleware(verifier, accounts.Active(h)) }
	mux.Handle("POST /v1/devices", guard(accounts.RegisterDevice))
	mux.Handle("DELETE /v1/devices/{id}", guard(accounts.DeleteDevice))
	mux.Handle("GET /v1/me/profile", guard(profiles.Read))
	mux.Handle("PATCH /v1/me/profile", guard(profiles.Patch))
	mux.Handle("POST /v1/me/onboarding", guard(profiles.Onboarding))
	mux.Handle("POST /v1/photos/upload-urls", guard(photos.Reserve))
	mux.Handle("POST /v1/photos/{id}/upload-url", guard(photos.Refresh))
	mux.Handle("GET /v1/photos", guard(photos.Read))
	mux.Handle("PATCH /v1/photos/{id}", guard(photos.Patch))
	mux.Handle("DELETE /v1/photos/{id}", guard(photos.Delete))
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
