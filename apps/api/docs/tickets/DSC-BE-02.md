# DSC-BE-02 — Ranking, deck cache and first-delivery exposure

Branch: `feature/DSC-BE-02-ranking-deck`.
Prerequisite: DSC-BE-01 (`1536a01`), which includes DSC-BE-00.

Implemented: pure Beta posterior/quality ranking; bounded rotating priority,
fresh and distance cohorts (deduplicated pool at most 300); at most 20 ordered
cards; one oldest current incoming-priority pin; fresh cards and the priority
pin count toward the configured top-half budget. Cold-start scores use an
explicit configured prior. The existing 14-day idle rule remains a hard filter.

`deck_cache` and relational `deck_cache_cards` preserve ordered membership for
30 minutes. Server-owned UUID cursors bind positions to the viewer/cache.
Stored preference revision, material movement relative to the cached location,
policy/ranking revisions, expiry and WIB midnight invalidate context. Reads
recheck the canonical DSC-BE-01 hard filters and sign only active photos. Public
cards omit exact coordinates, full surname, private profile fields and ranking
inputs. Occupation/degree remain null because their authored fields do not yet
exist in the onboarding schema.

`discovery_exposures` has a unique (viewer, candidate, WIB date) key. Candidate
`shown_today` increments only on first delivery, never on decisions or cache
creation. Reloads/paging deduplicate. Sorted candidate-counter locks enforce the
cap atomically across concurrent viewers; viewer locks use `FOR NO KEY UPDATE`
so foreign-key checks do not create account-row deadlocks. Projection/signing
finishes before the exposure transaction; failed signing and HEAD do not charge.
Only a currently valid incoming priority pin can bypass the cap. Priority
consumption is derived from actual delivered priority cache cards.

`PATCH /v1/me/discovery-preferences` stores age/radius preferences. Active
protected API traffic produces `discovery_activity` records. Strict optional
`DISCOVERY_POLICY_FILE` configuration lives in `internal/platform/config`;
unconfigured Discovery endpoints return 503. Example technical tuning inputs
are not product-approved deployment defaults. PRO selection is an injected
server-owned callback; the standalone API currently selects the free mix.

Exported interfaces for dependent tickets:

- `Handler.ContextTx(ctx, tx, viewer, target, contextID) error`: current owned,
  delivered, undecided card and current canonical eligibility in caller's tx.
- `Handler.Project(ctx, viewer, ids) ([]Card, error)` and
  `ProjectRadius(ctx, viewer, ids, radiusKM)`: current safe signed projection.
- `discovery_quality(candidate_id, segment_key, likes_w, passes_w, percentile,
  reply_rate, prior_mean, completed_matches)`: neutral empty view; DSC-BE-05
  replaces it with real segment/event projections. No worker is claimed here.
- `discovery_incoming_priority(viewer_id, candidate_id, created_at)`: neutral
  empty view; DSC-BE-03 supplies the irreversible action source. DSC-BE-03 also
  marks `deck_cache_cards.action_id` and replaces DSC-BE-01 pair exclusions.

No actions, wallet, quota grants, comment moderation, Featured members, billing
or Describe LLM jobs are included. Priority/quality producers remain explicit
successor dependencies, not completed functionality in this ticket.

Validation: public pure ranking and HTTP seams were approved in the task.
Ranking worked-example and top-half mix tests ran red then green. HTTP tests
use disposable PostgreSQL/PostGIS with controlled auth/storage fixtures and
cover cache stability, safe projection, block rechecks, cursor ownership,
preference/material-location/policy invalidation, expiry, first-delivery reload
deduplication, WIB rollover, 12 concurrent viewers at cap 1, current priority
TTL/cap bypass, HEAD and failed-storage no-charge behavior. Validation passed at this ticket source revision: `go test -race -tags integration
./...` against disposable PostGIS (API suite 33.988 s), `go vet ./...`,
`go build ./cmd/...`, `gofmt`, `git diff --check`, and OpenAPI YAML parsing.
No live Supabase/staging load evidence or production policy approval is claimed.

`graphify update .` completed AST extraction. Its environment lacks
`tree_sitter_sql`, so SQL files have no graph nodes; SQL is covered by actual
PostGIS migration and HTTP integration execution instead.
