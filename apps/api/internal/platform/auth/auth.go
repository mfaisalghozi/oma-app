package auth

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"oma/apps/api/internal/platform/httpapi"
)

type Verifier interface {
	Verify(context.Context, string) (string, error)
}
type identityKey struct{}

func UserID(ctx context.Context) string { s, _ := ctx.Value(identityKey{}).(string); return s }
func Middleware(v Verifier, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Fields(r.Header.Get("Authorization"))
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			httpapi.Fail(w, 401, "UNAUTHORIZED")
			return
		}
		id, err := v.Verify(r.Context(), parts[1])
		if err != nil || !httpapi.ValidID(id) {
			httpapi.Fail(w, 401, "UNAUTHORIZED")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), identityKey{}, id)))
	})
}

type signingKey struct {
	key any
	alg string
}
type JWKS struct {
	URL, Issuer, Audience string
	Client                *http.Client
	mu                    sync.Mutex
	keys                  map[string]signingKey
	expires, lastAttempt  time.Time
}

func NewJWKS(url, issuer, audience string) *JWKS {
	return &JWKS{URL: url, Issuer: issuer, Audience: audience, Client: &http.Client{Timeout: 5 * time.Second}}
}
func (j *JWKS) Verify(ctx context.Context, raw string) (string, error) {
	if j.Issuer == "" || j.Audience == "" || j.URL == "" {
		return "", errors.New("auth configuration missing")
	}
	claims := new(jwt.RegisteredClaims)
	token, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, errors.New("missing kid")
		}
		return j.key(ctx, kid, t.Method.Alg())
	}, jwt.WithValidMethods([]string{"RS256", "ES256"}), jwt.WithIssuer(j.Issuer), jwt.WithAudience(j.Audience), jwt.WithExpirationRequired())
	if err != nil || !token.Valid || !httpapi.ValidID(claims.Subject) {
		return "", errors.New("invalid token")
	}
	return claims.Subject, nil
}
func (j *JWKS) key(ctx context.Context, kid, alg string) (any, error) {
	j.mu.Lock()
	defer j.mu.Unlock()
	now := time.Now()
	k, ok := j.keys[kid]
	if ok && now.Before(j.expires) && k.alg == alg {
		return k.key, nil
	}
	// Unknown key IDs trigger at most one refresh per minute. Expired caches fail closed.
	if now.Sub(j.lastAttempt) < time.Minute {
		return nil, errors.New("signing key unavailable")
	}
	j.lastAttempt = now
	req, err := http.NewRequestWithContext(ctx, "GET", j.URL, nil)
	if err != nil {
		return nil, err
	}
	res, err := j.Client.Do(req)
	if err != nil {
		return nil, errors.New("JWKS unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return nil, errors.New("JWKS unavailable")
	}
	var body struct {
		Keys []struct{ Kid, Kty, Alg, Use, N, E, Crv, X, Y string }
	}
	if err = json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&body); err != nil {
		return nil, errors.New("invalid JWKS")
	}
	keys := map[string]signingKey{}
	decode := base64.RawURLEncoding.DecodeString
	for _, v := range body.Keys {
		if v.Kid == "" || (v.Use != "" && v.Use != "sig") {
			continue
		}
		switch v.Kty {
		case "RSA":
			n, en := decode(v.N)
			e, ee := decode(v.E)
			if en != nil || ee != nil || len(n) < 256 || len(e) == 0 || len(e) > 4 || (v.Alg != "" && v.Alg != "RS256") {
				continue
			}
			exponent := 0
			for _, b := range e {
				exponent = exponent*256 + int(b)
			}
			if exponent < 3 || exponent%2 == 0 {
				continue
			}
			keys[v.Kid] = signingKey{&rsa.PublicKey{N: new(big.Int).SetBytes(n), E: exponent}, "RS256"}
		case "EC":
			x, ex := decode(v.X)
			y, ey := decode(v.Y)
			if v.Crv != "P-256" || ex != nil || ey != nil || len(x) != 32 || len(y) != 32 || (v.Alg != "" && v.Alg != "ES256") {
				continue
			}
			pub := &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(x), Y: new(big.Int).SetBytes(y)}
			if pub.Curve.IsOnCurve(pub.X, pub.Y) {
				keys[v.Kid] = signingKey{pub, "ES256"}
			}
		}
	}
	j.keys = keys
	j.expires = now.Add(5 * time.Minute)
	if k, ok = keys[kid]; !ok || k.alg != alg {
		return nil, errors.New("unknown signing key")
	}
	return k.key, nil
}
