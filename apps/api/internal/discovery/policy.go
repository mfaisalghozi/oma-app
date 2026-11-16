package discovery

import (
	"database/sql"
	"errors"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/storage"
	"time"
)

type Policy struct {
	DefaultMinAge          int           `json:"default_min_age"`
	DefaultMaxAge          int           `json:"default_max_age"`
	Version                string        `json:"version"`
	DeckVersion            string        `json:"deck_version"`
	Ranking                RankingPolicy `json:"ranking"`
	DefaultRadiusKM        float64       `json:"default_radius_km"`
	MaxRadiusKM            float64       `json:"max_radius_km"`
	LocationFreshDays      int           `json:"location_fresh_days"`
	MaterialMovementMeters float64       `json:"material_movement_meters"`
	ShownDailyCap          int           `json:"shown_daily_cap"`
	PriorityCap            int           `json:"priority_cap"`
	FreshCap               int           `json:"fresh_cap"`
	FreshSlots             int           `json:"fresh_slots"`
	FreeTopHalf            int           `json:"free_top_half"`
	ProTopHalf             int           `json:"pro_top_half"`
	DistanceBandPercent    [4]int        `json:"distance_band_percent"`
	PriorityTTLDays        int           `json:"priority_ttl_days"`
	PriorityCapBypass      bool          `json:"priority_cap_bypass"`
}

func (p Policy) Validate() error {
	if err := p.candidatePolicy().Validate(); err != nil {
		return err
	}
	if p.Version == "" || p.DeckVersion == "" || p.Ranking.Version == "" || p.ShownDailyCap < 1 || p.PriorityCap != 1 || p.FreshSlots < 0 || p.FreshSlots > 20 || p.FreshCap < p.FreshSlots || p.FreshCap > 299 || p.FreeTopHalf < 0 || p.FreeTopHalf > 20 || p.ProTopHalf < 0 || p.ProTopHalf > 20 || p.PriorityTTLDays < 1 || !finite(p.MaterialMovementMeters) || p.MaterialMovementMeters <= 0 {
		return errors.New("invalid discovery policy")
	}
	if !finite(p.Ranking.LikeHalfLifeDays) || p.Ranking.LikeHalfLifeDays <= 0 || !finite(p.Ranking.MinSegmentDecisions) || p.Ranking.MinSegmentDecisions <= 0 {
		return errors.New("invalid ranking support or decay policy")
	}
	n := 0
	for _, v := range p.DistanceBandPercent {
		if v < 0 {
			return errors.New("negative distance quota")
		}
		n += v
	}
	if n != 100 {
		return errors.New("distance quotas must total100")
	}
	if _, e := Posterior(0, 0, p.Ranking.FallbackMean, p.Ranking); e != nil {
		return e
	}
	_, e := QualityScore(.5, .5, 0, 0, p.DefaultRadiusKM, p.Ranking)
	return e
}
func (p Policy) candidatePolicy() CandidatePolicy {
	return CandidatePolicy{p.DefaultRadiusKM, p.MaxRadiusKM, p.DefaultMinAge, p.DefaultMaxAge, p.LocationFreshDays, 14}
}

type Handler struct {
	Limits          *limits.Service
	DescribeContext ActionContextValidator
	DB              *sql.DB
	Store           storage.Store
	Policy          Policy
	Now             func() time.Time
	IsPro           func(viewerID string) bool
}

func (h *Handler) now() time.Time {
	if h.Now != nil {
		return h.Now().UTC()
	}
	return time.Now().UTC()
}
