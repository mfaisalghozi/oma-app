//go:build integration

package api_test

import (
	"context"
	"encoding/json"
	"fmt"
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/scores"
	"strings"
	"testing"
	"time"
)

func TestDescribeRetrievalFiltersBeforeLimitAndReturnsEvidenceBackedTiers(t *testing.T) {
	db, h, store, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 312; i++ {
		id := fmt.Sprintf("77777777-7777-4777-8777-%012d", i)
		for _, stmt := range []string{
			`INSERT INTO accounts(user_id,onboarding_completed_at) VALUES($1,now())`,
			`INSERT INTO profiles(user_id,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg) SELECT $1,full_name,birthdate,gender_id,show_me_option_id,'likes walking',160,weight_kg FROM profiles WHERE user_id='` + alice + `'`,
			`INSERT INTO user_consents(user_id,consent_type,document_version,decision,recorded_at) SELECT $1,consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id='` + alice + `'`,
			`INSERT INTO user_locations(user_id,location) SELECT $1,location FROM user_locations WHERE user_id='` + alice + `'`,
			`INSERT INTO photos(id,user_id,storage_path,content_type,file_size,position,status) VALUES(gen_random_uuid(),$1,'candidate/'||($1::uuid)::text||'.jpg','image/jpeg',1000,1,'active')`} {
			exec(stmt, id)
		}
	}
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)
	exact := "77777777-7777-4777-8777-000000000310"
	close := "77777777-7777-4777-8777-000000000311"
	exec(`UPDATE profiles SET height_cm=180 WHERE user_id=$1`, exact)
	exec(`UPDATE profiles SET height_cm=178,bio='I love hiking' WHERE user_id=$1`, close)
	n := 180.0
	criteria := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: &n}}, Nice: []describe.Criterion{{Field: "bio", Operator: "contains", Text: "hiking"}}, NotSearchable: []describe.Unsupported{{Text: "kind eyes"}}}
	policy := deckPolicy()
	r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: store, Policy: policy}}
	got, err := r.Retrieve(context.Background(), alice, criteria)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Results) != 2 || got.Results[0].Profile.ID != exact || got.Results[0].Tier != "exact" || got.Results[1].Profile.ID != close || got.Results[1].Tier != "close" || got.Results[1].Matched != 1 || got.Results[1].Total != 2 || len(got.NotSearchable) != 1 {
		t.Fatalf("unexpected retrieval: %+v", got)
	}

	projector, err := scores.New(db, policy.Ranking)
	if err != nil {
		t.Fatal(err)
	}
	ghosterEvidence := func(from, to int) {
		for i := from; i < to; i++ {
			other := fmt.Sprintf("77777777-7777-4777-8777-%012d", i)
			exec(`WITH m AS(INSERT INTO matches(user_low,user_high,created_at) VALUES(LEAST($1::uuid,$2::uuid),GREATEST($1::uuid,$2::uuid),now()-interval '3 days') RETURNING id) INSERT INTO score_reply_windows(match_id,opener_sender_id,respondent_id,opened_at) SELECT id,$1,$2,now()-interval '3 days' FROM m`, other, exact)
		}
		if _, err := projector.Project(context.Background(), time.Now(), true); err != nil {
			t.Fatal(err)
		}
	}
	ghosterEvidence(0, 9)
	sample, err := r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(sample.Results) != 2 {
		t.Fatalf("insufficient ghoster evidence: %+v %v", sample, err)
	}
	ghosterEvidence(9, 12)
	sample, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(sample.Results) != 1 || sample.Results[0].Profile.ID != close {
		t.Fatalf("source-backed ghoster included: %+v %v", sample, err)
	}
	exec(`DELETE FROM score_reply_windows WHERE respondent_id=$1`, exact)
	if _, err = projector.Project(context.Background(), time.Now(), true); err != nil {
		t.Fatal(err)
	}
	hobbyID := "99999999-9999-4999-8999-999999999991"
	exec(`INSERT INTO hobbies(id,category_id,code,label) SELECT $1,id,'hiking-retrieval','Hiking' FROM hobby_categories LIMIT 1`, hobbyID)
	exec(`INSERT INTO profile_hobbies(user_id,hobby_id) VALUES($1,$2)`, close, hobbyID)
	catalog := []describe.CatalogEntry{{Field: "hobby", ID: hobbyID, Label: "Hiking", Aliases: []string{"mendaki"}}}
	canonical, ok := describe.ResolveAlias(catalog, "hobby", "mendaki")
	if !ok {
		t.Fatal("catalog alias unresolved")
	}
	withHobby := criteria
	withHobby.Nice = append(append([]describe.Criterion{}, criteria.Nice...), describe.Criterion{Field: "hobby", Operator: "contains", CatalogID: canonical})
	hobbyResult, err := r.Retrieve(context.Background(), alice, withHobby)
	if err != nil || hobbyResult.Results[1].Matched != 2 || hobbyResult.Results[1].Total != 3 {
		t.Fatalf("authored hobbies evidence: %+v %v", hobbyResult, err)
	}
	raw, _ := json.Marshal(got)
	for _, field := range []string{`"score"`, `"weight_kg"`, `"storage_path"`, `"birthdate"`, `"quality"`, `"reply_rate"`, `"idle_days"`, `"latitude"`, `"EvidenceSnapshot"`, `"Snapshot"`, `"distance_km"`} {
		if strings.Contains(string(raw), field) {
			t.Fatalf("leaked %s", field)
		}
	}

	exec(`UPDATE user_locations SET location=public.ST_Project((SELECT location FROM user_locations WHERE user_id=$1),53000,radians(90)) WHERE user_id=$2`, alice, close)
	distance := 50.0
	criteria.Must = append(criteria.Must, describe.Criterion{Field: "distance_km", Operator: "lte", Number: &distance})
	exec(`UPDATE profiles SET radius_km=1 WHERE user_id=$1`, alice)
	got, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(got.Results) != 2 || got.RequestedRadiusKM != 50 || got.EffectiveRadiusKM != 55 || got.Results[1].Tier != "close" || len(got.Results[1].Violations) != 2 {
		t.Fatalf("close radius/projection: %+v %v", got, err)
	}
	exec(`UPDATE user_locations SET location=public.ST_Project((SELECT location FROM user_locations WHERE user_id=$1),103000,radians(90)) WHERE user_id=$2`, alice, close)
	distance = 100
	got, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(got.Results) != 1 || got.EffectiveRadiusKM != 100 {
		t.Fatalf("global maximum relaxed: %+v %v", got, err)
	}
	exec(`UPDATE user_locations SET location=(SELECT location FROM user_locations WHERE user_id=$1) WHERE user_id=$2`, alice, close)
	exec(`UPDATE profiles SET min_age=80 WHERE user_id=$1`, close)
	got, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(got.Results) != 1 {
		t.Fatalf("reciprocal age relaxed: %+v %v", got, err)
	}
	exec(`INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2)`, exact, alice)
	got, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(got.Results) != 0 {
		t.Fatalf("block relaxed: %+v %v", got, err)
	}

	exec(`UPDATE profiles SET min_age=NULL`)
	exec(`UPDATE profiles SET height_cm=180 WHERE user_id IN(SELECT user_id FROM profiles WHERE user_id<>$1 ORDER BY user_id LIMIT 10)`, alice)
	got, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(got.Results) != 10 {
		t.Fatalf("exact ten: %+v %v", got, err)
	}
	for _, result := range got.Results {
		if result.Tier != "exact" {
			t.Fatal("close tier included despite ten exact results")
		}
	}
	again, err := r.Retrieve(context.Background(), alice, criteria)
	if err != nil {
		t.Fatal(err)
	}
	for i, result := range got.Results {
		if again.Results[i].Profile.ID != result.Profile.ID {
			t.Fatal("ranking is nondeterministic")
		}
	}
	_, err = r.Retrieve(context.Background(), alice, describe.Criteria{NotSearchable: criteria.NotSearchable})
	if err != describe.ErrNoSearchableCriteria {
		t.Fatalf("unsupported broad search: %v", err)
	}
}

func TestDescribeZeroRadiusMeansSamePoint(t *testing.T) {
	db, _ := deckSetup(t)
	r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: deckPolicy()}}
	zero := 0.0
	for _, op := range []string{"lte", "eq"} {
		c := describe.Criteria{Must: []describe.Criterion{{Field: "distance_km", Operator: op, Number: &zero}}}
		got, err := r.Retrieve(context.Background(), alice, c)
		if err != nil || len(got.Results) != 1 || got.EffectiveRadiusKM != 0 {
			t.Fatalf("same point %s: %+v %v", op, got, err)
		}
		if _, err = db.Exec(`UPDATE user_locations SET location=public.ST_Project(location,1,0) WHERE user_id=$1`, bob); err != nil {
			t.Fatal(err)
		}

		tx, err := db.Begin()
		if err != nil {
			t.Fatal(err)
		}
		explicit, e := r.Query.VisibleRadiusTx(context.Background(), tx, alice, bob, 0)
		if e != nil || explicit {
			tx.Rollback()
			t.Fatalf("saved zero widened: %v %v", explicit, e)
		}
		ordinary, e := r.Query.VisibleTx(context.Background(), tx, alice, bob, 0)
		tx.Rollback()
		if e != nil || !ordinary {
			t.Fatalf("ordinary zero lost stored/default semantics: %v %v", ordinary, e)
		}
		got, err = r.Retrieve(context.Background(), alice, c)
		if err != nil || len(got.Results) != 0 {
			t.Fatalf("zero widened %s: %+v %v", op, got, err)
		}
		if _, err = db.Exec(`UPDATE user_locations SET location=(SELECT location FROM user_locations WHERE user_id=$1) WHERE user_id=$2`, alice, bob); err != nil {
			t.Fatal(err)
		}
	}
}
func TestDescribeDropsEvidenceChangedBeforeProjection(t *testing.T) {
	for _, change := range []string{`UPDATE profiles SET height_cm=100 WHERE user_id=$1`, `UPDATE profiles SET bio='changed' WHERE user_id=$1`, `DELETE FROM profile_hobbies WHERE user_id=$1`, `UPDATE user_locations SET location=public.ST_Project(location,1,0) WHERE user_id=$1`} {
		t.Run(change, func(t *testing.T) {
			db, _ := deckSetup(t)
			if _, err := db.Exec(`INSERT INTO profile_hobbies(user_id,hobby_id) SELECT $1,id FROM hobbies LIMIT 1`, bob); err != nil {
				t.Fatal(err)
			}
			r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: deckPolicy()}}
			n := 175.0
			criteria := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: &n}}}
			barrier, err := db.Begin()
			if err != nil {
				t.Fatal(err)
			}
			defer barrier.Rollback()
			if _, err = barrier.Exec(`LOCK TABLE universities IN ACCESS EXCLUSIVE MODE`); err != nil {
				t.Fatal(err)
			}
			type result struct {
				value describe.Retrieval
				err   error
			}
			done := make(chan result, 1)
			go func() { v, e := r.Retrieve(context.Background(), alice, criteria); done <- result{v, e} }()
			deadline := time.Now().Add(3 * time.Second)
			for {
				var waiting bool
				if err = db.QueryRow(`SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE 'SELECT p.user_id,p.full_name%')`).Scan(&waiting); err != nil {
					t.Fatal(err)
				}
				if waiting {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("projection never reached barrier")
				}
				time.Sleep(time.Millisecond)
			}
			if _, err = db.Exec(change, bob); err != nil {
				t.Fatal(err)
			}
			if err = barrier.Commit(); err != nil {
				t.Fatal(err)
			}
			got := <-done
			if got.err != nil || len(got.value.Results) != 0 {
				t.Fatalf("changed evidence returned: %+v %v", got.value, got.err)
			}
		})
	}
}

func TestDescribeConsumesRealQualityAndActionExclusions(t *testing.T) {
	db, h := deckSetup(t)
	other := "33333333-3333-4333-8333-333333333333"
	actor := "44444444-4444-4444-8444-444444444444"
	cloneDeckUser(t, db, other)
	cloneDeckUser(t, db, actor)
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)
	exec(`UPDATE accounts SET created_at=now()-interval '10 days',phone_verified_at=now()-interval '10 days' WHERE user_id=$1`, actor)
	for _, event := range []struct{ target, action string }{{bob, "like"}, {other, "pass"}} {
		exec(`WITH i AS(INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) VALUES($1,$2,$3,'regular_deck',gen_random_uuid(),now()) RETURNING id) INSERT INTO swipe_events(action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT i.id,$1,$2,$3,vg.code||':'||g.code,now() FROM i JOIN profiles vp ON vp.user_id=$1 JOIN profiles p ON p.user_id=$2 JOIN gender_options vg ON vg.id=vp.gender_id JOIN gender_options g ON g.id=p.gender_id`, actor, event.target, event.action)
	}
	projector, err := scores.New(db, deckPolicy().Ranking)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = projector.Project(context.Background(), time.Now(), true); err != nil {
		t.Fatal(err)
	}
	r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: deckPolicy()}}
	n := 100.0
	c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: &n}}}
	got, err := r.Retrieve(context.Background(), alice, c)
	if err != nil || len(got.Results) != 3 || got.Results[0].Profile.ID != bob {
		t.Fatalf("source quality did not rank bob first: %+v %v", got, err)
	}
	deck := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	swipe(t, h, "alice", "describe-exclusion-pass", swipeBody(bob, deck["context_id"].(string), "pass"), 200)
	got, err = r.Retrieve(context.Background(), alice, c)
	if err != nil {
		t.Fatal(err)
	}
	for _, result := range got.Results {
		if result.Profile.ID == bob {
			t.Fatal("passed candidate returned")
		}
	}
	// A retained match excludes the pair even without a prior outbound decision.
	exec(`INSERT INTO matches(user_low,user_high,created_at,state) VALUES(LEAST($1::uuid,$2::uuid),GREATEST($1::uuid,$2::uuid),now(),'unmatched')`, alice, other)
	got, err = r.Retrieve(context.Background(), alice, c)
	if err != nil {
		t.Fatal(err)
	}
	for _, result := range got.Results {
		if result.Profile.ID == other {
			t.Fatal("retained match returned")
		}
	}
}

func TestDescribeRanksReplyAndRecencyBeforeLimit(t *testing.T) {
	for _, factor := range []string{"reply", "recency"} {
		t.Run(factor, func(t *testing.T) {
			db, _ := deckSetup(t)
			exec := func(stmt string, args ...any) {
				t.Helper()
				if _, err := db.Exec(stmt, args...); err != nil {
					t.Fatal(err)
				}
			}
			fresh := "99999999-9999-4999-8999-999999999999"
			cloneDeckUser(t, db, fresh)
			if factor == "recency" {
				for i := 0; i < 10; i++ {
					id := fmt.Sprintf("33333333-3333-4333-8333-%012d", i)
					cloneDeckUser(t, db, id)
				}
				exec(`UPDATE accounts SET updated_at=now()-interval '5 days' WHERE user_id NOT IN($1,$2)`, alice, fresh)
			} else {
				exec(`WITH m AS(INSERT INTO matches(user_low,user_high,created_at) VALUES(LEAST($1::uuid,$2::uuid),GREATEST($1::uuid,$2::uuid),now()-interval '3 days') RETURNING id) INSERT INTO score_reply_windows(match_id,opener_sender_id,respondent_id,opened_at) SELECT id,$1,$2,now()-interval '3 days' FROM m`, fresh, bob)
			}
			exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)

			actor := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
			exec(`INSERT INTO accounts(user_id,created_at,phone_verified_at) VALUES($1,now()-interval '10 days',now()-interval '10 days')`, actor)
			exec(`WITH i AS(INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) SELECT $1,p.user_id,'like','regular_deck',gen_random_uuid(),now() FROM profiles p WHERE p.user_id<>$2 RETURNING *) INSERT INTO swipe_events(action_id,actor_id,target_id,action,segment_key,occurred_at) SELECT i.id,i.actor_id,i.target_id,i.action,vg.code||':'||g.code,i.created_at FROM i JOIN profiles p ON p.user_id=i.target_id JOIN profiles vp ON vp.user_id=$2 JOIN gender_options g ON g.id=p.gender_id JOIN gender_options vg ON vg.id=vp.gender_id`, actor, alice)
			projector, err := scores.New(db, deckPolicy().Ranking)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = projector.Project(context.Background(), time.Now(), true); err != nil {
				t.Fatal(err)
			}
			r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: deckPolicy()}}
			n := 100.0
			c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: &n}}}
			got, err := r.Retrieve(context.Background(), alice, c)
			if err != nil || len(got.Results) == 0 || got.Results[0].Profile.ID != fresh {
				t.Fatalf("%s did not rank before limit: %+v %v", factor, got, err)
			}
		})
	}
}

func TestDescribeAppliesSharedExposureCapBeforeLimit(t *testing.T) {
	db, _ := deckSetup(t)
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 12; i++ {
		id := fmt.Sprintf("33333333-3333-4333-8333-%012d", i)
		cloneDeckUser(t, db, id)
	}
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`)
	local := time.Now().In(time.FixedZone("WIB", 7*3600))
	now := time.Date(local.Year(), local.Month(), local.Day(), 16, 59, 59, 0, time.UTC)
	day := now.In(time.FixedZone("WIB", 7*3600)).Format("2006-01-02")
	exec(`INSERT INTO candidate_daily_exposures(candidate_id,bucket_date,shown_today) SELECT user_id,$1,1 FROM profiles WHERE user_id<>$2 AND user_id NOT IN('33333333-3333-4333-8333-000000000010','33333333-3333-4333-8333-000000000011')`, day, alice)
	exec(`INSERT INTO profile_interactions(actor_id,target_id,action,context_kind,context_id,created_at) VALUES('33333333-3333-4333-8333-000000000000',$1,'super_like','regular_deck',gen_random_uuid(),now())`, alice)
	policy := deckPolicy()
	policy.ShownDailyCap = 1
	r := describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: policy, Now: func() time.Time { return now }}}
	n := 100.0
	c := describe.Criteria{Must: []describe.Criterion{{Field: "height_cm", Operator: "gte", Number: &n}}}
	got, err := r.Retrieve(context.Background(), alice, c)
	if err != nil || len(got.Results) != 2 {
		t.Fatalf("cap/pin bypass/limit: %+v %v", got, err)
	}
	exec(`INSERT INTO discovery_exposures(viewer_id,candidate_id,bucket_date,delivered_at) VALUES($1,$2,$3,now())`, alice, bob, day)
	got, err = r.Retrieve(context.Background(), alice, c)
	if err != nil || len(got.Results) != 3 {
		t.Fatalf("already exposed reload lost: %+v %v", got, err)
	}
	now = now.Add(time.Second)
	got, err = r.Retrieve(context.Background(), alice, c)
	if err != nil || len(got.Results) != 10 {
		t.Fatalf("WIB cap did not reset: %+v %v", got, err)
	}
}
