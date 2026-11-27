# Continuous Integration and QA

This project inherits its Flutter build matrix from `Uwaang/flutter-template`. Once the dedicated GitHub repository is created, its own `main` branch is canonical; do not push app-specific code to the original template.

Any private historical CI or workstation-specific automation is managed separately and must **not** be copied into public branches, GitHub Actions, pull requests, logs, artifacts, or documentation.

## Default GitHub validation

Workflow: `.github/workflows/platform-builds.yml`

- On pull requests and pushes to `main`, run formatting, fixture unit tests, generated-source consistency, analyzer checks and Flutter tests.
- After the quality job succeeds, build **seven compile targets**: Web JavaScript, WebAssembly, Linux, Windows, Android profile AAB, macOS and unsigned iOS device app.
- Upload build artifacts for seven days using GitHub-hosted runners. Windows ZIP includes runtime files (not an installer); Android now includes both a profile AAB and an installable synthetic/debug-signed `app-production-profile.apk` under the same `compile-only-android` artifact.
- The `Artifact download guide` job adds an Actions run summary listing the seven artifact names, their purposes and download location. This is **not** an automatic GitHub Release or production CD deployment.
- Use only generated **non-secret placeholders** via `tool/create_ci_env.dart` and `tool/prepare_native_ci.py`; Android profile AAB uses synthetic/debug signing. These are **not** store-signed artifacts.
- A change consisting entirely of Markdown, agent guidance or archived workflow images is excluded using `paths-ignore`. Other changes still get the full quality and build matrix.
- `workflow_dispatch` remains available for an authorized manual build. Branch-protection required checks should be reviewed before marking an entire skipped workflow as required.

The active Flutter SDK version comes from `.fvmrc`. Executable workflow YAML and project configuration take precedence over historical text.

## Native Assets compilation cost

- **Use `dart tool/create_ci_env.dart`, not `dart run tool/create_ci_env.dart`**, for the standalone CI fixture script. The latter invokes the OpenCV Native Assets build hook even though the script only writes placeholder environment files.
- **Keep `dart run build_runner build --delete-conflicting-outputs` in each CI job**. This repository deliberately ignores generated Dart (including routing, model, provider and asset code). Fresh GitHub runners must regenerate it before compiling. The root quality job also validates generated code with analyzer and tests; `git diff --exit-code` alone does not detect ignored generated files.
- Actual Flutter native builds and the Linux Dart FFI smoke test still invoke the native OpenCV hook when needed. The direct script form does not disable Native Assets in the app or alter platform coverage.
- This is a low-maintenance first optimization. Evaluate further compiler/hook caches separately based on measured runtimes, cache size, and platform correctness.

## Native OpenCV validation

Workflow: `.github/workflows/native-vision.yml`

- Checkout the pinned `third_party/opencv` Git Submodule recursively.
- Build the C++ vision engine and static OpenCV components on Linux, Windows, macOS, Android ARM64, and iOS ARM64 using CMake.
- On Linux, run a separate Dart Native Assets smoke test to exercise the CMake build hook and C ABI through Dart FFI; compiling C++ alone does not verify the hook.
- The app root analyzer excludes `packages/vision_engine/**` because it is a separate pub package. Its own `dart pub get`, `dart analyze`, and `dart test` run from that package directory in the native CI workflow.
- Treat this as compilation validation only. Dart Native Assets hook packaging, mobile runtime loading, camera integration and Web OpenCV/WASM need independent tests.
- Every native matrix target must first complete successfully in the new repository before checks become required for merging.
- The inherited Web JS/WASM Flutter jobs do **not** yet compile the OpenCV engine.

## Web runtime verification (conditional)

Workflow: `.github/workflows/web-runtime-smoke.yml`

- Run automatically on relevant PRs and `main` pushes affecting `lib/`, `assets/`, `web/`, `qa/web/`, web runtime workflow, Flutter/lock/config versions or CI fixture setup.
- Compile **both Web JS and Web WASM**, then run the same Playwright Chromium first-screen smoke against each compiled artifact.
- The SPA server in `qa/web/spa_server.py` provides route fallback for refreshed client-side URLs without silently hiding missing assets.
- This is separate from compiling successfully. It checks that the splash disappears and the mock login actually renders.
- The tests do not use real Supabase credentials by default. See [QA](QA.md) for details.

The independent runtime job currently recompiles Web JS/WASM instead of consuming the platform build job's archives. Do not add an artifact handoff just to save lines; consider it only after comparing runtime, complexity and failure isolation.

## Public website previews (GitHub Pages)

Workflow: `.github/workflows/pages-preview.yml` (SCRUM-447).

This is **public, mock-only UI preview**, not production hosting. It reuses the existing Flutter Web build steps with `tool/create_ci_env.dart`, keeps Supabase credentials empty, and disables the default PWA service-worker caching for rapidly changing previews.

- After Pages is enabled, the expected **main** URL is `https://uwaang.github.io/flutter-template/`.
- Open, same-repository PRs (maximum three newest) are built into `https://uwaang.github.io/flutter-template/previews/pr-N/`, including the Material 3 redesign in PR #10. PRs from forks are not built.
- The actual site is a single GitHub Pages deployment from the **default branch**; `flutter build web --base-href` is set independently for the root app and each PR subdirectory. GitHub's `actions/upload-pages-artifact` and `actions/deploy-pages` publish it. Build jobs are read-only; only the separate deployment job has Pages/OIDC permissions.
- A push to `main`, successful PR Web JS/WASM runtime-smoke workflow, or manual `workflow_dispatch` refreshes the site. Draft PRs are included. A PR closed **without merging** may remain in Pages until the next refresh; manually run the workflow to remove it immediately.
- The build job also runs without deploying when this workflow itself changes in a pull request. This is a build smoke, **not** proof of a successful Pages deployment.
- **One-time repository setting:** `Settings → Pages → Build and deployment → Source → GitHub Actions`. The Pages URL is **not live** until that configuration is set and a deployment job succeeds. The connected GitHub code tools cannot change repository-admin Pages settings.
- The Pages uploader **must retain Flutter's `assets/.env*` files**: although their names begin with a dot, they are required by the `flutter_dotenv` initialization and have intentionally empty Supabase values in `tool/create_ci_env.dart`. `actions/upload-pages-artifact@v4` dropped these files by default, leaving the site at splash. Use `@v5` with `include-hidden-files: true`, validate that every staged hidden file is an expected non-secret fixture, then inspect the packaged tar to confirm the files survived. Never enable this option without the public-fixture validation.
- No PAT, new hosting provider, custom domain, API keys, backend tables, or GitHub Pages write token in the PR build step. The `github-pages` environment should permit deployments only from `main`.
- GitHub Pages uses **hash-based Flutter routes** (`/#/authentication`) because Pages does not provide the `index.html` rewrite required for path URLs such as `/authentication`. Page reloads or sharing a nested path otherwise produce GitHub Pages' own 404 page. Compile Pages Web JS with `--dart-define=FLUTTER_TEMPLATE_PAGES_HASH_ROUTING=true` and retain path-based routing for normal apps and the Playwright SPA server. The same opt-in routing condition must exist in each PR preview's `lib/app/setup/setup_app.dart` until that config change is merged into their common base. The root `/previews/pr-N/` path and URL fragment remain independent.
- The website includes Web **JS** builds for browser review, not the separately compiled WASM CI target. The seven-platform compile matrix and two actual Web runtime smoke jobs remain the source of truth for those validations.

## Android runtime verification (manual)

Workflow: `.github/workflows/android-runtime-smoke.yml`

- **Manual `workflow_dispatch` only**. An Android emulator run is not a required PR or `main` merge gate.
- Build a non-production profile APK, start an Android API 34 emulator, assert the rendered `Mock Sign In` screen and retain useful failure evidence.
- The Gradle preparation experiment uses `gradle/actions/setup-gradle@v6` with `cache-provider: basic` (open-source cache), replacing bespoke multi-mirror download and ZIP caching. The wrapper distribution remains version 8.14.3 and pins `distributionSha256Sum` in `android/gradle/wrapper/gradle-wrapper.properties`.
- `setup-gradle` validates the wrapper JAR. The distribution SHA check is enforced separately by Gradle Wrapper.
- **The simplified Gradle path is experimental until the emulator job succeeds**; restore the prior implementation if the old failure mode reappears. No auto-trigger is left on long-lived branches.

GitHub's `workflow_dispatch` is available for workflow files published on the repository default branch. Before this branch is merged, validate the experiment in an explicitly approved isolated test run rather than claiming it has passed.

## Real Supabase authentication

SDK, browser and Android live-auth tests remain **opt-in only** and must use a disposable test project. These tests can create real anonymous users, so they must never run automatically on public pull requests or against a production backend. See [Supabase-first setup](SUPABASE_FIRST.md) and [QA](QA.md).

## Public-source security and releases

- Keep standard CI on **GitHub-hosted runners** with read-only contents permissions. Do not register private lab computers, self-hosted runners or private network access as runners for untrusted public PRs.
- Do not add private CI YAML, internal DNS/IP addresses, personal directories, credentials, protected variables or signed release keys to public source or build logs.
- Inherited Firebase app-distribution and Play Store workflow examples are not part of the active repository CI. Do not reinstate them without a separate release design and review.
- Host compilation is **not** GUI-runtime validation on Windows/macOS/iOS, production code signing, full OAuth verification or App Store/Play Store deployment.
- The original upstream STRV license and attribution remain in source control.

See [Project setup](PROJECT_SETUP.md) for local configuration and private signing guidance, and [Project overview](PROJECT_OVERVIEW.md) for the app's actual startup integrations.
