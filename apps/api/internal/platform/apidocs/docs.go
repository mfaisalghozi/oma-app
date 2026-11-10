// Package apidocs serves Swagger UI and the shared OpenAPI contract.
package apidocs

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files/v2"
	"oma/libs/contracts"
)

const index = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>OMA API documentation</title>
<link rel="stylesheet" href="./swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="./swagger-ui-bundle.js"></script>
<script>
window.onload = function () {
  window.ui = SwaggerUIBundle({
    url: "./openapi.yaml",
    dom_id: "#swagger-ui",
    deepLinking: true,
    persistAuthorization: false,
    validatorUrl: null,
    queryConfigEnabled: false,
    presets: [SwaggerUIBundle.presets.apis],
    layout: "BaseLayout"
  });
};
</script>
</body>
</html>`

// Register exposes read-only documentation routes. API authentication remains on API routes.
func Register(router *gin.Engine) {
	spec := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/yaml; charset=utf-8")
		http.ServeContent(w, r, "openapi.yaml", time.Time{}, strings.NewReader(contracts.OpenAPI))
	})
	assets := http.StripPrefix("/swagger/", http.FileServer(http.FS(swaggerFiles.FS)))
	docs := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/swagger/", "/swagger/index.html":
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			http.ServeContent(w, r, "index.html", time.Time{}, strings.NewReader(index))
		case "/swagger/openapi.yaml":
			spec.ServeHTTP(w, r)
		default:
			assets.ServeHTTP(w, r)
		}
	})
	router.Match([]string{http.MethodGet, http.MethodHead}, "/swagger", func(c *gin.Context) { c.Redirect(http.StatusTemporaryRedirect, "/swagger/index.html") })
	router.Match([]string{http.MethodGet, http.MethodHead}, "/swagger/*path", gin.WrapH(docs))
	router.Match([]string{http.MethodGet, http.MethodHead}, "/openapi.yaml", gin.WrapH(spec))
}
