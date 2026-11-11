//go:build integration

package api_test

import (
	"net/http"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"oma/apps/api/internal/platform/storage"
	"strings"
	"testing"
)

func TestOwnProfileIncludesLabelsAndRelationsWithoutPublicSensitiveFields(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	got := call(t, h, "GET", "/v1/me/profile", "alice", "", 200)["data"].(map[string]any)
	if got["user_id"] != alice || got["gender"].(map[string]any)["label"] == nil || len(got["looking_for"].([]any)) != 1 || len(got["hobbies"].([]any)) != 1 || len(got["photos"].([]any)) != 1 {
		t.Fatalf("incomplete profile: %#v", got)
	}
	encoded := payload(t, got)
	if strings.Contains(encoded, "latitude") || strings.Contains(encoded, "longitude") || strings.Contains(encoded, "attractiveness") {
		t.Fatal("private scoring or coordinates exposed")
	}
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	call(t, h, "GET", "/v1/me/profile?user_id="+alice, "bob", "", 404)
}

func TestDiscoveryGuardAndQueryExcludeIncompleteOrRestrictedAccounts(t *testing.T) {
	db, h, store, body := onboardingSetup(t)
	eligibility := &discovery.Eligibility{DB: db}
	consumer := auth.Middleware(identityFixture{}, eligibility.Guard(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ids, err := eligibility.CandidateIDs(r.Context(), auth.UserID(r.Context()), 20)
		if err != nil {
			httpapi.HandleError(w, err)
			return
		}
		httpapi.Data(w, 200, ids)
	})))
	call(t, consumer, "GET", "/consumer", "alice", "", 403)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	call(t, h, "POST", "/v1/me/consents", "bob", acceptAll, 200)
	empty := call(t, consumer, "GET", "/consumer", "alice", "", 200)["data"].([]any)
	if len(empty) != 0 {
		t.Fatal("incomplete account returned in candidates")
	}
	photo := call(t, h, "POST", "/v1/photos/upload-urls", "bob", uploadOne, 201)["data"].([]any)[0].(map[string]any)
	store.objects[photo["path"].(string)] = storage.Info{Size: 1000, ContentType: "image/jpeg"}
	body["photos"] = []map[string]any{{"photo_id": photo["photo_id"], "position": 1}}
	call(t, h, "POST", "/v1/me/onboarding", "bob", payload(t, body), 201)
	got := call(t, consumer, "GET", "/consumer", "alice", "", 200)["data"].([]any)
	if len(got) != 1 || got[0] != bob {
		t.Fatalf("eligible candidate missing: %#v", got)
	}
	if _, err := db.Exec(`UPDATE accounts SET status='frozen' WHERE user_id=$1`, bob); err != nil {
		t.Fatal(err)
	}
	got = call(t, consumer, "GET", "/consumer", "alice", "", 200)["data"].([]any)
	if len(got) != 0 {
		t.Fatal("frozen candidate exposed")
	}
	if _, err := db.Exec(`UPDATE accounts SET status='active' WHERE user_id=$1`, bob); err != nil {
		t.Fatal(err)
	}
	call(t, h, "DELETE", "/v1/photos/"+photo["photo_id"].(string), "bob", "", 200)
	got = call(t, consumer, "GET", "/consumer", "alice", "", 200)["data"].([]any)
	if len(got) != 0 {
		t.Fatal("candidate without an active photo exposed")
	}
	call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"sensitive_data","accepted":false}]}`, 200)
	call(t, consumer, "GET", "/consumer", "alice", "", 403)
}
