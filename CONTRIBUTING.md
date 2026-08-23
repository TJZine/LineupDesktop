# Contributing to Lineup Desktop

Lineup Desktop is a pre-release Flutter-native desktop application with a narrow
Windows C++/libmpv boundary. Contributions should improve the current
architecture rather than preserve the historical Electron implementation.

Target `flutter-mvp` unless an issue or maintainer explicitly names another
base branch.

## Before contributing

Read:

1. [AGENTS.md](AGENTS.md)
2. [Documentation index](docs/README.md)
3. [Development](docs/DEVELOPMENT.md)
4. [Architecture](docs/architecture.md)

For Windows media, runner, engine, DirectComposition, or packaging changes, also
read [Windows Native Acceptance](docs/windows-native-validation.md) and
[Windows Runtime Provenance](docs/windows-runtime.md).

The preserved Electron implementation is on `electron-ui`; use the immutable
`bfaee636748f2a0d442f3690b7ba5262d32ff17c` baseline when provenance matters.
The `initial-build` branch is a later historical Flutter-replatform milestone.
Neither is a compatibility target; inspect the source that matches the evidence
being investigated.

## Architecture constraints

- Flutter/Dart owns application state, product policy, Plex workflows, channels,
  schedules, settings, persistence, diagnostics, UI, Guide, navigation, input,
  focus, overlays, and accessibility.
- C++ owns only behavior that materially requires native media or platform
  ownership: libmpv lifetime and commands, decoded-frame presentation, Windows
  handles, DirectComposition, fullscreen placement, and bounded native facts.
- Keep one authoritative owner per responsibility.
- Reject stale asynchronous work explicitly and bound queues, caches, and
  user-controlled workloads.
- Do not add Electron/WebView compatibility, helper processes, duplicate
  coordinators, event buses, service locators, speculative plugin systems, or
  dependency layers without a demonstrated owner and consumer.
- Prefer deletion or direct replacement over compatibility shims in this
  pre-release codebase.

## Development setup

Use the exact Flutter revision and native prerequisites documented in
[Development](docs/DEVELOPMENT.md). Do not silently substitute a newer SDK,
engine, patch, or media runtime when validating repository behavior.

Common checks:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Run focused tests while developing, then run the full relevant suite before
requesting review. A compiling Windows build does not prove native video,
DirectComposition, HDR, hardware decode, focus, or packaged runtime behavior.

## Change design

Before editing:

- trace the current owner, callers, tests, persistence, and failure behavior;
- identify the smallest cohesive change;
- state what evidence can prove it;
- consider security, accessibility, cancellation/currentness, and rollback; and
- avoid unrelated cleanup.

Add dependencies only when the concrete reliability or ownership benefit
outweighs activity, license, desktop support, transitive cost, and debugging
cost.

## Tests and validation

Match proof to risk:

| Change | Minimum expected evidence |
| --- | --- |
| Pure policy/model | Focused unit tests plus full format/analyze/test |
| Widget, focus, semantics, responsive layout | Focused widget tests at representative sizes and the relevant full suite |
| Persistence or credentials | Failure/rollback tests, scope isolation, and secret-flow review |
| Native player contract | Dart contract tests, C++/CMake build proof, lifecycle/stale-event review |
| DirectComposition, video layering, HDR, hardware decode, fullscreen, input, packaging | Physical Windows evidence at the exact commit, recorded through the native-acceptance plan |

Do not convert missing physical evidence into a support claim. Classify it as
unverified or blocked and state the exact test still required.

## Security and private data

Never commit or post:

- Plex tokens or authorization headers;
- token-bearing media or artwork URLs;
- credential-store output;
- private media metadata not required for a minimal reproduction;
- personal filesystem paths; or
- unredacted diagnostics, crash dumps, screenshots, or recordings.

Report vulnerabilities through [SECURITY.md](SECURITY.md), not a public issue.

## Documentation changes

Documentation is part of the product. A documentation change should:

- name its audience and status;
- distinguish implemented, deterministically tested, platform validated, and
  supported behavior;
- link to the authoritative version or provenance owner instead of duplicating
  volatile pins;
- include failure and recovery behavior;
- keep navigation links current; and
- use synthetic or deliberately redacted examples and screenshots.

When behavior changes, update the smallest authoritative document in the same
pull request. Do not rewrite historical audit sections to imply evidence they
did not observe.

## Commits and pull requests

Use coherent conventional commits such as:

```text
feat(guide): add ...
fix(player): prevent ...
docs: clarify ...
test(channels): cover ...
ci: gate ...
```

A pull request should explain:

- the user or maintainer problem;
- the ownership and architecture decision;
- what changed and what was intentionally not changed;
- validation actually performed;
- platform evidence still missing;
- security, accessibility, performance, and packaging effects when relevant;
  and
- rollback or recovery considerations for consequential changes.

Keep the diff focused. Do not merge a native-media change solely because CI
compiled it. Independent review is appropriate for credential/data-loss risk,
complex concurrency, native ABI or lifetime work, DirectComposition, HDR, and
release packaging, but it remains an explicit maintainer decision.

## Reporting issues

Use the repository issue templates and include the operating system, exact
commit or package build information, reproduction steps, expected and actual
behavior, and only redacted diagnostics. User-facing troubleshooting is in the
[User Guide](docs/user-guide.md).
