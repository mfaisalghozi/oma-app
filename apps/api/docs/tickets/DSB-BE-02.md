# DSB-BE-02 — Query parsing

Status: production parser code and controlled-provider validation implemented; live semantic acceptance blocked by DSB-BE-01 credentials/account evidence. No claim of 50 real calls, model accuracy, latency or cost. Depends on DSB-BE-01 (`69da56c`), which depends on DSC-BE-00 (`a2ee06a`). Branch: `feature/DSB-BE-02-query-parse`. No HTTP search creation, quota, retrieval, results, worker or moderation functionality belongs to this ticket.

## Contract

`internal/describe.Parser.Parse(ctx, query)` accepts original Bahasa Indonesia/English text and returns `Criteria`: server-captured `original_query`, version `v1`, normalized Bahasa `rewrite_id`, English `translation_en`, typed `must`, `nice`, and explicit `not_searchable` text/reason. `Decode(query, JSON, catalog, limits)` is the public pure validation and canonicalization seam. Must/Nice are flat AND clauses; unsupported OR/exclusions remain `unsupported_logic`, never silently become AND. Source `Evidence` quotes refer to the request, never to a candidate fact.

Fields: numeric `age`, `height_cm`, `distance_km` with `gte/lte/eq`; singular catalog `gender`, `religion`, `university`, `personality` with `eq`; catalog sets `hobby`, `looking_for` with `contains`; authored text `bio`, `ambition` with `contains`. Numeric `Number` is nullable so zero distance is distinct from absence. Text age mentions remain text criteria, separate from stored profile age. No arbitrary SQL, photo inputs or image-derived profile facts exist in the API. Appearance terms can only be searched as explicitly requested authored-text terms; unsupported appearance/image claims remain NotSearchable.

The caller supplies the active masterdata catalog including ID/EN aliases and server `Limits{MaxAge, MaxDistanceKM}`. Go resolves only unambiguous known aliases/IDs within the requested field. Canonical catalog output contains `CatalogID` and empty `Text`. Height bounds use existing profile constraints 100..250 cm; age is integer18..MaxAge, distance0..MaxDistanceKM. Validation rejects unknown fields/operators/IDs, ambiguous labels, mixed payload types, unknown/missing/duplicate JSON keys, null arrays, non-finite numbers, fractional age/height, inverted numeric bounds, absent/invented source evidence and trailing JSON. Implementation bounds are 500 query code points,24 total clauses,64KiB JSON,2000 rewrite/translation code points; the source technical document leaves the input cap proposed, so confirm that product cap before freezing an HTTP contract.

## Provider

`JSONProvider.Generate(ctx,prompt)` is the controlled external-provider seam. The parser sends only the query, needed catalog vocabulary and numeric policy. `NewBedrock(BedrockConfig{APIKey, Transport})` provides the actual Anthropic Messages structured-JSON adapter for provisional `anthropic.claude-haiku-4-5`, fixed Tokyo endpoint `https://bedrock-mantle.ap-northeast-1.api.aws/anthropic/v1/messages`; no regional fallback or redirects. `Transport` allows controlled fixtures without live processing. No automatic provider wiring or secret loading is introduced here. The integration owner must verify model availability and approve effective region, retention, disabled content logging and allowed request data before attaching real credentials.

The adapter sends `output_config.format` with the embedded JSON schema, rejects truncation/non-text/invalid JSON, never exposes provider body/errors, and makes at most three attempts (initial +2 retries) for transport errors,429 or5xx. Each attempt has10s context timeout, total30s including retries; existing shorter caller deadlines win. No parser-layer additional retries. Schema compilation can take approximately90s per AWS docs, conflicting with the approved10s request bound: retain10s and classify failure; operational warm-up/budget change requires explicit follow-up, no silent widening. Strict output guarantees shape, not semantic truth: rewrite, translation, unsupported classification and query intent still require DSB01 real model evaluation.

Primary documentation verified 2026-11-16:
- [AWS Anthropic Messages API](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-messages-api.html)
- [AWS structured output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
- [Claude structured outputs on Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-structured-outputs.html)

## Validation

TDD red/green at the previously approved public pure parser and controlled external provider seams: first failed compile for missing parser, then successful alias extraction; negative tests failed on duplicate/omitted JSON keys before strict shape validation; invalid policy reached the controlled provider before preflight fix; Bedrock adapter tests failed compile before implementation.

`go vet ./...`, `go test ./...`, `go build ./...` pass independently on this branch. Controlled cases cover original preservation, rewrites/translations, numeric values, ID/EN aliases, unsupported logic/evidence, authored/stored age distinction, malformed output, unknown IDs, bounds, contradictions, request schema/auth/endpoint, retries, cancellation and truncation. These fixtures verify code behavior only and are not model-quality evidence. Disposable DB integration tests retain their existing opt-in environment requirements; this ticket does not modify SQL. `graphify update .` completed AST-only with existing missing SQL parser dependency and JSON zero-node warnings; generated graph stays local, outside scoped ticket commit.
