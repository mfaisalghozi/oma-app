package media

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"net/http"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
)

type Handler struct {
	DB    *sql.DB
	Store storage.Store
}
type Photo struct {
	ID       string  `json:"id"`
	Path     string  `json:"storage_path"`
	Position *int    `json:"position"`
	Primary  bool    `json:"is_primary"`
	Status   string  `json:"status"`
	URL      *string `json:"signed_url"`
}

func newID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("secure randomness unavailable")
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
}
func (h *Handler) transaction(r *http.Request) (*sql.Tx, error) {
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		return nil, err
	}
	if err = account.LockActive(r.Context(), tx, auth.UserID(r.Context())); err != nil {
		tx.Rollback()
		return nil, err
	}
	return tx, nil
}
func (h *Handler) Reserve(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Photos []struct {
			Filename    string `json:"filename"`
			ContentType string `json:"content_type"`
			Size        int64  `json:"file_size"`
		} `json:"photos"`
	}
	if !httpapi.Decode(w, r, &body) {
		return
	}
	if len(body.Photos) < 1 || len(body.Photos) > 6 {
		httpapi.Fail(w, 422, "INVALID_PHOTO_DATA")
		return
	}
	for _, p := range body.Photos {
		if storage.Extension(p.ContentType) == "" || p.Size < 1 || p.Size > storage.MaxPhotoSize {
			httpapi.Fail(w, 422, "INVALID_PHOTO_DATA")
			return
		}
	}
	tx, err := h.transaction(r)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	var count int
	if err = tx.QueryRowContext(r.Context(), `SELECT count(*) FROM photos WHERE user_id=$1 AND status<>'deleted'`, id).Scan(&count); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if count+len(body.Photos) > 6 {
		httpapi.Fail(w, 422, "PHOTO_LIMIT_EXCEEDED")
		return
	}
	out := []storage.Upload{}
	for _, p := range body.Photos {
		photoID := newID()
		path := id + "/" + photoID + storage.Extension(p.ContentType)
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO photos(id,user_id,storage_path,content_type,file_size) VALUES($1,$2,$3,$4,$5)`, photoID, id, path, p.ContentType, p.Size); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		upload, e := h.Store.CreateUpload(r.Context(), path)
		if e != nil {
			httpapi.Fail(w, 503, "STORAGE_UNAVAILABLE")
			return
		}
		upload.PhotoID = photoID
		out = append(out, upload)
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 201, out)
}
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	if !httpapi.ValidID(r.PathValue("id")) {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	tx, err := h.transaction(r)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	var path string
	err = tx.QueryRowContext(r.Context(), `SELECT storage_path FROM photos WHERE id=$1 AND user_id=$2 AND status='pending_upload'`, r.PathValue("id"), auth.UserID(r.Context())).Scan(&path)
	if err == sql.ErrNoRows {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	upload, err := h.Store.CreateUpload(r.Context(), path)
	if err != nil {
		httpapi.Fail(w, 503, "STORAGE_UNAVAILABLE")
		return
	}
	upload.PhotoID = r.PathValue("id")
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, upload)
}
func List(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, store storage.Store, id string) ([]Photo, error) {
	rows, err := db.QueryContext(ctx, `SELECT id,storage_path,position,is_primary,status FROM photos WHERE user_id=$1 AND status<>'deleted' ORDER BY position NULLS LAST,created_at,id`, id)
	if err != nil {
		return nil, err
	}
	out := []Photo{}
	for rows.Next() {
		var p Photo
		if err = rows.Scan(&p.ID, &p.Path, &p.Position, &p.Primary, &p.Status); err != nil {
			rows.Close()
			return nil, err
		}
		out = append(out, p)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	for i := range out {
		if out[i].Status == "active" {
			url, e := store.SignRead(ctx, out[i].Path)
			if e != nil {
				return nil, &httpapi.Error{Status: 503, Code: "STORAGE_UNAVAILABLE"}
			}
			out[i].URL = &url
		}
	}
	return out, nil
}
func (h *Handler) Read(w http.ResponseWriter, r *http.Request) {
	out, err := List(r.Context(), h.DB, h.Store, auth.UserID(r.Context()))
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, out)
}
func (h *Handler) Patch(w http.ResponseWriter, r *http.Request) {
	if !httpapi.ValidID(r.PathValue("id")) {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	var body struct {
		Position *int  `json:"position"`
		Primary  *bool `json:"is_primary"`
	}
	if !httpapi.Decode(w, r, &body) {
		return
	}
	if body.Position == nil && body.Primary == nil || body.Position != nil && (*body.Position < 1 || *body.Position > 6) {
		httpapi.Fail(w, 422, "INVALID_PHOTO_DATA")
		return
	}
	tx, err := h.transaction(r)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	photoID := r.PathValue("id")
	var position int
	var primary bool
	err = tx.QueryRowContext(r.Context(), `SELECT position,is_primary FROM photos WHERE id=$1 AND user_id=$2 AND status='active'`, photoID, id).Scan(&position, &primary)
	if err == sql.ErrNoRows {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if body.Position != nil && *body.Position != position {
		if _, err = tx.ExecContext(r.Context(), `UPDATE photos SET position=$1,updated_at=now() WHERE user_id=$2 AND status='active' AND position=$3`, position, id, *body.Position); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		position = *body.Position
	}
	if body.Primary != nil {
		wasPrimary := primary
		primary = *body.Primary
		if primary {
			_, err = tx.ExecContext(r.Context(), `UPDATE photos SET is_primary=false,updated_at=now() WHERE user_id=$1 AND is_primary`, id)
		} else if wasPrimary {
			var replacement string
			err = tx.QueryRowContext(r.Context(), `SELECT id FROM photos WHERE user_id=$1 AND status='active' AND id<>$2 ORDER BY position LIMIT 1`, id, photoID).Scan(&replacement)
			if err == sql.ErrNoRows {
				httpapi.Fail(w, 422, "PRIMARY_PHOTO_REQUIRED")
				return
			}
			if err == nil {
				_, err = tx.ExecContext(r.Context(), `UPDATE photos SET is_primary=false WHERE id=$1`, photoID)
				if err == nil {
					_, err = tx.ExecContext(r.Context(), `UPDATE photos SET is_primary=true,updated_at=now() WHERE id=$1`, replacement)
				}
			}
		}
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE photos SET position=$1,is_primary=$2,updated_at=now() WHERE id=$3`, position, primary, photoID); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"photo_id": photoID, "position": position, "is_primary": primary, "status": "active"})
}
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	if !httpapi.ValidID(r.PathValue("id")) {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	tx, err := h.transaction(r)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	id := auth.UserID(r.Context())
	photoID := r.PathValue("id")
	var path string
	err = tx.QueryRowContext(r.Context(), `SELECT storage_path FROM photos WHERE id=$1 AND user_id=$2`, photoID, id).Scan(&path)
	if err == sql.ErrNoRows {
		httpapi.Fail(w, 404, "PHOTO_NOT_FOUND")
		return
	}
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE photos SET status='deleted',position=NULL,is_primary=false,updated_at=now() WHERE id=$1`, photoID); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE photos SET is_primary=true,updated_at=now() WHERE id=(SELECT id FROM photos WHERE user_id=$1 AND status='active' AND NOT EXISTS(SELECT 1 FROM photos WHERE user_id=$1 AND is_primary) ORDER BY position LIMIT 1)`, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = h.Store.Remove(r.Context(), path); err != nil && !errors.Is(err, storage.ErrNotFound) {
		httpapi.Fail(w, 503, "STORAGE_UNAVAILABLE")
		return
	}
	httpapi.Data(w, 200, map[string]any{"photo_id": photoID, "deleted": true})
}
