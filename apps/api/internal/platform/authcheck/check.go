// Package authcheck inspects public Supabase Auth flags without changing the project.
package authcheck

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Finding struct {
	Name   string `json:"name"`
	Passed bool   `json:"passed"`
}

type Report struct {
	Scope               string    `json:"scope"`
	PublicSettingsMatch bool      `json:"public_settings_match"`
	Checks              []Finding `json:"checks"`
}

// Check uses only the publishable/legacy anon key. Never supply a service-role key.
// Matching flags do not verify provider credentials, SMTP, redirects or live sign-in.
func Check(ctx context.Context, projectURL, publicKey string) (Report, error) {
	u, err := url.Parse(projectURL)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return Report{}, errors.New("invalid Supabase project URL")
	}
	loopback := u.Hostname() == "localhost"
	if ip := net.ParseIP(u.Hostname()); ip != nil {
		loopback = ip.IsLoopback()
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && loopback) {
		return Report{}, errors.New("Supabase URL must use HTTPS; HTTP is allowed only for local checks")
	}
	if strings.TrimSpace(publicKey) == "" {
		return Report{}, errors.New("SUPABASE_PUBLISHABLE_KEY is required")
	}
	u.Path = "/auth/v1/settings"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return Report{}, errors.New("cannot create Auth settings request")
	}
	req.Header.Set("apikey", publicKey)
	client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	if err != nil {
		return Report{}, errors.New("Auth settings request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return Report{}, errors.New("Auth settings endpoint did not return HTTP 200")
	}
	var settings struct {
		External struct {
			Email  *bool `json:"email"`
			Google *bool `json:"google"`
			Apple  *bool `json:"apple"`
		} `json:"external"`
		DisableSignup     *bool `json:"disable_signup"`
		MailerAutoconfirm *bool `json:"mailer_autoconfirm"`
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, (64<<10)+1))
	if err != nil || len(raw) > 64<<10 || json.Unmarshal(raw, &settings) != nil {
		return Report{}, errors.New("invalid Auth settings response")
	}
	if settings.External.Email == nil || settings.External.Google == nil || settings.External.Apple == nil || settings.DisableSignup == nil || settings.MailerAutoconfirm == nil {
		return Report{}, errors.New("Auth settings response is missing required flags")
	}
	report := Report{Scope: "public provider/email flags only; excludes credentials, password rules, SMTP, redirects and live flows", PublicSettingsMatch: true, Checks: []Finding{
		{"email_enabled", *settings.External.Email},
		{"confirmation_required", !*settings.MailerAutoconfirm},
		{"signup_enabled", !*settings.DisableSignup},
		{"google_enabled", *settings.External.Google},
		{"apple_enabled", *settings.External.Apple},
	}}
	for _, finding := range report.Checks {
		if !finding.Passed {
			report.PublicSettingsMatch = false
		}
	}
	return report, nil
}
