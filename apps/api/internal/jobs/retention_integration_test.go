//go:build integration

package jobs_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/jobs"
	"oma/apps/api/internal/scores"
)

func TestReconcilePrunesMetadataDespiteHookAndQueueFailure(t *testing.T) {
	db := workerDB(t)
	ctx := context.Background()
	now := time.Now().UTC()
	actor := "00000000-0000-0000-0000-000000000001"
	candidate := "00000000-0000-0000-0000-000000000002"
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := db.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO accounts(user_id) VALUES($1),($2)`, actor, candidate)
	exec(`WITH action AS (INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) VALUES($1,$2,'like','regular_deck',gen_random_uuid(),$3) RETURNING id) INSERT INTO swipe_events(action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT id,$1,$2,'like','male:female',$3 FROM action`, actor, candidate, now)
	exec(`INSERT INTO swipe_requests(actor_id,idempotency_key,payload_hash,action_id,expires_at) SELECT $1,repeat(key,64),'hash',id,expires FROM profile_interactions CROSS JOIN (VALUES('a',$2::timestamptz),('b',$3::timestamptz)) AS keys(key,expires)`, actor, now.Add(-time.Hour), now.Add(time.Hour))
	exec(`INSERT INTO deck_cache(viewer_id,generation,exposure_bucket_date,preference_revision,location_version,location,policy_version,ranking_version,created_at,expires_at,status) SELECT $1,g,CURRENT_DATE,1,1,ST_GeogFromText('SRID=4326;POINT(106 -6)'),'v1','v1',created,expires,'expired' FROM (VALUES(1,$2::timestamptz,$3::timestamptz),(2,$3::timestamptz,$4::timestamptz)) AS caches(g,created,expires)`, actor, now.Add(-8*24*time.Hour), now.Add(-time.Hour), now.Add(time.Hour))
	exec(`INSERT INTO deck_cache_cards(batch_id,candidate_id,position,selection_bucket) SELECT id,$1,1,'fresh' FROM deck_cache`, candidate)
	exec(`INSERT INTO deck_cursors(batch_id,position) SELECT id,1 FROM deck_cache`)
	exec(`INSERT INTO discovery_exposures(viewer_id,candidate_id,bucket_date,delivered_at) VALUES($1,$2,CURRENT_DATE,$3)`, actor, candidate, now)
	exec(`INSERT INTO daily_limit_operations(owner_id,meter,operation_id,bucket,units,payload_hash,state) SELECT actor_id,'likes',id,CURRENT_DATE,1,'hash','settled' FROM profile_interactions`)
	projector, err := scores.New(db, discovery.RankingPolicy{Version: "retention-v1", PriorStrength: 10, FallbackMean: .3, LikeHalfLifeDays: 30, MinSegmentDecisions: 200})
	if err != nil {
		t.Fatal(err)
	}
	hookErr := errors.New("hook unavailable")
	called := false
	runtime, err := jobs.New(db, projector, jobs.Options{Reconcile: func(context.Context) error { called = true; return hookErr }})
	if err != nil {
		t.Fatal(err)
	}
	err = runtime.Reconcile(ctx)
	if !called {
		t.Fatal("queue failure prevented reconciliation hook")
	}
	if !errors.Is(err, hookErr) || !strings.Contains(err.Error(), "river_job") {
		t.Fatalf("want hook and missing queue errors, got %v", err)
	}
	for table, want := range map[string]int{"swipe_requests": 1, "deck_cache": 1, "deck_cache_cards": 1, "deck_cursors": 1, "profile_interactions": 1, "swipe_events": 1, "discovery_exposures": 1, "daily_limit_operations": 1} {
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM ` + table).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Errorf("%s count=%d, want %d", table, n, want)
		}
	}
	var key string
	if err := db.QueryRow(`SELECT idempotency_key FROM swipe_requests`).Scan(&key); err != nil || key != strings.Repeat("b", 64) {
		t.Fatalf("valid replay binding lost: %q %v", key, err)
	}
	var generation int
	if err := db.QueryRow(`SELECT generation FROM deck_cache`).Scan(&generation); err != nil || generation != 2 {
		t.Fatalf("valid cache lost: %d %v", generation, err)
	}
}
