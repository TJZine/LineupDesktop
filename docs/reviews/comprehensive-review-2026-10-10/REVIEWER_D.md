Playback/Windows review completed read-only at `4fb7758034f4f47290fae13a4ea8275860ba1284`. Two defects survive source calibration; one additional lifecycle candidate needs a focused probe. No files, tests, caches, checkout state, or product configuration were changed. No executable verification was run by this reviewer.

**Retained findings**

| ID | Finding | Type / evidence status | Severity | Confidence |
|---|---|---|---|---|
| D-F01 | Authenticated-reference positive controls no longer recognize natural completion | Confirmed defect / CONFIRMED static | S2 Medium | High |
| D-F02 | Incomplete multipart timing uses inconsistent coordinates for DVR seeking | Confirmed defect / CONFIRMED static | S2 Medium | High |
| D-C03 | EOF before tune commitment can be discarded | Insufficient data / HYPOTHESIS | Potential S2 | Medium |
| Historical F15 | Native cache-wait/buffering projection remains absent | Existing deferred finding | Retain prior calibration | Static absence established |

**D-F01 — Authenticated-reference controls time out after successful EOF**

Classes C07/C13; journeys J07/J11.

The production native EOF branch now emits `ended` at [native_player.cpp:1174](/Users/tristan/Software/LineupDesktop/windows/runner/native_player.cpp:1174), introduced by `db30c286`. The harness decoder still finishes only for `stopped` or `error` at [authenticated_reference_test.cpp:75](/Users/tristan/Software/LineupDesktop/windows/runner/authenticated_reference_test.cpp:75).

A successful one-second MP4/MKV fixture therefore progresses, emits `ended`, and leaves `messenger.finished` false. The 12-second observation reaches `timed_out=true` at line 182; main returns failure at line 194. The Python positive-control checks also require a zero return code. This is a complete source demonstration of an incompatible terminal-state contract, not a claim that CTest was executed.

The decoder’s Release-active contract checks at lines 118–137 cover stopped/error sequences but omit `ended`, so they cannot catch this regression. Both native CTests remain `EXCLUDE_FROM_ALL` and outside CI; the Windows compile check does not execute this consumer.

Correction direction: recognize successful `ended` completion while retaining monotonic rejection and the positive controls’ progress-plus-no-rejection requirements. Add `ended`, progress→ended, and error→ended sequences to the existing real-codec contract checks. Then build and run the documented pinned-DLL authenticated-reference CTest three times on Windows. Do not weaken its containment assertions or change the correct production EOF distinction.

**D-F02 — A seek on part two can reload part one**

Classes C07/C10; journeys J07/J08.

The Player exposes local part position/duration whenever not all part durations are known at [player_coordinator.dart:350](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:350). But `seekTo` always feeds that public position into the aggregate mapper at [player_coordinator.dart:1174](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:1174).

Concrete valid input:

- Part one has a known duration of 60 seconds.
- Part two’s Plex duration is absent.
- After advancing to part two, native playback reports position 10 seconds and duration 90 seconds.
- The duration map still contains only part one: observed duration is retained on the load and added to the map at EOF, rather than during ordinary progress.

The public position is consequently 10 seconds. `seekBy(+30s)` requests 40 seconds. `_partForPosition` compares 40 against part one’s known 60-second boundary and returns `(part 0, 40s)` at [player_coordinator.dart:1018](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:1018). `seekTo` then reloads part one. The DVR slider passes the same local coordinate directly to `seekTo` at [player_view.dart:1162](/Users/tristan/Software/LineupDesktop/lib/playback/player_view.dart:1162).

This input is supported: `_parseMediaPart` explicitly preserves unknown durations at [plex_client.dart:1732](/Users/tristan/Software/LineupDesktop/lib/plex/plex_client.dart:1732), and the playback descriptor/request retains them. It violates the documented current-part fallback in [user-guide.md:281](/Users/tristan/Software/LineupDesktop/docs/user-guide.md:281).

Existing coverage checks unknown timing on the first part and aggregate projection once all boundaries become known. It does not combine a later active part, incomplete duration metadata, and a DVR seek.

Correction direction: make public timing and seek coordinates share one explicit policy. When presenting local part timing, seek locally within the active part; use aggregate mapping only when that presentation is aggregate. Keep initial live-join resolution distinct. Verify part-two forward/backward seeks and slider seeks, with complete metadata as the aggregate positive control. Physical Windows cross-part acceptance remains required after correction.

**D-C03 — Pending-load EOF is not retained for later commitment**

Classes C01/C07; journey J07. Parked pending evidence.

During a tune, `_activeLoad.request` exists before `_activePlayback` commits. `_event` obtains `request` solely from `_activePlayback` at [player_coordinator.dart:477](/Users/tristan/Software/LineupDesktop/lib/playback/player_coordinator.dart:477). A natural `ended` event in that interval cannot advance because line 517 requires that committed request. `_completePartLoad` can subsequently return the request at line 890, and `_performTune` commits it at lines 682–683 without checking its terminal state.

The source establishes what happens **if** EOF arrives in this interval. It does not establish that the current Windows message/microtask ordering produces that interval during a normal load; `DrainEvents` batching alone is insufficient proof. Near-EOF live joins and pending seeks are relevant cases.

Minimal controller-owned probe: reuse the existing continuation fixture and real coordinator; make a synthetic player emit playing→ended for the current generation before its load future settles, with valid progress and a duration inside the premature-end tolerance. Compare against ordinary EOF after completed tune. Observe successor loads, final intent/status, and committed loaded-program identity. Repeat through `WindowsNativePlayer`’s actual codec boundary if promoting this beyond the allowed-event-sequence claim. No probe was created or run here.

**Scope and evidence**

Wide inventory covered all seven `lib/playback` files, all six `test/playback` files, Windows runner source/header/test/CMake/manifest surfaces, the authenticated-reference Python runner, and their shell/bootstrap/controller/Plex consumers.

Deep inspection covered:

- Entire coordinator and Windows Dart adapter: tune serialization, load readiness, authorization replacement, multipart targets, EOF classification, confirmation timers, stop cleanup, sleep expiry, scope retirement, fullscreen ordering, disposal.
- Entire native player implementation/header: platform/worker ownership, command and event queues, playlist correlation, per-load headers, initialization restrictions, stop results, window-close handshake, fullscreen rollback and bounds projection.
- Player input dispatch, OSD timing/slider/actions, overlay transitions, track semantics/focus/scrolling, sleep picker, native surface and slate/error presentation.
- Native encoder and harness source; representative assertions for correlation, stop failure/retry, track execution versus observation, continuation boundaries, replacement, accessibility, transformed bounds and unknown timing.
- Relevant architecture, user guide, interface decisions, continuation plan, native acceptance/development instructions, authenticated-reference investigation, prior review/remediation status and CI definitions.

Important exclusions: private stores/logs/media, native execution, physical Windows observations, package execution, GPU/HDR output, actual screen-reader/remote behavior, opaque assets and build outputs. Engine patch and release-script implementation belong to the other assigned review unit; only their playback-facing contracts were considered here. Portable baseline results remain the controller’s evidence.

Read-only commands were Git status/revision/diff/log/show, `rg`, and source/document reads. Final inspected playback/native/test inputs had no local product delta, and HEAD remained unchanged. Existing modified October 7 reports and untracked review material were preserved.

**Dimension coverage**

| Dimension | Deep sample and disposition |
|---|---|
| Architecture/ownership | Dart owns schedule, presentation and interaction; native owns mpv/window mechanisms. No additional ownership violation established. The native interface represents a real boundary. |
| Correctness/failure modes | D-F02 retained; D-C03 parked. Cleanup, authorization retry ceiling, stop/load retirement and track confirmation guards were traced. |
| Maintainability/AI debt | No material concern promoted. `_PlaybackLoad` cohesively carries readiness, part, target and recovery; separate intent/lifetime identities have concrete obligations. File size was not treated as a defect. |
| Tests/CI | D-F01 retained. Strong existing negative/currentness tests; missing mixed-duration seek combination identified. No test run claimed. |
| Security/privacy | Per-file header, HTTPS requirement, redirect refusal, reference/autoload restrictions, bounded token validation and buffer clearing inspected. No new credential exposure established. D-F01 weakens usable verification, not demonstrated containment. |
| Build/release/supply chain | Native CMake pins and opt-in harness integration inspected. No further build defect established; broader package/provenance review excluded from this unit. |
| Operations/config/diagnostics | Fixed failure vocabulary and safe structured playback diagnostics inspected. Historical F15 remains: no `paused-for-cache` producer or adapter mapping. |
| Performance/concurrency/reliability | Queue count/byte bounds, correlation/metadata limits, worker teardown and UI notification coalescing inspected. No additional measured performance defect or clear data race established. |
| Docs/DX | Continuation and platform evidence limits are appropriately qualified. Multipart promise conflicts with D-F02. Planned transcode/HDR work was not reported as regression. |

**History-derived class reconciliation**

Representative diffs were inspected, not just commit titles.

| Class | Historical mechanism/fix and current sibling hunt |
|---|---|
| C01 | `835ab431` retained cleanup/readiness despite superseded seeks; `5acae4d1` unified load/recovery ownership. Searched load/seek/stop/dispose consumers and traced authorization, scope and continuation currentness. D-C03 is the remaining candidate. |
| C03 | `a061935a` added per-load redirect refusal; `3d2014e6` disabled references/autoload. Current native load options, token/header lifetime, Dart request construction, recovery and harness controls retain those protections. No new leak promoted. |
| C07 | `51900b52` bounded stop; `835ab431` separated cleanup obligation; `4e01d438` separated track execution/confirmation; `db30c286` split EOF/stop; `91b66b7e` preserved live-join progress; `cd2c08f6` ended presentation preservation at readiness. D-F01/D-F02 and D-C03 identified across their consumers. |
| C09 | `6b874f35` stopped event-driven timer rearming; `b86693d9` separated pointer/keyboard focus and retained loading pause; `0421c88e` fixed overlay activation/navigation. Current dispatch and timing guards retain these fixes; October 7 F07/F08 are resolved. |
| C10 | `02330deb` added complete actionable track semantics; `825070fd` retained footer visibility. Current rail scrolling, selected-row revelation, transformed native bounds and relevant widget assertions inspected. D-F02 concerns timing coordinates; physical DPI/AT remains unverified. |
| C11 | Existing native queue/correlation/encoder bounds and 250ms visible-position bucketing remain. Repeated event timer resets were not rediscovered. F15 buffering projection is still explicitly deferred. No measured cost claim made. |
| C13 | `d6fff072` required progress without later rejection; `29062716` latched rejection across stop. Both protections remain, but the newer EOF vocabulary was not propagated to the harness: D-F01. |

Repo-wide searches included native command consumers, terminal-state consumers, `loadId`/`stopId`/`trackResult`, bounds/fullscreen calls, authenticated options, buffering/cache properties and corresponding tests.

**Journey/action and input map**

| Entry/context | Eligibility, path and recovery |
|---|---|
| Manual tune, Page Up/Down, number entry | Channel lookup→serialized tune→cleanup→current schedule→PMS descriptor→native readiness/seek→channel commit. Error offers live Retry; newer intent/scope retires work. |
| Natural EOF | Duration/progress tolerance→next part or same-channel successor; lateness greater than 30 seconds joins live. Stopped/error does not count as natural EOF. |
| DVR transport/slider | Flutter setting suppresses transport keys/UI when off. When on, coordinator controls preserve currentness; D-F02 affects incomplete multipart seeking. |
| Audio/subtitle rail | Available native tracks enable entry. Request→correlated execution result→observed selected track; separate timeouts retain truthful confirmed selection and inline recovery. |
| Mini Guide | Up/Down browse; Page keys move seven rows; Enter/numpad Enter/Space/Select tune; Right or G/F2 opens full Guide. Persistent until explicit action/dismissal. |
| Track/error contexts | Track rail owns traversal/activation while G/F2 can leave; error permits Page channel recovery. Shell Ctrl destinations propagate to its leave guard. |
| OSD/Now Playing/Sleep | Presentation identity rejects stale focus callbacks; keyboard focus suspends OSD timeout; pointer activity resumes timeout. Sleep deadline survives pause/tune/Guide and yields to explicit cancellation. |
| Stop/logout/content/dispose | Immediate intent retirement plus independently correlated native cleanup; failed stop retains cleanup responsibility. Native teardown precedes messenger destruction. Physical shutdown remains unobserved. |
| Local `--media=` / macOS | Windows local load uses the same native boundary without PMS header. macOS backend consistently reports unsupported playback. |

**Exact MethodChannel inventory**

Channel: `lineup/native_player`; codec: `StandardMethodCodec`.

Outgoing methods:

- `initialize`, `dispose`, `play`, `pause`: no payload.
- `load`: `uri`, nullable `plexToken`, integer `loadId`.
- `seek`: nonnegative finite `seconds`.
- `stop`: positive `stopId`.
- `selectTrack`: `type` (`video`/`audio`/`subtitle`), nullable positive `id`, positive `loadId`, positive `requestId`.
- `setVolume`: finite `volume` in 0–100.
- `setFullscreen`: boolean `fullscreen`.
- `setVideoRect`: finite `left`, `top`, nonnegative `width`/`height`, positive `scale`.

Incoming method `event`:

- `state`: correlated `loadId`, state/message, optional normalized `failureCode`/`httpStatus`.
- `property`: correlated `loadId`, name/value for pause, time-pos, duration, track-list, video-format, video-codec, current-vo, hwdec-current, video-params.
- `stopResult`: `stopId`, boolean success.
- `trackResult`: `loadId`, `requestId`, boolean success.

Native emits loading/playing/ended/stopped/error plus initialization idle; it does not currently produce buffering or seeking states. Adapter-generated statuses and interface enum vocabulary are broader.

**Claim matrix and remaining acceptance**

| Authority | Disposition |
|---|---|
| User guide 281–285: aggregate timing versus current-part fallback | Implementation defect D-F02. |
| User guide 287–300 / continuation plan: successor, tolerance, priority | Implemented source/tests inspected; D-C03 needs evidence; physical continuation outstanding. |
| NativePlayer track contract / architecture | Execution and observation remain distinct; source agreement. |
| Architecture authenticated-load restrictions | Source agreement; current harness execution blocked by D-F01 until corrected. |
| User guide 302–309: focus/timers/AT | Source and existing widget coverage agree; physical Windows AT remains pending. |
| README/native validation: Windows implemented, acceptance incomplete; macOS unsupported | Accurately qualified. |
| Transcoding and automatic fullscreen HDR | Planned work; excluded from new regression findings. |

The pinned mpv API distinguishes EOF from external stop and defines file-loaded as decoding startup rather than terminal completion; it also permits EOF for interrupted/incomplete media, supporting the coordinator’s separate premature-end policy. [Pinned mpv client API](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/include/mpv/client.h#L1413).

Windows follow-up must retain exact source/runtime/package identity and cover both native CTests; real authenticated MP4/MKV playback and rejection/recovery; rapid replacement and pending shutdown; complete/incomplete multipart seeks; tracks; EOF/stop/error and 30-second boundaries; cache starvation/user-pause distinction; Player↔PiP, resize/minimize/fullscreen/mixed-DPI bounds; physical keyboard/remote/AT; representative codecs/subtitles/HDR; and packaged launch outside the checkout. None was executed here.

Automatic approval review rejected the callback to the parent chat, stating that messaging authorization was not established despite retrieval of the original human authorization reference. This report remains here for parent retrieval. Explicit approval is needed before retrying that callback.
