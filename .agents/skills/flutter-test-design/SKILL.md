---
name: flutter-test-design
description: Use when adding or changing LineupDesktop Dart/Flutter regression tests, async fakes, widget semantics/focus tests, goldens, or Dart platform-channel contract coverage. Does not replace physical Windows acceptance or prescribe new tests for prose-only edits.
---

# Flutter Test Design

Apply [the agent testing rules](../../../AGENTS.md#testing): **if this test disappeared, could a user-visible bug ship that no remaining test catches?**

## Strongest feasible proof and one owner

- Prefer real-app/executable E2E on generated/fixture inputs with a checked
  artifact where automation is credible. For desktop behavior impractical to
  automate, use the strongest real-widget/public-contract owner and name the
  remaining physical acceptance. Devices, browsers, and native media use a gated
  tier. [A missing harness](../../../docs/DEVELOPMENT.md#current-test-tiers-and-gaps) alone does not make E2E
  infeasible; synthetic UI and fake-boundary spine tests are narrower proof.
- Before adding a test, answer: (1) which user-visible behavior it protects;
  (2) which credible regression fails it; (3) why existing E2E/owner tests miss it;
  (4) whether it needs a production flag, export, hook, or injection parameter
  with no production caller. If (4) is yes or (3) has no answer, do not add it.
- Each behavior has one owner: the strongest, least-faked test. Add a parameter
  row (a Dart case loop) only for a genuinely distinct case: some mutation fails
  that case but not the existing owner cases. Do not add duplicate proof.
- A bug regression must fail on the pre-fix code, once, at the highest seam that
  reproduces it. Internal assertions never justify a test's existence.

## Observable behavior and the flow rule

User-visible means anything a user or persisted consumer can observe:
exit codes and documented output; files, records, caches, config; requests sent;
hangs, leaked children, partial writes; UI/platform behavior; documented API
returns/errors; whether a warning/error is emitted; cache reuse/invalidation.
Internal means fake call counts/order, intermediate fields, private helpers whose
public output is tested elsewhere, and undocumented log/progress order/rendering,
unless it crashes, hangs, or corrupts output.
**Flow rule:** a value is internal only if it never reaches a user-visible output.
Parsed, selected, formatted, or config values reaching a query, label, filename,
report, persisted file, or exit code are cases of that output's owner test.

## Isolated tests and forbidden patterns

List failure modes before writing code. Isolated tests are only for:

- `edge`: boundary input with a user-visible consequence;
- `failure`: user-visible failure E2E cannot trigger (timeout, kill, partial write,
  corrupt input, wrong exit code);
- `contract`: documented/persisted format, citing the line and exact field;
- `network`: strict HTTP or transport boundary;
- `security`;
- `platform`.

Never write tests with no assertion or one that cannot fail; self-comparisons or
expected values computed by the code under test; copied inventories, manifests,
export lists, or constants; source/import/string greps that do not guard a
user-facing key, byte, or path; private call-shape/order assertions with no
observable order; mocks implementing the asserted behavior; or tests that only
keep a test-only export, wrapper, or hook alive.
**Test-only production code is dead code:** a production symbol with no non-test
caller is deleted, not tested. Never add production code for tests.
For the program's own caches, records, and payloads, keep one test per failure
outcome (refused, raised, cache miss, unavailable), not per malformed branch.
User-authored input, external data, security checks, and cache identity keep
per-branch edge tests.

## Boundaries, types, and asynchronous work

- Mock only heavy/external boundaries (HTTP, subprocess, clock, browser, native
  runtime), never the collaborator under test. HTTP mocks reject unexpected
  requests. Every subprocess and wait has an explicit timeout, including CTest,
  pending futures, and widget settling; avoid wall-clock sleeps for races.
- Tests are type-checked like production by `flutter analyze`, including
  `test/`, `tool/visual/`, and `test_driver/`. Use real types/interfaces for fakes;
  every ignore carries a reason. No coverage-percentage gates: coverage is local
  diagnosis (`TZ=America/New_York flutter test --coverage`), not a target.
- Control late success/error, disposal, and replacement with `Completer`s,
  existing clocks, and bounded widget pumps. Attach expectations before releasing failing futures; avoid
  `pumpAndSettle` with repeating timers. Prove cancellation stops work, not only
  UI status; distinguish native command acceptance from readiness/idle.
- Assert visible and saved results after failed/superseded mutations. Use old
  valid serialized data for schema changes; new-serializer roundtrips cannot
  prove compatibility. Preserve corrupt bytes on failed recovery. Use synthetic credentials/metadata and recognizable
  secret sentinels. Tear down controllers, players, handlers, sockets, temporary
  directories, and timers; keep helpers in test support, outside production.

## Existing owners and platform evidence

Read the relevant owner, not every suite: [scheduler](../../../test/channels/scheduler_test.dart), [controller](../../../test/app/lineup_controller_test.dart),
[store](../../../test/persistence/app_store_test.dart), [IO transport](../../../test/plex/plex_io_transport_test.dart), [coordinator](../../../test/playback/player_coordinator_test.dart),
[native adapter](../../../test/playback/windows_native_player_test.dart), [surface](../../../test/playback/native_video_surface_test.dart), [UI fixtures](../../../test/support/ui_fixture.dart).
The IO owner proves peer closure before teardown; adapter tests scope messenger handlers and identities.
Prefer behavior/focus/semantics for interaction; reuse production widgets and
[golden support](../../../test/support/golden_test_support.dart) for visuals. The
optional screenshot suites under `tool/visual/` run explicitly; the two Guide/UI acceptance golden suites are macOS-only. CI retains exact Guide alpha checks.
Skipped suites are not proof; baseline updates do not approve design. Follow
[protected Player/UI agreements](../../../.interface-design/system.md#player-protected-baseline).
Use [verification commands and timezone prerequisites](../../../docs/DEVELOPMENT.md#verification-by-task).
Mocks/geometry do not prove moving video, HDR, native composition, or Windows input:
those require [physical Windows acceptance](../../../docs/windows-native-validation.md) at the exact commit.
Missing device evidence does not block unrelated portable work.
