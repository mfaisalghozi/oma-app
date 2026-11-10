package profile

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"time"
)

func lockCompleted(ctx context.Context, tx *sql.Tx, id string) error {
	if err := account.LockActive(ctx, tx, id); err != nil {
		return err
	}
	var completed bool
	if err := tx.QueryRowContext(ctx, `SELECT onboarding_completed_at IS NOT NULL FROM accounts WHERE user_id=$1`, id).Scan(&completed); err != nil {
		return err
	}
	if !completed {
		return &httpapi.Error{Status: 403, Code: "ONBOARDING_REQUIRED"}
	}
	return nil
}
func requireConsents(ctx context.Context, q Queryer, id string) error {
	ok, err := RequiredConsent(ctx, q, id)
	if err != nil {
		return err
	}
	if !ok {
		return &httpapi.Error{Status: 403, Code: "CONSENT_REQUIRED"}
	}
	return nil
}

// The value indicates whether an explicitly supplied null may clear the field.
var editableProfileFields = map[string]bool{
	"bio": false, "height_cm": false, "weight_kg": false, "ambition": true,
	"university_id": true, "religion_id": true, "personality_type_id": true,
	"pronoun_id": true, "show_me_option_id": false, "looking_for_ids": false, "hobby_ids": false,
}

func (h *Handler) Patch(w http.ResponseWriter, r *http.Request) {
	var body map[string]json.RawMessage
	if !httpapi.Decode(w, r, &body) {
		return
	}
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
	if err = requireConsents(r.Context(), tx, id); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var raw []byte
	err = tx.QueryRowContext(r.Context(), `SELECT row_to_json(p) FROM profiles p WHERE user_id=$1`, id).Scan(&raw)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	var p ProfileInput
	if err = json.Unmarshal(raw, &p); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	details := []httpapi.FieldError{}
	fields := map[string]bool{}
	var lookingFor, hobbies []string
	if len(body) == 0 {
		details = append(details, httpapi.FieldError{Field: "body", Reason: "AT_LEAST_ONE_FIELD_REQUIRED"})
	}
	for field, value := range body {
		nullable, ok := editableProfileFields[field]
		if !ok {
			details = append(details, httpapi.FieldError{Field: field, Reason: "FIELD_NOT_EDITABLE"})
			continue
		}
		if !nullable && bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			details = append(details, httpapi.FieldError{Field: field, Reason: "NULL_NOT_ALLOWED"})
			continue
		}
		var decodeErr error
		switch field {
		case "looking_for_ids":
			decodeErr = json.Unmarshal(value, &lookingFor)
		case "hobby_ids":
			decodeErr = json.Unmarshal(value, &hobbies)
		default:
			single, _ := json.Marshal(map[string]json.RawMessage{field: value})
			decodeErr = json.Unmarshal(single, &p)
		}
		if decodeErr != nil {
			details = append(details, httpapi.FieldError{Field: field, Reason: "INVALID_TYPE"})
			continue
		}
		fields[field] = true
	}
	validation, err := validateProfile(r.Context(), tx, p, fields)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	details = append(details, validation...)
	for _, selected := range []struct {
		field string
		ids   []string
	}{{"looking_for_ids", lookingFor}, {"hobby_ids", hobbies}} {
		if fields[selected.field] {
			bad, e := validateSelection(r.Context(), tx, selected.field, selected.ids)
			if e != nil {
				httpapi.HandleError(w, e)
				return
			}
			if bad != nil {
				details = append(details, *bad)
			}
		}
	}
	if len(details) > 0 {
		httpapi.Validation(w, "INVALID_PROFILE_DATA", details)
		return
	}
	var at time.Time
	err = tx.QueryRowContext(r.Context(), `UPDATE profiles SET bio=$1,height_cm=$2,weight_kg=$3,ambition=$4,university_id=$5,religion_id=$6,personality_type_id=$7,pronoun_id=$8,show_me_option_id=$9,updated_at=clock_timestamp() WHERE user_id=$10 RETURNING updated_at`, p.Bio, p.Height, p.Weight, p.Ambition, p.UniversityID, p.ReligionID, p.PersonalityID, p.PronounID, p.ShowMeID, id).Scan(&at)
	if err != nil {
		httpapi.HandleError(w, err)
		return
	}
	if fields["looking_for_ids"] {
		if _, err = tx.ExecContext(r.Context(), `DELETE FROM profile_looking_for WHERE user_id=$1`, id); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		for _, selected := range lookingFor {
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO profile_looking_for(user_id,looking_for_id) VALUES($1,$2)`, id, selected); err != nil {
				httpapi.HandleError(w, err)
				return
			}
		}
	}
	if fields["hobby_ids"] {
		if _, err = tx.ExecContext(r.Context(), `DELETE FROM profile_hobbies WHERE user_id=$1`, id); err != nil {
			httpapi.HandleError(w, err)
			return
		}
		for _, selected := range hobbies {
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO profile_hobbies(user_id,hobby_id) VALUES($1,$2)`, id, selected); err != nil {
				httpapi.HandleError(w, err)
				return
			}
		}
	}
	if err = tx.Commit(); err != nil {
		httpapi.HandleError(w, err)
		return
	}
	httpapi.Data(w, 200, map[string]any{"user_id": id, "updated": true, "updated_at": at})
}
