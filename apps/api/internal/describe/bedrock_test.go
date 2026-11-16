package describe_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	describe "oma/apps/api/internal/describe"
	"strings"
	"testing"
	"time"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func response(code int, body string) *http.Response {
	return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}
}
func TestBedrockStructuredRequestAndRetry(t *testing.T) {
	attempts := 0
	b, err := describe.NewBedrock(describe.BedrockConfig{APIKey: "fixture-key", Transport: transport(func(r *http.Request) (*http.Response, error) {
		attempts++
		if r.URL.String() != "https://bedrock-mantle.ap-northeast-1.api.aws/anthropic/v1/messages" || r.Header.Get("x-api-key") != "fixture-key" {
			t.Fatal("wrong endpoint/authentication")
		}
		deadline, ok := r.Context().Deadline()
		if !ok || time.Until(deadline) > 10*time.Second {
			t.Fatal("missing bounded attempt")
		}
		var body map[string]json.RawMessage
		if json.NewDecoder(r.Body).Decode(&body) != nil || len(body["output_config"]) == 0 {
			t.Fatal("missing structured schema")
		}
		if attempts < 3 {
			return response(503, `secret failure`), nil
		}
		return response(200, `{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"version\":\"v1\"}"}]}`), nil
	})})
	if err != nil {
		t.Fatal(err)
	}
	got, err := b.Generate(context.Background(), `{"query":"hiking"}`)
	if err != nil || string(got) != `{"version":"v1"}` || attempts != 3 {
		t.Fatalf("got %s, %v, attempts %d", got, err, attempts)
	}
}
func TestBedrockRejectsTruncationAndDoesNotRetryClientErrors(t *testing.T) {
	for _, tc := range []struct {
		status int
		body   string
	}{{400, "secret-invalid-key"}, {200, `{"stop_reason":"max_tokens","content":[{"type":"text","text":"{}"}]}`}, {200, `{"stop_reason":"end_turn","content":[{"type":"tool_use"}]}`}} {
		calls := 0
		b, _ := describe.NewBedrock(describe.BedrockConfig{APIKey: "fixture", Transport: transport(func(*http.Request) (*http.Response, error) { calls++; return response(tc.status, tc.body), nil })})
		_, err := b.Generate(context.Background(), "query")
		if err != describe.ErrProvider || calls != 1 {
			t.Fatalf("unexpected %v calls %d", err, calls)
		}
	}
}

func TestBedrockBoundsFailuresAndCancellation(t *testing.T) {
	calls := 0
	b, _ := describe.NewBedrock(describe.BedrockConfig{APIKey: "fixture", Transport: transport(func(*http.Request) (*http.Response, error) { calls++; return response(503, "not logged"), nil })})
	if _, err := b.Generate(context.Background(), "hiking"); err != describe.ErrProvider || calls != 3 {
		t.Fatalf("retry budget violated: %d %v", calls, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := b.Generate(ctx, "hiking"); err != describe.ErrProvider || calls != 3 {
		t.Fatalf("canceled request reached provider: %d %v", calls, err)
	}
	if _, err := describe.NewBedrock(describe.BedrockConfig{}); err != describe.ErrProvider {
		t.Fatal("missing credential accepted")
	}
}
