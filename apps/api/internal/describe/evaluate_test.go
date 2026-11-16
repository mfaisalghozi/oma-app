package describe_test

import (
	"math"
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/discovery"
	"testing"
)

func num(v float64) *float64 { return &v }
func TestEvaluateNumericCloseDoesNotClaimExactEvidence(t *testing.T) {
	c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: num(180)}}, Nice: []describe.Criterion{{Field: "bio", Operator: "contains", Text: "hiking"}}, NotSearchable: []describe.Unsupported{{Text: "kind eyes"}}}
	got, err := describe.Evaluate(c, describe.Evidence{HeightCM: 178, Bio: "I love hiking", DistanceKM: 5, Quality: 0.5}, 100)
	if err != nil || got.Tier != "close" || got.Matched != 1 || got.Total != 2 || len(got.Violations) != 1 || got.Violations[0].Deviation != 2 {
		t.Fatalf("unexpected evaluation: %+v %v", got, err)
	}
}

func TestEvaluateUnknownAndUnrelaxableEvidence(t *testing.T) {
	for _, must := range []describe.Criterion{
		{Field: "religion", Operator: "eq", CatalogID: "religion"},
		{Field: "bio", Operator: "contains", Text: "kind"},
		{Field: "age", Operator: "gte", Number: num(18)},
		{Field: "height_cm", Operator: "gte", Number: num(180)},
		{Field: "distance_km", Operator: "lte", Number: num(10)},
	} {
		got, err := describe.Evaluate(describe.Criteria{Must: []describe.Criterion{must}}, describe.Evidence{Age: 17, HeightCM: 177, DistanceKM: 12, Quality: 0.5}, 100)
		if err != nil || got.Tier != "excluded" || got.Matched != 0 {
			t.Fatalf("%s: %+v %v", must.Field, got, err)
		}
	}
}
func TestEvaluateRejectsAllUnsupported(t *testing.T) {
	_, err := describe.Evaluate(describe.Criteria{NotSearchable: []describe.Unsupported{{Text: "kind eyes"}}}, describe.Evidence{}, 100)
	if err != describe.ErrNoSearchableCriteria {
		t.Fatalf("got %v", err)
	}
}
func TestEvaluateNiceOnlyRelevanceAndUnknownDenominator(t *testing.T) {
	got, err := describe.Evaluate(describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: num(180)}}, Nice: []describe.Criterion{{Field: "bio", Operator: "contains", Text: "hiking"}, {Field: "religion", Operator: "eq", CatalogID: "missing"}}}, describe.Evidence{HeightCM: 180, Bio: "hiking", DistanceKM: 0, Quality: 1, ReplyRate: num(1)}, 100)
	if err != nil || got.Matched != 2 || got.Total != 3 || math.Abs(got.Score-0.7) > 1e-9 {
		t.Fatalf("got %+v %v", got, err)
	}
}

func TestEvaluateNeverLabelsBeyondGlobalRadiusExact(t *testing.T) {
	got, err := describe.Evaluate(describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: num(180)}}}, describe.Evidence{Age: 30, HeightCM: 180, DistanceKM: 101, Quality: .5}, 100)
	if err != nil || got.Tier != "excluded" {
		t.Fatalf("beyond maximum: %+v %v", got, err)
	}
}

func TestEvaluateNumericToleranceBoundaries(t *testing.T) {
	for _, tc := range []struct {
		field       string
		want, value float64
		tier        string
	}{
		{"height_cm", 180, 178, "close"}, {"height_cm", 180, 177, "excluded"},
		{"age", 30, 28, "close"}, {"age", 30, 27, "excluded"},
		{"distance_km", 50, 55, "close"}, {"distance_km", 50, 55.01, "excluded"},
		{"distance_km", 100, 104, "excluded"},
	} {
		e := describe.Evidence{Age: 30, HeightCM: 180, Quality: .5}
		if tc.field == "height_cm" {
			e.HeightCM = int(tc.value)
		} else if tc.field == "age" {
			e.Age = int(tc.value)
		} else {
			e.DistanceKM = tc.value
		}
		op := "gte"
		if tc.field == "distance_km" {
			op = "lte"
		}
		got, err := describe.Evaluate(describe.Criteria{Must: []describe.Criterion{{Field: tc.field, Operator: op, Number: num(tc.want)}}}, e, 100)
		if err != nil || got.Tier != tc.tier {
			t.Fatalf("%s=%v: %+v %v", tc.field, tc.value, got, err)
		}
	}
}

func TestEvaluateUsesSpecifiedDistanceFactor(t *testing.T) {
	c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: num(180)}}}
	got, err := describe.Evaluate(c, describe.Evidence{HeightCM: 180, Quality: .2, ReplyRate: num(1), DistanceKM: 50}, 100)
	// Relevance 1, quality .2 and half-radius distance factor .75: .6+.05+.1125.
	if err != nil || math.Abs(got.Score-.7625) > 1e-9 {
		t.Fatalf("worked distance score: %+v %v", got, err)
	}
}

func TestEvaluateUsesReplyAndRecencyQualityFactors(t *testing.T) {
	c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: num(180)}}}
	got, err := describe.Evaluate(c, describe.Evidence{HeightCM: 180, Quality: .8, ReplyRate: num(.5), IdleDays: 5}, 100, discovery.RankingPolicy{ReplyFloor: .4, RecencyHalfLifeDays: 5})
	// Quality .8*.7*.5=.28; relevance 1 and distance 0 give .6+.07+.15.
	if err != nil || math.Abs(got.Score-.82) > 1e-9 {
		t.Fatalf("worked reply/recency score: %+v %v", got, err)
	}
}
