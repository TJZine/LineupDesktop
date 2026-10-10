# Scheduled Program Continuation Plan

**Status:** Implemented on October 10, 2026. Product decisions below were made
by the user. Windows native compilation and the physical acceptance rows below
remain outstanding; portable verification does not establish native behavior.

**Problem:** When a channel's program reaches the end of its final media part,
Lineup clears playback and shows **Playback stopped**. A channel should keep
airing: the next scheduled program should start. The
[user guide](user-guide.md#known-limitations) currently lists this as a known
limitation.

## Approved behavior

A channel airs its schedule. Continuation is an automatic re-tune of the same
channel that prefers to start the next program from its beginning.

1. **Next program starts immediately.** When the loaded program ends naturally,
   start the program that follows it in the schedule, from its beginning. This
   also applies when the media ends before its scheduled slot does. There is no
   hold, waiting period, or new slate.
2. **Small lateness is carried.** Each switch takes a few seconds to load, so
   the channel can run slightly behind the Guide clock. Do not skip the opening
   of the next program to remove that delay.
3. **Catch up after falling far behind.** If the next program's scheduled start
   is more than **30 seconds** in the past when continuation begins (typically
   after a DVR pause), tune to whatever is airing now at its live position
   instead, exactly like a manual tune.
4. **A cut-off stream is a failure, not an ending.** If the media stops more than
   **30 seconds** before its known duration, do not advance. Show the existing
   error overlay with Retry; Retry is an ordinary tune (live join).
5. **Player program info follows the loaded program.** Player title, progress
   context, and **Up next** describe the program actually loaded, not the
   wall-clock schedule. The Guide and mini Guide rows stay wall-clock.
6. **Existing controls keep priority.** A user tune, Stop, sleep-timer expiry,
   sign-out, lineup/content change, or dispose supersedes a pending
   continuation. Continuation never retries automatically after a failure.

Accepted consequence: if a channel's files are consistently shorter than their
scheduled slots, playback drifts slightly ahead of the Guide until the next
manual tune.

Rejected alternatives:
- **Hold until the scheduled boundary:** adds waiting and UI for gaps that are
  usually seconds.
- **Time-shifted channels:** always play the next program from its start and
  never catch up. This needs a behind-live indicator, a jump-to-live action, and
  Guide/OSD changes.

## Current design facts

Line references are against `c23f65ae` and may move.

- **Tune joins live.** `PlayerCoordinator._performTune`
  (`lib/playback/player_coordinator.dart:534`) resolves
  `guide.ensureCurrentProgram(channelId)` and loads at
  `now - scheduled.start`, starting from 0 when that is 2 seconds or less.
- **Part advance stops after the final part.** `_advancePart` (`:915`) advances
  through parts of one Plex item. After the final part it clears
  `_activePlayback`/`_activeChannel`, which produces the **Playback stopped**
  slate (`lib/playback/player_view.dart`, `_StoppedSlate`).
- **Terminal events are handled together.** The coordinator treats
  `PlayerState.ended` and `PlayerState.stopped` alike (`:446`). It infers a
  natural end from "stopped while a request is active and not replacing".
- **Native does not distinguish end-of-file from stop.** The handler for
  `MPV_EVENT_END_FILE` (`windows/runner/native_player.cpp`, around line 1106)
  emits `stopped` for every non-error end reason. `ended` exists in the Dart
  enum but no native path sends it. `WindowsNativePlayer._handleState`
  (`lib/playback/windows_native_player.dart:428`) maps unknown states to `idle`.
- **Stop completion is independent.** Dart `stop()` completion does not wait
  for a native `stopped` event.
- **Program info is wall-clock.** `currentProgram`/`nextProgram` (`:210`) read
  `guide.currentProgram(id)` and `guide.nextProgram(id)` at wall-clock time.
  Consumers are `lineup_shell.dart` (`:103`, `:227`, `:554`) and
  `player_view.dart` (`:380`, `:751`, `:1399`). `player_view.dart:2480` reads the
  guide directly for mini Guide rows and stays wall-clock.
- **Successor lookup exists.** Schedules are back-to-back with no gaps.
  `GuideController.currentProgram(channelId, at)` already resolves the program
  at any instant, so the successor of program `P` is
  `guide.currentProgram(channelId, P.scheduled.end)`. `GuideProgram.id` combines
  channel, item, and scheduled start.
- **Clocks differ.** `GuideController` takes an injectable `clock` (the shell
  passes `widget.guideClock`, `lineup_shell.dart:75`). `PlayerCoordinator` calls
  `DateTime.now()` directly.
- **Content changes already stop playback.** A lineup/content-generation change
  stops active playback and increments `_tuneGeneration` (`_lineupChanged`,
  `:1535`), so a continuation always uses the schedule the tune used.
- **Position can read zero at the end.** mpv `time-pos` can become unavailable
  near end-of-file, so the terminal event's position may be zero. The last
  positive position observed during playback is the reliable progress fact.

## Contracts

### Native end reason (Unit 1)

- `MPV_EVENT_END_FILE` with `reason == MPV_END_FILE_REASON_EOF` and no error
  emits state `ended` with message `Playback ended` for the correlated load ID.
- STOP, QUIT, and other non-error reasons keep emitting `stopped`.
- Error and redirect handling are unchanged.
- `WindowsNativePlayer` maps `'ended'` to `PlayerState.ended`, with the same
  load-ID correlation and stale-event rejection as other states.

### Coordinator (Unit 2)

The coordinator is the single owner. Add no new class unless it removes real
complexity.

- **Clock.** Add an optional `DateTime Function()? clock` constructor
  parameter, defaulting to `DateTime.now`. Use it for all coordinator time
  reads, including the sleep timer. The shell passes `widget.guideClock`, so
  the guide and Player share one time source.
- **Loaded program.** Track the `GuideProgram` that the active channel playback
  represents.
  - Set it when a tune or continuation commits its request.
  - Clear it everywhere the active playback for that tune is retired.
  - Invariant: it is non-null only while a channel tune's playback is active.
  - Local initial media (`loadInitialMedia`) has none.
- **Natural end.** A terminal event is a natural end only when its state is
  `ended`, it belongs to the active load generation, the load is not
  replacing, and it is not premature.
- **Premature end.** The event is premature when the part's known duration `D`
  exists and the last positive native position observed for that part is
  earlier than `D − 30 s`.
  - For `D`, prefer the last positive native duration and fall back to the
    part's metadata duration.
  - If `D` is unknown, the end is natural.
  - A premature end on any part, final or not, does not advance. Record a
    normalized failure (code `premature_end`), set
    `_error = 'Playback ended before the program finished.'`, set
    `canRetry = true`, and present the error overlay.
- **`stopped` with an active request.** A `stopped` event with an active request
  that Lineup did not initiate is terminal. Retire playback as the current
  final-part path does, with no advance and no continuation. The existing
  replacing-load suppression for `stopped` is unchanged.
- **Natural end of a non-final part.** Load the next part (existing behavior).
- **Natural end of the final part with a loaded program `E`.** Start
  continuation for the same channel through the tune path:
  - Continuation takes a new tune generation exactly as `tune()` does, so any
    later user action supersedes it.
  - It honors sleep-deadline expiry the same way `tune()` does.
  - Native stop handling is as in `tune()`.
- **Program resolution.** Normal tunes are unchanged. For continuation:
  1. Await `guide.ensureCurrentProgram(channelId)`. If it returns null (for
     example, the channel was removed), retire playback quietly with no error.
  2. Set `S = guide.currentProgram(channelId, E.scheduled.end)`.
  3. If `S` is non-null, `S.id != E.id`, and
     `now − S.scheduled.start ≤ 30 s` (including negative values when running
     ahead), load `S` from its beginning with no initial position.
  4. Otherwise load the current wall-clock program using the normal tune
     position rule.
- **Continuation failure.** A failed continuation load uses the existing tune
  failure path (error overlay with Retry). There is no automatic retry.
- **Program info getters.**
  - `currentProgram` returns the program being loaded once a tune or
    continuation has resolved it. Otherwise it returns the loaded program.
    Otherwise it falls back to wall-clock `guide.currentProgram`.
  - `nextProgram` is `guide.currentProgram(channelId, current.scheduled.end)`
    when `current` comes from a tune or loaded program. Otherwise it is
    wall-clock `guide.nextProgram`.
  - Do not change Guide or mini Guide row sources.
- **Constants.** Name the two 30-second values separately (catch-up tolerance
  and premature-end tolerance). They are independent decisions.

### HDR interaction (recorded for the HDR plan)

A program boundary is the main place fullscreen HDR matching changes display
state. The HDR implementation plan should:

- treat the continuation load as the transition point;
- hold the first frame paused until the display converges (bounded at about
  3–4 seconds); and
- let that hold count toward the carried lateness above.

This plan does not implement HDR behavior.

## Implementation units

The [orchestrate-implementation-chats](../.agents/project.md#optional-delegation-presets)
pattern applies. Units 1 and 2 have disjoint write ownership and may run in
parallel. Unit 3 follows Unit 2. The orchestrator owns Git integration, the
final full verification, and acceptance.

Integrate Units 1 and 2 together. Unit 2 alone would treat every natural
end-of-file (still reported as `stopped`) as a terminal stop, which would break
multipart advance.

| Unit | Executor | Write ownership | Depends on |
| --- | --- | --- | --- |
| 1. Native end reason and transport | `worker_luna` | `windows/runner/native_player.cpp`, `lib/playback/windows_native_player.dart`, `test/playback/windows_native_player_test.dart` | none |
| 2. Coordinator continuation and loaded-program info | `worker` | `lib/playback/player_coordinator.dart`, `test/playback/player_coordinator_test.dart`, `lib/app/lineup_shell.dart` (clock wiring only); other tests only where existing expectations encode the replaced behavior | Unit 1 contract (not its code) |
| 3. Documentation | `worker_luna` or orchestrator | `docs/user-guide.md`, this plan's status line | Unit 2 behavior |

### Unit 1 evidence

- Transport tests: a native `ended` state event maps to `PlayerState.ended`
  with load correlation; a stale-load `ended` is ignored; `stopped` is
  unchanged.
- Native compile: run the Windows application compile check
  ([Development](DEVELOPMENT.md#application-compile-check)) on the Windows
  machine. If the executor is not on Windows, report the compile as
  outstanding rather than claiming it.
- No native CTest currently exercises `MPV_EVENT_END_FILE`. Physical acceptance
  covers it; do not invent a libmpv harness.

### Unit 2 evidence

Coordinator tests with the fake player and one injected clock shared with
`GuideController`. Use short scheduled items so boundaries are deterministic.

1. Natural final-part end on schedule: the successor loads with no initial
   position, and `currentProgram` is the successor.
2. Successor late by 30 seconds or less: it still loads from the beginning.
3. Successor late by more than 30 seconds: the wall-clock program loads at its
   live position.
4. Media ends before its scheduled end: the successor loads immediately from
   the beginning.
5. Premature end (last positive position earlier than `D − 30 s`): no advance,
   error overlay, and `canRetry`; Retry performs a normal live tune. Cover a
   final and a non-final part.
6. A terminal event with zero position after positive progress near the end
   counts as natural; this guards the `time-pos` reset.
7. `stopped` with an active request: no advance or continuation, and playback is
   retired.
8. Supersession during a continuation load: a user tune, Stop, content change,
   or dispose commits no stale load. A sleep deadline that has passed at the
   boundary expires sleep instead of continuing.
9. Continuation load failure: error overlay with Retry, and no automatic retry.
10. Local initial media that ends does not continue (existing standalone test
    semantics).
11. Program info: with the clock 10 seconds past the scheduled boundary while
    the previous program's media is still playing, `currentProgram` and
    `nextProgram` describe the loaded program and its successor. After
    continuation they advance.
12. Continuation never reloads the program that just ended.
13. Multipart: a non-final natural end still advances to the next part, with
    its existing timing behavior.

Update existing tests that encode "`stopped` advances parts" or "playback
clears after the final part" to the new contracts, and say which ones changed
in the report. Do not delete unrelated coverage.

### Unit 3 evidence

- Replace the user-guide known-limitation bullet with the approved behavior.
- Add a short description near the sequential-parts paragraph (DVR catch-up,
  failure on cut-off streams, Player info follows the loaded program).
- Set this plan's status after implementation.

### Portable verification (orchestrator, after integration)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

## Physical Windows acceptance

Use the exact integrated commit. The operator supplies a Plex channel with short
items, under 5 minutes each, and judges every observation; never record tokens,
URLs, or private titles.

| Scenario | Required observation |
| --- | --- |
| Three or more consecutive boundaries, direct play | The next program starts from its beginning each time; Player info changes with it; record the gap |
| One boundary with a transcoded item | Same; record the gap |
| DVR pause past the boundary by more than 30 seconds, then resume | The previous program finishes, then the channel joins what is airing now |
| Stop during the boundary load | No continuation after Stop |
| Sleep timer expiring near a boundary | Sleep wins; no continuation |
| Boundary while in PiP or with the Guide open | Continuation happens; no navigation change |
| Fullscreen boundary between SDR programs | Fullscreen, focus, and overlays intact |

Report Pass, Fail, or Blocked per row, with the commit SHA and build identity.

## Out of scope

- Gapless preloading of the next program.
- Fullscreen HDR matching (see the [HDR discovery plan](fullscreen-hdr-discovery-plan.md)).
- New Player UI.
- Changes to Guide wall-clock behavior.
- Automatic retry after failures.
- Alternate media versions.
