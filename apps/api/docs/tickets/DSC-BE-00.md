# DSC-BE-00 — onboarding BE baseline and Go CI

Base: origin/release/v0.1 at b128da0. The onboarding BE stack and Gin/Swagger are already merged upstream; this branch does not merge or push release.

Change: Go CI for API/contracts PRs and ticket-branch pushes. Checks formatting, vet, build, and race-enabled unit/PostGIS integration tests against a disposable service. No Discovery/Describe runtime changes belong to this ticket.

Validation: local equivalent commands are run before publishing. Hosted Actions execution is recorded separately after pushing; local success is not a claim that hosted CI has executed.
