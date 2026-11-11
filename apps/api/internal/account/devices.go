package account

import (
	"net/http"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"strings"
)

func (h *Handler) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
		Provider string `json:"provider"`
	}
	if !httpapi.Decode(w, r, &body) {
		return
	}
	if strings.TrimSpace(body.Token) == "" || len(body.Token) > 8192 || strings.ContainsAny(body.Token, "\r\n") || (body.Platform != "ios" && body.Platform != "android") || (body.Provider != "fcm" && body.Provider != "apns") {
		httpapi.Fail(w, 422, "INVALID_DEVICE_DATA")
		return
	}
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	if err = LockActive(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var deviceID string
	err = tx.QueryRowContext(r.Context(), `INSERT INTO device_tokens(user_id,token,platform,provider) VALUES($1,$2,$3,$4) ON CONFLICT(token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,provider=EXCLUDED.provider,updated_at=now() RETURNING id`, id, body.Token, body.Platform, body.Provider).Scan(&deviceID)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"device_id": deviceID, "registered": true})
}
func (h *Handler) DeleteDevice(w http.ResponseWriter, r *http.Request) {
	deviceID := r.PathValue("id")
	if !httpapi.ValidID(deviceID) {
		httpapi.Fail(w, 404, "DEVICE_NOT_FOUND")
		return
	}
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	if err = LockActive(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	result, err := tx.ExecContext(r.Context(), `DELETE FROM device_tokens WHERE id=$1 AND user_id=$2`, deviceID, id)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	count, err := result.RowsAffected()
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if count == 0 {
		httpapi.Fail(w, 404, "DEVICE_NOT_FOUND")
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"device_id": deviceID, "deleted": true})
}
