# Describe LLM spike

This is an isolated, synthetic-only benchmark, not the production parser. Python 3 standard library only. It never reads profiles, Supabase, `.env` files, photos or production queries. `queries.json` contains 50 authored cases: 25 Bahasa Indonesia, 20 English, five mixed. They become 50 real provider queries only when `--live` runs successfully. A fixture run is tooling verification, never model evidence.

From the repository root:

```sh
python3 -m unittest discover -s apps/api/tools/llm-spike
python3 apps/api/tools/llm-spike/run.py --prepare --output /tmp/describe-prepared.json
python3 apps/api/tools/llm-spike/run.py --fixture apps/api/tools/llm-spike/fixture.json --output /tmp/describe-fixture.json
python3 apps/api/tools/llm-spike/run.py --live --approval /tmp/llm-approval.json --output /tmp/describe-live.json
```

For live execution, an operator supplies a short-lived `AWS_BEARER_TOKEN_BEDROCK` through the process environment and creates an attestation outside the repo:

```json
{
  "model": "anthropic.claude-haiku-4-5",
  "region": "ap-northeast-1",
  "routing": "in-region",
  "data_retention_mode": "none",
  "content_logging_disabled": true,
  "evidence": "Operator/date and approved account configuration evidence reference"
}
```

The attestation is a prerequisite, not automated proof of account settings. Verify the effective model/account retention mode, permitted inference routing and disabled content invocation logging in the actual account. Do not put credentials in attestation or reports. No fallback to global/APAC/JP profiles or another vendor exists. The fixed HTTPS endpoint rejects redirects. No retries or prompt caching are used, so exactly one attempt per case is observable. Each request times out after 10 seconds; process overhead and network latency count in wall-clock latency. This is a sequential local baseline, not worker/staging throughput.

Reports preserve per-case output, provider usage, status and elapsed milliseconds; dataset/prompt/schema hashes identify inputs. Live summary metrics are withheld unless all 50 responses finish with `end_turn` and parse as JSON. p90 is nearest rank, the 45th of 50 ordered client wall-clock times. Estimated cost/search is total input tokens × $1.10/M plus output tokens × $5.50/M, divided by 50. Rates are the researched standard in-region list price; reverify before running. Estimates exclude taxes, networking and failed-attempt charges; reconcile the bill separately. Partial results are checkpointed after each call, preserving paid successes. Do not count reruns as the same benchmark.

A JSON response is not proof of correctness. Review each against the independent `review` rubric in `queries.json`, then record schema validity, rewrite/translation preservation, Must/Nice assignment, numeric extraction, unsupported-item handling and injection resistance. Review all 50, including failures. Require zero unsafe minor/contact/photo-inference or injection failures before considering deployment. No product accuracy/latency threshold was supplied: report measured values for review instead of inventing acceptance targets.

The proposed `spike-v1` schema uses `rewrite_id`, `translation_en`, `must`, `nice`, `not_searchable`. Criteria contain field/operator/number/text/evidence; labels remain text until server-side catalog resolution. Unsupported items retain text and reason. Production DSB-BE-02 owns validation, normalization and any revised schema. In particular Q07/Q16/Q42 expose an intentional decision point: a flat AND list cannot encode OR alternatives; the production schema must represent groups or classify such unsupported constructs explicitly, never silently change OR to AND. Fixture output is a single deliberately repetitive transport specimen and is not a semantic oracle.
