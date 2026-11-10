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



## Legal document registry

An operator must insert approved legal documents into `consent_documents` before
onboarding is enabled. Supported types are `terms`, `privacy`, and `sensitive_data`,
following the technical specification. Each row contains its type, version, title,
legal-document URL, `required`, and `active` flags. There may be only one active
version per type. Update active flags in a transaction when publishing new versions.
Legal documents themselves are hosted separately; the API only returns their URLs.

There are no fabricated production agreements or versions in migrations. An empty
required-document registry fails closed. `POST /v1/me/consents` accepts decisions
only, resolves versions on the backend, and records server timestamps. Re-accepting
appends history; a rejection or newer required document version requires consent
again. Consent history cannot be updated or deleted through ordinary SQL operations.
Consent revocation and its processing policy are tracked separately in ONB-BE-12.

## Master data

`GET /v1/profile-data?type=...` supports `gender`, `pronoun`, `show_me`,
`looking_for`, `university`, `religion`, `personality`, `hobby_category`, and `hobby`.
It requires an initialized active account. Search is a case-insensitive literal
substring. Pagination defaults to page 1 and limit 20, with a maximum limit of 100.
`category_id` is accepted only for hobbies. Inactive records are excluded.

Migration 003 seeds documented gender/show-me values, the initial He/Him pronoun,
and MBTI codes (INFJ uses the documented Advocate label). Migration 009 seeds
Outdoor, Indoor, and Gaming from PRD M08.

On 2026-11-09, the user approved the initial pronoun, looking-for, religion,
university and hobby catalogs. The approved explicit seed was applied to the OMA
Supabase database in one transaction and verified after commit. See
[approved catalog and application receipt](catalogs/README.md) for exact values,
counts and maintenance rules. Schema migrations do not apply this separate seed
script automatically. The university set is intentionally limited to the three
approved initial entries.
