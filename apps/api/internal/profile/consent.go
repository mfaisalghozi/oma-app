package profile

import (
	"context"
	"database/sql"
	"net/http"
	"time"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

type Queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}
type Consents struct{ DB *sql.DB }
type Document struct {
	Type     string `json:"type"`
	Title    string `json:"title"`
	Version  string `json:"version"`
	URL      string `json:"document_url"`
	Required bool   `json:"required"`
}
type Decision struct {
	Type       string    `json:"type"`
	Version    string    `json:"version"`
	Decision   string    `json:"decision"`
	RecordedAt time.Time `json:"accepted_at"`
}

// RequiredConsent checks the latest decision across all versions, then requires
// acceptance of every currently-required active version. An empty registry fails closed.
func RequiredConsent(ctx context.Context, q Queryer, id string) (bool, error) {
	var complete bool
	err := q.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM consent_documents WHERE active AND required)
 AND NOT EXISTS(SELECT 1 FROM consent_documents d
 LEFT JOIN LATERAL (SELECT decision,document_version FROM user_consents WHERE user_id=$1 AND consent_type=d.consent_type ORDER BY sequence DESC LIMIT 1) c ON true
 WHERE d.active AND d.required AND (c.decision IS DISTINCT FROM 'accepted' OR c.document_version IS DISTINCT FROM d.document_version))`, id).Scan(&complete)
	return complete, err
}
func (c *Consents) Required(ctx context.Context, id string) (bool, error) {
	return RequiredConsent(ctx, c.DB, id)
}
func (c *Consents) Documents(w http.ResponseWriter, r *http.Request) {
	rows, err := c.DB.QueryContext(r.Context(), `SELECT consent_type,title,document_version,document_url,required FROM consent_documents WHERE active ORDER BY consent_type`)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	defer rows.Close()
	out := []Document{}
	for rows.Next() {
		var d Document
		if err = rows.Scan(&d.Type, &d.Title, &d.Version, &d.URL, &d.Required); err != nil {
			httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
			return
		}
		out = append(out, d)
	}
	if rows.Err() != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	httpapi.Data(w, 200, out)
}
func latestConsents(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, id string) ([]Decision, error) {
	rows, err := db.QueryContext(ctx, `SELECT DISTINCT ON (consent_type) consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id=$1 ORDER BY consent_type,sequence DESC`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Decision{}
	for rows.Next() {
		var d Decision
		if err = rows.Scan(&d.Type, &d.Version, &d.Decision, &d.RecordedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}
func (c *Consents) Read(w http.ResponseWriter, r *http.Request) {
	out, err := latestConsents(r.Context(), c.DB, auth.UserID(r.Context()))
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	httpapi.Data(w, 200, out)
}
func (c *Consents) Accept(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Consents []struct {
			Type     string `json:"type"`
			Accepted *bool  `json:"accepted"`
		} `json:"consents"`
	}
	if !httpapi.Decode(w, r, &body) {
		return
	}
	if len(body.Consents) == 0 || len(body.Consents) > 3 {
		httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
		return
	}
	id := auth.UserID(r.Context())
	tx, err := c.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	defer tx.Rollback()
	if err = account.LockActive(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	seen := map[string]bool{}
	for _, d := range body.Consents {
		if d.Accepted == nil || seen[d.Type] {
			httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
			return
		}
		seen[d.Type] = true
		var version string
		err = tx.QueryRowContext(r.Context(), `SELECT document_version FROM consent_documents WHERE consent_type=$1 AND active FOR SHARE`, d.Type).Scan(&version)
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
			return
		}
		if err != nil {
			httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
			return
		}
		decision := "rejected"
		if *d.Accepted {
			decision = "accepted"
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO user_consents(user_id,consent_type,document_version,decision) VALUES($1,$2,$3,$4)`, id, d.Type, version, decision); err != nil {
			httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
			return
		}
	}
	complete, err := RequiredConsent(r.Context(), tx, id)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	out, err := latestConsents(r.Context(), tx, id)
	if err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.Fail(w, 500, "INTERNAL_SERVER_ERROR")
		return
	}
	httpapi.Data(w, 200, map[string]any{"consents": out, "required_consents_completed": complete})
}
