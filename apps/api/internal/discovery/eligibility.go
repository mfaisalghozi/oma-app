// Package discovery supplies the eligibility boundary for a future discovery module.
// It deliberately does not expose a discovery HTTP endpoint or matching algorithm.
package discovery

import (
	"context"
	"database/sql"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type Eligibility struct{ DB *sql.DB }
type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func check(ctx context.Context, q queryer, id string) error {
	if !httpapi.ValidID(id) {
		return &httpapi.Error{Status: 401, Code: "UNAUTHORIZED"}
	}
	var status string
	var completed, consented, located bool
	err := q.QueryRowContext(ctx, `SELECT status,onboarding_completed_at IS NOT NULL,required_consents_completed(user_id),EXISTS(SELECT 1 FROM user_locations WHERE user_id=a.user_id) FROM accounts a WHERE user_id=$1`, id).Scan(&status, &completed, &consented, &located)
	if err == sql.ErrNoRows {
		return &httpapi.Error{Status: 403, Code: "ACCOUNT_NOT_INITIALIZED"}
	}
	if err != nil {
		return err
	}
	if err = account.StatusError(status); err != nil {
		return err
	}
	if !completed {
		return &httpapi.Error{Status: 403, Code: "ONBOARDING_REQUIRED"}
	}
	if !consented {
		return &httpapi.Error{Status: 403, Code: "CONSENT_REQUIRED"}
	}
	if !located {
		return &httpapi.Error{Status: 403, Code: "LOCATION_REQUIRED"}
	}
	return nil
}
func (e *Eligibility) Check(ctx context.Context, id string) error { return check(ctx, e.DB, id) }

// Guard expects authentication middleware to have populated the JWT subject.
func (e *Eligibility) Guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := e.Check(r.Context(), auth.UserID(r.Context())); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// CandidateIDs applies eligibility on the database side before limiting results.
// It returns identifiers only; ranking, pagination and public-profile projection belong to discovery.
func (e *Eligibility) CandidateIDs(ctx context.Context, viewerID string, limit int) ([]string, error) {
	if limit < 1 || limit > 100 {
		return nil, &httpapi.Error{Status: 400, Code: "INVALID_LIMIT"}
	}
	tx, err := e.DB.BeginTx(ctx, &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	if err = check(ctx, tx, viewerID); err != nil {
		return nil, err
	}
	rows, err := tx.QueryContext(ctx, `SELECT a.user_id FROM accounts a JOIN profiles p ON p.user_id=a.user_id JOIN user_locations l ON l.user_id=a.user_id WHERE a.status='active' AND a.onboarding_completed_at IS NOT NULL AND a.user_id<>$1 AND required_consents_completed(a.user_id) AND EXISTS(SELECT 1 FROM photos ph WHERE ph.user_id=a.user_id AND ph.status='active') ORDER BY a.user_id LIMIT $2`, viewerID, limit)
	if err != nil {
		return nil, err
	}
	out := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		out = append(out, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
}
