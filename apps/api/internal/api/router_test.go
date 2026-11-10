package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"oma/apps/api/internal/api"
)

func TestRouterErrorsUseAPIEnvelope(t *testing.T) {
	handler := api.New(nil, nil)
	for _, tc := range []struct {
		method, path, code string
		status             int
	}{
		{"GET", "/missing", "NOT_FOUND", 404},
		{"POST", "/health", "METHOD_NOT_ALLOWED", 405},
		{"GET", "/v1/photos/", "NOT_FOUND", 404},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, httptest.NewRequest(tc.method, tc.path, nil))
			if response.Code != tc.status {
				t.Fatalf("status %d, want %d", response.Code, tc.status)
			}
			var body struct {
				Error struct {
					Code string `json:"code"`
				} `json:"error"`
			}
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body.Error.Code != tc.code {
				t.Fatalf("error %q, want %q", body.Error.Code, tc.code)
			}
		})
	}
}

func TestHealthSupportsGetAndHead(t *testing.T) {
	handler := api.New(nil, nil)
	for _, method := range []string{http.MethodGet, http.MethodHead} {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(method, "/health", nil))
		if method == http.MethodHead && response.Body.Len() != 0 {
			t.Fatal("HEAD returned a response body")
		}
		if response.Code != 200 {
			t.Fatalf("%s: status %d", method, response.Code)
		}
	}
}
