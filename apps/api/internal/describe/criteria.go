package describe

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"math"
	"strings"
	"unicode/utf8"
)

var ErrInvalidCriteria = errors.New("invalid describe criteria")

type CatalogEntry struct {
	Field   string   `json:"field"`
	ID      string   `json:"id"`
	Label   string   `json:"label"`
	Aliases []string `json:"aliases"`
}
type Limits struct {
	MaxAge        int
	MaxDistanceKM float64
}
type Criterion struct {
	Field     string   `json:"field"`
	Operator  string   `json:"operator"`
	Number    *float64 `json:"number"`
	Text      string   `json:"text"`
	Evidence  string   `json:"evidence"`
	CatalogID string   `json:"catalog_id,omitempty"`
}
type Unsupported struct {
	Text   string `json:"text"`
	Reason string `json:"reason"`
}
type Criteria struct {
	Version       string        `json:"version"`
	OriginalQuery string        `json:"original_query"`
	RewriteID     string        `json:"rewrite_id"`
	TranslationEN string        `json:"translation_en"`
	Must          []Criterion   `json:"must"`
	Nice          []Criterion   `json:"nice"`
	NotSearchable []Unsupported `json:"not_searchable"`
}

func Decode(query string, raw []byte, catalog []CatalogEntry, limits Limits) (Criteria, error) {
	fail := func() (Criteria, error) { return Criteria{}, ErrInvalidCriteria }
	if !validText(query, 500) || !utf8.ValidString(query) || !limits.valid() || len(raw) > 65536 {
		return fail()
	}
	if strictShape(raw) != nil {
		return fail()
	}
	var out Criteria
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&out); err != nil {
		return fail()
	}
	if dec.Decode(new(any)) != io.EOF {
		return fail()
	}
	if out.Version != "v1" || out.OriginalQuery != "" || !validText(out.RewriteID, 2000) || !validText(out.TranslationEN, 2000) || out.Must == nil || out.Nice == nil || out.NotSearchable == nil || len(out.Must)+len(out.Nice)+len(out.NotSearchable) > 24 {
		return fail()
	}
	out.OriginalQuery = query
	for _, list := range [][]Criterion{out.Must, out.Nice} {
		bounds := map[string][2]float64{}
		for i := range list {
			c := &list[i]
			if !validText(c.Evidence, 500) || !strings.Contains(strings.ToLower(query), strings.ToLower(c.Evidence)) || c.CatalogID != "" {
				return fail()
			}
			switch c.Field {
			case "age", "height_cm", "distance_km":
				if c.Number == nil || c.Text != "" || (c.Operator != "gte" && c.Operator != "lte" && c.Operator != "eq") {
					return fail()
				}
				min, max := float64(18), float64(limits.MaxAge)
				if c.Field == "height_cm" {
					min, max = 100, 250
				}
				if c.Field == "distance_km" {
					min, max = 0, limits.MaxDistanceKM
				}
				n := *c.Number
				if math.IsNaN(n) || math.IsInf(n, 0) || n < min || n > max || (c.Field != "distance_km" && n != math.Trunc(n)) {
					return fail()
				}
				b, exists := bounds[c.Field]
				if !exists {
					b = [2]float64{min, max}
				}
				if c.Operator == "gte" || c.Operator == "eq" {
					b[0] = math.Max(b[0], n)
				}
				if c.Operator == "lte" || c.Operator == "eq" {
					b[1] = math.Min(b[1], n)
				}
				if b[0] > b[1] {
					return fail()
				}
				bounds[c.Field] = b
			case "gender", "religion", "university", "personality", "hobby", "looking_for":
				op := "eq"
				if c.Field == "hobby" || c.Field == "looking_for" {
					op = "contains"
				}
				if c.Number != nil || c.Operator != op || !validText(c.Text, 200) {
					return fail()
				}
				id, ok := ResolveAlias(catalog, c.Field, c.Text)
				if !ok {
					return fail()
				}
				c.CatalogID = id
				c.Text = ""
			case "bio", "ambition":
				if c.Number != nil || c.Operator != "contains" || !validText(c.Text, 100) {
					return fail()
				}
			default:
				return fail()
			}
		}
	}
	for _, n := range out.NotSearchable {
		if !validText(n.Text, 500) || !strings.Contains(strings.ToLower(query), strings.ToLower(n.Text)) {
			return fail()
		}
		switch n.Reason {
		case "unsupported_field", "unsupported_logic", "unavailable_evidence", "unknown_catalog", "unsafe_age", "contradictory":
		default:
			return fail()
		}
	}
	return out, nil
}
func ResolveAlias(entries []CatalogEntry, field, text string) (string, bool) {
	token := strings.ToLower(strings.TrimSpace(text))
	id := ""
	for _, e := range entries {
		if e.Field != field || e.ID == "" {
			continue
		}
		names := append([]string{e.ID, e.Label}, e.Aliases...)
		for _, name := range names {
			if token == strings.ToLower(strings.TrimSpace(name)) {
				if id != "" && id != e.ID {
					return "", false
				}
				id = e.ID
			}
		}
	}
	return id, id != ""
}
func validText(s string, max int) bool {
	return strings.TrimSpace(s) != "" && utf8.ValidString(s) && utf8.RuneCountInString(s) <= max
}

func (l Limits) valid() bool {
	return l.MaxAge >= 18 && l.MaxDistanceKM > 0 && !math.IsNaN(l.MaxDistanceKM) && !math.IsInf(l.MaxDistanceKM, 0)
}
