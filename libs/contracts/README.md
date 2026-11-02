# API contracts

`openapi.yaml` is the shared OpenAPI contract for the Go API, Flutter mobile,
and future web frontend. Update it when API request or response shapes change.

Nx tracks `contracts` as an implicit dependency of `api`, `mobile`, and `web`,
so schema changes mark consumers as affected. Client generation and schema
validation can be added here when their tooling is chosen.
