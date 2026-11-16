package jobs_test

import (
	"oma/apps/api/internal/jobs"
	"testing"
	"time"
)

func TestNightlyAtMidnightWIB(t *testing.T) {
	before := time.Date(2026, 11, 16, 16, 59, 59, 0, time.UTC)
	if got := jobs.NextNightly(before); !got.Equal(before.Add(time.Second)) {
		t.Fatalf("reset %v", got)
	}
	if got := jobs.NextNightly(before.Add(time.Second)); !got.Equal(before.Add(time.Second + 24*time.Hour)) {
		t.Fatalf("next reset %v", got)
	}
}
