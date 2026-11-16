# DSB-BE-03 — Describe retrieval and ranking

Branch `feature/DSB-BE-03-retrieval-ranking` starts at DSB-BE-02 `94b31ad`.
It merges DSC-BE-02 `ae686c1` for the canonical candidate query, public profile projection,
and segment quality read contract. It does not copy search jobs or quota code.

The public seam is `describe.Retriever.Retrieve(ctx, viewerID, criteria)`.
The caller supplies parsed/canonicalized DSB-BE-02 criteria and configured Discovery
query/profile dependencies. The call returns up to ten public profiles, exact/close
tiers, actual matched/searchable counts, reasons, and numeric deviations for unmet
Must clauses. NotSearchable clauses remain separately visible and never count as
fulfilled. All-unsupported/empty criteria return an actionable error.

Eligibility remains Discovery's canonical SQL: account, onboarding, consent,
active photo, recent location/activity, mutual gender/stored age preferences,
blocks and pair exclusions. Typed Must predicates run before ranking and LIMIT.
Exact candidates precede close candidates; close only fills remaining spaces.
Height and request age tolerate two units (adults only). A request distance upper
bound expands by ten percent, capped at five kilometres and the server maximum.
A lower distance bound stays strict. A missing distance upper bound uses the
configured default radius. Describe may reach beyond an ordinary stored deck radius.

`RequestedRadiusKM` and `EffectiveRadiusKM` distinguish the requested distance from
the outer accepted close boundary. DSB-BE-04 must persist the latter with its action
context, so a returned close candidate remains authorized at that accepted radius.

Ranking is deterministic: 0.6 Nice relevance (unknown = zero; no Nice = one),
0.25 within-segment quality percentile, 0.15 normalized distance. Ties use distance
and profile ID. Quality joins the viewer-gender:target-gender segment only.
Qualifying ghosters (at least ten completed matches, reply rate below 0.2) are
excluded. The SQL ranks the filtered universe before taking ten; it does not
retrieve an arbitrary 300 and then apply the requested predicates.

The call has a five-second deadline and uses the existing spatial predicate.
No realistic staging query-cost or latency claim is made. Profile projection
rechecks current visibility, signs active photos, and returns approximate distance.
Private location, birthdate, weight, storage paths and ranking scores are absent.

Release dependencies: DSC-BE-03 must replace the pair-exclusion read view with real
actions/matches; DSC-BE-05 must produce the segment quality/reply projection.
DSC-BE-02's empty neutral quality view is an integration contract, not real quality
acceptance. DSB-BE-01's live provider evidence remains blocked on credentials.
DSB-BE-04 owns HTTP search creation, quota/reservation accounting, provider calls,
logs, durable workers, saved last results and action context persistence.

Validation: public pure evaluation and real disposable PostgreSQL/PostGIS retrieval
fixtures cover numeric tolerance, unknown evidence, all-unsupported rejection,
312-candidate pre-limit filtering, exact-first ordering, exact-ten behavior,
authored hobby aliases, wider close radius/global maximum, reciprocal age,
blocking, stable ties and public projection. After merging the prerequisite,
`go vet ./...`, `go build ./...`, `go test ./...`, and
`GIN_MODE=release TEST_DATABASE_URL=<disposable PostGIS> go test -race -tags integration ./...`
all pass. The API integration package completed in 40.6 seconds. These are local
fixtures, not staging latency or live provider evidence.

`graphify update .` refreshed the local AST graph (596 nodes, 1190 edges). SQL
extraction is incomplete because the optional `tree_sitter_sql` grammar is absent;
five JSON fixtures/configuration files produced no nodes. Generated graph files
remain local and are not part of this ticket commit.
