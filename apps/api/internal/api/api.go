package api

import (
	"context"
	"database/sql"
	"io"

	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/masterdata"
	"oma/apps/api/internal/media"
	"oma/apps/api/internal/platform/apidocs"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
	"oma/apps/api/internal/profile"
	"time"

	"github.com/gin-gonic/gin"
)

func New(db *sql.DB, verifier auth.Verifier) http.Handler {
	return NewWithStorage(db, verifier, storage.Unavailable{})
}

func NewWithStorage(db *sql.DB, verifier auth.Verifier, store storage.Store) http.Handler {
	router := gin.New()
	router.RedirectTrailingSlash = false
	router.RedirectFixedPath = false
	router.HandleMethodNotAllowed = true
	// Proxy headers must not affect identity unless trusted proxies are explicitly configured.
	_ = router.SetTrustedProxies(nil)
	router.Use(gin.CustomRecoveryWithWriter(io.Discard, func(c *gin.Context, _ any) {
		if !c.Writer.Written() {
			httpapi.Fail(c.Writer, 500, "INTERNAL_SERVER_ERROR")
		}
		c.Abort()
	}))
	router.Use(func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
		defer cancel()
		c.Request = c.Request.WithContext(ctx)
		c.Next()
	})
	router.NoRoute(func(c *gin.Context) { httpapi.Fail(c.Writer, 404, "NOT_FOUND") })
	router.NoMethod(func(c *gin.Context) { httpapi.Fail(c.Writer, 405, "METHOD_NOT_ALLOWED") })
	apidocs.Register(router)
	// Retain the HTTP handler boundary while Gin owns route matching and middleware.
	route := func(method, path string, handler http.Handler) {
		adapted := func(c *gin.Context) {
			for _, param := range c.Params {
				c.Request.SetPathValue(param.Key, param.Value)
			}
			if c.Request.Method == http.MethodHead {
				c.Writer = &headWriter{ResponseWriter: c.Writer}
			}
			handler.ServeHTTP(c.Writer, c.Request)
		}
		router.Handle(method, path, adapted)
		if method == http.MethodGet {
			router.HEAD(path, adapted)
		}
	}
	route(
		"GET", "/health",
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { httpapi.Write(w, 200, map[string]string{"status": "ok"}) }),
	)

	photos := &media.Handler{DB: db, Store: store}
	profiles := &profile.Handler{DB: db, Store: store}
	consents := &profile.Consents{DB: db}
	accounts := &account.Handler{DB: db, Consents: consents.Required}
	master := &masterdata.Handler{DB: db}

	route(
		"POST", "/v1/me/initialize",
		auth.Middleware(verifier, http.HandlerFunc(accounts.Initialize)),
	)

	guard := func(h http.HandlerFunc) http.Handler { return auth.Middleware(verifier, accounts.Active(h)) }
	route("POST", "/v1/devices", guard(accounts.RegisterDevice))
	route("DELETE", "/v1/devices/:id", guard(accounts.DeleteDevice))
	route("GET", "/v1/me/profile", guard(profiles.Read))
	route("PATCH", "/v1/me/profile", guard(profiles.Patch))
	route("PUT", "/v1/me/location", guard(profiles.PutLocation))
	route("DELETE", "/v1/me/location", guard(profiles.DeleteLocation))
	route("POST", "/v1/me/onboarding", guard(profiles.Onboarding))
	route("POST", "/v1/photos/upload-urls", guard(photos.Reserve))
	route("POST", "/v1/photos/:id/upload-url", guard(photos.Refresh))
	route("GET", "/v1/photos", guard(photos.Read))
	route("PATCH", "/v1/photos/:id", guard(photos.Patch))
	route("DELETE", "/v1/photos/:id", guard(photos.Delete))

	route(
		"GET", "/v1/profile-data",
		auth.Middleware(verifier, accounts.Active(http.HandlerFunc(master.List))),
	)
	route("GET", "/v1/consents/documents", http.HandlerFunc(consents.Documents))
	route(
		"GET", "/v1/me/consents",
		auth.Middleware(verifier, accounts.Active(http.HandlerFunc(consents.Read))),
	)
	route(
		"POST", "/v1/me/consents",
		auth.Middleware(verifier, accounts.Active(http.HandlerFunc(consents.Accept))),
	)
	route("POST", "/v1/me/consents/revocations", guard(consents.Revoke))

	return router
}

// HEAD executes GET semantics without sending a response body, including in HTTP fixtures.
type headWriter struct{ gin.ResponseWriter }

func (w *headWriter) Write(p []byte) (int, error)       { w.WriteHeaderNow(); return len(p), nil }
func (w *headWriter) WriteString(s string) (int, error) { return w.Write([]byte(s)) }
