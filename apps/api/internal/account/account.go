package account

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type ConsentStatus func(context.Context, string) (bool, error)
type Handler struct {
	DB       *sql.DB
	Consents ConsentStatus
}
type State struct {
	UserID         string     `json:"user_id"`
	Status         string     `json:"account_status"`
	Created        bool       `json:"account_created"`
	Completed      bool       `json:"onboarding_completed"`
	CompletedAt    *time.Time `json:"onboarding_completed_at"`
	SuspendedUntil *time.Time `json:"suspended_until,omitempty"`
	NextAction     string     `json:"next_action"`
}

func (h *Handler) State(ctx context.Context, id string) (State, error) {
	s := State{UserID: id}
	err := h.DB.QueryRowContext(ctx, `SELECT status,onboarding_completed_at,suspended_until FROM accounts WHERE user_id=$1`, id).Scan(&s.Status, &s.CompletedAt, &s.SuspendedUntil)
	s.Completed = s.CompletedAt != nil
	return s, err
}
func (h *Handler) Initialize(w http.ResponseWriter, r *http.Request) {
	id := auth.UserID(r.Context())
	res, err := h.DB.ExecContext(r.Context(), `INSERT INTO accounts(user_id) VALUES($1) ON CONFLICT(user_id) DO NOTHING`, id)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	n, err := res.RowsAffected()
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	s, err := h.State(r.Context(), id)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	s.Created = n == 1
	switch {
	case s.Status != "active":
		s.NextAction = "account_restricted"
	default:
		accepted := false
		if h.Consents != nil {
			accepted, err = h.Consents(r.Context(), id)
			if err != nil {
				httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
				return
			}
		}
		switch {
		case !accepted:
			s.NextAction = "accept_consents"
		case !s.Completed:
			s.NextAction = "complete_onboarding"
		default:
			s.NextAction = "discovery"
		}
	}
	httpapi.Data(w, 200, s)
}
func (h *Handler) Active(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s, err := h.State(r.Context(), auth.UserID(r.Context()))
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 403, "ACCOUNT_NOT_INITIALIZED")
			return
		}
		if err != nil {
			httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
			return
		}
		switch s.Status {
		case "frozen":
			httpapi.Fail(w, 403, "ACCOUNT_FROZEN")
			return
		case "suspended":
			httpapi.Fail(w, 403, "ACCOUNT_SUSPENDED")
			return
		case "active":
		default:
			httpapi.Fail(w, 403, "ACCOUNT_RESTRICTED")
			return
		}
		next.ServeHTTP(w, r)
	})
}
