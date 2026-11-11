//go:build integration

package api_test

import (
	"net/http"
	"oma/apps/api/internal/discovery"
	"oma/apps/api/internal/platform/auth"
	"oma/apps/api/internal/platform/httpapi"
	"testing"
)

func TestLocationUpdateValidationConsentAndDeletion(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	eligibility := &discovery.Eligibility{DB: db}
	consumer := auth.Middleware(identityFixture{}, eligibility.Guard(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { httpapi.Data(w, 200, map[string]bool{"eligible": true}) })))
	got := call(t, h, "PUT", "/v1/me/location", "alice", `{"latitude":0,"longitude":0}`, 200)["data"].(map[string]any)
	if got["updated_at"] == nil || got["latitude"] != nil || got["longitude"] != nil {
		t.Fatal("location response exposes coordinates or lacks timestamp")
	}
	for _, bad := range []string{`{"latitude":91,"longitude":0}`, `{"latitude":0,"longitude":-181}`, `{"latitude":0}`, `{"latitude":"bad","longitude":106}`, `{"latitude":1e309,"longitude":106}`} {
		call(t, h, "PUT", "/v1/me/location", "alice", bad, 422)
	}
	call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"sensitive_data","accepted":false}]}`, 200)
	call(t, h, "PUT", "/v1/me/location", "alice", `{"latitude":-6,"longitude":106}`, 403)
	call(t, h, "DELETE", "/v1/me/location", "alice", "", 200)
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	out := call(t, consumer, "GET", "/consumer", "alice", "", 403)
	if out["error"].(map[string]any)["code"] != "LOCATION_REQUIRED" {
		t.Fatalf("missing location not handled: %#v", out)
	}
	call(t, h, "DELETE", "/v1/me/location", "alice", "", 200)
	call(t, h, "PUT", "/v1/me/location", "alice", `{"latitude":-90,"longitude":180}`, 200)
	call(t, consumer, "GET", "/consumer", "alice", "", 200)
}
