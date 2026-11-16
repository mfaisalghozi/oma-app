# DSB-BE-01 — LLM spike

Status: **BLOCKED for live execution**. Tooling and research are ready; no real provider calls, cost/search measurements, p90 measurements or verified model winner are claimed.

Branch: `feature/DSB-BE-01-llm-spike`. Prerequisite: DSC-BE-00 (`a2ee06a`), independent of all Discovery feature tickets. Scope: `tools/llm-spike` and this evidence file only. Production parsing belongs to DSB-BE-02. The latest ticket title requires 50 real Bahasa/English queries; the 50 synthetic cases checked in here have not met that live requirement.

## Actual blocker and evidence

On 2026-11-16, discovery of credential names found no exported AWS, Bedrock, OpenAI, Anthropic, Azure, Google, Gemini or LLM variables. `~/.aws/config` and `~/.aws/credentials` do not exist. The authorized API `.env` contains only DATABASE_URL, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, API_ADDR and TEST_DATABASE_URL; values were not printed. These database credentials do not authorize model use. No approved provider account, model access, ZDR/routing evidence or short-term Bedrock bearer token is available. Running `--live` exits before network access with `AWS_BEARER_TOKEN_BEDROCK is absent; no provider calls made`.

An operator must provide Tokyo in-region model access, short-lived bearer authentication and account evidence for effective ZDR plus disabled content logging; then execute and review all 50 cases as documented in the [runner guide](../../tools/llm-spike/README.md). Do not reuse a ChatGPT session credential or send actual profile/user data. No account settings were changed.

## Provisional selection and primary-source research

Recommend benchmarking **Claude Haiku 4.5 on Amazon Bedrock mantle in Tokyo** first, provisionally. This is a cost-oriented candidate, not a measured winner. The [Bedrock availability table](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html) lists Haiku 4.5 in-region on Tokyo mantle; runtime in-region is unavailable and Singapore offers only global for this model. Tokyo runtime with APAC/JP inference would not satisfy the approved Tokyo/Singapore-only restriction. The [mantle integration guide](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock) documents the Messages API, `anthropic.claude-haiku-4-5`, short-term bearer authentication, structured output support and regional routing.

The [2026-11-09 Anthropic price list](https://assets.claude.com/a04aca860a54b7323e33f449706e9b43680e1346.pdf) quotes Haiku 4.5 Bedrock standard in-region rates of $1.10/M input and $5.50/M output. [AWS pricing](https://aws.amazon.com/bedrock/pricing/) remains the authority for the selected account/tier. A hypothetical 1,000 input + 300 output tokens costs $0.00275/search, or $0.1375 for 50; this is arithmetic planning only, not an observation. No USD/IDR conversion or fabricated token counts are reported.

The [AWS retention policy](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html) distinguishes effective `none` from `default`; `store=false` alone does not establish ZDR. Verify actual account/model eligibility and logging. A global direct Anthropic endpoint or an unspecified proxy cannot establish the regional requirement, so this harness has no such fallback. Other providers/models were not benchmarked; reconsider candidates if Haiku fails the semantic review or account requirements.

## Handoff and validation

The spike's schema and prompt cover Bahasa rewrite, English translation, Must, Nice and NotSearchable, without implementing the parser or production search path. Flat-criterion OR handling remains an explicit schema limitation to resolve in DSB-BE-02, not evidence of an observed model failure. Fields/HTTP contract and operator execution steps are in the runner guide.

Validated offline: one CLI fixture test passes with 50 outputs, `live=false`, `p90_ms=null`, `cost_per_search_usd=null`; preparation emits all 50 planned cases; live preflight fails on the actual missing credential. Fixture results are not committed as live evidence. Baseline `go vet ./...` and `go test ./...` pass (database-backed integration checks retain their existing environment gates). `graphify update .` completed: 385 nodes/772 edges; it warns that the three benchmark JSON assets produce no nodes and SQL extraction lacks `tree_sitter_sql`. Generated graph artifacts are local and excluded from this ticket commit. Acceptance still outstanding: all 50 real responses, semantic review, cost/search, p90 and final provider/model decision.
