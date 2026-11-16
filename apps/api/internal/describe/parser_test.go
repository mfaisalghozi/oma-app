package describe_test

import (
	"context"
	"encoding/json"
	"errors"
	describe "oma/apps/api/internal/describe"
	"testing"
)

type controlledProvider func(context.Context, string) ([]byte, error)

func (p controlledProvider) Generate(ctx context.Context, prompt string) ([]byte, error) {
	return p(ctx, prompt)
}
func TestParserKeepsUnsupportedEvidenceAndTextSeparateFromStoredAge(t *testing.T) {
	p := describe.Parser{Limits: describe.Limits{MaxAge: 100, MaxDistanceKM: 200}, Provider: controlledProvider(func(ctx context.Context, prompt string) ([]byte, error) {
		var payload map[string]any
		if json.Unmarshal([]byte(prompt), &payload) != nil || payload["query"] != "bio says 25, brown hair from photos" {
			t.Fatal("request missing original query")
		}
		return []byte(`{"version":"v1","rewrite_id":"Bio menyebut 25; rambut cokelat dari foto tidak tersedia.","translation_en":"Bio says 25; brown hair from photos is unavailable.","must":[{"field":"bio","operator":"contains","number":null,"text":"25","evidence":"bio says 25"}],"nice":[],"not_searchable":[{"text":"brown hair from photos","reason":"unavailable_evidence"}]}`), nil
	})}
	got, err := p.Parse(context.Background(), "bio says 25, brown hair from photos")
	if err != nil {
		t.Fatal(err)
	}
	if got.Must[0].Field != "bio" || got.Must[0].Number != nil || got.NotSearchable[0].Reason != "unavailable_evidence" {
		t.Fatalf("unexpected %+v", got)
	}
}
func TestParserReturnsSafeProviderError(t *testing.T) {
	p := describe.Parser{Limits: describe.Limits{MaxAge: 100, MaxDistanceKM: 200}, Provider: controlledProvider(func(context.Context, string) ([]byte, error) { return nil, errors.New("secret-provider-response") })}
	_, err := p.Parse(context.Background(), "hiking")
	if !errors.Is(err, describe.ErrProvider) {
		t.Fatalf("unexpected %v", err)
	}
}
func TestInvalidQueryAndPolicyNeverReachProvider(t *testing.T) {
	for _, tc := range []struct {
		query  string
		limits describe.Limits
	}{{"", describe.Limits{MaxAge: 100, MaxDistanceKM: 200}}, {"hiking", describe.Limits{MaxAge: 17, MaxDistanceKM: 200}}} {
		p := describe.Parser{Limits: tc.limits, Provider: controlledProvider(func(context.Context, string) ([]byte, error) {
			t.Fatal("invalid query/policy reached paid provider")
			return nil, nil
		})}
		if _, err := p.Parse(context.Background(), tc.query); err != describe.ErrInvalidCriteria {
			t.Fatalf("unexpected %v", err)
		}
	}
}
