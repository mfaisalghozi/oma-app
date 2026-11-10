package auth_test

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"oma/apps/api/internal/platform/auth"
)

func TestSupabaseJWTValidation(t *testing.T) {
	private, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	var requests atomic.Int32
	keys := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		enc := base64.RawURLEncoding.EncodeToString
		json.NewEncoder(w).Encode(map[string]any{"keys": []any{map[string]any{"kid": "current", "kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig", "x": enc(private.X.FillBytes(make([]byte, 32))), "y": enc(private.Y.FillBytes(make([]byte, 32)))}}})
	}))
	defer keys.Close()
	verifier := auth.NewJWKS(keys.URL, "https://project.supabase.co/auth/v1", "authenticated")
	valid := func() jwt.RegisteredClaims {
		return jwt.RegisteredClaims{Subject: "11111111-1111-4111-8111-111111111111", Issuer: "https://project.supabase.co/auth/v1", Audience: jwt.ClaimStrings{"authenticated"}, ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}
	}
	sign := func(c jwt.RegisteredClaims, kid string) string {
		t.Helper()
		token := jwt.NewWithClaims(jwt.SigningMethodES256, c)
		token.Header["kid"] = kid
		raw, err := token.SignedString(private)
		if err != nil {
			t.Fatal(err)
		}
		return raw
	}
	for i := 0; i < 2; i++ {
		id, err := verifier.Verify(context.Background(), sign(valid(), "current"))
		if err != nil || id != "11111111-1111-4111-8111-111111111111" {
			t.Fatalf("valid session rejected: %v", err)
		}
	}
	if requests.Load() != 1 {
		t.Fatal("valid cached key fetched repeatedly")
	}
	for _, tc := range []struct {
		name   string
		change func(*jwt.RegisteredClaims)
	}{
		{"wrong issuer", func(c *jwt.RegisteredClaims) { c.Issuer = "https://attacker.invalid" }},
		{"wrong audience", func(c *jwt.RegisteredClaims) { c.Audience = jwt.ClaimStrings{"another-app"} }},
		{"expired", func(c *jwt.RegisteredClaims) { c.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Hour)) }},
		{"missing expiration", func(c *jwt.RegisteredClaims) { c.ExpiresAt = nil }},
		{"invalid identity", func(c *jwt.RegisteredClaims) { c.Subject = "not-a-user-id" }},
		{"not yet valid", func(c *jwt.RegisteredClaims) { c.NotBefore = jwt.NewNumericDate(time.Now().Add(time.Hour)) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := valid()
			tc.change(&c)
			if _, err := verifier.Verify(context.Background(), sign(c, "current")); err == nil {
				t.Fatal("invalid token accepted")
			}
		})
	}
	if _, err := verifier.Verify(context.Background(), sign(valid(), "unknown")); err == nil {
		t.Fatal("unknown key accepted")
	}
	if _, err := verifier.Verify(context.Background(), "not-a-jwt"); err == nil {
		t.Fatal("malformed token accepted")
	}
}
