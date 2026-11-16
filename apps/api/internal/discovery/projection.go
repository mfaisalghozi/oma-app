package discovery

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"oma/apps/api/internal/platform/httpapi"
	"strings"
)

type Photo struct {
	ID       string `json:"id"`
	Position int    `json:"position"`
	ReadURL  string `json:"read_url"`
}
type PublicOption struct {
	ID    string `json:"id"`
	Code  string `json:"code"`
	Label string `json:"label"`
}
type PublicUniversity struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	CountryCode string `json:"country_code"`
}
type Card struct {
	EvidenceSnapshot string            `json:"-"`
	Hobbies          []PublicOption    `json:"hobbies"`
	LookingFor       []PublicOption    `json:"looking_for"`
	Personality      *PublicOption     `json:"personality"`
	Religion         *PublicOption     `json:"religion"`
	University       *PublicUniversity `json:"university"`

	ID               string  `json:"id"`
	DisplayName      string  `json:"display_name"`
	Age              int     `json:"age"`
	HeightCM         int     `json:"height_cm"`
	ApproxDistanceKM int     `json:"approx_distance_km"`
	Bio              string  `json:"bio"`
	Ambition         *string `json:"ambition"`
	Occupation       *string `json:"occupation"`
	EducationDegree  *string `json:"education_degree"`
	Revision         int64   `json:"profile_revision"`
	Photos           []Photo `json:"photos"`
}

func (h *Handler) Project(ctx context.Context, viewer string, ids []string) ([]Card, error) {
	return h.project(ctx, viewer, ids, nil)
}

func (h *Handler) project(ctx context.Context, viewer string, ids []string, radius *float64) ([]Card, error) {
	if err := check(ctx, h.DB, viewer); err != nil {
		return nil, err
	}
	out := []Card{}
	if len(ids) == 0 {
		return out, nil
	}
	if len(ids) > 300 {
		return nil, &httpapi.Error{Status: 400, Code: "INVALID_LIMIT"}
	}
	args := []any{viewer, 0, h.Policy.DefaultRadiusKM, h.Policy.MaxRadiusKM, h.Policy.LocationFreshDays, 14, h.Policy.DefaultMinAge, h.Policy.DefaultMaxAge}
	if radius != nil {
		args[1] = *radius
	}
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := h.DB.QueryContext(ctx, `SELECT p.user_id,p.full_name,date_part('year',age(p.birthdate))::int,p.height_cm,public.ST_Distance(l.location,vl.location)/1000,p.bio,p.ambition,NULL::text,NULL::text,p.revision,`+evidenceSnapshotSQL+`,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('id',h.id,'code',h.code,'label',h.label) ORDER BY h.code) FROM profile_hobbies ph JOIN hobbies h ON h.id=ph.hobby_id WHERE ph.user_id=p.user_id),'[]'::jsonb),
 COALESCE((SELECT jsonb_agg(jsonb_build_object('id',lf.id,'code',lf.code,'label',lf.label) ORDER BY lf.code) FROM profile_looking_for pl JOIN looking_for_options lf ON lf.id=pl.looking_for_id WHERE pl.user_id=p.user_id),'[]'::jsonb),
 COALESCE((SELECT jsonb_build_object('id',mb.id,'code',mb.code,'label',mb.label) FROM personality_types mb WHERE mb.id=p.personality_type_id),'null'::jsonb),
 COALESCE((SELECT jsonb_build_object('id',rel.id,'code',rel.code,'label',rel.label) FROM religions rel WHERE rel.id=p.religion_id),'null'::jsonb),
 COALESCE((SELECT jsonb_build_object('id',u.id,'name',u.name,'country_code',u.country_code) FROM universities u WHERE u.id=p.university_id),'null'::jsonb)`+candidateFrom("", radius != nil)+` AND p.user_id IN (`+placeholders(len(ids), 9)+`)`, args...)
	if err != nil {
		return nil, err
	}
	cards := map[string]Card{}
	for rows.Next() {
		var c Card
		var name string
		var distance float64
		var hobbies, lookingFor, personality, religion, university []byte
		if err = rows.Scan(&c.ID, &name, &c.Age, &c.HeightCM, &distance, &c.Bio, &c.Ambition, &c.Occupation, &c.EducationDegree, &c.Revision, &c.EvidenceSnapshot, &hobbies, &lookingFor, &personality, &religion, &university); err != nil {
			rows.Close()
			return nil, err
		}
		for _, value := range []struct {
			raw    []byte
			target any
		}{{hobbies, &c.Hobbies}, {lookingFor, &c.LookingFor}, {personality, &c.Personality}, {religion, &c.Religion}, {university, &c.University}} {
			if err = json.Unmarshal(value.raw, value.target); err != nil {
				rows.Close()
				return nil, err
			}
		}
		words := strings.Fields(name)
		if len(words) > 0 {
			c.DisplayName = words[0]
		}
		c.ApproxDistanceKM = int(math.Round(distance))
		c.Photos = []Photo{}
		cards[c.ID] = c
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if len(cards) == 0 {
		return out, nil
	}
	args = []any{}
	for id := range cards {
		args = append(args, id)
	}
	rows, err = h.DB.QueryContext(ctx, `SELECT id,user_id,position,storage_path FROM photos WHERE status='active' AND user_id IN (`+placeholders(len(args), 1)+`) ORDER BY user_id,position`, args...)
	if err != nil {
		return nil, err
	}
	type item struct {
		photo       Photo
		owner, path string
	}
	items := []item{}
	for rows.Next() {
		var x item
		if err = rows.Scan(&x.photo.ID, &x.owner, &x.photo.Position, &x.path); err != nil {
			rows.Close()
			return nil, err
		}
		items = append(items, x)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	for _, x := range items {
		if h.Store == nil {
			return nil, &httpapi.Error{Status: 503, Code: "STORAGE_UNAVAILABLE"}
		}
		url, e := h.Store.SignRead(ctx, x.path)
		if e != nil {
			return nil, e
		}
		x.photo.ReadURL = url
		c := cards[x.owner]
		c.Photos = append(c.Photos, x.photo)
		cards[x.owner] = c
	}
	for _, id := range ids {
		if c, ok := cards[id]; ok && len(c.Photos) > 0 {
			out = append(out, c)
		}
	}
	return out, nil
}
func unavailable() error { return &httpapi.Error{Status: 404, Code: "NOT_FOUND"} }
func stale() error       { return &httpapi.Error{Status: 409, Code: "STALE_DISCOVERY_CONTEXT"} }
func rowsMissing(err error) error {
	if err == sql.ErrNoRows {
		return unavailable()
	}
	return err
}

func placeholders(n, offset int) string {
	v := make([]string, n)
	for i := range v {
		v[i] = fmt.Sprintf("$%d", i+offset)
	}
	return strings.Join(v, ",")
}

func (h *Handler) ProjectRadius(ctx context.Context, viewer string, ids []string, radiusKM float64) ([]Card, error) {
	if !finite(radiusKM) || radiusKM < 0 {
		return nil, &httpapi.Error{Status: 400, Code: "INVALID_RADIUS"}
	}
	return h.project(ctx, viewer, ids, &radiusKM)
}
