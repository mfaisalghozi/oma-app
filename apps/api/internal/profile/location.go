package profile

import (
	"encoding/json"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"time"
)

func (h *Handler) PutLocation(w http.ResponseWriter, r *http.Request) {
	var fields map[string]json.RawMessage
	if !httpapi.Decode(w, r, &fields) {
		return
	}
	for field := range fields {
		if field != "latitude" && field != "longitude" {
			httpapi.Fail(w, 400, "INVALID_REQUEST")
			return
		}
	}
	var body Coordinates
	invalid := json.Unmarshal(fields["latitude"], &body.Latitude) != nil
	invalid = json.Unmarshal(fields["longitude"], &body.Longitude) != nil || invalid
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	if err = lockCompleted(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = account.RequireConsents(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if invalid || !body.Valid() {
		httpapi.Fail(w, 422, "INVALID_COORDINATES")
		return
	}
	var at time.Time
	err = tx.QueryRowContext(r.Context(), `INSERT INTO user_locations(user_id,location) VALUES($1,public.ST_SetSRID(public.ST_MakePoint($2,$3),4326)::public.geography) ON CONFLICT(user_id) DO UPDATE SET location=EXCLUDED.location,updated_at=clock_timestamp() RETURNING updated_at`, id, *body.Longitude, *body.Latitude).Scan(&at)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"updated": true, "updated_at": at})
}
func (h *Handler) DeleteLocation(w http.ResponseWriter, r *http.Request) {
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	if err = lockCompleted(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	// Removing stored location remains available after consent revocation.
	if _, err = tx.ExecContext(r.Context(), `DELETE FROM user_locations WHERE user_id=$1`, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]bool{"deleted": true})
}
