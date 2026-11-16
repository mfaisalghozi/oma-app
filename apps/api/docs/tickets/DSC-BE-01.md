# DSC-BE-01 — candidate query

Branch: `feature/DSC-BE-01-candidate-query`. Depends on DSC-BE-00 (`a2ee06a`).

This independently building slice adds `discovery.CandidateQuery` with validated,
explicit `CandidatePolicy`. `Candidates(ctx, viewerID, radiusKM, limit)` returns
internal ID, gender ID, calendar age, pair distance and activity time for at most
300 eligible profiles. `VisibleTx` rechecks an individual target using the same
hard filters in a caller-owned transaction. The viewer must be authenticated by
the consumer; query access checks account/onboarding/consent/location in the same
snapshot as candidate selection. Neither function serializes public profiles.

PostGIS geography ST_DWithin applies a meter radius before LIMIT. Zero radius uses
the stored viewer radius, then policy default; every radius is capped by policy
maximum. Reciprocal gender and age preferences, adulthood, active account,
completed onboarding, current required consent, active photo, recent location,
activity cutoff, either-direction blocks and directed pair exclusions apply before
LIMIT. Results use ID order only as a stable query order; rotating selection and
ranking belong to DSC-BE-02. No production defaults are invented in this slice.

Migration 010 owns only `profiles.min_age/max_age/radius_km`, `user_blocks`,
`discovery_activity`, and the `discovery_pair_exclusions(viewer_id,candidate_id)`
read view. New tables have RLS enabled with no client policies. Existing PostGIS
GiST and photo/consent lookup indexes are reused. Age preferences remain nullable
and fall back independently to configured adult bounds.

## Integration dependencies and limits

- DSC-BE-03 must replace the initially empty pair exclusion view with directed
  already-decided interactions plus both directions of canonical matches. This
  branch has no action/match producer, so it does **not** claim those exclusions
  are integrated end to end. The query's consumer contract is tested by replacing
  the view with a fixture row.
- Safety must write authoritative blocks to `user_blocks`; this is not a block
  HTTP endpoint or full Safety implementation.
- A trusted activity producer must upsert `discovery_activity.last_active_at`.
  Until a row exists the explicit baseline is `accounts.updated_at`, consistent
  with the prior implementation. The query enforces a configured cutoff but this
  branch does not claim complete user-session activity ingestion. A dedicated
  activity record takes precedence over later account metadata changes.
- Existing `Eligibility.CandidateIDs` remains the Sprint 1 compatibility seam.
  All new Discovery/Describe consumers must use `CandidateQuery`; the old seam
  does not implement Sprint 2 proximity, preferences or pair exclusions.
- No HTTP route, deck/cache, ranking projection, quota, wallet, action, worker,
  provider integration, preference-write endpoint or public profile DTO is added.
  Runtime policy wiring belongs to the first endpoint consumer in DSC-BE-02.
- `VisibleTx` provides a visibility read, not serialization against concurrent
  Safety writes; action transaction locking/revalidation belongs to DSC-BE-03.

## Validation

The approved public query seam is tested through the existing disposable
PostgreSQL/PostGIS fixture (isolated schema per test). Tests cover radius and
server maximum, limit/nonfinite validation, transaction visibility, reciprocal
age/gender, both block directions, frozen/incomplete accounts, missing photo,
idle, missing/stale location, minors, consent withdrawal and the exclusion view.
The first test failed to compile on absent public query types before implementation.

Checks: gofmt; `go vet ./...`; `go build ./...`;
`go test -race -tags=integration ./...` using TEST_DATABASE_URL for the disposable
local database. No staging or production database was used. No load, device,
external provider or real Safety/activity integration claim is made.

`graphify update .` generated the local AST graph. It warned that SQL extraction
is unavailable because tree_sitter_sql is not installed; SQL correctness is checked
by real migration/query integration tests instead. Generated local graph files
are not part of this ticket's source commit.
