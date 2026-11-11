package authcheck_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"oma/apps/api/internal/platform/authcheck"
)

func TestPublicAuthSettingsReportPendingProvidersAndConfirmation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.URL.Path != "/auth/v1/settings" || r.Header.Get("apikey") != "public-fixture-key" {
			t.Errorf("unexpected settings request")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"external":{"email":true,"google":false,"apple":false},"disable_signup":false,"mailer_autoconfirm":false}`))
	}))
	defer server.Close()
	report, err := authcheck.Check(context.Background(), server.URL, "public-fixture-key")
	if err != nil {
		t.Fatal(err)
	}
	if report.PublicSettingsMatch {
		t.Fatal("disabled OAuth providers reported ready")
	}
	expected := map[string]bool{"email_enabled": true, "confirmation_required": true, "signup_enabled": true, "google_enabled": false, "apple_enabled": false}
	if len(report.Checks) != len(expected) {
		t.Fatalf("unexpected checks: %#v", report)
	}
	for _, check := range report.Checks {
		want, exists := expected[check.Name]
		if !exists || check.Passed != want {
			t.Fatalf("unexpected check: %#v", check)
		}
	}
}

func TestPublicAuthSettingsFailClosedOnIncompleteResponses(t *testing.T) {
	for _, body := range []string{`{}`, `{"external":{"email":true,"google":true,"apple":true}}`, `{"external":{"email":true,"google":true,"apple":true},"disable_signup":false,"mailer_autoconfirm":null}`, `not json`} {
		t.Run(body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(body)) }))
			defer server.Close()
			if _, err := authcheck.Check(context.Background(), server.URL, "public-fixture-key"); err == nil {
				t.Fatal("incomplete settings accepted")
			}
		})
	}
}

func TestPublicAuthSettingsDoesNotFollowRedirects(t *testing.T) {
	leaked := false
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { leaked = true }))
	defer target.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, http.StatusFound) }))
	defer server.Close()
	if _, err := authcheck.Check(context.Background(), server.URL, "public-fixture-key"); err == nil {
		t.Fatal("redirect accepted")
	}
	if leaked {
		t.Fatal("API key sent to redirected target")
	}
}

func TestMatchingPublicFlagsHaveLimitedScope(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"external":{"email":true,"google":true,"apple":true},"disable_signup":false,"mailer_autoconfirm":false}`))
	}))
	defer server.Close()
	report, err := authcheck.Check(context.Background(), server.URL, "public-fixture-key")
	if err != nil {
		t.Fatal(err)
	}
	if !report.PublicSettingsMatch || report.Scope == "" {
		t.Fatalf("unexpected report: %#v", report)
	}
}
