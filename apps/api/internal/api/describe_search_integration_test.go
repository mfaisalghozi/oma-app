//go:build integration

package api_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"github.com/riverqueue/river"
	"net/http"
	"net/http/httptest"
	"oma/apps/api/internal/api"
	"oma/apps/api/internal/describe"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/jobs"
	"oma/apps/api/internal/limits"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/scores"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestDescribeMissingProviderFailsClosed(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	call(t, h, "POST", "/v1/describe/searches", "alice", `{"query":"tall"}`, 503)
	usage := call(t, h, "GET", "/v1/me/usage", "alice", "", 200)["data"].(map[string]any)["searches"].(map[string]any)
	if usage["reserved"] != float64(0) || usage["used"] != float64(0) {
		t.Fatalf("missing provider reserved quota: %+v", usage)
	}
}

type describeProvider struct {
	fail bool
	raw  []byte
}

func (p *describeProvider) Generate(context.Context, string) ([]byte, error) {
	if p.fail {
		return nil, describe.ErrProvider
	}
	if p.raw != nil {
		return p.raw, nil
	}
	return []byte(`{"version":"v1","rewrite_id":"tinggi 180","translation_en":"height 180","must":[{"field":"height_cm","operator":"gte","number":180,"text":"","evidence":"180"}],"nice":[],"not_searchable":[]}`), nil
}
func searchService(t *testing.T) (*sql.DB, *describe.Service, http.Handler, *describeProvider) {
	t.Helper()
	db, h, store, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	benefit, err := limits.NewService(limits.Config{})
	if err != nil {
		t.Fatal(err)
	}
	p := &describeProvider{}
	policy := deckPolicy()
	service := &describe.Service{DB: db, Limits: benefit, Parser: describe.Parser{Provider: p, Limits: describe.Limits{MaxAge: 80, MaxDistanceKM: 100}}, Retriever: describe.Retriever{Query: discovery.CandidateQuery{DB: db, Policy: discovery.CandidatePolicy{DefaultRadiusKM: 25, MaxRadiusKM: 100, DefaultMinAge: 18, DefaultMaxAge: 80, LocationFreshDays: 30, IdleDays: 14}}, Profiles: &discovery.Handler{DB: db, Store: store, Policy: policy}}}
	if err = jobs.Migrate(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	service.Client, err = describe.NewInsertClient(db)
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /searches", service.Create)
	mux.HandleFunc("GET /searches/latest", service.Latest)
	mux.HandleFunc("GET /searches/{search_id}", service.Status)
	mux.HandleFunc("GET /searches/{search_id}/results", service.Results)
	mux.Handle("GET /usage", service.Limits.HandlerUsage(db))
	return db, service, auth.Middleware(identityFixture{}, mux), p
}
func createSearch(t *testing.T, h http.Handler, key, query string, want int) map[string]any {
	t.Helper()
	r := httptest.NewRequest("POST", "/searches", strings.NewReader(`{"query":"`+query+`"}`))
	r.Header.Set("Authorization", "Bearer alice")
	r.Header.Set("Idempotency-Key", key)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != want {
		t.Fatalf("search status%d want%d: %s", w.Code, want, w.Body.String())
	}
	var v map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	return v
}
func TestDescribeValidEmptyConsumesQuotaFailurePreservesLastSuccess(t *testing.T) {
	_, s, h, p := searchService(t)
	var last string
	for i := 1; i <= 3; i++ {
		key := fmt.Sprintf("99999999-9999-4999-8999-%012d", i)
		v := createSearch(t, h, key, "height 180", 202)["data"].(map[string]any)
		id := v["search_id"].(string)
		createSearch(t, h, key, "height 181", 409)
		createSearch(t, h, key, "height 180", 200)
		createSearch(t, h, "99999999-9999-4999-8999-000000000099", "height 180", 409)
		if err := s.Run(context.Background(), id); err != nil {
			t.Fatal(err)
		}
		last = id
		result := call(t, h, "GET", "/searches/latest", "alice", "", 200)["data"].(map[string]any)
		if result["search_id"] != id {
			t.Fatalf("valid zero result: %+v", result)
		}
		call(t, h, "GET", "/searches/"+id, "bob", "", 404)
		call(t, h, "GET", "/searches/"+id+"/results", "bob", "", 404)
	}
	createSearch(t, h, "99999999-9999-4999-8999-000000000004", "height 180", 429)
	usage := call(t, h, "GET", "/usage", "alice", "", 200)["data"].(map[string]any)["searches"].(map[string]any)
	if usage["used"] != float64(3) || usage["reserved"] != float64(0) {
		t.Fatalf("wrong quota: %+v", usage)
	}
	// Move the trusted clock to the next WIB day, then fail a new provider request.
	s.Now = func() time.Time { return time.Now().Add(24 * time.Hour) }
	p.fail = true
	v := createSearch(t, h, "99999999-9999-4999-8999-000000000005", "height 180", 202)["data"].(map[string]any)
	if err := s.Run(context.Background(), v["search_id"].(string)); err != nil {
		t.Fatal(err)
	}
	result := call(t, h, "GET", "/searches/latest", "alice", "", 200)["data"].(map[string]any)
	if result["search_id"] != last {
		t.Fatal("failed search replaced last success")
	}
}

type heldDescribeProvider struct {
	started chan struct{}
	release chan struct{}
}

func (p heldDescribeProvider) Generate(context.Context, string) ([]byte, error) {
	close(p.started)
	<-p.release
	return (&describeProvider{}).Generate(context.Background(), "")
}
func TestDescribeExpiredLeaseRefundsOriginalBucketAndFencesLateWorker(t *testing.T) {
	db, s, h, _ := searchService(t)
	start := time.Date(2026, 11, 16, 16, 59, 50, 0, time.UTC)
	var offset atomic.Int64
	s.Now = func() time.Time { return start.Add(time.Duration(offset.Load()) * time.Second) }
	provider := heldDescribeProvider{started: make(chan struct{}), release: make(chan struct{})}
	s.Parser.Provider = provider
	v := createSearch(t, h, "99999999-9999-4999-8999-000000000101", "height 180", 202)["data"].(map[string]any)
	id := v["search_id"].(string)
	done := make(chan error, 1)
	go func() { done <- s.Run(context.Background(), id) }()
	<-provider.started
	offset.Store(31)
	// A restarted process sees the durable expired lease and releases it, independently of River retry delivery.
	restarted := *s
	projector, err := scores.New(db, deckPolicy().Ranking)
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := jobs.New(db, projector, jobs.Options{RegisterWorkers: restarted.RegisterWorkers, Reconcile: restarted.Reconcile})
	if err != nil {
		t.Fatal(err)
	}
	restarted.Client = runtime.Client
	if _, err = db.Exec(`ALTER TABLE river_job RENAME TO unavailable_river_job`); err != nil {
		t.Fatal(err)
	}
	if err = runtime.Reconcile(context.Background()); err == nil {
		t.Fatal("missing queue unexpectedly reconciled")
	}
	if _, err = db.Exec(`ALTER TABLE unavailable_river_job RENAME TO river_job`); err != nil {
		t.Fatal(err)
	}
	close(provider.release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	status := call(t, h, "GET", "/searches/"+id, "alice", "", 200)["data"].(map[string]any)
	if status["status"] != "failed" {
		t.Fatalf("late worker resurrected search: %+v", status)
	}
	s.Parser.Provider = &describeProvider{}
	// The next day still has all three searches; the old-day reservation is not charged there.
	for i := 1; i <= 3; i++ {
		key := fmt.Sprintf("99999999-9999-4999-8999-%012d", 200+i)
		v := createSearch(t, h, key, "height 180", 202)["data"].(map[string]any)
		if err := s.Run(context.Background(), v["search_id"].(string)); err != nil {
			t.Fatal(err)
		}
	}
	createSearch(t, h, "99999999-9999-4999-8999-000000000299", "height 180", 429)
	offset.Store(0)
	for i := 1; i <= 3; i++ {
		v := createSearch(t, h, fmt.Sprintf("old-bucket-%d", i), "height 180", 202)["data"].(map[string]any)
		if err := s.Run(context.Background(), v["search_id"].(string)); err != nil {
			t.Fatal(err)
		}
	}
	createSearch(t, h, "old-bucket-fourth", "height 180", 429)
}

func TestDescribeSavedResultsUseAuthorizedCloseRadiusAndSuppressStaleEvidence(t *testing.T) {
	db, s, h, p := searchService(t)
	exec := func(stmt string, args ...any) {
		t.Helper()
		if _, err := db.Exec(stmt, args...); err != nil {
			t.Fatal(err)
		}
	}
	candidate := "77777777-7777-4777-8777-000000000001"
	for _, stmt := range []string{
		`INSERT INTO accounts(user_id,onboarding_completed_at) VALUES($1,now())`,
		`INSERT INTO profiles(user_id,full_name,birthdate,gender_id,show_me_option_id,bio,height_cm,weight_kg) SELECT $1,full_name,birthdate,gender_id,show_me_option_id,'I enjoy hiking',180,weight_kg FROM profiles WHERE user_id='` + alice + `'`,
		`INSERT INTO user_consents(user_id,consent_type,document_version,decision,recorded_at) SELECT $1,consent_type,document_version,decision,recorded_at FROM user_consents WHERE user_id='` + alice + `'`,
		`INSERT INTO user_locations(user_id,location) SELECT $1,public.ST_Project(location,53000,radians(90)) FROM user_locations WHERE user_id='` + alice + `'`,
		`INSERT INTO photos(id,user_id,storage_path,content_type,file_size,position,status) VALUES(gen_random_uuid(),$1,'candidate/photo.jpg','image/jpeg',1000,1,'active')`} {
		exec(stmt, candidate)
	}
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone'),radius_km=1 WHERE user_id=$1`, alice)
	exec(`UPDATE profiles SET show_me_option_id=(SELECT id FROM show_me_options WHERE code='everyone') WHERE user_id=$1`, candidate)
	p.raw = []byte(`{"version":"v1","rewrite_id":"dalam 50","translation_en":"within 50","must":[{"field":"distance_km","operator":"lte","number":50,"text":"","evidence":"50"}],"nice":[{"field":"bio","operator":"contains","number":null,"text":"hiking","evidence":"hiking"}],"not_searchable":[]}`)
	v := createSearch(t, h, "99999999-9999-4999-8999-000000000301", "within 50 hiking", 202)["data"].(map[string]any)
	id := v["search_id"].(string)
	if err := s.Run(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	s.Retriever.Profiles.Policy.DefaultRadiusKM = 2
	result := call(t, h, "GET", "/searches/"+id+"/results", "alice", "", 200)["data"].(map[string]any)["results"].([]any)
	if len(result) != 1 || result[0].(map[string]any)["tier"] != "close" {
		t.Fatalf("lost authorized53km candidate: %+v", result)
	}
	exec(`UPDATE profiles SET bio='I now enjoy swimming' WHERE user_id=$1`, candidate)
	result = call(t, h, "GET", "/searches/"+id+"/results", "alice", "", 200)["data"].(map[string]any)["results"].([]any)
	if len(result) != 1 || result[0].(map[string]any)["profile_updated"] != true || result[0].(map[string]any)["reason"] != nil || result[0].(map[string]any)["matched"] != nil {
		t.Fatalf("stale evidence returned: %+v", result)
	}
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if err = s.ContextTx(context.Background(), tx, alice, candidate, id); err != nil {
		t.Fatalf("authorized close action rejected: %v", err)
	}
	if err = s.ContextTx(context.Background(), tx, bob, candidate, id); err == nil {
		t.Fatal("foreign Describe context accepted")
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
	exec(`INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2)`, candidate, alice)
	result = call(t, h, "GET", "/searches/"+id+"/results", "alice", "", 200)["data"].(map[string]any)["results"].([]any)
	if len(result) != 0 {
		t.Fatal("blocked candidate remained visible")
	}
	exec(`DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2`, candidate, alice)
	realAPI := api.NewWithDescribeServices(db, identityFixture{}, s.Retriever.Profiles.Store, s.Retriever.Profiles.Policy, s.Limits, s)
	request := httptest.NewRequest("POST", "/v1/discovery/actions", strings.NewReader(fmt.Sprintf(`{"candidate_id":%q,"kind":"like","context":{"kind":"describe","id":%q}}`, candidate, id)))
	request.Header.Set("Authorization", "Bearer alice")
	request.Header.Set("Idempotency-Key", "close-action")
	writer := httptest.NewRecorder()
	realAPI.ServeHTTP(writer, request)
	if writer.Code != 200 {
		t.Fatalf("close candidate action: %d %s", writer.Code, writer.Body.String())
	}
}

func TestDescribeUnsupportedQueryRefundsAndPROGetsTwenty(t *testing.T) {
	_, s, h, p := searchService(t)
	p.raw = []byte(`{"version":"v1","rewrite_id":"mata","translation_en":"eyes","must":[],"nice":[],"not_searchable":[{"text":"eyes","reason":"unavailable_evidence"}]}`)
	v := createSearch(t, h, "opaque-case-sensitive-KEY", "eyes", 202)["data"].(map[string]any)
	if err := s.Run(context.Background(), v["search_id"].(string)); err != nil {
		t.Fatal(err)
	}
	status := call(t, h, "GET", "/searches/"+v["search_id"].(string), "alice", "", 200)["data"].(map[string]any)
	if status["status"] != "failed" || status["error_code"] != "INVALID_SEARCH_QUERY" {
		t.Fatalf("unsupported query became broad success: %+v", status)
	}
	p.raw = []byte(`{}`)
	malformed := createSearch(t, h, "malformed-provider-json", "height 180", 202)["data"].(map[string]any)
	if err := s.Run(context.Background(), malformed["search_id"].(string)); err != nil {
		t.Fatal(err)
	}
	malformedStatus := call(t, h, "GET", "/searches/"+malformed["search_id"].(string), "alice", "", 200)["data"].(map[string]any)
	if malformedStatus["status"] != "failed" {
		t.Fatalf("invalid provider parse accepted: %+v", malformedStatus)
	}
	pro, err := limits.NewService(limits.Config{Environment: "test", DevelopmentPROUserIDs: []string{alice}})
	if err != nil {
		t.Fatal(err)
	}
	s.Limits = pro
	p.raw = nil
	for i := 0; i < 20; i++ {
		v := createSearch(t, h, fmt.Sprintf("pro-search-%d", i), "height 180", 202)["data"].(map[string]any)
		if err = s.Run(context.Background(), v["search_id"].(string)); err != nil {
			t.Fatal(err)
		}
	}
	createSearch(t, h, "pro-search-21", "height 180", 429)
}

func TestDescribeTransactionalQueueRecoversAcceptedSearchAfterRestart(t *testing.T) {
	db, s, h, _ := searchService(t)
	// An unavailable queue rolls back the search and its hold together.
	if _, err := db.Exec(`ALTER TABLE river_job RENAME TO unavailable_river_job`); err != nil {
		t.Fatal(err)
	}
	createSearch(t, h, "unavailable-queue", "height 180", 500)
	if _, err := db.Exec(`ALTER TABLE unavailable_river_job RENAME TO river_job`); err != nil {
		t.Fatal(err)
	}
	usage := call(t, h, "GET", "/usage", "alice", "", 200)["data"].(map[string]any)["searches"].(map[string]any)
	if usage["reserved"] != float64(0) || usage["used"] != float64(0) {
		t.Fatalf("failed enqueue consumed: %+v", usage)
	}
	created := createSearch(t, h, "durable-before-worker-start", "height 180", 202)["data"].(map[string]any)
	id := created["search_id"].(string)
	projector, err := scores.New(db, deckPolicy().Ranking)
	if err != nil {
		t.Fatal(err)
	}
	restarted := *s
	runtime, err := jobs.New(db, projector, jobs.Options{RegisterWorkers: restarted.RegisterWorkers, Reconcile: restarted.Reconcile})
	if err != nil {
		t.Fatal(err)
	}
	restarted.Client = runtime.Client
	events, unsubscribe := runtime.Client.Subscribe(river.EventKindJobCompleted)
	defer unsubscribe()
	if err = runtime.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := runtime.Stop(ctx); err != nil {
			t.Error(err)
		}
	}()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case event := <-events:
			if event.Job.Kind == "describe_search" {
				status := call(t, h, "GET", "/searches/"+id, "alice", "", 200)["data"].(map[string]any)
				if status["status"] != "succeeded" {
					t.Fatalf("accepted search lost on restart: %+v", status)
				}
				return
			}
		case <-deadline:
			t.Fatal("Describe job not completed")
		}
	}
}

func TestDescribeConcurrentLastSearchAndCaseSensitiveReplay(t *testing.T) {
	_, s, h, _ := searchService(t)
	for i := 0; i < 2; i++ {
		v := createSearch(t, h, fmt.Sprintf("completed-%d", i), "height 180", 202)["data"].(map[string]any)
		if err := s.Run(context.Background(), v["search_id"].(string)); err != nil {
			t.Fatal(err)
		}
	}
	type response struct {
		code int
		id   string
	}
	responses := make(chan response, 2)
	start := make(chan struct{})
	for _, key := range []string{"case-sensitive-key", "CASE-sensitive-key"} {
		go func(key string) {
			<-start
			req := httptest.NewRequest("POST", "/searches", strings.NewReader(`{"query":"height 180"}`))
			req.Header.Set("Authorization", "Bearer alice")
			req.Header.Set("Idempotency-Key", key)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, req)
			v := response{code: w.Code}
			if w.Code == 202 {
				var body struct {
					Data struct {
						ID string `json:"search_id"`
					} `json:"data"`
				}
				if json.Unmarshal(w.Body.Bytes(), &body) == nil {
					v.id = body.Data.ID
				}
			}
			responses <- v
		}(key)
	}
	close(start)
	a, b := <-responses, <-responses
	if a.code != 202 {
		a, b = b, a
	}
	if a.code != 202 || (b.code != 409 && b.code != 429) {
		t.Fatalf("lastsearch race %+v %+v", a, b)
	}
	if err := s.Run(context.Background(), a.id); err != nil {
		t.Fatal(err)
	}
	createSearch(t, h, "fourth-search", "height 180", 429)
}
