---
name: flutter-test-design
description: Use when adding or changing LineupDesktop Dart/Flutter regression tests, async fakes, widget semantics/focus tests, goldens, or Dart platform-channel contract coverage. Does not replace physical Windows acceptance or prescribe new tests for prose-only edits.
---

# Flutter Test Design

Test the observable contract through the nearest existing seam. Reuse meaningful
coverage; add a regression for a real failure or a changed invariant, not to mirror
private branches or increase test count. Do not add production layers solely to
expose internals to tests.

## Choose the seam

Read the example relevant to the behavior, not every suite:

| Behavior | Existing example and useful proof |
| --- | --- |
| Scheduling and content policy | [scheduler tests](../../../test/channels/scheduler_test.dart): deterministic inputs, boundary times, stable outputs |
| Superseded operations and state mutations | [controller tests](../../../test/app/lineup_controller_test.dart): observable state, delayed failures, save/rollback, credential ordering |
| Persisted format and recovery | [store tests](../../../test/persistence/app_store_test.dart): earlier serialized state, original corrupt bytes, real temporary files and failed recovery |
| HTTP cancellation | [IO transport tests](../../../test/plex/plex_io_transport_test.dart): loopback peer disconnects before client teardown; stale-result rejection alone does not prove abort |
| Playback policy | [coordinator tests](../../../test/playback/player_coordinator_test.dart): use the existing native fake while exercising real coordination |
| Native Dart contract | [adapter tests](../../../test/playback/windows_native_player_test.dart): scoped messenger handler, captured request identity and injected native events |
| Flutter composition | [surface tests](../../../test/playback/native_video_surface_test.dart) and [UI fixtures](../../../test/support/ui_fixture.dart): real widgets, geometry, focus, semantics, synthetic content |

## Make failures observable

- Control asynchronous ordering with `Completer`s and injected clocks or widget
  pumps. Cover the relevant late success/error, disposal, or replacement sequence.
  Attach expectations before releasing a failing future. Avoid wall-clock sleeps
  for races and `pumpAndSettle` when a ticker or repeating timer cannot settle.
- Fake external boundaries, not the owner whose behavior is being proved. For
  cancellation tests, distinguish work stopping from a cancelled UI status. For
  native load/stop tests, distinguish command acceptance from readiness/idle.
- For persisted mutations, assert the visible and saved result after failure or
  supersession. Include old valid serialized data when changing a schema; a
  roundtrip using only the new serializer cannot prove compatibility.
- Use synthetic credentials and metadata. Test secret absence across producer
  output with recognizable sentinels; do not bring real Plex data into fixtures.
- Register teardown for controllers, player instances, channel handlers, sockets,
  temporary directories, and timers. Keep fixture helpers in test support and
  preserve production/fixture encapsulation.

## Calibrate UI and platform evidence

Prefer behavior, focus, and semantics assertions for interaction changes. For
visual changes, reuse the production widget harness and
[golden support](../../../test/support/golden_test_support.dart). The two optional golden
suites under `tool/visual/` are macOS-only and run explicitly for visual review;
required CI retains the exact `test/app/guide_opacity_test.dart` checks.
A skipped suite is not visual proof. Updating a baseline
does not approve a design: follow
[the interface system](../../../.interface-design/system.md#player-protected-baseline)
for protected Player comparisons and existing UI agreements.

Use the maintained [verification map](../../../docs/DEVELOPMENT.md#verification-by-task)
for commands and host prerequisites, reusing still-current results. Adapter mocks
and geometry tests cannot establish moving video, HDR, native composition, or
Windows input behavior. Keep those claims tied to
[physical Windows acceptance](../../../docs/windows-native-validation.md) at the
tested commit; missing device evidence does not block unrelated portable work.
