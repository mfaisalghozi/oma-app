//go:build integration

package api_test

import (
	"context"
	"oma/apps/api/internal/discovery"
	"testing"
	"time"
)

func TestPruneCachesRetentionAndOwnedChildren(t *testing.T) {
	db, _ := deckSetup(t)
	now := time.Now().UTC().Truncate(time.Microsecond)
	old := now.Add(-8 * 24 * time.Hour)
	add := func(g int, created, expires time.Time, status string) string {
		t.Helper()
		var id string
		if err := db.QueryRow(`INSERT INTO deck_cache(viewer_id,generation,location_version,preference_revision,location,policy_version,ranking_version,expires_at,exposure_bucket_date,created_at,status) SELECT $1,$2,1,1,location,'v1','v1',$3,$4,$5,$6 FROM user_locations WHERE user_id=$1 RETURNING id`, alice, g, expires, now, created, status).Scan(&id); err != nil {
			t.Fatal(err)
		}
		for _, q := range []string{`INSERT INTO deck_cache_cards(batch_id,candidate_id,position,selection_bucket) VALUES($1,'` + bob + `',1,'fresh')`, `INSERT INTO deck_cursors(batch_id,position) VALUES($1,1)`} {
			if _, err := db.Exec(q, id); err != nil {
				t.Fatal(err)
			}
		}
		return id
	}
	removed := add(1, old, old.Add(30*time.Minute), "expired")
	staleActive := add(6, old, old.Add(30*time.Minute), "active")
	kept := []string{add(2, now.Add(-time.Hour), now.Add(-30*time.Minute), "expired"), add(3, old, now.Add(time.Hour), "expired"), add(4, old, now.Add(time.Hour), "expired"), add(5, now.Add(-7*24*time.Hour), now.Add(-time.Hour), "expired")}
	if _, err := db.Exec(`INSERT INTO discovery_exposures(viewer_id,candidate_id,bucket_date,delivered_at) VALUES($1,$2,$3::timestamptz::date,$3::timestamptz)`, alice, bob, old); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO candidate_daily_exposures(candidate_id,bucket_date,shown_today) VALUES($1,$2,1)`, bob, old); err != nil {
		t.Fatal(err)
	}
	prune := func(want int64) {
		t.Helper()
		tx, err := db.BeginTx(context.Background(), nil)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback()
		n, err := discovery.PruneCachesTx(context.Background(), tx, now)
		if err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Fatalf("pruned %d, want %d", n, want)
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`UPDATE deck_cache SET viewer_id=$1,status='active' WHERE generation=4`, bob); err != nil {
		t.Fatal(err)
	}
	prune(2)
	for _, table := range []string{"deck_cache", "deck_cache_cards", "deck_cursors"} {
		key := "batch_id"
		if table == "deck_cache" {
			key = "id"
		}
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM `+table+` WHERE `+key+`=$1`, removed).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("old %s survived", table)
		}
		if err := db.QueryRow(`SELECT count(*) FROM `+table+` WHERE `+key+`=$1`, staleActive).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("abandoned active %s survived", table)
		}
		for _, id := range kept {
			if err := db.QueryRow(`SELECT count(*) FROM `+table+` WHERE `+key+`=$1`, id).Scan(&n); err != nil {
				t.Fatal(err)
			}
			if n != 1 {
				t.Fatalf("retained %s disappeared", table)
			}
		}
	}
	for _, table := range []string{"discovery_exposures", "candidate_daily_exposures"} {
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM ` + table).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Fatalf("%s changed", table)
		}
	}
	prune(0)
}

func TestPruneCachesBoundsBatchAndSkipsLockedRows(t *testing.T) {
	db, _ := deckSetup(t)
	now := time.Now().UTC()
	if _, err := db.Exec(`INSERT INTO deck_cache(viewer_id,generation,location_version,preference_revision,location,policy_version,ranking_version,expires_at,exposure_bucket_date,created_at,status) SELECT $1,g,1,1,location,'v1','v1',$2::timestamptz,$2::timestamptz::date,$2::timestamptz,'expired' FROM user_locations CROSS JOIN generate_series(1,1002) g WHERE user_id=$1`, alice, now.Add(-8*24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	locked, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer locked.Rollback()
	var id string
	if err := locked.QueryRow(`SELECT id FROM deck_cache ORDER BY id LIMIT 1 FOR UPDATE`).Scan(&id); err != nil {
		t.Fatal(err)
	}
	prune := func(want int64) {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback()
		n, err := discovery.PruneCachesTx(ctx, tx, now)
		if err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Fatalf("pruned %d, want %d", n, want)
		}
		if err := tx.Commit(); err != nil {
			t.Fatal(err)
		}
	}
	prune(1000)
	prune(1)
	if err := locked.Commit(); err != nil {
		t.Fatal(err)
	}
	prune(1)
	prune(0)
}
