# DSC-BE-05 — score projection and nightly worker

Branch: `feature/DSC-BE-05-score-worker`. Stacked on DSC-BE-03 swipe actions
(`f4826ca`) and DSC-BE-02 cache retention (`f15ada6`), including DSC-BE-04 limits
and their prerequisites.
Migration 014 owns score tables and replaces the neutral `discovery_quality` view.
No Describe jobs, providers, comment policy, Featured or billing behavior belongs
in this ticket.

## Behavior

`internal/scores.Service.Project` consumes immutable `swipe_events`. Each fast
transaction claims at most 1,000 events that lack a permanent per-event receipt;
there is no sequence high-watermark. A lower event ID committed after a higher ID
is processed on a later run. Receipts and score changes commit together. Projection
recomputes affected candidate/segment totals, so replay cannot add weight twice.
An advisory transaction lock serializes projectors, including nightly runs.
Repeatable-read snapshots keep the source set and receipts consistent when actions
commit during a rebuild. Both fast and nightly claims use the same `occurred_at <= now`
cutoff as aggregation, so an event visible after the caller captures `now` remains
unreceipted until an eligible later run. Source swipe events and their receipts
are never purged.

Segments use the event's historical viewer-gender:target-gender codes. Like and
super-like each contribute one positive before actor weighting and decay. Passes
contribute negative evidence. Accounts younger than three days, non-active accounts
and accounts without trusted phone verification contribute zero. More than 80%
positive decisions in the last 100 swipes gives weight 0.25; otherwise weight 1.
Evidence decays with a 30-day half-life and a 120-day window. Explicit policy supplies
fallback mean, prior strength and minimum weighted segment support; sparse segments
use the fallback, rather than an invented learned prior. The worker rejects a
half-life other than 30 days. Example policy values require production review.

Nightly rebuilds all actor weights, segment priors, candidate posteriors and
within-segment percentiles in one transaction. Retroactive suspensions and phone
verification changes therefore correct historical contributions. Empty candidate
segments receive the prior. Fast updates preserve the previous percentile (0.5
for new rows); percentile ranking is a nightly operation. The existing Discovery
activity projection remains the single recency source and the existing ranking
function applies its configured recency decay.

Reply metadata contains only match ID, participants and server timestamps. Incoming
opener opportunities count after 48 hours; a first qualifying reply within that
window contributes a reply. The smoothed rate is `(replies+3)/(opportunities+4)`.
The historical view name `completed_matches` means this opportunity count, **not**
the total match count. With no producer evidence, it is zero and reply rate is 0.75.

## Trusted producer integration and remaining acceptance

`RecordPhoneVerificationTx` is an integration boundary for a trusted Supabase Auth
synchronizer; no phone verification is inferred from account age, ordinary login,
client claims, or membership. Its nullable account field defaults to unknown.
There is no Auth verification ingestion producer in the current baseline. Until
that producer is wired, unknown actors deliberately have zero contribution.

`RecordReplyWindowTx` is the Chat integration boundary. Chat must call it in its
message-metadata transaction for the first qualifying opener/reply; it validates
match participants and preserves the first opener and earliest qualifying reply
on replay. The authoritative Chat producer/qualifying-message implementation is
outside this stack and remains blocked on Chat integration. This ticket provides
and tests the integration helper; it does not claim live Chat or Auth ingestion.
No message bodies or fake verification facts are stored.

## Worker operations

River 0.49.0 uses `riverdatabasesql` and the application's `*sql.DB`. These pinned
new dependencies implement the approved D17 queue. Apply domain migrations first,
then explicitly apply River's own queue migrations; neither API nor worker startup
automatically applies them:

```sh
go run ./cmd/migrate -direction=up
go run ./cmd/worker -migrate
DISCOVERY_POLICY_FILE=config/discovery.example.json go run ./cmd/worker
```

Set the server `DATABASE_URL` in the environment. Worker configuration uses the
same validated Discovery policy as the API. Typed jobs are `score_project` and
`nightly`; fast projection runs every second. Reconciliation runs at startup and
every 60 seconds and restores missing score jobs and overdue nightly rebuilds.
Each reconciliation first runs the optional domain hook, then prunes at most 1,000
expired 24-hour swipe replay bindings and at most 1,000 expired deck caches older
than seven days, including their owned cards/cursors, in one short transaction.
Maintenance runs independently of River queue availability; hook, maintenance and
queue failures are collected while other reconciliation work is still attempted.
Permanent interactions, swipe events, quota operations and exposure history are
untouched. Logical API expiry remains authoritative between cleanup runs.
Nightly schedule is 00:00 Asia/Jakarta (17:00 UTC); successful rebuild runs are
recorded durably so downtime catches up. SIGTERM stops intake and gives existing
jobs 30 seconds to drain before cancellation. Nightly jobs permit up to ten minutes
of execution during ordinary operation. Failed jobs remain retryable in River.
`jobs.Options` permits future tickets to register their own workers/reconciler
without importing their domains into Discovery's worker implementation.

## Validation

Public pure-function tests cover weight thresholds, restrictions and decay. Public
score-service tests use disposable PostgreSQL/PostGIS for late lower-ID commits,
replay, future-cutoff deferral in both fast and nightly runs followed by exactly-once
fast catch-up, 1,001-event bounded backlog, equal paid/free positive weight, expiry,
retroactive suspension/phone revocation, priors, reply metadata and percentiles.
Public worker tests cover explicit River migrations/replay, typed job replay and
graceful draining with controlled in-flight work. Validation passed on the completed dependency stack: `go vet ./...`,
`go build ./...`, and `go test -race -tags=integration ./...` against the disposable
PostgreSQL/PostGIS database on localhost:55432. Graphify AST update completed; SQL
graph extraction reported the optional `tree_sitter_sql` dependency is absent.
Generated graph output remains local and is not part of the ticket commit.

Cutoff regression receipt: both fast and nightly cases first failed because the
event at `t+1s` was claimed by `Project(t)`. After the fix, each case claims zero
at `t`, the ordinary fast run at `t+2s` claims one weighted event, and replay claims
zero without changing quality. The fresh full suite passed with
`go test -race -tags=integration -count=1 ./...`; `go vet ./...` and
`go build ./...` also passed on the cutoff correction.

Retention regression receipt: the public `Runtime.Reconcile` PostGIS test first
failed because a missing `river_job` table prevented the domain hook. After the
fix, both hook and queue errors are returned while expired bindings/cache children
are removed, valid entries remain, and permanent interaction/event/quota/exposure
history remains intact. The fixture requires no River migration or provider.
The completed retention stack passed `go vet ./...`, `go build ./...`, and
`go test -race -tags=integration -count=1 -p=1 ./...`. Package serialization avoids
cross-package contention on the projector's database-wide advisory lock; a default
parallel run passed all other packages but observed the score projector busy in
one existing score test. Graphify AST update completed with the same optional SQL
parser warning noted above.
