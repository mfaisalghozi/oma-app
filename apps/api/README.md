# Oma backend

The runtime uses Supabase PostgreSQL, Supabase Auth and private Supabase Storage.
Local PostgreSQL/PostGIS is used only for disposable integration tests.

## Runtime setup

Install Go 1.26+ and run `npm ci` at the monorepo root. From `apps/api`, run
`go mod download`. Configure the variables in `.env.example` in your shell or
secret manager. The Go process does not automatically read `.env` files.

Use a direct or session-mode Supabase database connection for migrations.
The backend needs a trusted database role with access to its tables. RLS is enabled
with no client policies: mobile clients must access application data through Go.
Keep that database credential on the backend; never put it in Flutter or web code.

From the monorepo root:

```sh
npx nx run api:migrate
npm run api
curl http://localhost:8080/health
```

Supabase must use ES256 or RS256 asymmetric JWT signing. The API validates the
signature, issuer, `authenticated` audience, expiry and UUID subject using cached
JWKS. Legacy HS256 tokens are intentionally rejected. Provider configuration and
end-to-end sign-in must be verified in staging separately.

`POST /v1/me/initialize` requires a Bearer access token and is idempotent. Consent
routing is fail closed until the consent ticket wires the active document policy.
Suspended accounts remain restricted until their status is changed explicitly;
`suspended_until` is returned as metadata and does not automatically lift a ban.

Migrations run explicitly, not on API startup. Each up migration is transactional
and tracked in `schema_migrations`. Revert the latest migration only in a disposable
or reviewed environment with `npx nx run api:migrate -- --direction=down`.

## Automated checks

```sh
# From apps/api; no database required for unit tests
go test -race ./...
go vet ./...
go build ./...
```

From the monorepo root, start a disposable test database and run integration tests:

```sh
docker compose -f infrastructure/docker/compose.test.yaml up -d --wait
export TEST_DATABASE_URL='postgresql://postgres:oma_test@127.0.0.1:55432/oma_test?sslmode=disable'
npx nx run api:test-integration
docker compose -f infrastructure/docker/compose.test.yaml down
```

The PostGIS image uses amd64 emulation on Apple Silicon. Tests create isolated
schemas and delete only those schemas on cleanup. **Never** set `TEST_DATABASE_URL`
to staging or production. Integration tests require this variable and fail rather
than silently skip when it is missing. The integration target is never cached.


