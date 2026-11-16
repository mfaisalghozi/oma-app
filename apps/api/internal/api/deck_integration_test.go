//go:build integration

package api_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/api"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
	"sync"
	"testing"
	"time"
)

func deckPolicy() discovery.Policy {
	return discovery.Policy{Version: "fixture-v1", DeckVersion: "fixture-deck-v1", Ranking: discovery.RankingPolicy{Version: "v1", PriorStrength: 10, FallbackMean: .3, ReplyFloor: .4, RecencyHalfLifeDays: 5, LikeHalfLifeDays: 30, MinSegmentDecisions: 200}, DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, MaterialMovementMeters: 2000, ShownDailyCap: 150, PriorityCap: 1, FreshCap: 30, FreshSlots: 2, FreeTopHalf: 5, ProTopHalf: 10, DistanceBandPercent: [4]int{25, 25, 25, 25}, PriorityTTLDays: 7, PriorityCapBypass: true}
}
func deckSetup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db, h, store, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	for _, stmt := range []string{
		`INSERT INTO accounts(user_id,onboarding_completed_at) VALUES('` + bob + `',now())`,
		`INSERT INTO profiles(user_id,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg) SELECT '` + bob + `',full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg FROM profiles WHERE user_id='` + alice + `'`,
		`INSERT INTO user_consents(user_id,consent_type,document_version,decision,recorded_at) SELECT '` + bob + `',consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id='` + alice + `'`,
		`INSERT INTO user_locations(user_id,location) SELECT '` + bob + `',location FROM user_locations WHERE user_id='` + alice + `'`,
		`INSERT INTO photos(id,user_id,storage_path,content_type,file_size,position,status) VALUES('88888888-8888-4888-8888-888888888888','` + bob + `','candidate/deck.jpg','image/jpeg',1000,1,'active')`,
		`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone')`} {
		if _, e := db.Exec(stmt); e != nil {
			t.Fatal(e)
		}
	}
	return db, api.NewWithDiscoveryPolicy(db, identityFixture{}, store, deckPolicy())
}
func TestDeckCachesOrderProjectsSafeFieldsAndRechecksCurrentEligibility(t *testing.T) {
	db, h := deckSetup(t)
	first := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	cards := first["cards"].([]any)
	if len(cards) != 1 {
		t.Fatalf("deck: %#v", first)
	}
	card := cards[0].(map[string]any)
	for _, key := range []string{"score", "theta_mean", "likes_w", "latitude", "longitude", "storage_path", "full_name", "weight_kg", "random_key"} {
		if _, ok := card[key]; ok {
			t.Fatalf("private field %s", key)
		}
	}
	second := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if first["context_id"] != second["context_id"] {
		t.Fatal("cache reshuffled")
	}
	path := "/v1/discovery/candidates/" + bob + "?context_id=" + first["context_id"].(string)
	call(t, h, "GET", path, "alice", "", 200)
	call(t, h, "GET", path, "bob", "", 404)
	if _, e := db.Exec(`INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2)`, bob, alice); e != nil {
		t.Fatal(e)
	}
	call(t, h, "GET", path, "alice", "", 404)
	empty := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if len(empty["cards"].([]any)) != 0 {
		t.Fatal("blocked cached card leaked")
	}
}

func TestDeckDeduplicatesDeliveryCapsConcurrentViewersAndResetsAtWIBMidnight(t *testing.T) {
	db, base := deckSetup(t)
	_ = base
	const target = "33333333-3333-4333-8333-333333333333"
	clone := func(id string) { cloneDeckUser(t, db, id) }
	clone(target)
	// Dedicated token fixture permits many concurrent authenticated viewers.
	viewers := []string{alice, bob}
	for i := 0; i < 10; i++ {
		id := fmt.Sprintf("44444444-4444-4444-8444-%012d", i)
		clone(id)
		viewers = append(viewers, id)
	}
	policy := deckPolicy()
	policy.ShownDailyCap = 1
	now := time.Now().UTC()
	day := time.Date(now.Year(), now.Month(), now.Day(), 16, 59, 59, 0, time.UTC)
	handler := &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: policy, Now: func() time.Time { return day }}
	h := auth.Middleware(uuidIdentity{}, http.HandlerFunc(handler.Deck))
	fetch := func(viewer string) map[string]any {
		return call(t, h, "GET", "/v1/discovery", viewer, "", 200)["data"].(map[string]any)
	}
	first := fetch(alice)
	has := func(d map[string]any, id string) bool {
		for _, raw := range d["cards"].([]any) {
			if raw.(map[string]any)["id"] == id {
				return true
			}
		}
		return false
	}
	if !has(first, target) || !has(fetch(alice), target) {
		t.Fatal("first delivery or reload missing candidate")
	}
	for _, viewer := range viewers[1:] {
		if has(fetch(viewer), target) {
			t.Fatal("first-delivery cap bypassed by another viewer")
		}
	}
	// Yesterday's cached membership is deliverable in today's new exposure bucket.
	day = day.Add(time.Second)
	if !has(fetch(bob), target) {
		t.Fatal("WIB rollover did not reopen exposure budget")
	}
	day = day.Add(24 * time.Hour)
	if _, e := db.Exec(`UPDATE deck_cache SET status='expired'`); e != nil {
		t.Fatal(e)
	}
	var wg sync.WaitGroup
	results := make(chan bool, len(viewers))
	errs := make(chan string, len(viewers))
	for _, viewer := range viewers {
		wg.Add(1)
		go func(v string) {
			defer wg.Done()
			req := httptest.NewRequest("GET", "/v1/discovery", nil)
			req.Header.Set("Authorization", "Bearer "+v)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			if w.Code != 200 {
				errs <- w.Body.String()
				return
			}
			var out map[string]any
			if e := json.Unmarshal(w.Body.Bytes(), &out); e != nil {
				errs <- e.Error()
				return
			}
			results <- has(out["data"].(map[string]any), target)
		}(viewer)
	}
	wg.Wait()
	close(results)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	delivered := 0
	for yes := range results {
		if yes {
			delivered++
		}
	}
	if delivered != 1 {
		t.Fatalf("concurrent cap delivered target to %d viewers, want1", delivered)
	}
}

type uuidIdentity struct{}

func (uuidIdentity) Verify(_ context.Context, token string) (string, error) {
	if !httpapi.ValidID(token) {
		return "", fmt.Errorf("invalid fixture")
	}
	return token, nil
}

type deckReadStore struct{ storage.Unavailable }

func (deckReadStore) SignRead(_ context.Context, path string) (string, error) {
	return "https://storage.test/signed/" + path, nil
}

func cloneDeckUser(t *testing.T, db *sql.DB, id string) {
	t.Helper()
	for _, stmt := range []string{
		`INSERT INTO accounts(user_id,onboarding_completed_at) VALUES($1,now())`,
		`INSERT INTO profiles(user_id,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg) SELECT $1,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg FROM profiles WHERE user_id='` + alice + `'`,
		`INSERT INTO user_consents(user_id,consent_type,document_version,decision,recorded_at) SELECT $1,consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id='` + alice + `'`,
		`INSERT INTO user_locations(user_id,location) SELECT $1,location FROM user_locations WHERE user_id='` + alice + `'`,
		`INSERT INTO photos(id,user_id,storage_path,content_type,file_size,position,status) VALUES(gen_random_uuid(),$1,'candidate/'||($1::uuid)::text||'.jpg','image/jpeg',1000,1,'active')`} {
		if _, e := db.Exec(stmt, id); e != nil {
			t.Fatal(e)
		}
	}
}

func TestDeckCursorsAndMaterialContextChanges(t *testing.T) {
	db, h := deckSetup(t)
	cloneDeckUser(t, db, "33333333-3333-4333-8333-333333333333")
	first := call(t, h, "GET", "/v1/discovery?limit=1", "alice", "", 200)["data"].(map[string]any)
	token, ok := first["next_cursor"].(string)
	if !ok {
		t.Fatal("missing server cursor")
	}
	next := call(t, h, "GET", "/v1/discovery?cursor="+token, "alice", "", 200)["data"].(map[string]any)
	if len(next["cards"].([]any)) != 1 || next["cards"].([]any)[0].(map[string]any)["id"] == first["cards"].([]any)[0].(map[string]any)["id"] {
		t.Fatal("paging duplicated card")
	}
	call(t, h, "GET", "/v1/discovery?cursor="+token, "bob", "", 400)
	call(t, h, "GET", "/v1/discovery?cursor=made-up", "alice", "", 400)
	call(t, h, "PATCH", "/v1/me/discovery-preferences", "alice", `{"radius_km":20,"min_age":18,"max_age":80}`, 200)
	call(t, h, "GET", "/v1/discovery?cursor="+token, "alice", "", 409)
	second := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if second["context_id"] == first["context_id"] {
		t.Fatal("stored preference change retained cache")
	}
	// Reuse the original location as a baseline without exposing it in a response.
	var lon, lat float64
	if err := db.QueryRow(`SELECT public.ST_X(location::public.geometry),public.ST_Y(location::public.geometry) FROM user_locations WHERE user_id=$1`, alice).Scan(&lon, &lat); err != nil {
		t.Fatal(err)
	}
	call(t, h, "PUT", "/v1/me/location", "alice", fmt.Sprintf(`{"latitude":%f,"longitude":%f}`, lat, lon+.001), 200)
	small := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if small["context_id"] != second["context_id"] {
		t.Fatal("immaterial movement reshuffled cache")
	}
	call(t, h, "PUT", "/v1/me/location", "alice", fmt.Sprintf(`{"latitude":%f,"longitude":%f}`, lat, lon+.03), 200)
	large := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if large["context_id"] == small["context_id"] {
		t.Fatal("material movement did not invalidate cache")
	}
	if _, err := db.Exec(`UPDATE deck_cache SET expires_at=now()-interval '1 minute'`); err != nil {
		t.Fatal(err)
	}
	expired := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if expired["context_id"] == large["context_id"] {
		t.Fatal("expired cache retained")
	}
}
func TestFailedStorageProjectionDoesNotConsumeExposure(t *testing.T) {
	db, _ := deckSetup(t)
	const third = "33333333-3333-4333-8333-333333333333"
	cloneDeckUser(t, db, third)
	p := deckPolicy()
	p.ShownDailyCap = 1
	failing := api.NewWithDiscoveryPolicy(db, identityFixture{}, storage.Unavailable{}, p)
	call(t, failing, "GET", "/v1/discovery", "alice", "", 500)
	healthy := api.NewWithDiscoveryPolicy(db, uuidIdentity{}, deckReadStore{}, p)
	out := call(t, healthy, "GET", "/v1/discovery", third, "", 200)["data"].(map[string]any)
	found := false
	for _, raw := range out["cards"].([]any) {
		if raw.(map[string]any)["id"] == bob {
			found = true
		}
	}
	if !found {
		t.Fatal("failed signing consumed exposure")
	}
}

func TestPriorityPinBypassesCapOnlyWhileCurrentAndCountsTowardDeckMix(t *testing.T) {
	db, _ := deckSetup(t)
	const third = "33333333-3333-4333-8333-333333333333"
	cloneDeckUser(t, db, third)
	p := deckPolicy()
	p.ShownDailyCap = 1
	h := api.NewWithDiscoveryPolicy(db, uuidIdentity{}, deckReadStore{}, p)
	call(t, h, "GET", "/v1/discovery", third, "", 200)
	if _, err := db.Exec(`CREATE OR REPLACE VIEW discovery_incoming_priority AS SELECT '` + alice + `'::uuid AS viewer_id,'` + bob + `'::uuid AS candidate_id,now()-interval '1 day' AS created_at`); err != nil {
		t.Fatal(err)
	}
	pinned := call(t, h, "GET", "/v1/discovery", alice, "", 200)["data"].(map[string]any)
	cards := pinned["cards"].([]any)
	if len(cards) == 0 || cards[0].(map[string]any)["id"] != bob {
		t.Fatal("incoming priority did not pin through cap")
	}
	repeat := call(t, h, "GET", "/v1/discovery", alice, "", 200)["data"].(map[string]any)
	if pinned["context_id"] != repeat["context_id"] {
		t.Fatal("priority cache unstable")
	}
	// HEAD creates a cached pin without delivering it to a new viewer.
	const fourth = "44444444-4444-4444-8444-444444444444"
	cloneDeckUser(t, db, fourth)
	if _, err := db.Exec(`CREATE OR REPLACE VIEW discovery_incoming_priority AS SELECT '` + fourth + `'::uuid AS viewer_id,'` + bob + `'::uuid AS candidate_id,now()-interval '1 day' AS created_at`); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("HEAD", "/v1/discovery", nil)
	req.Header.Set("Authorization", "Bearer "+fourth)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if _, err := db.Exec(`CREATE OR REPLACE VIEW discovery_incoming_priority AS SELECT '` + fourth + `'::uuid AS viewer_id,'` + bob + `'::uuid AS candidate_id,now()-interval '8 days' AS created_at`); err != nil {
		t.Fatal(err)
	}
	expired := call(t, h, "GET", "/v1/discovery", fourth, "", 200)["data"].(map[string]any)
	for _, raw := range expired["cards"].([]any) {
		if raw.(map[string]any)["id"] == bob {
			t.Fatal("expired priority bypassed cap")
		}
	}
}
func TestDiscoveryPolicyRevisionInvalidatesCache(t *testing.T) {
	db, _ := deckSetup(t)
	handler := &discovery.Handler{DB: db, Store: deckReadStore{}, Policy: deckPolicy()}
	h := auth.Middleware(identityFixture{}, http.HandlerFunc(handler.Deck))
	first := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	handler.Policy.Version = "fixture-v2"
	second := call(t, h, "GET", "/v1/discovery", "alice", "", 200)["data"].(map[string]any)
	if first["context_id"] == second["context_id"] {
		t.Fatal("policy revision did not invalidate cache")
	}
}
