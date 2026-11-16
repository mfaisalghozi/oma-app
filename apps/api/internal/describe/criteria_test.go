package describe_test

import (
	describe "oma/apps/api/internal/describe"
	"strings"
	"testing"
)

func TestDecodePreservesQueryAndResolvesCatalog(t *testing.T) {
	query := "Harus perempuan, minimal 180 cm; suka hiking lebih baik"
	raw := []byte(`{"version":"v1","rewrite_id":"Harus perempuan dengan tinggi minimal 180 cm; lebih disukai suka mendaki.","translation_en":"Must be a woman at least 180 cm tall; hiking preferred.","must":[{"field":"gender","operator":"eq","number":null,"text":"perempuan","evidence":"perempuan"},{"field":"height_cm","operator":"gte","number":180,"text":"","evidence":"minimal 180 cm"}],"nice":[{"field":"hobby","operator":"contains","number":null,"text":"hiking","evidence":"suka hiking"}],"not_searchable":[]}`)
	got, err := describe.Decode(query, raw, []describe.CatalogEntry{{Field: "gender", ID: "woman-id", Label: "Woman", Aliases: []string{"perempuan"}}, {Field: "hobby", ID: "hiking-id", Label: "Mendaki", Aliases: []string{"hiking"}}}, describe.Limits{MaxAge: 120, MaxDistanceKM: 200})
	if err != nil {
		t.Fatal(err)
	}
	if got.OriginalQuery != query || got.Must[0].CatalogID != "woman-id" || got.Must[1].Number == nil || *got.Must[1].Number != 180 || got.Nice[0].CatalogID != "hiking-id" {
		t.Fatalf("unexpected parse: %+v", got)
	}
}

func TestDecodeRejectsUnsafeOrMalformedCriteria(t *testing.T) {
	base := `{"version":"v1","rewrite_id":"Usia minimal 25","translation_en":"Age at least 25","must":[{"field":"age","operator":"gte","number":25,"text":"","evidence":"25"}],"nice":[],"not_searchable":[]}`
	for name, raw := range map[string]string{
		"duplicate":         strings.Replace(base, `"version":"v1"`, `"version":"v2","version":"v1"`, 1),
		"omitted value":     strings.Replace(base, `"text":"",`, "", 1),
		"minor":             strings.Replace(base, `"number":25`, `"number":17`, 1),
		"sql field":         strings.Replace(base, `"field":"age"`, `"field":"DROP TABLE profiles"`, 1),
		"unknown property":  strings.Replace(base, `"version":"v1"`, `"sql":"SELECT 1","version":"v1"`, 1),
		"null arrays":       strings.Replace(base, `"nice":[]`, `"nice":null`, 1),
		"invented evidence": strings.Replace(base, `"evidence":"25"`, `"evidence":"180 cm"`, 1),
		"invalid operator":  strings.Replace(base, `"operator":"gte"`, `"operator":"regex"`, 1),
		"trailing object":   base + `{}`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := describe.Decode("Usia 25", []byte(raw), nil, describe.Limits{MaxAge: 100, MaxDistanceKM: 200}); err == nil {
				t.Fatal("unsafe criteria accepted")
			}
		})
	}
}

func TestDecodeRejectsUnknownCatalogAndInvalidNumericBounds(t *testing.T) {
	const head = `{"version":"v1","rewrite_id":"Cari orang","translation_en":"Find someone","must":[`
	const tail = `],"nice":[],"not_searchable":[]}`
	cases := map[string]string{
		"unknown catalog":     `{"field":"hobby","operator":"contains","number":null,"text":"invented-id","evidence":"hiking"}`,
		"catalog wrong field": `{"field":"gender","operator":"eq","number":null,"text":"hiking","evidence":"hiking"}`,
		"fractional age":      `{"field":"age","operator":"gte","number":25.5,"text":"","evidence":"25"}`,
		"height bounds":       `{"field":"height_cm","operator":"gte","number":251,"text":"","evidence":"251"}`,
		"distance bounds":     `{"field":"distance_km","operator":"lte","number":201,"text":"","evidence":"201"}`,
		"negative distance":   `{"field":"distance_km","operator":"lte","number":-1,"text":"","evidence":"1"}`,
		"contradictory ages":  `{"field":"age","operator":"gte","number":30,"text":"","evidence":"30"},{"field":"age","operator":"lte","number":25,"text":"","evidence":"25"}`,
		"mixed numeric/text":  `{"field":"age","operator":"gte","number":25,"text":"25","evidence":"25"}`,
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := describe.Decode("hiking 25 30 251 201", []byte(head+c+tail), []describe.CatalogEntry{{Field: "hobby", ID: "hiking-id", Label: "hiking"}}, describe.Limits{MaxAge: 100, MaxDistanceKM: 200})
			if err == nil {
				t.Fatal("unsafe criterion accepted")
			}
		})
	}
}
func TestResolveAliasRejectsAmbiguousLabels(t *testing.T) {
	_, ok := describe.ResolveAlias([]describe.CatalogEntry{{Field: "hobby", ID: "a", Label: "Jalan", Aliases: []string{"walking"}}, {Field: "hobby", ID: "b", Label: "Walking"}}, "hobby", " walking ")
	if ok {
		t.Fatal("ambiguous catalog alias accepted")
	}
}
func TestUnsupportedLogicIsPreserved(t *testing.T) {
	raw := []byte(`{"version":"v1","rewrite_id":"Muslim atau Kristen","translation_en":"Muslim or Christian","must":[],"nice":[],"not_searchable":[{"text":"Muslim atau Kristen","reason":"unsupported_logic"}]}`)
	got, err := describe.Decode("Muslim atau Kristen", raw, nil, describe.Limits{MaxAge: 100, MaxDistanceKM: 200})
	if err != nil || len(got.Must) != 0 || got.NotSearchable[0].Reason != "unsupported_logic" {
		t.Fatalf("unsupported logic lost: %+v %v", got, err)
	}
}
