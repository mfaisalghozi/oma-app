package profile

import (
	"context"
	"database/sql"
	"math"
	"oma/apps/api/internal/platform/httpapi"
	"strings"
	"time"
	"unicode/utf8"
)

type ProfileInput struct {
	FullName      string  `json:"full_name"`
	Birthdate     string  `json:"birthdate"`
	GenderID      string  `json:"gender_id"`
	PronounID     *string `json:"pronoun_id"`
	ShowMeID      string  `json:"show_me_option_id"`
	Bio           string  `json:"bio"`
	Height        int     `json:"height_cm"`
	Weight        int     `json:"weight_kg"`
	UniversityID  *string `json:"university_id"`
	Ambition      *string `json:"ambition"`
	ReligionID    *string `json:"religion_id"`
	PersonalityID *string `json:"personality_type_id"`
}
type Coordinates struct {
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
}

func (c *Coordinates) Valid() bool {
	return c != nil && c.Latitude != nil && c.Longitude != nil && !math.IsNaN(*c.Latitude) && !math.IsNaN(*c.Longitude) && !math.IsInf(*c.Latitude, 0) && !math.IsInf(*c.Longitude, 0) && *c.Latitude >= -90 && *c.Latitude <= 90 && *c.Longitude >= -180 && *c.Longitude <= 180
}

type validationQuery interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

var referenceQueries = map[string]string{
	"gender_id":           `SELECT EXISTS(SELECT 1 FROM gender_options WHERE id=$1 AND is_active)`,
	"pronoun_id":          `SELECT EXISTS(SELECT 1 FROM pronoun_options WHERE id=$1 AND is_active)`,
	"show_me_option_id":   `SELECT EXISTS(SELECT 1 FROM show_me_options WHERE id=$1 AND is_active)`,
	"university_id":       `SELECT EXISTS(SELECT 1 FROM universities WHERE id=$1 AND is_active)`,
	"religion_id":         `SELECT EXISTS(SELECT 1 FROM religions WHERE id=$1 AND is_active)`,
	"personality_type_id": `SELECT EXISTS(SELECT 1 FROM personality_types WHERE id=$1 AND is_active)`,
}

func validateProfile(ctx context.Context, q validationQuery, p ProfileInput, fields map[string]bool) ([]httpapi.FieldError, error) {
	out := []httpapi.FieldError{}
	check := func(field string) bool { return fields == nil || fields[field] }
	bad := func(field, reason string) { out = append(out, httpapi.FieldError{Field: field, Reason: reason}) }
	if check("full_name") && (utf8.RuneCountInString(strings.TrimSpace(p.FullName)) < 2 || utf8.RuneCountInString(p.FullName) > 100) {
		bad("full_name", "INVALID_LENGTH")
	}
	if check("birthdate") {
		birth, err := time.Parse("2006-01-02", p.Birthdate)
		today := time.Now().UTC().Truncate(24 * time.Hour)
		switch {
		case err != nil:
			bad("birthdate", "INVALID_DATE")
		case birth.After(today):
			bad("birthdate", "FUTURE_BIRTHDATE")
		case birth.AddDate(18, 0, 0).After(today):
			bad("birthdate", "USER_UNDER_18")
		}
	}
	if check("bio") && (strings.TrimSpace(p.Bio) == "" || utf8.RuneCountInString(p.Bio) > 255) {
		bad("bio", "INVALID_LENGTH")
	}
	if check("height_cm") && (p.Height < 100 || p.Height > 250) {
		bad("height_cm", "OUT_OF_RANGE")
	}
	if check("weight_kg") && (p.Weight < 25 || p.Weight > 300) {
		bad("weight_kg", "OUT_OF_RANGE")
	}
	if check("ambition") && p.Ambition != nil && utf8.RuneCountInString(*p.Ambition) > 500 {
		bad("ambition", "INVALID_LENGTH")
	}
	refs := []struct {
		field string
		id    *string
	}{{"gender_id", &p.GenderID}, {"show_me_option_id", &p.ShowMeID}, {"pronoun_id", p.PronounID}, {"university_id", p.UniversityID}, {"religion_id", p.ReligionID}, {"personality_type_id", p.PersonalityID}}
	for _, ref := range refs {
		if !check(ref.field) || ref.id == nil {
			continue
		}
		if !httpapi.ValidID(*ref.id) {
			bad(ref.field, "INVALID_MASTER_DATA_REFERENCE")
			continue
		}
		var exists bool
		if err := q.QueryRowContext(ctx, referenceQueries[ref.field], *ref.id).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			bad(ref.field, "INVALID_MASTER_DATA_REFERENCE")
		}
	}
	return out, nil
}
func validateSelection(ctx context.Context, q validationQuery, field string, ids []string) (*httpapi.FieldError, error) {
	bad := func(reason string) (*httpapi.FieldError, error) {
		return &httpapi.FieldError{Field: field, Reason: reason}, nil
	}
	if len(ids) == 0 {
		return bad("AT_LEAST_ONE_REQUIRED")
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if !httpapi.ValidID(id) {
			return bad("INVALID_MASTER_DATA_REFERENCE")
		}
		if seen[strings.ToLower(id)] {
			return bad("DUPLICATE_SELECTION")
		}
		seen[strings.ToLower(id)] = true
	}
	var query string
	switch field {
	case "looking_for_ids":
		query = `SELECT count(*) FROM looking_for_options WHERE id=ANY($1::uuid[]) AND is_active`
	case "hobby_ids":
		query = `SELECT count(*) FROM hobbies h JOIN hobby_categories c ON c.id=h.category_id WHERE h.id=ANY($1::uuid[]) AND h.is_active AND c.is_active`
	default:
		return bad("INVALID_MASTER_DATA_REFERENCE")
	}
	var count int
	if err := q.QueryRowContext(ctx, query, ids).Scan(&count); err != nil {
		return nil, err
	}
	if count != len(ids) {
		return bad("INVALID_MASTER_DATA_REFERENCE")
	}
	return nil, nil
}
