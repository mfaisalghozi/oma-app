# DSB-BE-03 — Describe retrieval and ranking

Branch `feature/DSB-BE-03-retrieval-ranking` starts at DSB-BE-02 `94b31ad`.
It merges DSC-BE-02 `ae686c1` for the canonical candidate query, public profile projection,
and segment quality read contract. Merge `ed4c9a2` brings DSC-BE-05 `89fe7b1`
and its real DSC-BE-03/04 prerequisites: irreversible actions/matches, limits,
and the source-event quality/reply producer. Search jobs and quota workflows
remain owned by DSB-BE-04.

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
Zero is a valid explicit Describe radius: only the same point qualifies. Saved
Describe actions must call `CandidateQuery.VisibleRadiusTx` to retain that scope;
ordinary `Candidates`/`VisibleTx` zero retains stored/default radius semantics.

Ranking is deterministic: 0.6 Nice relevance (unknown = zero; no Nice = one),
0.25 quality, 0.15 distance factor. Quality is the within-segment percentile
multiplied by `(reply_floor+(1-reply_floor)*reply_rate)*2^(-idle_days/half_life)`;
the configured defaults retain the specified reply floor 0.4 and five-day half-life.
The distance factor is `1-0.5*distance/radius` (same-point zero radius is one).
SQL ranks before LIMIT and pure evaluation uses the same `Profiles.Policy.Ranking`
inputs. Ties use distance
and profile ID. Quality joins the viewer-gender:target-gender segment only.
Qualifying ghosters (at least ten completed matches, reply rate below 0.2) are
excluded. The SQL ranks the filtered universe before taking ten; it does not
retrieve an arbitrary 300 and then apply the requested predicates.

The call has a five-second deadline and uses the existing spatial predicate.
No realistic staging query-cost or latency claim is made. Profile projection
rechecks current visibility, signs active photos, and returns approximate distance.
Private location, birthdate, weight, storage paths and ranking scores are absent.
An internal snapshot covers profile revisions, evaluated age, both location
versions, and hobby/relationship relations. The projection reads its snapshot
with the public card; retrieval drops changed candidates before emitting their
reasons. Snapshot metadata is excluded from JSON. SQL and pure evaluation share
numeric tolerance policy, distance factor and ranking weights; eligibility joins and predicates
use one explicit composition helper.

Describe applies the shared candidate daily exposure cap before LIMIT. A candidate
already delivered to the same viewer in the current WIB day remains eligible for
reload; incoming priority never bypasses the Describe cap. `FilteredPolicy` gets
the cap, ranking policy and clock from the profile handler. DSB-BE-04 owns the
atomic delivery increment and the final cap recheck for racing deliveries.

The branch contains the real DSC-BE-03 pair-exclusion view and DSC-BE-05 quality
producer. Retrieval acceptance uses source interactions/events, a real score
projection, and unanswered match reply windows; it does not replace quality with
a synthetic neutral view. DSB-BE-01's live provider evidence remains blocked on
credentials.
DSB-BE-04 owns HTTP search creation, quota/reservation accounting, provider calls,
logs, durable workers, saved last results and action context persistence.

Validation: public pure evaluation and real disposable PostgreSQL/PostGIS retrieval
fixtures cover numeric tolerance, unknown evidence, all-unsupported rejection,
312-candidate pre-limit filtering, exact-first ordering, exact-ten behavior,
authored hobby aliases, wider close radius/global maximum, reciprocal age,
blocking, stable ties and public projection. Additional fixtures verify source
quality ranking, irreversible pass/retained-match exclusions, true-zero radius
retrieval/action checks, and deterministic profile height/bio/hobby/location edits
between filtering and projection using a database lock barrier. Worked numeric
examples verify reply/recency quality and the distance coefficient; source-backed
ranking fixtures verify reply and recency before LIMIT. Cap fixtures cover a pool
larger than ten, reload deduplication, no priority bypass and WIB midnight. After merging the prerequisite,
`go vet ./...`, `go build ./...`, `go test ./...`, and
`GIN_MODE=release TEST_DATABASE_URL=<disposable PostGIS> go test -race -tags integration ./...`
all pass. These are local
fixtures, not staging latency or live provider evidence.

`graphify update .` refreshed the local AST graph. SQL
extraction is incomplete because the optional `tree_sitter_sql` grammar is absent;
five JSON fixtures/configuration files produced no nodes. Generated graph files
remain local and are not part of this ticket commit.
