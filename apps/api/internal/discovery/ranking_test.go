package discovery_test

import (
	"math"
	"oma/apps/api/internal/discovery"
	"testing"
)

func TestColdStartAndReplyQualityRanking(t *testing.T) {
	policy := discovery.RankingPolicy{Version: "v1", PriorStrength: 10, FallbackMean: 0.3, ReplyFloor: 0.4, RecencyHalfLifeDays: 5, LikeHalfLifeDays: 30, MinSegmentDecisions: 200}
	p, err := discovery.Posterior(0, 0, 0.3, policy)
	if err != nil || math.Abs(p.Mean()-0.3) > 1e-9 {
		t.Fatalf("cold start: %#v %v", p, err)
	}
	score, err := discovery.QualityScore(0.3, 0.75, 0, 4, 10, policy)
	if err != nil || math.Abs(score-0.204) > 1e-9 {
		t.Fatalf("worked score: %f %v", score, err)
	}
	if _, err = discovery.QualityScore(0.3, 0.75, 0, 11, 10, policy); err == nil {
		t.Fatal("outside radius accepted")
	}
}
