//go:build integration

package api_test

import (
	"context"
	"math"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/storage"
	"testing"
)

func TestCandidateQueryUsesRadiusAndReciprocalPreferences(t *testing.T) {
	db, h, store, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	call(t, h, "POST", "/v1/me/consents", "bob", acceptAll, 200)
	photo := call(t, h, "POST", "/v1/photos/upload-urls", "bob", uploadOne, 201)["data"].([]any)[0].(map[string]any)
	store.objects[photo["path"].(string)] = storage.Info{Size: 1000, ContentType: "image/jpeg"}
	body["photos"] = []map[string]any{{"photo_id": photo["photo_id"], "position": 1}}
	call(t, h, "POST", "/v1/me/onboarding", "bob", payload(t, body), 201)
	q := discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}
	assertCount := func(want int) {
		t.Helper()
		got, err := q.Candidates(context.Background(), alice, 25, 20)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != want {
			t.Fatalf("got %v candidates, want %d", got, want)
		}
	}
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)
	assertCount(1)
	for _, radius := range []float64{-1, math.NaN(), math.Inf(1)} {
		if _, err := q.Candidates(context.Background(), alice, radius, 1); err == nil {
			t.Fatal("invalid radius accepted")
		}
	}
	for _, limit := range []int{0, 301} {
		if _, err := q.Candidates(context.Background(), alice, 25, limit); err == nil {
			t.Fatal("invalid limit accepted")
		}
	}
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	visible, err := q.VisibleTx(context.Background(), tx, alice, bob, 25)
	tx.Rollback()
	if err != nil || !visible {
		t.Fatalf("transaction visibility: %v %v", visible, err)
	}
	exec(`UPDATE user_locations SET location=public.ST_SetSRID(public.ST_MakePoint(107.8,-6.2),4326)::public.geography WHERE user_id=$1`, bob)
	assertCount(0)
	got, err := q.Candidates(context.Background(), alice, 10000, 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatal("server radius maximum bypassed")
	}
	exec(`UPDATE user_locations SET location=(SELECT location FROM user_locations WHERE user_id=$1) WHERE user_id=$2`, alice, bob)
	assertCount(1)
	exec(`UPDATE profiles SET min_age=40 WHERE user_id=$1`, bob)
	assertCount(0)
	exec(`UPDATE profiles SET min_age=NULL,max_age=20 WHERE user_id=$1`, alice)
	assertCount(0)
	exec(`UPDATE profiles SET min_age=NULL,max_age=NULL`)
	assertCount(1)
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code<> 'everyone' AND code<>(SELECT g.code FROM profiles p JOIN gender_options g ON g.id=p.gender_id WHERE p.user_id=$1) LIMIT 1) WHERE user_id=$2`, alice, bob)
	assertCount(0)
}

func TestCandidateQueryExcludesUnsafeAndStaleCandidatesBeforeLimit(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO accounts(user_id,onboarding_completed_at) VALUES($1,now())`, bob)
	exec(`INSERT INTO profiles(user_id,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg) SELECT $1,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg FROM profiles WHERE user_id=$2`, bob, alice)
	exec(`INSERT INTO user_consents(user_id,consent_type,document_version,decision,recorded_at) SELECT $1,consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id=$2`, bob, alice)
	exec(`INSERT INTO user_locations(user_id,location) SELECT $1,location FROM user_locations WHERE user_id=$2`, bob, alice)
	exec(`INSERT INTO photos(id,user_id,storage_path,content_type,file_size,position,status) VALUES('88888888-8888-4888-8888-888888888888',$1,'candidate/query.jpg','image/jpeg',1000,1,'active')`, bob)
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)
	q := discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}
	assertCount := func(want int) {
		t.Helper()
		got, err := q.Candidates(context.Background(), alice, 0, 1)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != want {
			t.Fatalf("got %v candidates, want %d", got, want)
		}
	}
	assertCount(1)
	for _, tc := range []struct{ name, hide, restore string }{
		{"block outgoing", `INSERT INTO user_blocks(blocker_id,blocked_id) VALUES('` + alice + `','` + bob + `')`, `DELETE FROM user_blocks`},
		{"block incoming", `INSERT INTO user_blocks(blocker_id,blocked_id) VALUES('` + bob + `','` + alice + `')`, `DELETE FROM user_blocks`},
		{"frozen", `UPDATE accounts SET status='frozen' WHERE user_id='` + bob + `'`, `UPDATE accounts SET status='active'`},
		{"incomplete", `UPDATE accounts SET onboarding_completed_at=NULL WHERE user_id='` + bob + `'`, `UPDATE accounts SET onboarding_completed_at=now()`},
		{"photo", `UPDATE photos SET status='deleted',position=NULL,is_primary=false WHERE user_id='` + bob + `'`, `UPDATE photos SET status='active',position=1 WHERE user_id='` + bob + `'`},
		{"idle", `INSERT INTO discovery_activity(user_id,last_active_at) VALUES('` + bob + `',now()-interval '15 days')`, `DELETE FROM discovery_activity`},
		{"stale location", `UPDATE user_locations SET updated_at=now()-interval '31 days' WHERE user_id='` + bob + `'`, `UPDATE user_locations SET updated_at=now()`},
		{"missing location", `DELETE FROM user_locations WHERE user_id='` + bob + `'`, `INSERT INTO user_locations(user_id,location) SELECT '` + bob + `',location FROM user_locations WHERE user_id='` + alice + `'`},
		{"underage", `UPDATE profiles SET birthdate=current_date-interval '17 years' WHERE user_id='` + bob + `'`, `UPDATE profiles SET birthdate='2000-01-15' WHERE user_id='` + bob + `'`},
		{"exclusion source", `CREATE OR REPLACE VIEW discovery_pair_exclusions AS SELECT '` + alice + `'::uuid AS viewer_id,'` + bob + `'::uuid AS candidate_id`, `CREATE OR REPLACE VIEW discovery_pair_exclusions AS SELECT NULL::uuid AS viewer_id,NULL::uuid AS candidate_id WHERE false`},
	} {
		t.Run(tc.name, func(t *testing.T) { exec(tc.hide); assertCount(0); exec(tc.restore); assertCount(1) })
	}
	call(t, h, "POST", "/v1/me/consents", "bob", `{"consents":[{"type":"sensitive_data","accepted":false}]}`, 200)
	assertCount(0)
}
