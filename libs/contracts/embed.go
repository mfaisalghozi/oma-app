// Package contracts embeds the shared API contract for runtime documentation.
package contracts

import _ "embed"

// OpenAPI is the canonical API contract embedded when the API is built.
//
//go:embed openapi.yaml
var OpenAPI string
