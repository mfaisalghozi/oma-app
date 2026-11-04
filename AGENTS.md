# AGENTS.md

Guidance for AI coding agents (and new humans) working in this repository.
Read `README.md` first for the project overview, structure, architecture and
local setup. This file covers how to work here.

## Project in one paragraph

OMA (Ocean Match) is a dating app for Indonesia with agent-based matching.
This Nx monorepo holds the Flutter mobile app (`apps/mobile`), the Go API and
worker (`apps/api`), a future Vue web app (`apps/web`) and the shared OpenAPI
contract (`libs/contracts`). Supabase provides Auth, Postgres (+ PostGIS) and
Storage.

## Sources of truth

- **Product:** the PRD and the v0.1 screen designs (screen codes such as M04b,
  M09, M11c). Code and comments refer to screens by these codes.
- **Work items:** the Notion Feature Progress board. Ticket keys look like
  `ONB-FE-07`.
- **API shapes:** `libs/contracts/openapi.yaml`. When the mobile app needs an
  endpoint that is not in the contract yet, write the call against the shape
  the PRD describes and flag it in the PR.

Never invent product behaviour. If the design and the backend disagree (for
example a field length), follow the design, keep the value in one constant,
and flag the mismatch in the PR.

## Branches and pull requests

- Integration branch: `release/v0.1`. `main` is for releases.
- One branch per ticket, cut from `release/v0.1`, named
  `feature/<TICKET>-<short-slug>` (for example
  `feature/ONB-FE-05-consent`).
- Open a draft PR into `release/v0.1`. Stack a branch on another one only when
  the ticket really depends on unmerged work, and say so in the PR body.
- Use Conventional Commits with a scope:
  `feat(mobile): ...`, `fix(api): ...`, `test(mobile): ...`, `docs: ...`.
- Keep a PR to one ticket. List open questions in the PR body instead of
  guessing.

## Before you push

Run the checks for the app you touched, from the repository root:

```sh
# Flutter
npx nx run mobile:format-check
npx nx run mobile:lint
npx nx run mobile:test

# Go
npx nx run api:lint
npx nx run api:test
```

Or directly in `apps/mobile`: `dart format lib test`, `flutter analyze`,
`flutter test`. All of them must pass with zero analyzer issues. Never skip or
delete a failing test to get green.

If you change UI, regenerate goldens on Linux with
`flutter test --update-goldens --tags golden` and look at the new images
before committing them.

## Flutter conventions (`apps/mobile`)

- **Layers:** `features/<name>/{domain,data,application,presentation}`.
  `domain` is pure Dart (no Flutter, Supabase or Dio imports). `presentation`
  never imports `data` directly; it reads providers from `application`.
- **Riverpod 3, hand-written providers** (no codegen). Async notifiers use
  `retry: (_, _) => null`. Don't read `ref` or `state` inside `onDispose`;
  capture what you need first.
- **Plugins behind interfaces.** Wrap every platform plugin (image picker,
  geolocator, FCM, nsfw_detect, secure storage) in an adapter with an
  interface in `domain`, so tests use fakes and never touch a platform
  channel.
- **API calls** go through `core/api/ApiClient`. Don't create a raw `Dio`.
  Errors arrive as `Failure` subtypes from `core/errors/failure.dart`; map
  them to UI states, never show raw messages.
- **Routing:** add paths to `app/routes.dart` and screens to
  `app/router.dart`. Gate logic lives in the pure `resolveStartRoute`; add a
  unit test when you change it.
- **UI:** build from `core/widgets` (`OmaScaffold`, `OmaButton`, `OmaField`,
  `OmaChoiceChip`, `OmaBanner`) and theme tokens in `core/theme`. Don't hard-code
  colours or fonts. Support light and dark themes.
- **Config:** new build-time values go in `AppConfig` and
  `config/dev.example.json`. Never commit `config/dev.json` or any secret.
- **Dependencies:** versions in `pubspec.yaml` are pinned exactly. Add or bump
  one on purpose, and say why in the PR.
- **Tests:** put tests under `test/` mirroring `lib/`. Use
  `baseOverrides(...)` from `test/helpers/fakes.dart` and `pumpScreen` /
  `goldenBothThemes` from `test/helpers/golden.dart`.
- **Privacy:** location is rounded on device before it leaves the phone,
  photos are checked on device before upload, and onboarding drafts live in
  secure storage and are cleared on sign-out. Keep it that way.

## Go conventions (`apps/api`)

- Entry points in `cmd/api` and `cmd/worker`; business modules under
  `internal/<module>`. The API envelope is `{"data": ...}` on success and
  `{"error": {"code", "message", "details"}}` on failure.
- Run `go fmt`, `go vet` and `go test ./...` (or the Nx targets above).

## Environment notes

- Flutter must satisfy Dart `^3.13.7` (the scaffold used Flutter 3.47.9).
  In cloud sessions the SDK is at `/opt/flutter-sdk/flutter/bin`; add it to
  `PATH`.
- Cloud sessions have no Android SDK or Xcode, so they can run analyze and
  tests but cannot build or run the app on a device. Say so in the PR when a
  change was not run on a device.
- Don't commit build output, `coverage/`, `.dart_tool/` or `node_modules/`.
