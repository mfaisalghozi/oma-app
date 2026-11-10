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
	if err := migrations.Down(context.Background(), db); err != nil {
		t.Fatal(err)
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
