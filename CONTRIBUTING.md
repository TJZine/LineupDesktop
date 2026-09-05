# Contributing to Lineup Desktop

Lineup Desktop is a pre-release Flutter-native desktop application with a narrow
Windows C++/libmpv boundary. Contributions should improve the current
architecture rather than preserve the historical Electron implementation.

Target `flutter-mvp` unless an issue or maintainer explicitly names another
base branch.

## Before contributing

Start with [AGENTS.md](AGENTS.md), then read the relevant workflow and ownership
sections it names. Use the [documentation index](docs/README.md) when the right
authority is unclear. Read Windows acceptance and runtime provenance sections
when the task involves native behavior, packaging, or support claims; broaden
reading when an invariant remains unclear.

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

Use the exact Flutter revision and task-specific prerequisites documented in
[Development](docs/DEVELOPMENT.md). Do not silently substitute a newer SDK,
engine, patch, or media runtime when validating repository behavior.

Commands and evidence boundaries live in
[Development's verification map](docs/DEVELOPMENT.md#verification-by-task).

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

Use [Development](docs/DEVELOPMENT.md#verification-by-task) to select focused
tests and the relevant full checks. Reuse inspected results while their tested
code, inputs, dependencies, and relevant environment remain unchanged; rerun
checks invalidated by edits or integration. Documentation-only changes need
structural and claim checks, not product test reruns.

Classify missing physical Windows evidence as unverified or blocked for the
specific native/support claim, and state the exact scenario still required.
It does not block unrelated portable work. Compilation alone never establishes
native presentation, HDR, hardware decode, physical input, or package runtime
behavior.

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
