# Development

Lineup Desktop work normally moves through five activities in one session:

1. **Inspect** the current flow, its owners, tests, and platform constraints.
   Use `git show origin/initial-build:<path>` only when historical behavior is
   relevant.
2. **Decide** the responsibility owner, dependency direction, failure behavior,
   and proportionate proof before editing.
3. **Implement** the smallest cohesive change that meets current requirements.
   Delete displaced alternatives and keep commits coherent.
4. **Verify** with fresh, observed evidence matched to the risk.
5. **Self-review and close out** the complete diff, remaining platform limits,
   and whether independent review is specifically worthwhile.

These are not mandatory separate agents, sessions, tracked plans, Tiers, or
handoff formats. Independent review is optional and never launched
automatically. Recommend it for novel security boundaries, credential or data
loss risks, complex concurrency, native ABI/lifetime work, or Windows media and
presentation changes whose proof deserves a second specialist.

## Architecture practice

Use a feature-oriented modular monolith. A feature owns its models, policies,
state, and UI where that improves cohesion. The application bootstrap is the
single composition root; dependencies point from that root into features and
are passed explicitly through constructors. Avoid repeated
`data/domain/presentation` ceremonies and generic `core` or `utils` dumping
grounds. Local widget state stays local. Adopt one state-management package only
when a concrete cross-feature asynchronous state graph shows a material
debugging, testing, or correctness advantage over Flutter/Dart built-ins.

Current requirements outrank hypothetical compatibility. Keep one owner per
responsibility and make cancellation/currentness explicit for asynchronous
work. Bound queues and caches whose inputs can grow.

## Quality and safety

- Test pure policies and public seams. Add widget/integration/manual proof when
  behavior depends on focus, accessibility, rendering, lifecycle, or native
  platform integration. Do not use brittle tests merely to increase coverage.
- Evaluate each dependency for current need, activity, license, desktop support,
  transitive cost, debuggability, and standard-library alternatives. Record
  material license obligations before shipping bundled native libraries.
- Never commit Plex credentials, authorization headers, tokenized media URLs,
  private media metadata, or unredacted diagnostics. Redact at the owner before
  values cross logging, UI, or export boundaries.
- Keep scheduling deterministic and pure. Cancel or reject stale network and
  playback results. Avoid blocking the UI isolate; measure before optimizing,
  then isolate CPU-heavy work and bound large guide/channel workloads.
- Use coherent conventional commits. Keep generated platform scaffolding with
  the feature that requires it, and do not mix unrelated cleanup.

## Commands

Flutter SDK `3.47.0` (revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05`, Dart `3.13.0`) is the reproducible
toolchain for macOS, Windows, and CI.

```sh
dart format .
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run -d macos
flutter build macos
flutter build windows # run on Windows
```
