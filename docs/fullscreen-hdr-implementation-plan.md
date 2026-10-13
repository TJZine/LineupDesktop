# Fullscreen HDR Implementation Plan

**Status:** Units 1–5 implemented, integrated, and deterministically verified on
October 11, 2026. Physical
Windows 10, Windows 11, and portable-package acceptance remain pending. It implements the
[Fullscreen HDR Presentation Specification](fullscreen-hdr-spec.md) using the
[Windows 10 discovery result](fullscreen-hdr-discovery-plan.md#discovery-result-october-9-2026).
The user approved the product decisions below. Two rounds of independent
read-only review against `cd2c08f6` found two blockers and a number of gaps;
this revision incorporates all of them. Physical acceptance happens in the user's final full-app
test; this plan lists those rows but schedules no separate run.

## Decisions

| Topic | Decision |
| --- | --- |
| Architecture | Keep the existing libmpv `gpu-next`/D3D11 child presentation and patched Flutter DirectComposition. mpv already renders correctly for whatever state the display is in, without a refresh, so Lineup configures no mpv output options. |
| Matching | While a fullscreen matching session is active, HDR content gets HDR display presentation and SDR content gets SDR, including turning HDR off for SDR when it was on before. When Lineup stops owning the display, it restores the state it found. |
| What counts as HDR | Any stream whose decoded `video-params` transfer is PQ or HLG (the existing `PlayerTelemetry.isHdr` rule). This includes Dolby Vision, which decodes as PQ. mpv outputs these as HDR10; the TV shows HDR10, not Dolby Vision. HDR10+ plays as static HDR10. Dolby Vision profile 7 plays only its HDR10 base layer. |
| Program boundaries | Hold the new program paused on its first frame until the display has switched (bounded; see [Hold](#hold)). The hold counts toward the [continuation plan's](schedule-continuation-plan.md) carried lateness. |
| Windows versions | Windows 10 and Windows 11 are both enabled. The route is chosen from the capability the machine reports, not the OS version. Windows 11 is unverified until tested on the borrowed machine. |
| Instances | One Lineup instance per Windows user session. A second launch brings the existing window forward and exits. |
| Crash protection | A guardian process restores the display if Lineup exits abnormally while owning a changed display state. If the guardian cannot be confirmed armed, Lineup does not change the display. |

### Confirmed UI decisions

The user confirmed all three items before dispatch; they are implemented.

1. **Setting:** a Playback settings switch, **Match display HDR in
   fullscreen**, after **DVR playback controls**. Default **on**. Subtitle:
   "Switch Windows HDR on for HDR programs and off for SDR programs while
   fullscreen, then restore your display setting."
2. **Presentation during a hold:** no new UI. A hold looks like a slower
   start: the Player shows its existing preparing presentation
   (**Preparing playback**, then the existing **Starting playback…** label
   after 2 seconds). The OSD status label and transport button render as
   they do while loading, never as Paused with a Play button, and no overlay
   changes.
3. **Diagnostics wording:**
   - Add rows titled **Windows display**, **HDR matching**, and **Renderer
     output**.
   - Replace "Media signal values do not verify display HDR output." with
     "Display state is reported by Windows; it does not verify the TV's
     picture."
   - Include these rows in the support report, with normalized values only.

## Session model

A **matching session** belongs to one display target (adapter LUID plus
target ID). Dart decides when a session should exist and what it wants. The
native controller owns display mechanics, ownership, and restoration.

- **Start:** all of these hold:
  - the setting is on;
  - the Lineup window is fullscreen;
  - playback intent exists (`hasPlaybackIntent`, including tuning and
    continuation loads);
  - the Player is the visible shell destination;
  - the full Guide is not showing. In this codebase the full Guide and its PiP
    video are one state, `PlayerOverlay.fullGuide`.

  Other overlays do not prevent a start.
- **Continues:** while the window stays fullscreen, the setting stays on, and
  playback intent exists. Opening the full Guide during a session does not
  end it, so the TV doesn't blank every time the Guide opens.
- **Ends:** on any of:
  - leaving fullscreen;
  - turning the setting off;
  - Stop;
  - a playback error overlay;
  - sign-out or lineup scope reset;
  - app close or dispose;
  - the window's target changing or disappearing.
- **Desired state:**
  - `hdr` when the active load's first `video-params` with a non-null
    transfer is HDR;
  - `sdr` when that transfer is known and not HDR;
  - `unknown` otherwise, including audio-only media. `unknown` never causes a
    change.

### Ownership and restoration (native)

Ownership is tracked **per target** and outlives individual sessions.

- **Not owned:** when a session starts on a target, the controller captures
  the observed state as the **original state**. If that state cannot be
  observed, the session is `unavailable` and nothing changes.
- **Owned:** Lineup owns a target from its first write **attempt**, made only
  after the guardian is confirmed armed. The attempted state counts as
  Lineup's own write even if verification times out.
  A session that starts on an owned target inherits the existing original
  state and guardian; it never captures again. This covers Retry after an
  error, Stop then tune, re-entering fullscreen, and an in-flight restore.
- **Expected state:** while a session is active, the expected state is the
  last attempted write, or the original state before any write. Observing the
  last attempted or last verified state is never an external change.
- **External change:** a state observed while no Lineup write is in flight,
  differing from the expected state, suspends the session.
  - **Owned:** ownership is relinquished, no further writes happen, nothing is
    restored, and the guardian is disarmed.
  - **Not owned:** the change is accepted and the session is suspended.
  - **Detection:** a re-query on `WM_DISPLAYCHANGE` or `WM_SETTINGCHANGE`,
    plus polling every 2 seconds while a session is active or ownership
    exists.
- **Release:** when a session ends on an owned target, restore the original
  state if the observed state equals the last verified or last attempted
  write, then verify it.
  Success releases ownership and disarms the guardian. Failure keeps the
  guardian armed so it retries after exit.
- **Ordering:** session ends and starts are processed in order and never
  coalesced away. Only `desired` changes within one session are coalesced:
  the worker always reconciles toward the newest desired state.
- **Disappearing target:** if the target disappears while owned (for example,
  the TV is powered off), keep ownership and the original state for that
  target identity. When it reappears and the observed state equals the last
  verified or attempted write, restore it unless a new session has started
  there. A new
  session on it inherits ownership.
- **Late success:** a write for a superseded revision that succeeds late is
  verified and recorded as the last write, then reconciled toward the newest
  desired state.

### Hold

The hold keeps a viewer from missing content while the TV resynchronizes. It
uses the native player directly and never changes the overlay.

- **Start paused:** within an active session, every load starts paused:
  tunes, continuations, part advances, and authorization-recovery reloads.
  This uses the new `startPaused` load flag ([Load contract](#load-contract)).
  Each paused load registers exactly one hold.
  - Exception: skip `startPaused` when the newest report for the current
    session is `unavailable` or `suspended`, since no switch can happen.
- **Session starting after a load began:** this covers entering fullscreen,
  closing the full Guide, returning to the Player destination, turning the
  setting on, or a Guide tune that starts a session after its load was
  dispatched unpaused.
  - Register a hold that does not pause up front.
  - At the decision point, pause only when the desired state is known and
    differs from the observed state in the first `active` report for the new
    revision.
  - If the user had already paused, never auto-resume.
- **Decision point:** the first `video-params` with a non-null transfer for
  the active load generation. After readiness, an actual track-list update for
  that generation with no selected video track resolves `unknown`; a reset
  empty snapshot at readiness is not evidence of audio-only media. If no
  transfer has arrived by the fallback time, treat the state as `unknown`.
  - **Fallback time:** 2 seconds after the first position report at or past
    the load's start target, or after readiness when there is no target, and
    never later than 6 seconds after readiness.
  - Native seek completion is not observable: `seek` completes on queue
    acceptance.
- **Resume immediately:** when the desired state is `unknown` or already
  equals the observed state.
- **Otherwise:** send the change and resume at the first of:
  1. a report for this revision or later with `outcome: matched` and
     `wrote: true`, followed by a **1.5-second settle**;
  2. `matched` with `wrote: false` (resume now);
  3. `failed`;
  4. `session` reported `inactive`, `unavailable`, or `suspended`;
  5. **4 seconds** after sending the change request.
- **Ending a hold early:**
  - User Play ends the hold and resumes now.
  - A user Pause cancels the auto-resume.
  - Leaving fullscreen or another session end during a hold resumes playback.
  - A newer tune, Stop, sleep expiry, or scope retirement cancels the hold
    without resuming, because that load is gone.
- **Invariant:** every paused-started load ends its hold in exactly one
  resume, unless a user pause, a supersession, or an error intervenes. With
  DVR controls off the viewer cannot unpause, so a stranded hold is a defect.
- **Presentation:** do not rewrite `status`.
  - The coordinator exposes `displayHoldActive`.
    - `player_view.dart` adds it to its `preparing` condition, so the existing
      **Preparing playback** presentation shows.
    - The OSD and Now Playing status label (`_statusLabel` and the status
      text) and the transport play/pause button render as they do for
      `PlayerState.loading` while it is true.
  - The busy-label computation in `notifyListeners` treats an active hold as
    busy, so the existing **Starting playback…** label appears after
    2 seconds.
  - The overlay policy in `_event` ignores the `paused` and `playing`
    transitions that the hold itself causes. The hold never calls `showOsd()`
    or bumps `_controlGeneration`, and it leaves continuation presentation
    preservation untouched.
  - Shell consumers of `status.state` (such as the Guide now-watching
    marker) are unaffected.

Leaving fullscreen and other session ends never pause playback; restoration
runs while playback continues.

## Native contracts

### Load contract

- `NativePlayer.load` gains `bool startPaused = false`.
- The channel `load` arguments carry it, and the native `QueuedCommand` stores
  it.
- `RunCommand(load)` sets mpv `pause` to `startPaused` (today it forces 0 at
  `native_player.cpp:873`).
- `WindowsNativePlayer.load` sets `_paused = startPaused` in place of the
  `_resetMediaState` assumption (`windows_native_player.dart:721`). It still
  reports `paused` when `FILE_LOADED` emits `playing`.
- Readiness completion keeps keying on the raw native `playing` state.

### Display controller

Add a native display controller owned by `WindowsNativePlayer`, in new files
`windows/runner/display_dynamic_range.{h,cpp}`.

- **API seam:** a `DisplayConfigApi` interface over `QueryDisplayConfig` and
  `DisplayConfigGetDeviceInfo`/`DisplayConfigSetDeviceInfo`, with a real
  implementation and a CTest fake. Add a `DisplayGuardianLink` interface
  (`Arm`, `Update`, `Disarm`, `IsAlive`), with a fake for CTest; Unit 3
  supplies the real one. Keep policy out of both real implementations.
- **Thread:** one dedicated worker thread for every DisplayConfig call. Set
  calls block about 350 ms, and display messages can arrive before they
  return. Nothing touching DisplayConfig runs on the platform thread or the
  shared mpv command/event thread. Reports reach Dart through the existing
  platform event queue.
- **Target mapping:**
  1. `MonitorFromWindow(top_level_window_)`.
  2. `GetMonitorInfoW`.
  3. The `QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS)` path whose source GDI
     name matches.
  4. Exactly one active target must match; otherwise the session is
     `unavailable` (`ambiguous_target`).
  5. Re-map on `WM_DISPLAYCHANGE`, `WM_MOVE`, and `WM_WINDOWPOSCHANGED`.
- **Route selection:** decided per target at session start.
  - **New route:** used when `GET_ADVANCED_COLOR_INFO_2` succeeds.
    - Observed state for ownership and restore is
      `highDynamicRangeUserEnabled`.
    - Writes use `SET_HDR_STATE`.
    - `activeColorMode` is reported to Diagnostics only. A policy-limited
      display (for example, on battery) therefore doesn't produce endless
      `not_observed` failures.
    - HDR capability comes from its HDR-supported field.
  - **Legacy route:**
    - State comes from `GET_ADVANCED_COLOR_INFO`; `advancedColorEnabled` is
      the HDR state on Windows 10.
    - Writes use `SET_ADVANCED_COLOR_STATE`.
    - `advancedColorSupported == false` means `not_hdr_capable`.
  - **SDK:** the application build requires Windows SDK `10.0.26100` or newer.
    The discovery build already selected it. Enforce it in
    `windows/runner/CMakeLists.txt` with a clear configure error, and record it
    in `DEVELOPMENT.md`. If the newer declarations are gated by
    `NTDDI_VERSION`, raise it only in the shared `DisplayConfigApi`
    translation unit, which the guardian also uses; runtime detection keeps
    Windows 10 safe. Confirm field names against the
    installed headers.
- **Write sequence:**
  1. Ensure the guardian is confirmed armed (see [Guardian](#guardian)).
  2. Send the guardian an `update` with the attempted state.
  3. Write.
  4. Re-query until the requested state is observed or 3 seconds pass.
  5. Record the result as the last verified write, or report `failed`.
  6. Send the guardian an `update`.
  7. Report the outcome to Dart.

  A write that fails verification stays in the guardian record and the
  controller as the **attempted state** until a later write replaces it. Step
  6 must not clear it, so a write that takes effect late is still restored.
- **App close:**
  - `window_close_ready_` requires native dispose complete **and** either
    session-end restoration complete or a 3-second timer elapsed. Today only
    `dispose_ready_` drives it (`native_player.cpp:1355-1373`).
  - The controller's destructor waits a bounded time for its worker, then
    follows the existing bounded-wait/terminate pattern
    (`native_player.cpp:371-388`) rather than blocking on a stuck
    `DisplayConfigSetDeviceInfo`. The guardian covers that case.
- **Windows shutdown or logoff:**
  - On `WM_QUERYENDSESSION`, return true.
  - On `WM_ENDSESSION` with `wParam == TRUE`, ask the worker to release
    ownership and wait at most 2 seconds. This is the one bounded wait
    allowed on the platform thread.
  - Document that a shutdown which cuts this short leaves the display state
    as Windows saved it.
- **Hot restart:** `initialize` resets the expected Dart revision, since the
  native player survives a Dart hot restart (`native_player.cpp:559-561`).
- **Relaunch after a crash:** the native process lifecycle owns admission,
  independently of the ordinary single-instance window guard.
  - Before original-state capture or matching writes, the display worker
    waits at most 3 seconds for explicit resolution of **every** predecessor
    target in the native recovery journal. An unowned or abandoned mutex,
    helper exit, or broken pipe does not establish restoration success.
  - A bounded, versioned journal scoped to the user/logon session records
    target identity, captured route/original, and attempted/verified writes.
    Registration and attempted-state recording must succeed before mutation;
    the guardian acknowledges protection before the first write.
    A registration with no attempted or verified state can be retired without
    display access only after the exact parent generation is proven dead.
    This covers a crash before helper launch; PID reuse is checked using
    creation time, and access/query uncertainty retains the record.
  - The cross-process gate serializes journal transitions and conditional
    recovery, rather than being held by each guardian for its whole lifetime.
    Multiple retained targets coexist. Stale guardians cannot restore a
    record that has already been safely resolved.
  - Failed restoration, target loss, and corrupt/unavailable coordination
    remain unresolved. Recovery explicitly distinguishes safe resolution
    from uncertainty. The journal retains uncertainty after helper handles
    have closed; it is native recovery data, not a preference or media log.
  - Timeout or uncertainty disables matching for the process lifetime.
    Current-revision reports use `session=unavailable`, `outcome=failed`,
    `reason=guardian_unavailable`, `wrote=false`, and `owned=false`.
    Playback and bounded shutdown remain usable. Display/settings notices,
    player recreation, and Dart hot restart cannot bypass failed admission.
  - Admission waits and journal operations run off the platform thread.
    IPC acknowledgment waits do not hold the cross-process gate.
    The journal is checksummed and bounded to 32 outstanding target records;
    exhaustion or invalid data fails closed without evicting a retained target.

### Dart ↔ native messages

Method `setDisplayMatching`, Dart to native:

| Field | Type | Meaning |
| --- | --- | --- |
| `revision` | int | Strictly increasing; reset by `initialize` |
| `session` | bool | Whether a matching session should be active |
| `desired` | `hdr` \| `sdr` \| `unknown` | Wanted state; ignored when `session` is false |

- Dart sends a new revision only when `session` or `desired` changes.
- The call returns when it is queued.

Event `{type: 'display', ...}`, native to Dart, player-scoped (not
load-scoped):

| Field | Values |
| --- | --- |
| `revision` | Newest revision this report reflects |
| `session` | `inactive`, `active`, `suspended`, `unavailable` |
| `observed` | `hdr`, `sdr`, `unknown` |
| `outcome` | `idle`, `pending`, `matched`, `failed` |
| `wrote` | bool: whether this outcome required a write |
| `owned` | bool |
| `reason` | null, or one of `unsupported_api`, `not_hdr_capable`, `ambiguous_target`, `state_unknown`, `guardian_unavailable`, `set_rejected`, `not_observed`, `external_change`, `restore_failed`, `target_lost` |
| `route` | `hdr_state`, `advanced_color`, `none` |
| `activeColorMode` | `sdr`, `wcg`, `hdr`, `unknown` (new route only; Diagnostics) |

Routing:
- `WindowsNativePlayer` routes `type: display` before the current-load filter
  (`windows_native_player.dart:416`), as it does for `stopResult`.
- It exposes the newest report through a player-scoped getter and stream, not
  `PlayerTelemetry`, which is reset per load.
- The coordinator listens to that stream independently of load generation.

### Renderer telemetry

- Observe `video-target-params` and forward allowlisted normalized transfer,
  primaries, and surface format through the existing parameter encoder
  (`native_player.cpp:1405-1415`).
- These are per-load facts in `PlayerTelemetry`, added to
  `_eventVisibleFacts`, and used for Diagnostics only.

### Guardian

The guardian runs the same `lineup_desktop.exe` in a separate mode, so the
package gains no files.

- **Startup:**
  - `wWinMain` dispatches `--display-guardian` before COM, Flutter, or the
    single-instance mutex.
  - The guardian initializes no Flutter engine and creates no window.
  - `flutter_windows.dll` and `libmpv-2.dll` are still mapped because they are
    imported statically. This is acceptable because they sit beside the exe.
  - It participates in the native recovery journal and cross-process gate;
    it does not own an exclusive global mutex for its lifetime.
  - It uses the same real `DisplayConfigApi` and route detection as the
    controller.
- **Launch:**
  - Create two anonymous pipes (commands to the guardian, acknowledgments to
    the parent) and a duplicated, inheritable, `SYNCHRONIZE`-only parent
    process handle.
  - Pass exactly the guardian's pipe ends and the parent handle through
    `STARTUPINFOEX` with `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`. The parent's
    ends are non-inheritable.
  - Arguments are the handle values.
- **Protocol:** fixed-size, versioned binary records with a sequence number.
  - Kinds are `arm`, `update`, and `disarm`.
  - Fields identify the owning process generation and recovery record, target
    adapter LUID and target ID, original state, last verified written state,
    and in-flight target state (or none).
  - The guardian acknowledges each record. The parent treats a missing `arm`
    acknowledgment within 2 seconds as `guardian_unavailable`.
  - A later write or acknowledgment failure means the guardian is lost: make
    no further writes, report it, and still attempt normal release.
- **Trigger:** broken pipe or end-of-file without a prior `disarm`, or the
  parent handle signaled.
- **Action:**
  1. Acquire the recovery gate and validate the exact journal record. An
     already resolved record causes no display write.
  2. Query the target using its captured route.
  3. If the observed state differs from the original state **and** equals the
     last verified write or the attempted (in-flight) state, write the
     original state and verify it once.
  4. Resolve only an explicitly safe result. Unknown/failed restoration
     retains the record and prevents successor matching. An external state
     is respected without writing over it.
  5. Release the gate and exit; helper exit itself is not a success signal.
  Malformed or out-of-order records end the guardian without display changes
  and do not erase unresolved journal records.
- **Lifetime:** one guardian per owned target. It is disarmed after verified
  release or on suspension.
- **Known limits:** power loss, an OS crash, a shutdown that cuts the
  `WM_ENDSESSION` wait short, or the guardian being killed with Lineup leave
  the display in its last state. Document this.

### Single instance

In `wWinMain`, after the guardian dispatch, create the named mutex
`Local\TJZine.LineupDesktop.Instance`. If it already exists:

1. Find the other process's top-level `Lineup Desktop` window.
2. Restore it if minimized and bring it to the foreground.
3. Exit with success.

The second launch's arguments (for example `--media`) are ignored; document
this in the user guide and development notes. A second `flutter run` while
Lineup is open exits the same way.

## Dart contracts

- **Transport:**
  - `NativePlayer` gains `setDisplayMatching(DisplayMatchingRequest)`, a
    `displayReport` getter, a `displayReports` stream, and the `startPaused`
    load flag.
  - `UnsupportedNativePlayer` (macOS) reports `unavailable`.
  - Update every implementer:
    - `test_driver/ui_harness.dart`
    - `test/support/ui_fixture.dart`
    - `test/app/product_spine_test.dart`
    - `test/app/lineup_app_test.dart`
    - `test/playback/player_view_test.dart`
    - `test/playback/native_video_surface_test.dart`
    - `test/playback/player_coordinator_test.dart`
- **Policy owner:**
  - Put session/desired computation and hold sequencing in
    `lib/playback/display_matching.dart`, driven by `PlayerCoordinator`.
  - Pure rules (session, desired) are testable without timers.
  - The hold uses the coordinator's injected clock and supersession
    generations, and calls `player.pause()`/`player.play()` directly.
  - The coordinator supplies:
    - fullscreen state;
    - visible shell destination, pushed by `LineupShell` whenever
      `_selectedIndex` changes;
    - overlay;
    - playback intent;
    - load generation and `video-params`;
    - the setting;
    - user Play/Pause notifications;
    - the hold presentation projection.
- **Setting:**
  - Add `matchDisplayHdr` to `LineupSettings` with the confirmed default.
  - Add it to `fields` and to the `requiredFields` exclusion
    (`lineup_settings.dart:119-151`), so existing saved settings stay valid.
  - Add the row in `lineup_shell.dart` with the `_SettingsSwitchTile` pattern.
- **Diagnostics:**
  - The confirmed rows and wording above appear in the view and the support
    report.
  - Display reports reach Diagnostics through `diagnosticPlaybackSnapshot`.
  - `_shellPlayerFacts` includes them so Diagnostics rebuilds when they
    change.
  - No new Player notice in this version.

## Implementation units

The orchestrator owns Git integration, cross-unit contracts, final
verification, and documentation consistency. Native compilation and CTest need
the Windows machine; a unit run elsewhere reports them as outstanding.

| Unit | Executor | Write ownership | Depends on |
| --- | --- | --- | --- |
| 1. Single instance | `worker_luna` | `windows/runner/main.cpp` (instance block only) | none |
| 2. Native controller, load flag, telemetry | `worker` | new `windows/runner/display_dynamic_range.*` and its CTest, `windows/runner/CMakeLists.txt` (controller test target, SDK check), `native_player.{h,cpp}` (load `startPaused`, `setDisplayMatching`, display events, close/dispose/end-session hooks, `video-target-params`), `flutter_window.cpp` (message forwarding, `WM_QUERYENDSESSION`/`WM_ENDSESSION`) | none (contracts above) |
| 3. Guardian | `worker` | new `windows/runner/display_guardian.*` and its CTest, `main.cpp` (guardian dispatch), `CMakeLists.txt` (guardian test target), the single construction site in `native_player.cpp` that passes the real `DisplayGuardianLink` | Units 1 and 2 |
| 4a. Dart transport and setting | `worker_luna` | `native_player.dart`, `windows_native_player.dart`, `unsupported_native_player.dart`, the seven implementers listed above, `lineup_settings.dart`, the `lineup_shell.dart` settings row, their tests | none (contracts above); UI item 1 confirmed |
| 4b. Dart policy, hold, diagnostics | `worker` | new `lib/playback/display_matching.dart` and its tests, `player_coordinator.dart` (policy wiring, hold, `displayHoldActive`, display reports in `diagnosticPlaybackSnapshot`) and its tests, `lineup_shell.dart` (Player-destination push to the coordinator and display facts in `_shellPlayerFacts`), `player_view.dart` (the `preparing` condition, status label, status text, and transport button for an active hold only), diagnostics view and support report, their tests | 4a; UI items 2 and 3 confirmed |
| 5. Documentation | `worker_luna` or orchestrator | spec status, `architecture.md` presentation ownership, `user-guide.md` (setting, behavior, single instance, DV/HLG/HDR10+ notes, known limits), `windows-native-validation.md` HDR rows, `DEVELOPMENT.md` (SDK requirement, single instance), the discovery plan's Windows 11 wording, this plan's status | 1–4b |

- **Parallel:** Units 1, 2, and 4a can run at the same time.
- **Sequential:** Unit 3 follows 1 and 2 (shared `main.cpp`, `CMakeLists.txt`,
  and the construction site). Unit 4b follows 4a.
- **Integration:** the orchestrator integrates 2, 3, 4a, and 4b together.
  Unit 4b alone would start loads paused against a native side that ignores
  the flag.

### Integration record (October 11, 2026)

The controller integrated the disjoint shared-checkout units on
`codex/desktop-ui-second-pass`, based on `e8377816`, which contains the requested
`4fb7758034f4f47290fae13a4ea8275860ba1284`. No push or merge was performed.

| Unit | Commit | Outcome |
| --- | --- | --- |
| 1 | `48758671` | Single-instance focus/exit behavior |
| 2 | `cd628bd3`, `c6794519` | Display controller/load flag/renderer telemetry; target-session report edge correction |
| 3 | `57a9e762` | Same-executable guardian and protocol tests |
| 4a | `183c6bd1`, `5d7d27e2` | Dart transport, compatible default-on setting, implementers/tests; legacy persistence expectations retain the new default |
| 4b | `d91d0f74` | Session/hold policy, Player projection, Diagnostics/support report |
| 5 | Documentation commit following this record | Current contracts, development commands and pending physical rows |

Unit 4b escalated a source-contract conflict: a capable native remap originally
restarted its target session without reporting an end, and the player-scoped
event has no target identity. The accepted correction emits an ordered
`inactive` report before the new `active`/`unavailable` report at the same Dart
revision. Dart treats that edge as a new post-load session hold; ordinary
same-target polls do not rearm it. Native and Dart regressions cover this seam.
No product contract remains unresolved.

Existing test changes preserve their prior behavior assertions. Unit 4a updates
all `NativePlayer` fakes and derived load overrides for the transport contract,
adds setting round-trip/missing-key and UI-row assertions, and updates two
legacy persistence expected maps to include `matchDisplayHdr: true` while
preserving their original input bytes and no-quarantine checks. Unit 4b extends
coordinator and Player-view fixtures to observe correlated paused starts/display
reports, adds session/hold/continuation/recovery/retirement regressions and
preparing/loading UI assertions, and adds Diagnostics view/support-report
normalization checks. No existing test was removed or weakened. Existing native
test sources are unchanged; the authenticated-reference target links the new
production controller/guardian translation units.

### Changed files by unit

Paths below are relative to the repository root. Shared files appear under each
unit whose commit changed them.

| Unit | Files |
| --- | --- |
| 1 | `windows/runner/main.cpp` |
| 2 | `windows/runner/display_dynamic_range.{h,cpp}`, `display_dynamic_range_test.cpp`, `CMakeLists.txt`, `native_player.{h,cpp}`, `flutter_window.cpp` (all under `windows/runner/`) |
| 3 | `windows/runner/display_guardian.{h,cpp}`, `display_guardian_test.cpp`, `main.cpp`, `native_player.cpp`, `CMakeLists.txt` (all under `windows/runner/`) |
| 4a | `lib/playback/{native_player,windows_native_player,unsupported_native_player}.dart`, `lib/settings/lineup_settings.dart`, `lib/app/lineup_shell.dart`; `test_driver/ui_harness.dart`, `test/support/ui_fixture.dart`; `test/app/{product_spine,lineup_app,channel_studio_view,desktop_native_audit,desktop_settings}_test.dart`, `test/playback/{player_view,native_video_surface,player_coordinator,windows_native_player}_test.dart`, `test/settings/lineup_settings_test.dart`, `test/persistence/app_store_test.dart` |
| 4b | `lib/playback/{display_matching,player_coordinator,player_view}.dart`, `lib/app/{lineup_shell,diagnostics_view}.dart`, `lib/diagnostics/diagnostics.dart`; `test/playback/{display_matching,player_coordinator,player_view}_test.dart`, `test/app/desktop_diagnostics_test.dart`, `test/diagnostics/diagnostics_test.dart` |
| 5 | `docs/{fullscreen-hdr-spec,architecture,user-guide,windows-native-validation,DEVELOPMENT,fullscreen-hdr-discovery-plan,fullscreen-hdr-implementation-plan}.md` |

### Final deterministic verification

The October 11 results below remain historical evidence for their named
candidate. The October 13 admission correction changes native lifecycle and
test inputs; it does not inherit those native passes or close physical rows.

Application source candidate: `5d7d27e2b25a1676bf0b3257973721866f699700`, with
only the seven Unit 5 documents changing afterwards. Those documentation edits
do not change the checked Dart/native inputs. Machine: Windows 10 Home
`10.0.19045`; Flutter `3.47.6` at
`5fc346839b5d0eef006ed8404392afb4dfae428d`, Dart `3.13.5`; application Windows
SDK `10.0.26100.0`, MSVC `19.44.35228`; prepared pinned libmpv runtime unchanged.
Ignored logs are under `build/fullscreen-hdr-verification/`.

| Check | Observed output |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | Exit 0; 92 files, 0 changed |
| `flutter analyze` | Exit 0; No issues found (3.7 seconds) |
| `TZ=America/New_York flutter test` (PowerShell process environment equivalent) | Exit 0; 1,458 passed, one existing Eastern DST fold prerequisite skipped (40 seconds) |
| Supplementary full `flutter test`, Windows Eastern timezone with process `TZ` unset | Exit 0; 1,459 passed, no skips (39 seconds); Eastern DST fold prerequisite executed and passed |
| Application compile check, `flutter build windows` | Exit 0; built `build/windows/x64/runner/Release/lineup_desktop.exe` (38.7 seconds); stock-engine compile/link evidence only |
| Build all four opt-in CTest targets | Exit 0 |
| CTest Release, all targets | 4/4 passed, zero failures, 9.45 seconds total: encoder 0.07, authenticated reference 9.07, controller 0.05, guardian 0.24 seconds |
| SDK rejection probe (Unit 2) | SDK `10.0.22621.0` configure rejected with the clear minimum-SDK error |
| Documentation | `git diff --check` passed; local link paths exist |

The Windows OS timezone was already Eastern Standard Time and was not changed.
A local Dart probe established that setting the POSIX `TZ` name on this Windows
runtime produces offsets 0/+1, while unsetting it produces the required -5/-4
offsets. Both requested-command and canonical-Windows results are retained;
the corrected Windows recipe is in [Development](DEVELOPMENT.md#portable-commands).
macOS-only alpha tests are excluded on this host. No Windows HDR setting was
changed, no process was killed, and no physical rows were run. The
[physical matrix](windows-native-validation.md#fullscreen-hdr-physical-rows)
remains pending for the user's final full-app test, including Windows 11 and
the portable package.

## Evidence

### Admission correction verification (October 13, 2026)

Local correction based on PR #44 head
`d0c49b9e1368b5a8e409f561197bab2975e4d2a9`, base
`97f56df4e8b6a5e337534a83c57a15c12173b797`. The exact correction commit is
recorded in Git; the following results apply to its unchanged Dart/native
policy inputs. Host: macOS ARM64, pinned Flutter `3.47.6` at
`5fc346839b5d0eef006ed8404392afb4dfae428d`.

- `flutter pub get`: passed.
- `dart tool/format.dart --check`: passed, 104 files, no changes.
- `flutter analyze`: passed, no issues.
- Focused Eastern-time display-matching, Windows-adapter and coordinator
  tests: 296 passed.
- `TZ=America/New_York flutter test --reporter failures-only`: 1,562 passed.
- Apple Clang `21.0.0`, C++17, `-Wall -Wextra -Werror`, AddressSanitizer and
  UndefinedBehaviorSanitizer: the existing controller/worker fake suite,
  including failed-admission reports, retry/hot-restart latching and bounded
  release, passed in a temporary portable harness. The real Win32 API class
  was replaced by an inert adapter and Win32 types/Sleep were shimmed;
  production admission was excluded and test callbacks supplied admission.
  This is policy/worker evidence, **not** Windows compilation, journal/IPC
  execution or process-admission proof.
- Focused independent source review and `git diff --check`: completed; the
  corrected deadline calculation, known-unmutated orphan cleanup and shared
  conditional-restoration policy received a follow-up review.

The new deterministic Win32 process fixture is wired into the opt-in
`display_guardian` CTest. Native compilation and all four affected Windows
CTests remain **unrun** because this host lacks the Windows SDK/runtime.
Use the [affected-target commands and prerequisites](DEVELOPMENT.md#current-test-tiers-and-gaps),
then complete the physical Windows 10/11 and exact-package rows. The new fixture
uses real processes and production admission/recovery with controlled display
effects and a controlled successor guardian link. Its negative control detects
premature capture, not the entire historical wrong-restoration chain. Source
review and portable policy results do not mark that fixture or physical rows
passed. Earlier CI/package and Windows results retain their original candidate
identities and do not validate this correction.

### Original implementation evidence

**Native controller CTest, fake API, fake guardian, fake clock (Unit 2):**
- Original-state capture; no write when the display already matches.
- SDR→HDR and HDR→SDR writes; HDR→HDR writes nothing.
- The newest desired state wins; a late stale success is reconciled.
- Rejected set and not-observed-within-3-seconds report `failed` with the
  observed state.
- External change before any write and after a write: suspended, with no
  reversal; when owned, ownership is relinquished and the guardian disarmed.
- A write that succeeds but is observed only after the 3-second verify window
  keeps ownership. The late observation is not an external change, and
  release still restores.
- Release restores only when observed equals the last verified or attempted
  write; a failed restore keeps the guardian armed.
- A session end followed by a session start during an in-flight restore
  inherits ownership and never recaptures.
- A target that disappears and reappears while owned is restored or
  inherited correctly.
- Ambiguous target, unsupported API, and not-HDR-capable report `unavailable`
  with no write.
- Route selection: the new route when `GET_ADVANCED_COLOR_INFO_2` succeeds,
  with ownership from `highDynamicRangeUserEnabled`; the legacy route
  otherwise.
- A missing guardian `arm` acknowledgment, or a lost guardian, means no
  further writes.
- A target change releases the old target and starts a new session.

**Guardian CTest (Unit 3):**
- Record validation and sequence checks.
- Restore when the pipe breaks while observed is in {last verified,
  in-flight} and differs from the original state.
- No action after `disarm`, when observed equals the original state, when
  observed is something else, or on malformed records.
- Acknowledgment behavior.

**Dart tests (4a transport and settings; 4b everything else):**
- Transport:
  - `startPaused` encoding;
  - display reports routed independently of load ID;
  - stale and malformed report rejection;
  - revision reset on `initialize`.
- Settings round-trip and the default when the key is missing.
- Diagnostics projection and support-report rows.
- Session and desired rules:
  - fullscreen, setting, intent, Player destination, and full Guide;
  - error or Stop ending a session.
- Hold:
  - resume after matched with a write plus settle;
  - immediate resume when matched without a write, when unknown, and when no
    `video-params` arrive by the fallback time;
  - resume on `failed`, inactive/unavailable/suspended reports, and the
    4-second request deadline;
  - user Play during a hold;
  - user Pause cancelling the auto-resume;
  - entering fullscreen while paused never resumes;
  - a session starting after an unpaused load began (fullscreen entry,
    closing the full Guide, returning to the Player destination, enabling the
    setting) pauses only when a change is needed;
  - `startPaused` is skipped when the current session is `unavailable` or
    `suspended`;
  - the fallback time: 2 seconds after the first position at or past the
    start target, 2 seconds after readiness without a target, and capped at
    6 seconds after readiness;
  - a hold shows the existing preparing presentation and loading-style
    status label and transport button, never Paused or a Play button, and
    leaves overlays and the Guide now-watching marker unchanged;
  - a session end during a hold resumes;
  - supersession cancels the hold without resuming;
  - part-advance and authorization-recovery loads hold;
  - audio-only media;
  - a continuation inside a session keeps its presentation preservation and
    lateness rule;
  - display reports update the Diagnostics snapshot and shell facts.

**Portable verification (orchestrator):**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

**On Windows:** run the application compile check and all CTest targets.

**User's final full test (physical rows):**
- **Transitions and holds:**
  - HDR10 fullscreen entry from SDR;
  - an HDR→SDR and an SDR→HDR program boundary, with hold and blanking;
  - HDR→HDR with no blanking;
  - Windows HDR already on, then an SDR program.
- **Restoration:**
  - leaving fullscreen, Stop, and app close each restore the display;
  - Error then Retry, and leaving then re-entering fullscreen, never leave
    the display changed afterwards.
- **External change:** turning HDR off manually mid-session suspends matching
  and is not undone.
- **Guardian:** end only the main Lineup process during a session, using Task
  Manager's Details tab **End task** on the main window's PID, or
  `taskkill /PID <pid>` without `/T`. The guardian restores the display.
- **Instances:** a second launch focuses the existing window.
- **Content:** Dolby Vision and, if available, HLG samples.
- **Guide and Player UI:**
  - the full Guide inside a session;
  - OSD, Now Playing, focus, and remote/keyboard input across transitions.
- **Display target:**
  - moving fullscreen playback to a different display, if one is connected;
  - powering the TV off and on while Lineup owns the display.
- **Diagnostics rows.**
- **Windows 11** on the borrowed machine.
- **Packaged release:** the same core rows in the portable package before any
  release claim.

## Out of scope

- Exclusive fullscreen, mpv output options, and replacement renderers.
- Refresh-rate and resolution matching.
- True Dolby Vision output.
- A Player notice for matching failures.
- Matching in windowed playback.
- Multi-display policy beyond re-mapping the window's target.
