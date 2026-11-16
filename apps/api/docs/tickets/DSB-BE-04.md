# DSB-BE-04 — durable Describe searches, quota and saved results

Branch: `feature/DSB-BE-04-search-history`.

Dependencies actually merged: DSB-BE-03 retrieval `3a043e2`, DSC-BE-04 limits
`ee9d35f`, DSC-BE-03 action wire/state `c151394`, DSC-BE-05 score/River worker
`89fe7b1`. Corrected retrieval zero-radius/evidence-coherence `9aada77` and score cutoff
`9363ac2` are also actually merged.

## Implemented

- Fixed WIB daily limits from the real limits service: 3 free, 20 trusted
  development PRO. A successful empty search consumes one quota. Technical,
  provider, malformed parse and unsupported-only query failures release the hold.
- Atomic SQL creation of search, reservation and typed River job; opaque
  case-sensitive bounded request keys with 24-hour expiry independent of WIB
  midnight, payload conflict detection, owned failed
  retry references, and one in-flight search per owner. Fresh attempts receive a
  random search UUID used as their permanent quota operation; expired request keys
  can be reused without replaying or deleting historical settled/released usage.
- Provider IO outside SQL locks; existing Bedrock adapter has 10-second attempts,
  initial request plus two retry attempts within the overall 30-second deadline.
  Work has a 30-second fenced lease. Restart/expired lease reconciliation refunds
  exactly once in the reservation's original WIB bucket. Late workers cannot
  resurrect completed failures. Queue reconciliation runs at startup/every 60 seconds;
  lease cleanup executes even when score-job insertion fails.
- Query and parsed rewrite/translation logs are owner-selected and protected with
  RLS without client policies, matching the established backend-only access model. Saved rows contain candidate IDs,
  revisions and authored evidence only; no signed URLs or raw provider output,
  prompts, credentials, coordinates or inferred photo facts are persisted.
- Settlement locks all involved accounts in canonical order, then rechecks current
  owner eligibility and candidate visibility/evidence inside that transaction.
  Revocation refunds; changed or blocked candidates are dropped before persistence.
  No provider or storage signing runs under those locks.
- Saved reads project current eligible profiles with fresh photo signing at the
  persisted effective radius. Eligible changed profiles remain but their old
  reasons, counts, tier, violations and criterion evidence are suppressed.
- Atomic first-delivery accounting shares the Discovery viewer/candidate/WIB-day
  exposure records and cap, without a priority bypass. HEAD does not deliver;
  Describe actions require an actually delivered saved result.
- Authoritative Describe action hook owns context membership and radius; the
  Discovery module imports no Describe package. Numeric close candidates beyond
  ordinary viewer radius remain actionable under their owned saved context.
- API/worker composition registers Describe beside unchanged score workers;
  no `sprint2` runtime configuration. Missing provider configuration returns 503
  without reserving quota or making a provider call.

## Wire and semantics

Preserves `/v1/describe/searches`, `/latest`, `/{search_id}` and
`/{search_id}/results`, opaque `Idempotency-Key`, query/optional `retry_of`,
`search_id/status/criteria/error_code/poll_after_seconds` and version metadata.
Results preserve `candidate/ordinal/profile_updated/criterion_evaluations`, with
new retrieval N/M, reason, tier and numeric violations. Actual processing exposes
queued/parsing/retrieving then terminal status; ranking happens within retrieval.
Latest means **last successful search**, including empty success. This explicit
user-approved rule overrides the previous latest-attempt behavior: failures and
quota rejection preserve recovery of the prior successful result.

Query-log retention has no approved duration; no query-log expiry/deletion is
enforced, and the last successful search is retained. Request-key mappings expire
after the separately approved 24 hours. Physical expired-key pruning runs at startup and every 60 seconds, bounded to
1000 expired mappings per invocation with SKIP LOCKED. Discovery cache pruning
is owned by DSC-BE-02/05; permanent actions, source
events, limits operations and saved search logs are not deleted.

## Validation status

Targeted real disposable PostGIS and real River tests pass for quota 3/20, empty
success, provider/malformed/unsupported refunds, owner isolation, replay mismatch,
case-sensitive concurrent last-search requests, enqueue rollback, accepted-work
restart, lease fencing, original WIB bucket release, cleanup during unrelated
queue failure, stale evidence suppression and a real 53 km Describe action with
ordinary viewer radius 1 km. Corrected explicit zero-radius successful-empty searches charge once. A
24-hour key-reuse regression covers midnight replay, new random operations after
expiry and original/current quota buckets. Full final vet/build/race evidence is
recorded below after dependency merges.

Live model execution remains **BLOCKED** because user-confirmed account evidence
and credentials are unavailable. No model calls, 50-query acceptance, live cost,
p90 latency or final model winner are claimed. This limitation does not authorize
requesting credentials again. Comment/moderation, Featured, billing/refund flows
and production rollout remain outside this branch. No push or release merge.
