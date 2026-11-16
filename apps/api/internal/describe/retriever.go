package describe

import (
	"context"
	"fmt"
	"math"
	"oma/apps/api/internal/discovery"
	"time"
)

type Result struct {
	Profile discovery.Card `json:"profile"`
	Evaluation
}
type Retrieval struct {
	Criteria          Criteria      `json:"criteria"`
	RequestedRadiusKM float64       `json:"requested_radius_km"`
	EffectiveRadiusKM float64       `json:"effective_radius_km"`
	Results           []Result      `json:"results"`
	NotSearchable     []Unsupported `json:"not_searchable"`
}
type Retriever struct {
	Query    discovery.CandidateQuery
	Profiles *discovery.Handler
}

func (r *Retriever) Retrieve(ctx context.Context, viewer string, c Criteria) (Retrieval, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out := Retrieval{Criteria: c, Results: []Result{}, NotSearchable: append([]Unsupported{}, c.NotSearchable...)}
	if len(c.Must)+len(c.Nice) == 0 {
		return out, ErrNoSearchableCriteria
	}
	if r.Profiles == nil || r.Query.DB == nil || r.Profiles.DB != r.Query.DB {
		return out, fmt.Errorf("invalid retrieval configuration")
	}
	convert := func(list []Criterion) []discovery.CandidateClause {
		v := make([]discovery.CandidateClause, len(list))
		for i, c := range list {
			v[i] = discovery.CandidateClause{Field: c.Field, Operator: c.Operator, Number: c.Number, Text: c.Text, CatalogID: c.CatalogID}
		}
		return v
	}
	radius := r.Query.Policy.DefaultRadiusKM
	hasDistanceBound := false
	for _, criterion := range c.Must {
		if criterion.Field != "distance_km" || criterion.Number == nil || (criterion.Operator != "lte" && criterion.Operator != "eq") {
			continue
		}
		if !hasDistanceBound {
			radius = *criterion.Number
		} else {
			radius = math.Min(radius, *criterion.Number)
		}
		hasDistanceBound = true
	}
	out.RequestedRadiusKM = math.Min(radius, r.Query.Policy.MaxRadiusKM)
	if hasDistanceBound {
		radius += discovery.DescribeNumericTolerance("distance_km", radius)
	}
	radius = math.Min(radius, r.Query.Policy.MaxRadiusKM)
	out.EffectiveRadiusKM = radius
	now := time.Now()
	if r.Profiles.Now != nil {
		now = r.Profiles.Now()
	}
	candidates, err := r.Query.Filtered(ctx, viewer, radius, convert(c.Must), convert(c.Nice), discovery.FilteredPolicy{Ranking: r.Profiles.Policy.Ranking, ShownDailyCap: r.Profiles.Policy.ShownDailyCap, Now: now})
	if err != nil {
		return out, err
	}
	ids := make([]string, len(candidates))
	for i, candidate := range candidates {
		ids[i] = candidate.ID
	}
	cards, err := r.Profiles.ProjectRadius(ctx, viewer, ids, radius)
	if err != nil {
		return out, err
	}
	projected := map[string]discovery.Card{}
	for _, card := range cards {
		projected[card.ID] = card
	}
	for _, candidate := range candidates {
		card, ok := projected[candidate.ID]
		if !ok || card.EvidenceSnapshot != candidate.Snapshot {
			continue
		}
		evaluation, e := Evaluate(c, Evidence{ID: candidate.ID, Age: candidate.Age, HeightCM: candidate.HeightCM, DistanceKM: candidate.DistanceKM, Quality: candidate.Quality, ReplyRate: &candidate.ReplyRate, IdleDays: candidate.IdleDays, Bio: candidate.Bio, Ambition: candidate.Ambition, Catalog: candidate.Catalog}, radius, r.Profiles.Policy.Ranking)
		if e != nil {
			return out, e
		}
		if evaluation.Tier == "excluded" {
			continue
		}
		out.Results = append(out.Results, Result{Profile: card, Evaluation: evaluation})
	}
	return out, nil
}
