package limits

import (
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

// HandlerUsage is mounted behind the caller's identity and account guards.
func (s *Service) HandlerUsage(db *sql.DB) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			httpapi.Fail(w, 405, "METHOD_NOT_ALLOWED")
			return
		}
		if r.URL.RawQuery != "" {
			httpapi.Fail(w, 400, "INVALID_REQUEST")
			return
		}
		owner := auth.UserID(r.Context())
		if !httpapi.ValidID(owner) {
			httpapi.Fail(w, 401, "UNAUTHORIZED")
			return
		}
		tx, err := db.BeginTx(r.Context(), nil)
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		defer tx.Rollback()
		u, err := s.UsageTx(r.Context(), tx, owner, time.Now())
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 404, "ACCOUNT_NOT_FOUND")
			return
		}
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		if err = tx.Commit(); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		httpapi.Data(w, 200, u)
	})
}
