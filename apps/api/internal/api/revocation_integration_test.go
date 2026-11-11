//go:build integration

package api_test

import (
	"net/http"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"testing"
)

func TestConsentRevocationRestrictsProcessingAndCanBeReaccepted(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	call(t, h, "POST", "/v1/me/consents/revocations", "alice", `{"consent_types":["terms","unsupported"]}`, 400)
	state := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "discovery" {
		t.Fatal("invalid batch partly revoked consent")
	}
	got := call(t, h, "POST", "/v1/me/consents/revocations", "alice", `{"consent_types":["sensitive_data"],"reason":"User requested revocation"}`, 200)["data"].(map[string]any)
	if got["revoked"].([]any)[0].(map[string]any)["revoked_at"] == nil {
		t.Fatal("missing server revocation time")
	}
	state = call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "accept_consents" {
		t.Fatal("revocation did not change routing")
	}
	statuses := call(t, h, "GET", "/v1/me/consents", "alice", "", 200)["data"].([]any)
	for _, row := range statuses {
		v := row.(map[string]any)
		if v["type"] == "sensitive_data" && (v["decision"] != "revoked" || v["revoked_at"] == nil || v["accepted_at"] != nil) {
			t.Fatalf("invalid revoked status: %#v", v)
		}
	}
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"blocked edit"}`, 403)
	call(t, h, "PUT", "/v1/me/location", "alice", `{"latitude":0,"longitude":0}`, 403)
	call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 403)
	id := body["photos"].([]map[string]any)[0]["photo_id"].(string)
	call(t, h, "PATCH", "/v1/photos/"+id, "alice", `{"is_primary":true}`, 403)
	eligibility := &discovery.Eligibility{DB: db}
	consumer := auth.Middleware(identityFixture{}, eligibility.Guard(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { httpapi.Data(w, 200, true) })))
	call(t, consumer, "GET", "/consumer", "alice", "", 403)
	call(t, h, "DELETE", "/v1/me/location", "alice", "", 200)
	call(t, h, "DELETE", "/v1/photos/"+id, "alice", "", 200)
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"allowed edit"}`, 200)
	call(t, h, "PUT", "/v1/me/location", "alice", `{"latitude":0,"longitude":0}`, 200)
	call(t, consumer, "GET", "/consumer", "alice", "", 200)
}
