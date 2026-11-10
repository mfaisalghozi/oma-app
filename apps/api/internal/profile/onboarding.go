package profile

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
)

type Handler struct {
	DB    *sql.DB
	Store storage.Store
}
type SelectedPhoto struct {
	ID       string `json:"photo_id"`
	Position int    `json:"position"`
}
type OnboardingInput struct {
	Profile    ProfileInput    `json:"profile"`
	LookingFor []string        `json:"looking_for_ids"`
	Hobbies    []string        `json:"hobby_ids"`
	Photos     []SelectedPhoto `json:"photos"`
	Location   *Coordinates    `json:"location"`
}

func (h *Handler) Onboarding(w http.ResponseWriter, r *http.Request) {
	var body OnboardingInput
	if !httpapi.Decode(w, r, &body) {
		return
	}
	id := auth.UserID(r.Context())
	tx, err := h.DB.BeginTx(r.Context(), nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	defer tx.Rollback()
	if err = account.LockActive(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var completed *time.Time
	if err = tx.QueryRowContext(r.Context(), `SELECT onboarding_completed_at FROM accounts WHERE user_id=$1`, id).Scan(&completed); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if completed != nil {
		httpapi.Fail(w, 409, "ONBOARDING_ALREADY_COMPLETED")
		return
	}
	consented, err := RequiredConsent(r.Context(), tx, id)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if !consented {
		httpapi.Fail(w, 403, "CONSENT_REQUIRED")
		return
	}
	details, err := validateProfile(r.Context(), tx, body.Profile, nil)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	for _, s := range []struct {
		field string
		ids   []string
	}{{"looking_for_ids", body.LookingFor}, {"hobby_ids", body.Hobbies}} {
		bad, e := validateSelection(r.Context(), tx, s.field, s.ids)
		if e != nil {
			httpapi.HandleError(w, e)
			return
		}
		if bad != nil {
			details = append(details, *bad)
		}
	}
	if body.Location != nil && !body.Location.Valid() {
		details = append(details, httpapi.FieldError{Field: "location", Reason: "INVALID_COORDINATES"})
	}
	minPosition := 7
	seenID := map[string]bool{}
	seenPosition := map[int]bool{}
	if len(body.Photos) < 1 || len(body.Photos) > 6 {
		details = append(details, httpapi.FieldError{Field: "photos", Reason: "ONE_TO_SIX_REQUIRED"})
	}
	for i := range body.Photos {
		body.Photos[i].ID = strings.ToLower(body.Photos[i].ID)
		photo := body.Photos[i]
		if !httpapi.ValidID(photo.ID) || seenID[photo.ID] || seenPosition[photo.Position] || photo.Position < 1 || photo.Position > 6 {
			details = append(details, httpapi.FieldError{Field: "photos", Reason: "INVALID_PHOTO_SELECTION"})
		}
		seenID[photo.ID] = true
		seenPosition[photo.Position] = true
		if photo.Position < minPosition {
			minPosition = photo.Position
		}
	}
	if len(details) > 0 {
		httpapi.Validation(w, "ONBOARDING_VALIDATION_FAILED", details)
		return
	}
	for _, photo := range body.Photos {
		var path, contentType string
		err = tx.QueryRowContext(r.Context(), `SELECT storage_path,content_type FROM photos WHERE id=$1 AND user_id=$2 AND status='pending_upload'`, photo.ID, id).Scan(&path, &contentType)
		if err == sql.ErrNoRows {
			httpapi.Fail(w, 422, "PHOTO_UPLOAD_INCOMPLETE")
			return
		}
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		info, e := h.Store.ObjectInfo(r.Context(), path)
		if errors.Is(e, storage.ErrNotFound) {
			httpapi.Fail(w, 422, "PHOTO_UPLOAD_INCOMPLETE")
			return
		}
		if e != nil {
			httpapi.Fail(w, 503, "STORAGE_UNAVAILABLE")
			return
		}
		if info.Size < 1 || info.Size > storage.MaxPhotoSize || storage.Extension(info.ContentType) == "" || info.ContentType != contentType {
			httpapi.Fail(w, 422, "PHOTO_UPLOAD_INCOMPLETE")
			return
		}
	}
	p := body.Profile
	_, err = tx.ExecContext(r.Context(), `INSERT INTO profiles(user_id,full_name,birthdate,gender_id,pronoun_id,show_me_option_id,bio,height_cm,weight_kg,university_id,ambition,religion_id,personality_type_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`, id, strings.TrimSpace(p.FullName), p.Birthdate, p.GenderID, p.PronounID, p.ShowMeID, p.Bio, p.Height, p.Weight, p.UniversityID, p.Ambition, p.ReligionID, p.PersonalityID)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	for _, selected := range body.LookingFor {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO profile_looking_for(user_id,looking_for_id) VALUES($1,$2)`, id, selected); err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	for _, selected := range body.Hobbies {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO profile_hobbies(user_id,hobby_id) VALUES($1,$2)`, id, selected); err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	if body.Location != nil {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO user_locations(user_id,location) VALUES($1,public.ST_SetSRID(public.ST_MakePoint($2,$3),4326)::public.geography)`, id, *body.Location.Longitude, *body.Location.Latitude); err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	for _, photo := range body.Photos {
		if _, err = tx.ExecContext(r.Context(), `UPDATE photos SET status='active',position=$1,is_primary=$2,updated_at=now() WHERE id=$3 AND user_id=$4`, photo.Position, photo.Position == minPosition, photo.ID, id); err != nil {
			httpapi.HandleError(w, err)
			return
		}
	}
	var at time.Time
	if err = tx.QueryRowContext(r.Context(), `UPDATE accounts SET onboarding_completed_at=clock_timestamp(),updated_at=now() WHERE user_id=$1 RETURNING onboarding_completed_at`, id).Scan(&at); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 201, map[string]any{"user_id": id, "onboarding_completed": true, "onboarding_completed_at": at})
}
