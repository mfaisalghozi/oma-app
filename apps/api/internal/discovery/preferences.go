package discovery

import (
	"encoding/json"
	"math"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
)

func (h *Handler) Preferences(w http.ResponseWriter, r *http.Request) {
	if err := h.configured(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var fields map[string]json.RawMessage
	if !httpapi.Decode(w, r, &fields) {
		return
	}
	if len(fields) == 0 {
		httpapi.Fail(w, 400, "INVALID_REQUEST")
		return
	}
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	viewer := auth.UserID(r.Context())
	if err = account.LockActive(r.Context(), tx, viewer); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = check(r.Context(), tx, viewer); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var minAge, maxAge int
	var radius float64
	if err = tx.QueryRowContext(r.Context(), `SELECT COALESCE(min_age,$2),COALESCE(max_age,$3),COALESCE(radius_km,$4) FROM profiles WHERE user_id=$1`, viewer, h.Policy.DefaultMinAge, h.Policy.DefaultMaxAge, h.Policy.DefaultRadiusKM).Scan(&minAge, &maxAge, &radius); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	invalid := false
	for key, raw := range fields {
		if string(raw) == "null" {
			invalid = true
			continue
		}
		switch key {
		case "min_age":
			invalid = json.Unmarshal(raw, &minAge) != nil || invalid
		case "max_age":
			invalid = json.Unmarshal(raw, &maxAge) != nil || invalid
		case "radius_km":
			invalid = json.Unmarshal(raw, &radius) != nil || invalid
		default:
			invalid = true
		}
	}
	if invalid || minAge < 18 || maxAge < minAge || maxAge > 32767 || math.IsNaN(radius) || math.IsInf(radius, 0) || radius <= 0 || radius > h.Policy.MaxRadiusKM {
		httpapi.Fail(w, 422, "INVALID_DISCOVERY_PREFERENCES")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE profiles SET min_age=$2,max_age=$3,radius_km=$4,updated_at=clock_timestamp() WHERE user_id=$1`, viewer, minAge, maxAge, radius); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"min_age": minAge, "max_age": maxAge, "radius_km": radius})
}
