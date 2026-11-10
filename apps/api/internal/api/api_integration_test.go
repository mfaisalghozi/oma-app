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
