//go:build integration

package api_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"oma/apps/api/internal/account"
	"oma/apps/api/internal/api"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/migrations"
)

const alice = "11111111-1111-4111-8111-111111111111"
const bob = "22222222-2222-4222-8222-222222222222"

type identityFixture struct{}

func (identityFixture) Verify(_ context.Context, token string) (string, error) {
	if token == "alice" {
		return alice, nil
	}
	if token == "bob" {
		return bob, nil
	}
	return "", fmt.Errorf("invalid fixture token")
}

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Fatal("TEST_DATABASE_URL must point to a disposable PostgreSQL/PostGIS database")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	admin := stdlib.OpenDB(*cfg)
	// A migrated `public` schema silently shadows this test's schema: the
	// search_path below falls through to it, so a test that drops its own
	// tables still finds the public copies and passes when it must fail.
	var publicTables int
	if err = admin.QueryRow(`SELECT count(*) FROM information_schema.tables
		WHERE table_schema='public'
		  AND table_name IN ('accounts','profiles','photos','consent_documents')`).Scan(&publicTables); err != nil {
		t.Fatal(err)
	}
	if publicTables > 0 {
		t.Fatal("TEST_DATABASE_URL points at a database with application tables in public; use a disposable database whose public schema is empty")
	}
	schema := fmt.Sprintf("test_%d", time.Now().UnixNano())
	if _, err = admin.Exec("CREATE SCHEMA " + schema); err != nil {
		t.Fatal(err)
	}
	cfg.RuntimeParams["search_path"] = schema + ",public"
	db := stdlib.OpenDB(*cfg)
	t.Cleanup(func() { db.Close(); admin.Exec("DROP SCHEMA " + schema + " CASCADE"); admin.Close() })
	if err = migrations.Up(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	return db, api.New(db, identityFixture{})
}

func call(t *testing.T, h http.Handler, method, path, token, body string, status int) map[string]any {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	if w.Code != status {
		t.Fatalf("%s %s: status=%d want=%d body=%s", method, path, w.Code, status, w.Body.String())
	}
	var out map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestInitializeIsIdempotentAndDerivesIdentityFromToken(t *testing.T) {
	_, h := setup(t)
	first := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	second := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if first["user_id"] != alice || first["account_created"] != true || second["account_created"] != false || second["next_action"] != "accept_consents" || second["onboarding_completed"] != false || second["onboarding_completed_at"] != nil {
		t.Fatalf("unexpected initialization: %#v %#v", first, second)
	}
	call(t, h, "POST", "/v1/me/initialize", "", "", 401)
	call(t, h, "POST", "/v1/me/initialize", "invalid", "", 401)
}

func TestAccountRestrictionsAndDatabaseFailuresFailClosed(t *testing.T) {
	db, h := setup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	for _, status := range []string{"frozen", "suspended"} {
		if _, err := db.Exec(`UPDATE accounts SET status=$1,onboarding_completed_at=now() WHERE user_id=$2`, status, alice); err != nil {
			t.Fatal(err)
		}
		out := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
		if out["next_action"] != "account_restricted" || out["onboarding_completed"] != true {
			t.Fatalf("unexpected restricted state: %#v", out)
		}
	}
	db.Close()
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 500)
}

func TestAccountMigrationCanBeRevertedAndReapplied(t *testing.T) {
	db, h := setup(t)
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM schema_migrations`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	for range count {
		if err := migrations.Down(context.Background(), db); err != nil {
			t.Fatal(err)
		}
	}
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 500)
	if err := migrations.Up(context.Background(), db); err != nil {
		t.Fatal(err)
	}
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
}

func TestActiveAccountGuard(t *testing.T) {
	db, h := setup(t)
	accounts := &account.Handler{DB: db}
	guarded := auth.Middleware(identityFixture{}, accounts.Active(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { httpapi.Data(w, 200, map[string]bool{"allowed": true}) })))
	call(t, guarded, "GET", "/protected", "bob", "", 403)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, guarded, "GET", "/protected", "alice", "", 200)
	for _, tc := range []struct{ status, code string }{{"frozen", "ACCOUNT_FROZEN"}, {"suspended", "ACCOUNT_SUSPENDED"}} {
		if _, err := db.Exec(`UPDATE accounts SET status=$1 WHERE user_id=$2`, tc.status, alice); err != nil {
			t.Fatal(err)
		}
		got := call(t, guarded, "GET", "/protected", "alice", "", 403)
		if got["error"].(map[string]any)["code"] != tc.code {
			t.Fatalf("wrong restriction: %#v", got)
		}
	}
	db.Close()
	call(t, guarded, "GET", "/protected", "alice", "", 500)
}

func seedDocuments(t *testing.T, db *sql.DB) {
	t.Helper()
	_, err := db.Exec(`INSERT INTO consent_documents(consent_type,title,document_version,document_url,required,active) VALUES
 ('terms','Terms','1.0','https://legal.example.test/terms/1.0',true,true),
 ('privacy','Privacy','1.0','https://legal.example.test/privacy/1.0',true,true),
 ('sensitive_data','Sensitive data','1.0','https://legal.example.test/sensitive/1.0',true,true)`)
	if err != nil {
		t.Fatal(err)
	}
}

const acceptAll = `{"consents":[{"type":"terms","accepted":true},{"type":"privacy","accepted":true},{"type":"sensitive_data","accepted":true}]}`

func TestConsentAcceptanceAndAccountRouting(t *testing.T) {
	db, h := setup(t)
	seedDocuments(t, db)
	docs := call(t, h, "GET", "/v1/consents/documents", "", "", 200)["data"].([]any)
	if len(docs) != 3 {
		t.Fatalf("wrong document list: %#v", docs)
	}
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	partial := call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"terms","accepted":true}]}`, 200)["data"].(map[string]any)
	if partial["required_consents_completed"] != false {
		t.Fatal("missing consent treated as complete")
	}
	call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"unsupported","accepted":true}]}`, 400)
	accepted := call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)["data"].(map[string]any)
	if accepted["required_consents_completed"] != true {
		t.Fatalf("required consent incomplete: %#v", accepted)
	}
	state := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "complete_onboarding" {
		t.Fatalf("wrong route: %#v", state)
	}
	// Simulate an already-onboarded account as the fixture for the bootstrap route.
	if _, err := db.Exec(`UPDATE accounts SET onboarding_completed_at=now() WHERE user_id=$1`, alice); err != nil {
		t.Fatal(err)
	}
	state = call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "discovery" {
		t.Fatalf("wrong completed route: %#v", state)
	}
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	status := call(t, h, "GET", "/v1/me/consents", "alice", "", 200)["data"].([]any)
	if len(status) != 3 {
		t.Fatalf("wrong latest consent status: %#v", status)
	}
}

func TestConsentVersionChangeAndLatestDecision(t *testing.T) {
	db, h := setup(t)
	seedDocuments(t, db)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	out := call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"privacy","accepted":false}]}`, 200)["data"].(map[string]any)
	if out["required_consents_completed"] != false {
		t.Fatal("rejection did not supersede prior acceptance")
	}
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	_, err := db.Exec(`UPDATE consent_documents SET active=false WHERE consent_type='terms'; INSERT INTO consent_documents(consent_type,title,document_version,document_url,active) VALUES('terms','Updated terms','2.0','https://legal.example.test/terms/2.0',true)`)
	if err != nil {
		t.Fatal(err)
	}
	state := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "accept_consents" {
		t.Fatal("old document acceptance treated as current")
	}
	out = call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)["data"].(map[string]any)
	if out["required_consents_completed"] != true {
		t.Fatal("renewed consent did not restore completion")
	}
	if _, err = db.Exec(`DROP TABLE user_consents`); err != nil {
		t.Fatal(err)
	}
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 500)
}

func TestMasterDataTypesSearchPaginationAndValidation(t *testing.T) {
	db, h := setup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	for _, kind := range []string{"gender", "pronoun", "show_me", "looking_for", "university", "religion", "personality", "hobby_category", "hobby"} {
		got := call(t, h, "GET", "/v1/profile-data?type="+kind, "alice", "", 200)["data"].(map[string]any)
		if got["type"] != kind || got["items"] == nil {
			t.Fatalf("invalid %s result: %#v", kind, got)
		}
	}
	_, err := db.Exec(`INSERT INTO universities(id,name,country_code) VALUES('33333333-3333-4333-8333-333333333333','Alpha Indonesia','ID'),('44444444-4444-4444-8444-444444444444','Beta Indonesia','ID'); INSERT INTO universities(name,country_code,is_active) VALUES('Hidden Indonesia','ID',false)`)
	if err != nil {
		t.Fatal(err)
	}
	got := call(t, h, "GET", "/v1/profile-data?type=university&q=Indonesia&page=2&limit=1", "alice", "", 200)["data"].(map[string]any)
	if len(got["items"].([]any)) != 1 || got["pagination"].(map[string]any)["total"] != float64(2) {
		t.Fatalf("bad pagination: %#v", got)
	}
	got = call(t, h, "GET", "/v1/profile-data?type=university&q=Indonesia&page=99&limit=1", "alice", "", 200)["data"].(map[string]any)
	if len(got["items"].([]any)) != 0 || got["pagination"].(map[string]any)["total"] != float64(2) {
		t.Fatalf("out-of-range totals lost: %#v", got)
	}
	for _, q := range []string{"type=accounts", "type=gender&page=0", "type=gender&limit=101", "type=gender&category_id=" + alice, "type=hobby&category_id=not-a-uuid"} {
		call(t, h, "GET", "/v1/profile-data?"+q, "alice", "", 400)
	}
}

func TestHobbyCategoryFilterExcludesInactiveRecords(t *testing.T) {
	db, h := setup(t)
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	_, err := db.Exec(`INSERT INTO hobby_categories(id,code,label) VALUES('33333333-3333-4333-8333-333333333333','test_outdoors','Test outdoors'),('44444444-4444-4444-8444-444444444444','test_music','Test music'); INSERT INTO hobbies(category_id,code,label,is_active) VALUES('33333333-3333-4333-8333-333333333333','test_hiking','Test Hiking',true),('33333333-3333-4333-8333-333333333333','test_hidden','Test Hidden',false),('44444444-4444-4444-8444-444444444444','test_guitar','Test Guitar',true)`)
	if err != nil {
		t.Fatal(err)
	}
	got := call(t, h, "GET", "/v1/profile-data?type=hobby&category_id=33333333-3333-4333-8333-333333333333&q=Hiking", "alice", "", 200)["data"].(map[string]any)
	items := got["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["code"] != "test_hiking" {
		t.Fatalf("wrong category filter: %#v", got)
	}
}
