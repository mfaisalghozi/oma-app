//go:build integration

package api_test

import (
	"os"
	"testing"
)

func TestApprovedCatalogServesSearchableOptionsWithoutDuplicateImports(t *testing.T) {
	db, handler := setup(t)
	call(t, handler, "POST", "/v1/me/initialize", "alice", "", 200)
	proposal, err := os.ReadFile("../../catalogs/initial-review.sql")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err = db.Exec(string(proposal)); err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct {
		query, field, expected string
		count                  int
	}{
		{"type=pronoun&q=She", "code", "she_her", 1},
		{"type=looking_for&q=Long-term", "code", "long_term_relationship", 1},
		{"type=religion&q=Buddhism", "code", "buddhism", 1},
		{"type=university&q=Gadjah", "name", "Universitas Gadjah Mada", 1},
		{"type=hobby&q=Hiking", "code", "hiking", 1},
	} {
		result := call(t, handler, "GET", "/v1/profile-data?"+tc.query, "alice", "", 200)["data"].(map[string]any)
		items := result["items"].([]any)
		if len(items) != tc.count || items[0].(map[string]any)[tc.field] != tc.expected {
			t.Fatalf("%s: %#v", tc.query, result)
		}
	}
	intentions := call(t, handler, "GET", "/v1/profile-data?type=looking_for&q=Short-term", "alice", "", 200)["data"].(map[string]any)["items"].([]any)
	if len(intentions) != 1 || intentions[0].(map[string]any)["label"] != "Short-term" {
		t.Fatalf("reviewed label was not applied: %#v", intentions)
	}
	religions := call(t, handler, "GET", "/v1/profile-data?type=religion&limit=100", "alice", "", 200)["data"].(map[string]any)["items"].([]any)
	if len(religions) != 9 {
		t.Fatalf("expected 9 approved religions, got %d", len(religions))
	}
	for _, item := range religions {
		if item.(map[string]any)["code"] == "confucianism" {
			t.Fatal("unapproved religion seeded")
		}
	}
	categories := call(t, handler, "GET", "/v1/profile-data?type=hobby_category&q=Outdoor", "alice", "", 200)["data"].(map[string]any)["items"].([]any)
	id := categories[0].(map[string]any)["id"].(string)
	hobbies := call(t, handler, "GET", "/v1/profile-data?type=hobby&category_id="+id+"&q=Hiking", "alice", "", 200)["data"].(map[string]any)["items"].([]any)
	if len(hobbies) != 1 || hobbies[0].(map[string]any)["category_id"] != id {
		t.Fatalf("incorrect category association: %#v", hobbies)
	}
}
