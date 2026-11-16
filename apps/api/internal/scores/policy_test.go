package scores_test

import (
	"oma/apps/api/internal/scores"
	"testing"
	"time"
)

func TestActorWeightRulesAndHalfLife(t *testing.T) {
	now := time.Date(2026, 11, 16, 17, 0, 0, 0, time.UTC)
	verified := now.Add(-10 * 24 * time.Hour)
	for _, tt := range []struct {
		status          string
		age             int
		verified        *time.Time
		positive, total int
		want            float64
	}{
		{"active", 10, &verified, 80, 100, 1}, {"active", 10, &verified, 81, 100, .25},
		{"active", 2, &verified, 0, 100, 0}, {"active", 10, nil, 0, 100, 0}, {"suspended", 10, &verified, 0, 100, 0},
	} {
		got := scores.ActorWeight(tt.status, now.Add(-time.Duration(tt.age)*24*time.Hour), tt.verified, tt.positive, tt.total, now)
		if got != tt.want {
			t.Fatalf("%+v: got %v", tt, got)
		}
	}
	if got := scores.Decay(now.Add(-30*24*time.Hour), now); got != .5 {
		t.Fatalf("30 day decay %v", got)
	}
	if got := scores.Decay(now.Add(-121*24*time.Hour), now); got != 0 {
		t.Fatalf("120 day cutoff %v", got)
	}
}
