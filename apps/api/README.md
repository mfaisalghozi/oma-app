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
  candidates to active completed profiles with current consent and a location.
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
