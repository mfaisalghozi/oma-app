# Oma

A monorepo using Nx to run tasks for a Flutter mobile app, a Go backend, and a
future web frontend. npm manages workspace tooling, pub manages Flutter
packages, and Go modules manage backend dependencies.

## Repository structure

```text
apps/
  mobile/                 # Flutter application
    android/
    ios/
    lib/
    test/
    assets/
    pubspec.yaml
    project.json
  api/
    cmd/api/              # HTTP API with GET /health
    cmd/worker/           # Worker scaffold; no jobs configured yet
    internal/             # auth, profile, discovery, matching, chat,
                          # moderation, platform (reserved directories)
    migrations/
    go.mod
    project.json
  web/                    # Placeholder for the future web frontend
libs/contracts/           # Shared OpenAPI contract
  openapi.yaml
  project.json
tools/scripts/
infrastructure/
  docker/
  deployment/
```

Empty directories are tracked with `.gitkeep`. Infrastructure directories are
reserved for future Docker and deployment configuration.

## Workspace installation

Install Node.js 24 and npm, then run the following commands from the repository
root:

```sh
node --version
npm --version
npm ci
npx nx show projects
```

The project list should include `mobile`, `api`, `web`, and `contracts`.
`npm ci` installs Nx and the configured npm workspaces using the root
`package-lock.json`. It does not install Flutter packages or Go modules.

Install only the additional toolchains needed for the app you work on, as
described below. Make sure their executables are available on your `PATH`.

If you use direnv, the root `.envrc` scopes GitHub CLI authentication to the
personal account. Run `direnv allow` if prompted.

## Mobile app installation

### Prerequisites

1. [Install the Flutter SDK](https://docs.flutter.dev/install) and add its `bin`
   directory to your `PATH`. Dart is included with Flutter.
2. Use a Flutter release that satisfies `apps/mobile/pubspec.yaml`, which
   currently requires Dart `^3.13.7`. The original scaffold used Flutter 3.47.9
   with Dart 3.13.7.
3. Configure your target platform:
   - **Android:** install Android Studio, the Android SDK, and a compatible JDK
     using the [Flutter Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).
     Create an emulator or connect an Android device with USB debugging enabled.
   - **iOS:** use macOS with Xcode and follow the
     [Flutter iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup).
     Start an iOS simulator or connect a configured iPhone.

Check the toolchain and resolve any issues reported for your target platform:

```sh
flutter --version
flutter doctor -v
flutter devices
```

### Install dependencies and run

After completing the workspace installation, run from the repository root:

```sh
npx nx run mobile:pub-get
npm run mobile
```

To select a specific device, replace `DEVICE_ID` with an ID from `flutter devices`:

```sh
npx nx run mobile:serve -- -d DEVICE_ID
```

You can also use Flutter directly from the app directory:

```sh
cd apps/mobile
flutter pub get
flutter run
```

### Check and build

Run these commands from the repository root:

```sh
npx nx run mobile:lint
npx nx run mobile:test
npx nx run mobile:format-check
npx nx run mobile:format
npx nx run mobile:build                   # Android APK
npx nx run mobile:build:appbundle          # Android App Bundle
npx nx run mobile:build:ios                # iOS build without code signing
```

Build output is written to `apps/mobile/build/`; test coverage is written to
`apps/mobile/coverage/`. Android builds require the Android toolchain, and iOS
builds require macOS and Xcode. Signing and distribution require additional
platform configuration.

The Dart package name remains `oma_app`; the Android and iOS application IDs
are unchanged.

## API and worker installation

### Prerequisites

[Install Go](https://go.dev/doc/install) 1.26 or later, as required by
`apps/api/go.mod`, and verify the installation:

```sh
go version
```

### Install dependencies

After completing the workspace installation, download Go module dependencies:

```sh
cd apps/api
go mod download
cd ../..
```

The scaffold currently uses only the Go standard library, so this step may
report that there are no module dependencies to download. A `go.sum` file will
be generated when external dependencies requiring checksums are added.

The current API and worker do not require a database, message broker, or `.env`
file. Business modules, migrations, and job processing are not implemented yet.

### Run the API

From the repository root:

```sh
npm run api
```

The API listens on port `8080` by default. In a second terminal, verify it with:

```sh
curl http://localhost:8080/health
```

Expected response:

```json
{"status":"ok"}
```

To change the listening address in a POSIX shell:

```sh
API_ADDR=127.0.0.1:9090 npm run api
```

### Run the worker

In a separate terminal at the repository root:

```sh
npm run worker
```

The worker is a scaffold that waits for a shutdown signal. Stop it with `Ctrl+C`.
It shares the API's Go module and needs no separate dependency installation.

To run either entry point without Nx, use these commands from `apps/api`
(in separate terminals if running both):

```sh
go run ./cmd/api
go run ./cmd/worker
```

### Check and build

From the repository root:

```sh
npx nx run api:lint                       # go vet ./...
npx nx run api:test                       # go test ./...
npx nx run api:format                     # go fmt ./...
npx nx run api:build
```

The build produces API and worker executables in `dist/apps/api/`.

## Web app installation

`apps/web` is currently a placeholder registered as the `@oma/web` npm workspace.
It has no frontend framework, dependencies, or runnable targets yet. The
workspace installation (`npm ci` at the repository root) already includes it;
there is no separate installation or development server at this stage.

When implementing the web frontend:

1. Add the framework and application code under `apps/web`.
2. Add its dependencies to `apps/web/package.json` using npm workspaces, for example
   `npm install PACKAGE_NAME --workspace=@oma/web`, replacing `PACKAGE_NAME` with
   the actual package name. Commit the updated root `package-lock.json`.
3. Define the corresponding development, build, test, and lint targets in
   `apps/web/project.json`.
4. Document the framework's environment variables and run commands here.

Keep the Nx project name as `web` and use the root npm lockfile. See the
[npm workspaces guide](https://docs.npmjs.com/cli/using-npm/workspaces/) for
workspace dependency management.

## CI/CD

GitHub Actions workflows live in `.github/workflows/`:

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `mobile-ci.yml` | PRs and pushes to `main` / `release/**` touching `apps/mobile` | `pub get --enforce-lockfile`, `dart format` check, `flutter analyze --fatal-infos`, `flutter test --coverage` (goldens included). Golden diffs are uploaded as the `golden-failures` artifact when a test fails. |
| `api-ci.yml` | PRs and pushes touching `apps/api` | `gofmt` check, `go vet`, `go test -race`, build of API + worker. |
| `mobile-cd.yml` | `v*` tags and manual runs | Release AAB + APK (Ubuntu) and an unsigned `Runner.app` zip (macOS), uploaded as workflow artifacts. Tag `v0.1.0` builds version `0.1.0`; the build number is the workflow run number. |
| `mobile-integration.yml` | Manual only | Placeholder that runs `integration_test/` on an Android emulator. Skips until `apps/mobile/integration_test/` exists. |

### Goldens and the pinned toolchain

Golden images are compared pixel-for-pixel, so CI pins Flutter `3.47.9` and the
`ubuntu-24.04` runner. Goldens rendered on macOS or Windows will not match.
Regenerate them on Linux with the same Flutter version
(`flutter test --update-goldens`). To bump Flutter, change `FLUTTER_VERSION` in
every workflow, regenerate goldens, and commit both in one PR.

### Secrets

| Secret | Used by | Status |
| --- | --- | --- |
| `DART_DEFINES_JSON` | CD builds | Optional now. JSON passed with `--dart-define-from-file` (same keys as `config/dev.example.json`). Without it, builds have no Supabase/API config. |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Android release signing | TODO. Release builds currently use the debug key. |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play Console upload | TODO. Needs the Play developer account. |
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` | iOS signing (`flutter build ipa`) | TODO. Needs the Apple Developer account. |
| `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_P8` | TestFlight upload | TODO. |
| `GOOGLE_SERVICES_JSON_BASE64`, `GOOGLE_SERVICE_INFO_PLIST_BASE64` | Firebase (FCM, Crashlytics) | TODO. Needs the Firebase projects. |

The TODO steps are marked with `TODO(signing)`, `TODO(store)` and
`TODO(firebase)` comments in `mobile-cd.yml`.

## Shared contracts

`libs/contracts/openapi.yaml` defines the shared API contract. No separate
installation is required. Update the contract when API request or response
shapes change. Client generation and automatic schema validation have not been
configured yet.

The `api`, `mobile`, and `web` projects depend on `contracts` in the Nx graph.
Contract changes mark those consumers as affected and invalidate their related
cached tasks.

## Workspace checks and caching

From the repository root:

```sh
npm run lint                             # Flutter analyze and go vet
npm test                                 # Flutter test and go test
npm run build                            # Go binaries and Android APK
npm run graph
npx nx affected -t lint,test --base=main --head=HEAD
```

Workspace commands require the toolchains for all selected apps. Web and
contracts currently have no build, test, or lint targets. For CI on the main
branch, set `--base` to the appropriate comparison commit or branch.

Nx caches lint/test tasks and Go builds. Mobile builds, dependency installation,
formatting, and running applications are not cached. Lint/test inputs include
toolchain versions; Go build inputs also include Go platform configuration.

To bypass both the Nx cache and Go's test cache:

```sh
npx nx run api:test --skip-nx-cache -- -count=1
```

See the [Nx project configuration reference](https://nx.dev/docs/reference/project-configuration)
and [Nx cache input reference](https://nx.dev/docs/reference/inputs) for details.
