package profile

import (
	"database/sql"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"time"
	"unicode/utf8"
)

type Revocation struct {
	Type string    `json:"type"`
	At   time.Time `json:"revoked_at"`
}

func (c *Consents) Revoke(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Types  []string `json:"consent_types"`
		Reason *string  `json:"reason"`
	}
	if !httpapi.Decode(w, r, &body) {
		return
	}
	if len(body.Types) < 1 || len(body.Types) > 3 {
		httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
		return
	}
	if body.Reason != nil && utf8.RuneCountInString(*body.Reason) > 1000 {
		httpapi.Validation(w, "INVALID_CONSENT_REQUEST", []httpapi.FieldError{{Field: "reason", Reason: "INVALID_LENGTH"}})
		return
	}
	supported := map[string]bool{"terms": true, "privacy": true, "sensitive_data": true}
	seen := map[string]bool{}
	for _, t := range body.Types {
		if !supported[t] || seen[t] {
			httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
			return
		}
		seen[t] = true
	}
	tx, err := c.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	if err = account.LockActive(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	out := []Revocation{}
	for _, kind := range body.Types {
		var version string
		err = tx.QueryRowContext(r.Context(), `SELECT document_version FROM user_consents WHERE user_id=$1 AND consent_type=$2 ORDER BY sequence DESC LIMIT 1`, id, kind).Scan(&version)
		if err == sql.ErrNoRows {
			err = tx.QueryRowContext(r.Context(), `SELECT document_version FROM consent_documents WHERE consent_type=$1 AND active FOR SHARE`, kind).Scan(&version)
		}
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 400, "INVALID_CONSENT_TYPE")
			return
		}
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		revocation := Revocation{Type: kind}
		err = tx.QueryRowContext(r.Context(), `INSERT INTO user_consents(user_id,consent_type,document_version,decision,reason) VALUES($1,$2,$3,'revoked',$4) RETURNING recorded_at`, id, kind, version, body.Reason).Scan(&revocation.At)
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		out = append(out, revocation)
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"revoked": out})
}
