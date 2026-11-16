//go:build integration

package api_test

import (
	"context"
	"encoding/json"
	"fmt"
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/discovery"
	"strings"
	"testing"
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

	ghosterView := func(count int) {
		exec(fmt.Sprintf(`CREATE OR REPLACE VIEW discovery_quality AS SELECT p.user_id AS candidate_id,vg.code||':'||g.code AS segment_key,0::double precision AS likes_w,0::double precision AS passes_w,0.9::double precision AS percentile,0.1::double precision AS reply_rate,NULL::double precision AS prior_mean,%d::bigint AS completed_matches FROM profiles p JOIN gender_options g ON g.id=p.gender_id JOIN profiles vp ON vp.user_id='%s' JOIN gender_options vg ON vg.id=vp.gender_id WHERE p.user_id='%s'`, count, alice, exact))
	}
	ghosterView(9)
	sample, err := r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(sample.Results) != 2 {
		t.Fatalf("insufficient ghoster evidence: %+v %v", sample, err)
	}
	ghosterView(10)
	sample, err = r.Retrieve(context.Background(), alice, criteria)
	if err != nil || len(sample.Results) != 1 || sample.Results[0].Profile.ID != close {
		t.Fatalf("qualifying ghoster included: %+v %v", sample, err)
	}
	exec(`CREATE OR REPLACE VIEW discovery_quality AS SELECT NULL::uuid AS candidate_id,NULL::text AS segment_key,0::double precision AS likes_w,0::double precision AS passes_w,0.5::double precision AS percentile,0.75::double precision AS reply_rate,NULL::double precision AS prior_mean,0::bigint AS completed_matches WHERE false`)
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
	for _, field := range []string{`"score"`, `"weight_kg"`, `"storage_path"`, `"birthdate"`, `"quality"`, `"latitude"`} {
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
