//go:build integration

package api_test

import "testing"

func TestProfilePatchChangesOnlySubmittedFieldsAndReplacesRelations(t *testing.T) {
	db, h, _, body := onboardingSetup(t)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	before := call(t, h, "GET", "/v1/me/profile", "alice", "", 200)["data"].(map[string]any)
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"Updated biography"}`, 200)
	after := call(t, h, "GET", "/v1/me/profile", "alice", "", 200)["data"].(map[string]any)
	if after["bio"] != "Updated biography" || after["height_cm"] != before["height_cm"] || after["full_name"] != before["full_name"] {
		t.Fatalf("unsubmitted fields changed: %#v", after)
	}
	_, err := db.Exec(`INSERT INTO looking_for_options(id,code,label) VALUES('66666666-6666-4666-8666-666666666666','test_new_intention','New intention'); INSERT INTO hobbies(id,category_id,code,label) VALUES('77777777-7777-4777-8777-777777777777','44444444-4444-4444-8444-444444444444','test_new_hobby','New hobby')`)
	if err != nil {
		t.Fatal(err)
	}
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"looking_for_ids":["66666666-6666-4666-8666-666666666666"],"hobby_ids":["77777777-7777-4777-8777-777777777777"]}`, 200)
	after = call(t, h, "GET", "/v1/me/profile", "alice", "", 200)["data"].(map[string]any)
	for field, id := range map[string]string{"looking_for": "66666666-6666-4666-8666-666666666666", "hobbies": "77777777-7777-4777-8777-777777777777"} {
		items := after[field].([]any)
		if len(items) != 1 || items[0].(map[string]any)["id"] != id {
			t.Fatalf("%s not replaced: %#v", field, items)
		}
	}
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"must roll back","university_id":"22222222-2222-4222-8222-222222222222"}`, 422)
	after = call(t, h, "GET", "/v1/me/profile", "alice", "", 200)["data"].(map[string]any)
	if after["bio"] != "Updated biography" {
		t.Fatal("invalid request partially persisted")
	}
}
func TestProfilePatchRequiresCompletionAndConsentAndRejectsReadOnlyFields(t *testing.T) {
	_, h, _, body := onboardingSetup(t)
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"New biography"}`, 403)
	call(t, h, "POST", "/v1/me/onboarding", "alice", payload(t, body), 201)
	for _, bad := range []string{`{"birthdate":"2000-01-01"}`, `{"hobby_ids":[]}`, `{"height_cm":null}`, `{"weight_kg":"heavy"}`, `{}`} {
		call(t, h, "PATCH", "/v1/me/profile", "alice", bad, 422)
	}
	call(t, h, "POST", "/v1/me/consents", "alice", `{"consents":[{"type":"sensitive_data","accepted":false}]}`, 200)
	call(t, h, "PATCH", "/v1/me/profile", "alice", `{"bio":"New biography"}`, 403)
}
