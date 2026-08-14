# Review Context

- Source: inferred from repository instructions and stable project documentation; no tracked `.codex/review-context.md` exists.
- Cache status: Refreshed.
- Stack and runtime: Native Flutter/Dart desktop application targeting macOS and Windows. Reproducible toolchain is Flutter 3.47.0 / Dart 3.13.0.
- Architecture and ownership: Flutter/Dart owns product logic, Guide behavior, networking, scheduling, state, input, focus, overlays, and accessibility. C++ is limited to native media/platform behavior. The Dart application is a feature-oriented modular monolith with one composition root.
- Review calibration: Inspect real call paths, fix root causes, keep one owner per responsibility, avoid speculative abstractions and new dependencies, make asynchronous cancellation/currentness explicit, and bound queues/caches whose inputs can grow.
- High-risk areas: Credentials and token-bearing Plex URLs; asynchronous schedule/currentness behavior; native libmpv lifetime and Windows DirectComposition integration; release provenance and packaging.
- Verification canon: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`; macOS and Windows builds where platform code changes. Hardware, HDR, and DirectComposition claims require Windows evidence.
- CI: Ubuntu formatting/analyze/tests, plus macOS and Windows builds. The Windows job also runs focused portable-UI tests and builds against a pinned local-development libmpv artifact; Windows engine inputs additionally trigger a pinned patched-engine build.
- Uncertainties: No maintainer-curated tracked review profile exists. Team process and risk tolerance beyond repository instructions are unknown.
- Evidence: `AGENTS.md`, `docs/DEVELOPMENT.md`, `docs/architecture.md`, `pubspec.yaml`, `.github/workflows/ci.yml`.
