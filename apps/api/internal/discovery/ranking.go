package discovery

import (
	"errors"
	"math"
)

type RankingPolicy struct {
	Version             string  `json:"version"`
	PriorStrength       float64 `json:"prior_strength"`
	FallbackMean        float64 `json:"fallback_mean"`
	ReplyFloor          float64 `json:"reply_floor"`
	RecencyHalfLifeDays float64 `json:"recency_half_life_days"`
	LikeHalfLifeDays    float64 `json:"like_half_life_days"`
	MinSegmentDecisions float64 `json:"min_segment_decisions"`
}
type BetaPosterior struct{ Alpha, Beta float64 }

func (p BetaPosterior) Mean() float64 { return p.Alpha / (p.Alpha + p.Beta) }
func finite(v float64) bool           { return !math.IsNaN(v) && !math.IsInf(v, 0) }
func Posterior(likes, passes, mean float64, p RankingPolicy) (BetaPosterior, error) {
	if !finite(likes) || !finite(passes) || !finite(mean) || !finite(p.PriorStrength) || likes < 0 || passes < 0 || mean <= 0 || mean >= 1 || p.PriorStrength <= 0 {
		return BetaPosterior{}, errors.New("invalid like-rate inputs")
	}
	return BetaPosterior{likes + p.PriorStrength*mean, passes + p.PriorStrength*(1-mean)}, nil
}
func QualityScore(theta, reply, idleDays, distanceKM, radiusKM float64, p RankingPolicy) (float64, error) {
	for _, v := range []float64{theta, reply, idleDays, distanceKM, radiusKM, p.ReplyFloor, p.RecencyHalfLifeDays} {
		if !finite(v) {
			return 0, errors.New("non-finite ranking input")
		}
	}
	if theta < 0 || theta > 1 || reply < 0 || reply > 1 || idleDays < 0 || distanceKM < 0 || radiusKM <= 0 || distanceKM > radiusKM || p.RecencyHalfLifeDays <= 0 || p.ReplyFloor < 0 || p.ReplyFloor > 1 {
		return 0, errors.New("invalid ranking input")
	}
	return theta * (p.ReplyFloor + (1-p.ReplyFloor)*reply) * math.Exp2(-idleDays/p.RecencyHalfLifeDays) * (1 - 0.5*distanceKM/radiusKM), nil
}
