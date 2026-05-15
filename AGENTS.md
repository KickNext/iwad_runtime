# AGENTS.md

This file is for coding agents working in this repository. Keep user-facing
README content focused on package usage; keep maintenance, release, and agent
workflow rules here.

## Project

`iwad_runtime` is a Flutter plugin/package that runs app-supplied IWAD data
through native FFI backends and a web WASM backend.

- Do not bundle, download, imply, or test with proprietary IWAD data in the
  repository.
- Applications must provide an IWAD path or bytes explicitly.
- Preserve support for Android, iOS, Linux, macOS, Web, and Windows.
- Native platforms use `dart:ffi`; Web uses the bundled WASM assets.
- Save data must remain scoped by IWAD identity, including the IWAD basename
  and content hash prefix, so different WAD files do not collide.
- The package source and vendored engine code are GPL-2.0-or-later. The
  canonical `LICENSE` file is intentionally kept in a form that `pana`
  recognizes as OSI-approved GPL-2.0.

## Repository Hygiene

- Prefer small, direct changes that match the existing structure.
- Use `rg`/`rg --files` for code search.
- Do not commit generated build products, `.dart_tool`, Flutter ephemeral
  directories, local save data, logs, screenshots, or local config files.
- Do not edit vendored engine code or generated bindings unless the task
  explicitly requires it.
- If `lib/iwad_runtime_bindings_generated.dart` must change, regenerate it from
  the FFI source instead of editing it by hand.
- Keep `.pubignore` from excluding root platform plugin folders such as `ios/`
  and `macos/`; pub.dev needs those files for platform support.

## Public API

- Export public package API from `lib/iwad_runtime.dart`.
- Keep public API documented with dartdoc. The pub.dev score requires at least
  20% coverage; the current target is to stay comfortably above that threshold.
- Avoid exposing backend internals unless they are part of the package contract.
- For new user-facing API, add focused tests and update the example if the API
  changes the normal integration path.

## Platform Verification

For changes that touch runtime behavior, input, audio, persistence, startup,
assets, FFI, WASM, or platform folders, verify more than compilation when
possible:

- macOS: run the example with `flutter run` and confirm video, input, audio,
  quit/suspend behavior, and save/load.
- iPhone/iOS: run on the device or simulator and confirm the app does not show
  a white screen, displays errors clearly, and save/load survives relaunch.
- Web: run the example in a browser and confirm frame rendering, input, audio,
  and save/load.
- Web WASM: run `bash tool/build_web_wasm.sh` and `flutter build web --wasm`
  from `example/`.
- For save changes, verify persistence across app restarts and verify that two
  different IWAD identities create separate save directories.

## Local Checks

Run the narrowest useful checks while developing, then run the package checks
before publishing or pushing a release-oriented change:

```sh
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run
```

For pub.dev scoring, use the same analyzer family as pub.dev when available:

```sh
dart pub global activate pana
dart pub global run pana . --no-warning --json
```

Expected release-readiness targets:

- `flutter analyze`: no issues.
- `flutter test`: all tests pass.
- `dart pub publish --dry-run`: 0 warnings.
- `pana`: 160/160 when the remote repository has the same committed state.

## CI/CD

CI lives in `.github/workflows/ci.yml` and must continue to cover:

- package checks on Ubuntu: `flutter pub get`, `flutter analyze`,
  `flutter test`, and `dart pub publish --dry-run`;
- Web WASM build;
- Android debug build;
- Linux debug build;
- macOS debug build;
- iOS simulator debug build;
- Windows debug build.

Publishing lives in `.github/workflows/publish.yml`. The publish job must stay
gated by release validation and all platform build jobs. Keep OIDC publishing
through the Dart reusable workflow; do not add long-lived pub.dev credentials.

## Versioning And Publishing

Package versions follow semantic versioning in `pubspec.yaml`.

- Stable releases use plain versions such as `0.1.0`, `0.1.1`, `0.2.0`.
- Prereleases use versions such as `0.2.0-dev.1`, `0.2.0-beta.1`,
  `0.2.0-rc.1`.
- Do not use Flutter app-style build metadata such as `+1` or `+1dev` for
  normal package releases.
- Every published version needs a matching `## x.y.z` section in
  `CHANGELOG.md`.

Before publishing a release:

1. Update `version:` in `pubspec.yaml`.
2. Add a matching `## x.y.z` section to `CHANGELOG.md`.
3. Run `dart run tool/check_release_version.dart vx.y.z`.
4. Run `flutter analyze`, `flutter test`, `dart pub publish --dry-run`, and
   `pana`.

The first pub.dev release must be published manually with:

```sh
dart pub publish
```

After the package exists on pub.dev, enable automated publishing for
`KickNext/iwad_runtime` with tag pattern `v{{version}}`. Pushing a matching Git
tag, such as `v0.1.0`, triggers the publish workflow.

## Dependency And Asset Rules

- Keep runtime dependencies minimal.
- Avoid adding platform-specific dependencies unless the corresponding platform
  behavior is tested.
- Keep Web assets in `assets/` and ensure `pubspec.yaml` lists every asset
  needed by the web loader.
- If WASM assets are rebuilt, run the web WASM build and package dry-run before
  publishing.

## Documentation Rules

- README is for package users: what the package does, how to use it, platform
  status, multiplayer boundaries, and legal notes.
- AGENTS.md is for maintainers and agents: release process, verification,
  CI/CD, repository workflow, and internal constraints.
- Keep examples concise and legally neutral; never reference proprietary IWAD
  distribution.
