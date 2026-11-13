# Oma backend

The runtime uses Supabase PostgreSQL, Supabase Auth and private Supabase Storage.
Local PostgreSQL/PostGIS is used only for disposable integration tests.


## HTTP framework

The API uses [Gin](https://gin-gonic.com/en/docs/) 1.12 for routing and request
middleware. Existing domain handlers retain the standard `http.Handler` boundary;
the Gin adapter transfers route parameters into request path values. JWT identity,
account restrictions, strict JSON decoding, and response envelopes remain shared.
Gin applies a ten-second request context deadline and sanitized panic recovery.
Unknown routes and unsupported methods return JSON API errors. Automatic path
redirects are disabled; GET routes also accept HEAD without a response body.
Proxy headers are not trusted by default. No request-body or authorization-header
logging is enabled. Set `GIN_MODE=release` in deployment to suppress debug route
registration output; server timeouts and graceful shutdown remain configured in
`cmd/api`.

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

Use a database that has no tables in `public` for `TEST_DATABASE_URL`. Each test
creates its own schema and sets `search_path` to `<test schema>,public`. If
`public` holds migrated tables, a test that drops its own tables falls through to
the `public` copies and passes when it must fail.

## Local database for development

The mobile app needs a reachable API with seeded data. Use a disposable local
database. Do not point this at the shared Supabase project.

```sh
# 1. Start Postgres/PostGIS on 127.0.0.1:55432
docker compose -f infrastructure/docker/compose.test.yaml up -d --wait

# 2. Create and migrate a development database
docker exec oma-be-integration-postgres-1 \
  psql -U postgres -d postgres -c 'CREATE DATABASE oma_dev;'
export DATABASE_URL='postgresql://postgres:oma_test@127.0.0.1:55432/oma_dev'
go run ./cmd/migrate

# 3. Apply the two seed scripts. Migrations do not apply them.
./scripts/seed-local.sh

# 4. Start the API. It needs the real Supabase URL and service key.
export SUPABASE_URL='https://<project>.supabase.co'
export SUPABASE_SERVICE_ROLE_KEY='...'
go run ./cmd/api
```

Keep the development database separate from `TEST_DATABASE_URL`. The first run
needs `profile-photos` to exist in the Supabase project, because startup verifies
the bucket and exits when the check fails.

`catalogs/dev-consent-documents.sql` holds placeholder legal documents for local
work only. It is not approved legal copy and must not reach a shared environment.

`scripts/seed-local.sh` applies both files to `DATABASE_URL` and stops on the
first error. The API logs a warning at startup when no consent document is
active, because the symptom of a missing registry row (every account stuck at
`accept_consents`) is otherwise hard to trace.



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

## Photo storage

Apply the reviewed `infrastructure/supabase/profile-storage.sql` to your selected
Supabase project. Set the server-only `SUPABASE_SERVICE_ROLE_KEY`. Startup verifies
that `profile-photos` is private with image MIME restrictions and a 10 MiB limit.
Review existing Storage policies: clients must not have unrestricted writes or
upserts that bypass backend-generated upload paths.

Photos are reserved under `JWT-sub/photo-UUID.ext`. The request filename is never
used as a path. Account-row locking serializes reservations and enforces the six
active/reserved photo limit, including concurrent requests. Signing failures roll
back the reservations. Capabilities are returned to the caller, never persisted or
logged. Pending photos can refresh their upload capability without reserving a new
slot. Active photo positions are unique; primary-photo changes and swaps are atomic.

Supabase's [signed upload capabilities](https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl)
last two hours; `expires_at` is read from the provider's returned capability. Read
URLs expire after five minutes. The backend never claims it can revoke an issued
capability early. A deleted reservation remains tombstoned, so an old upload token
cannot reactivate or expose it. Object deletion is retried by repeating DELETE if
Storage returns 503; database metadata is already hidden. A previously issued
upload capability may recreate that tombstoned object until it expires. Expired
reservation/orphan cleanup remains an operational follow-up.

NSFW moderation remains on the mobile client for MVP, as confirmed by the user.
Storage adapter tests use a local HTTP fixture; bucket policies and direct uploads
must still be verified against the staging Supabase project.

## Final onboarding

`POST /v1/me/onboarding` accepts the complete form defined in the shared OpenAPI
contract. It requires an active initialized account and current required consents.
There is no server-side step progress. The backend validates calendar age 18+,
field lengths/ranges, active master-data references, unique photo IDs/positions,
and uploaded object metadata before committing the profile. Location is optional;
location-based discovery must exclude profiles without one.

The account row is locked for the submission. Profile relationships, PostGIS
location, selected photo activation and `onboarding_completed_at` commit together.
A retry after a successful response was lost returns 409
`ONBOARDING_ALREADY_COMPLETED`; it does not create duplicate records. Storage
uploads are external to the database transaction and remain available for a retry
if database persistence fails. Device registration uses its separate endpoint.

Validation failures return 422 `ONBOARDING_VALIDATION_FAILED` with all invalid
fields. Malformed JSON, unknown properties or incompatible JSON value types return
400 `INVALID_REQUEST`. Missing uploaded objects return 422
`PHOTO_UPLOAD_INCOMPLETE`; Storage outages return 503 and do not complete onboarding.
Birthdates and exact coordinates are never logged or returned in public responses.

## Device tokens

`POST /v1/devices` upserts a push token for an initialized active account.
`platform` accepts `ios`/`android`; `provider` accepts `fcm`/`apns`. A token is unique
across accounts. Registering the same installation after switching accounts moves
that token to the new authenticated owner while preserving its device ID. The old
owner can no longer delete it. `DELETE /v1/devices/{id}` only removes a device
currently owned by the caller. Device tokens are never logged or returned.

## Own profile and discovery eligibility

`GET /v1/me/profile` returns the authenticated user's own profile with reference
labels, selected hobbies/intentions and signed read URLs for active photos. It
includes the owner's birthdate as specified by the technical document, but never
exact coordinates or private attractiveness scores. It cannot select another user.

Per the user's scope decision, there is **no discovery HTTP endpoint** yet.
`internal/discovery.Eligibility` provides:

- `Guard(handler)`: compose after JWT middleware to require an initialized active
  account, completed onboarding, current required consent and a stored location.
- `CandidateIDs(ctx, viewerID, limit)`: use the authenticated JWT subject for
  `viewerID`. A read-only repeatable-read transaction checks the viewer and filters
  candidates to active completed profiles with current consent, a location and at
  least one active photo, as required by PRD M09.
  It excludes the viewer and limits results to 1–100 IDs.

The future discovery module must use this guard/query rather than unfiltered
profile reads. Ranking and public-profile projection are outside this ticket.
Tests exercise a consumer handler that composes these public interfaces.

## Profile updates

`PATCH /v1/me/profile` requires an active completed account and current required
consent. Only these supplied fields are editable: bio, height, weight, ambition,
university, religion, personality, pronoun, show-me preference, looking-for IDs and
hobby IDs. Optional scalar values can be cleared with JSON null; required fields
cannot. Relation arrays replace the entire selection and must remain nonempty.

Unsubmitted fields retain their current values. All edits commit in one
transaction, and validation errors return 422 `INVALID_PROFILE_DATA` with field
details. Birthdate, name, gender, photos and location are not editable through this
endpoint. Birthdate verification remains a separate future flow; photos/location
have separate endpoints. The response includes the new `updated_at` timestamp.

## Location updates

`PUT /v1/me/location` validates latitude [-90, 90] and longitude [-180, 180], then
upserts a WGS84 PostGIS geography point (longitude first). Missing, non-numeric,
overflowing, or out-of-range coordinates return 422 `INVALID_COORDINATES`. It requires an active
completed account and current required consent. The response contains only an
update flag and timestamp. `DELETE /v1/me/location` is idempotent and remains
available without consent; it removes only the authenticated user's row.

No exact coordinates are logged or returned by these endpoints. After deletion,
the discovery eligibility guard returns `LOCATION_REQUIRED` and candidate queries
exclude that account until it stores a valid location again.

## Consent revocation and processing restrictions

`POST /v1/me/consents/revocations` accepts `consent_types` and an optional reason
(up to 1,000 characters). It appends a new server-timestamped revoked decision;
previous decisions remain immutable. Duplicate or unsupported types are rejected.
The response returns each type and its `revoked_at` timestamp. Consent reads expose
`recorded_at` for all decisions, `accepted_at` only for accepted decisions, and
`revoked_at` only for revoked decisions. Reasons are not logged or returned.

The user confirmed this policy: when any currently required agreement lacks
current acceptance, initialization routes to `accept_consents`; discovery access,
profile edits, location writes, and new photo capabilities/edits are blocked until
re-acceptance. This also prevents initial sensitive photo processing before
required consent. Initialization, consent APIs, own-data reads and deleting
location/photos remain available to active accounts. Existing account suspensions
and freezes continue to restrict protected endpoints.

Revocation and processing mutations lock the same account row. Re-acceptance
restores processing eligibility without overwriting consent history. This does not
revoke already-issued Supabase capabilities; their provider expiry still applies.

## Auth configuration verification

For ONB-BE-01, run `go run ./cmd/auth-check` from this directory with
`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` exported. It reads public Auth flags
without creating users or updating settings. See
[Auth readiness](../../infrastructure/supabase/auth-readiness.md) for its limits,
known public identifiers, and pending provider/SMTP/deep-link verification.

## Swagger API documentation

Start the API using `npm run api` from the repository root, then open:

- Swagger UI: <http://localhost:8080/swagger/index.html> (`/swagger` redirects here).
- OpenAPI YAML: <http://localhost:8080/openapi.yaml>.

Use the host and port configured by `API_ADDR` when they differ from the default.
Documentation is public and read-only; protected API operations still require a
valid Supabase access token. Click **Authorize**, paste the access token without
adding `Bearer`, and use **Try it out** to call an endpoint. Authorization is kept
in the current page's memory and is not persisted across reloads. Requests from
Try it out use the API origin serving the documentation, including its actual
host and port. They execute real API operations, so use the intended environment.

The single source of truth remains `libs/contracts/openapi.yaml`. The Go module
in `libs/contracts` embeds that exact file into the API binary through a local
module replacement. Swagger UI assets are also embedded through the pinned
`github.com/swaggo/files/v2` dependency. No CDN or external validator is used at
runtime, and no `swag init` or annotation generation step is needed. Update the
shared YAML when API contracts change, then restart `npm run api` or rebuild the
binary. Build from the repository checkout so the local contracts module exists;
the compiled binary serves documentation independently of its working directory.

Configuration follows the [Swagger UI configuration reference](https://swagger.io/docs/open-source-tools/swagger-ui/usage/configuration/).
