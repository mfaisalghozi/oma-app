# API contracts

`openapi.yaml` is the shared OpenAPI contract for the Go API, Flutter mobile,
and future web frontend. Update it when API request or response shapes change.

Nx tracks `contracts` as an implicit dependency of `api`, `mobile`, and `web`,
so schema changes mark consumers as affected. Client generation and schema
validation can be added here when their tooling is chosen.

The `oma/libs/contracts` Go module embeds `openapi.yaml` directly for the API's
Swagger UI at `/swagger/index.html` and YAML at `/openapi.yaml`. The API uses a
local `replace` directive to this directory; no generated copy of the contract is
maintained. Rebuild/restart the API after editing the YAML. Its relative server
URL `/` makes Try it out target the API origin that served the docs.
