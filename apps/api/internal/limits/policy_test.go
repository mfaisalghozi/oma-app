package limits_test

import (
	"oma/apps/api/internal/limits"
	"testing"
	"time"
)

func TestWIBResetAndFixedGrants(t *testing.T) {
	before := time.Date(2026, 11, 16, 16, 59, 59, 0, time.UTC)
	day, reset := limits.Bucket(before)
	if day != "2026-11-16" || !reset.Equal(time.Date(2026, 11, 16, 17, 0, 0, 0, time.UTC)) {
		t.Fatalf("bucket %s reset %v", day, reset)
	}
	day, _ = limits.Bucket(reset)
	if day != "2026-11-17" {
		t.Fatal(day)
	}
	for _, tc := range []struct {
		full, pro       bool
		likes, searches int
	}{{false, false, 15, 3}, {true, false, 30, 3}, {false, true, 15, 20}, {true, true, 30, 20}} {
		g := limits.Grants(tc.full, tc.pro)
		if g.Likes != tc.likes || g.Searches != tc.searches {
			t.Fatalf("grants %+v", g)
		}
	}
}

func TestDevelopmentPRORequiresTrustedEnvironmentAndUUIDs(t *testing.T) {
	id := "11111111-1111-4111-8111-111111111111"
	for _, env := range []string{"", "prod", "production", "staging", "unknown"} {
		if _, err := limits.NewService(limits.Config{Environment: env, DevelopmentPROUserIDs: []string{id}}); err == nil {
			t.Fatalf("accepted PRO in %q", env)
		}
	}
	if _, err := limits.NewService(limits.Config{Environment: "development", DevelopmentPROUserIDs: []string{"*"}}); err == nil {
		t.Fatal("accepted wildcard")
	}
	if _, err := limits.NewService(limits.Config{Environment: "development", DevelopmentPROUserIDs: []string{id}}); err != nil {
		t.Fatal(err)
	}
}
