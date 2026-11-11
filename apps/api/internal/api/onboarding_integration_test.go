//go:build integration

package api_test

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"oma/apps/api/internal/api"
	"oma/apps/api/internal/platform/storage"
	"testing"
	"time"
)

func onboardingSetup(t *testing.T) (*sql.DB, http.Handler, *storageFixture, map[string]any) {
	t.Helper()
	db, _ := setup(t)
	store := &storageFixture{objects: map[string]storage.Info{}}
	h := api.NewWithStorage(db, identityFixture{}, store)
	seedDocuments(t, db)
	_, err := db.Exec(`INSERT INTO looking_for_options(id,code,label) VALUES('33333333-3333-4333-8333-333333333333','test_relationship','Test relationship'); INSERT INTO hobby_categories(id,code,label) VALUES('44444444-4444-4444-8444-444444444444','test_category','Test category'); INSERT INTO hobbies(id,category_id,code,label) VALUES('55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444','test_hobby','Test hobby')`)
	if err != nil {
		t.Fatal(err)
	}
	call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	first := func(kind string) string {
		result := call(t, h, "GET", "/v1/profile-data?type="+kind, "alice", "", 200)["data"].(map[string]any)
		return result["items"].([]any)[0].(map[string]any)["id"].(string)
	}
	photo := call(t, h, "POST", "/v1/photos/upload-urls", "alice", uploadOne, 201)["data"].([]any)[0].(map[string]any)
	store.objects[photo["path"].(string)] = storage.Info{Size: 1000, ContentType: "image/jpeg"}
	body := map[string]any{"profile": map[string]any{"full_name": "Example Person", "birthdate": "2000-01-15", "gender_id": first("gender"), "show_me_option_id": first("show_me"), "bio": "A test profile.", "height_cm": 175, "weight_kg": 70}, "looking_for_ids": []string{"33333333-3333-4333-8333-333333333333"}, "hobby_ids": []string{"55555555-5555-4555-8555-555555555555"}, "photos": []map[string]any{{"photo_id": photo["photo_id"], "position": 1}}, "location": map[string]any{"latitude": -6.2088, "longitude": 106.8456}}
	return db, h, store, body
}
func payload(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestOnboardingCompletesAtomicallyAndRejectsRepeatSubmission(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	got := call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)["data"].(map[string]any)
	if got["onboarding_completed"] != true || got["onboarding_completed_at"] == nil {
		t.Fatalf("missing completion: %#v", got)
	}
	state := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["next_action"] != "discovery" {
		t.Fatalf("wrong completion route: %#v", state)
	}
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 409)
	photos := call(t, h, "GET", "/v1/photos", "alice", "", 200)["data"].([]any)
	if len(photos) != 1 || photos[0].(map[string]any)["status"] != "active" {
		t.Fatalf("photo not activated: %#v", photos)
	}
}
func TestOnboardingReturnsAllValidationErrors(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	profile := body["profile"].(map[string]any)
	profile["full_name"] = "x"
	profile["birthdate"] = "2015-01-01"
	profile["gender_id"] = bob
	profile["height_cm"] = 99
	body["hobby_ids"] = []string{}
	got := call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 422)["error"].(map[string]any)
	if got["code"] != "ONBOARDING_VALIDATION_FAILED" {
		t.Fatalf("wrong validation code: %#v", got)
	}
	fields := map[string]bool{}
	for _, v := range got["details"].([]any) {
		fields[v.(map[string]any)["field"].(string)] = true
	}
	for _, name := range []string{"full_name", "birthdate", "gender_id", "height_cm", "hobby_ids"} {
		if !fields[name] {
			t.Errorf("missing error for %s", name)
		}
	}
}
func TestOnboardingRequiresConsentAndUploadedObjects(t *testing.T) {
	_, h, store, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"sensitive_data","accepted":false}]}`, 200)
	got := call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 403)
	if got["error"].(map[string]any)["code"] != "CONSENT_REQUIRED" {
		t.Fatal("missing consent error")
	}
	call(t, h, "POST", "/v1/me/consents", "alice", acceptAll, 200)
	store.objects = map[string]storage.Info{}
	got = call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 422)
	if got["error"].(map[string]any)["code"] != "PHOTO_UPLOAD_INCOMPLETE" {
		t.Fatal("missing object not rejected")
	}
}
func TestOnboardingRollsBackAfterDatabaseFailure(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	_, err := db.Exec(`CREATE FUNCTION fail_completion() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected test failure'; END; $$; CREATE TRIGGER fail_completion BEFORE UPDATE ON accounts FOR EACH ROW WHEN (NEW.onboarding_completed_at IS NOT NULL) EXECUTE FUNCTION fail_completion()`)
	if err != nil {
		t.Fatal(err)
	}
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 500)
	state := call(t, h, "POST", "/v1/me/initialize", "alice", "", 200)["data"].(map[string]any)
	if state["onboarding_completed"] != false {
		t.Fatal("failure committed completion")
	}
	photos := call(t, h, "GET", "/v1/photos", "alice", "", 200)["data"].([]any)
	if photos[0].(map[string]any)["status"] != "pending_upload" {
		t.Fatal("failure committed photo activation")
	}
	if _, err = db.Exec(`DROP TRIGGER fail_completion ON accounts; DROP FUNCTION fail_completion()`); err != nil {
		t.Fatal(err)
	}
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
}

func TestOnboardingRejectsAnotherAccountsPhoto(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/initialize", "bob", "", 200)
	call(t, h, "POST", "/v1/me/consents", "bob", acceptAll, 200)
	other := call(t, h, "POST", "/v1/photos/upload-urls", "bob", uploadOne, 201)["data"].([]any)[0].(map[string]any)
	body["photos"] = []map[string]any{{"photo_id": other["photo_id"], "position": 1}}
	got := call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 422)
	if got["error"].(map[string]any)["code"] != "PHOTO_UPLOAD_INCOMPLETE" {
		t.Fatal("foreign photo not rejected")
	}
}

func TestOnboardingRejectsCaseVariantsOfSamePhoto(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	old := body["photos"].([]map[string]any)[0]["photo_id"]
	id := "abcdefab-cdef-4abc-8def-abcdefabcdef"
	if _, err := db.Exec(`UPDATE photos SET id=$1 WHERE id=$2`, id, old); err != nil {
		t.Fatal(err)
	}
	body["photos"] = []map[string]any{{"photo_id": id, "position": 1}, {"photo_id": "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF", "position": 2}}
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 422)
}

func TestOnboardingCalendarAgeAndLocationValidation(t *testing.T) {
	for _, tc := range []struct {
		name        string
		years, days int
		status      int
	}{{"exactly eighteen", -18, 0, 201}, {"eighteen tomorrow", -18, 1, 422}, {"future birthdate", 0, 1, 422}} {
		t.Run(tc.name, func(t *testing.T) {
			_, h, _, body := onboardingSetup(t)
			body["profile"].(map[string]any)["birthdate"] = time.Now().UTC().AddDate(tc.years, 0, tc.days).Format("2006-01-02")
			call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), tc.status)
		})
	}
	_, h, _, body := onboardingSetup(t)
	body["location"] = map[string]any{"latitude": 91, "longitude": 181}
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 422)
}
