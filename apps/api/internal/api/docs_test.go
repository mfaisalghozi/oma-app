package api_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"oma/apps/api/internal/api"
)

func TestSwaggerDocumentationIsAvailableWithoutAuthentication(t *testing.T) {
	handler := api.New(nil, nil)
	for _, tc := range []struct{ path, contentType, contains string }{
		{"/swagger/index.html", "text/html", "SwaggerUIBundle"},
		{"/openapi.yaml", "application/yaml", "openapi: 3.0.3"},
		{"/swagger/swagger-ui.css", "text/css", "swagger-ui"},
		{"/swagger/swagger-ui-bundle.js", "javascript", "SwaggerUIBundle"},
	} {
		t.Run(tc.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, tc.path, nil))
			if response.Code != 200 {
				t.Fatalf("status %d: %s", response.Code, response.Body.String())
			}
			if !strings.Contains(response.Header().Get("Content-Type"), tc.contentType) || !strings.Contains(response.Body.String(), tc.contains) {
				t.Fatalf("unexpected documentation response for %s", tc.path)
			}
		})
	}
}

func TestSwaggerLinksAndHeadRequestsWork(t *testing.T) {
	handler := api.New(nil, nil)
	redirect := httptest.NewRecorder()
	handler.ServeHTTP(redirect, httptest.NewRequest("GET", "/swagger", nil))
	if redirect.Code != 307 || redirect.Header().Get("Location") != "/swagger/index.html" {
		t.Fatalf("unexpected docs redirect: %#v", redirect.Result())
	}
	for _, path := range []string{"/swagger/", "/swagger/index.html", "/swagger/openapi.yaml", "/openapi.yaml", "/swagger/swagger-ui.css"} {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest("HEAD", path, nil))
		if response.Code != 200 || response.Body.Len() != 0 {
			t.Fatalf("HEAD %s: status=%d bytes=%d", path, response.Code, response.Body.Len())
		}
	}
	spec := httptest.NewRecorder()
	handler.ServeHTTP(spec, httptest.NewRequest("GET", "/swagger/openapi.yaml", nil))
	for _, expected := range []string{"/v1/me/onboarding:", "supabaseJWT:", "scheme: bearer", "url: /"} {
		if !strings.Contains(spec.Body.String(), expected) {
			t.Fatalf("missing OpenAPI content %q", expected)
		}
	}
	unauthorized := httptest.NewRecorder()
	handler.ServeHTTP(unauthorized, httptest.NewRequest("GET", "/v1/me/profile", nil))
	if unauthorized.Code != 401 {
		t.Fatalf("protected endpoint status=%d", unauthorized.Code)
	}
}
