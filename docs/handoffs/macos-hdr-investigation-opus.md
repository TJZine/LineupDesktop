# macOS HDR brightness investigation — handoff to Opus 5.5

## Request and boundaries

Investigate this issue independently and suggest a cause, discriminating
experiment, or justified correction. Challenge the existing hypotheses. No root
cause has been established and no production HDR workaround has landed.

The user requested this handoff after the latest experiment. Further Codex HDR
experiments are paused. Start by reading the existing evidence; do not immediately
rebuild, relaunch, resize, reload, or otherwise destroy the current scene.
Propose consequential instrumentation/runtime changes before implementing them.
Use synthetic fixtures only, preserve the accepted runtime, and keep production
changes separate from diagnostic copies. Any implementation should receive an
independent adversarial review before integration. No release, main-branch merge,
signing/account changes, purchase work or communication to other people is part
of this investigation.

Read `/Users/tristan/Software/LineupDesktop/AGENTS.md` and
`/Users/tristan/Software/LineupDesktop/.agents/project.md`. Flutter/Dart owns
interaction and playback policy; native code owns media/platform mechanisms.
The approved Player layout must remain unchanged. The historical port plan is
context, not a requirement to retain an unhelpful abstraction or investigation.

## Repository and environment

- Checkout: `/Users/tristan/Software/LineupDesktop`, branch `platform/macos`.
- Source HEAD at preparation: `82be4c249a546019c32bf34646912ce6fcca0357`.
  The tree was clean before adding this handoff. Later handoff-only commits do
  not change the product inputs described here; verify current status yourself.
- Apple Silicon Mac, macOS 27, physical EDR display. First-release target is
  Apple Silicon, existing bundle ID `com.tjzine.lineupDesktop`, deployment target
  macOS 12.0; older-OS acceptance remains unverified.
- Pinned Flutter: `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`.
  Prefix its `bin` on PATH; the default Flutter is the wrong version.
  Framework revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5.
- Accepted immutable runtime:
  `/Users/tristan/Software/LineupDesktop/build/macos-runtime/dist/arm64`.
  Do not rebuild or modify this directory to try a diagnostic patch.
- Runtime lock SHA-256:
  `7df202602cc5a0276a7ac8762b0b4289e33e2db4a01d8adc352ca438ab9e842c`.
  BUILD-INFO SHA-256:
  `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.
  libmpv SHA-256:
  `625eb842c7d9ef5e3324a0ff44733adcf4cfa82b0fabe8bb5edb73d555adc30f`.
  mpv commit `3186d369f9f090cd1363be0ac46a037824b702c6`.
- Original app was built with the real-protocol synthetic harness
  `/Users/tristan/Software/LineupDesktop/test_driver/macos_native_harness.dart`.
  Channel 1 is SDR gray; channel 2 is an HDR PQ ramp with a moving bright bar.
  Schedule/program labels change with the clock; fixture identities stay fixed.
- Fixture paths:
  `/Users/tristan/Library/Containers/com.tjzine.lineupDesktop/Data/tmp/lineup-media/sdr-long.mp4`
  and the adjacent `hdr10-long.mp4`.

## Established physical observations

The user sees substantial brightness changes that screenshots do not capture.
Treat their direct observations as physical evidence. PQ flags, screenshots,
target metadata, compilation and headless tests do not establish HDR brightness.

1. In Player, switching SDR → HDR can leave HDR visibly dim. Opening Guide on
   the same clip restores brightness; returning to Player retains it.
2. An unchanged-original-app baseline was held through three human judgments:
   C: SDR → HDR in Player **dim**; D: same clip in Guide **brightness recovered**;
   E: same clip back in Player **still normally bright**.
3. A foreground, fixed-size windowed sequence with waits of 8 seconds on HDR,
   8 seconds on SDR, then 5 seconds on HDR ended normally bright. The user
   clarified the failure occurs when switching back and forth faster.
4. The user then performed `1 Return → 2 Return → 1 Return → 2 Return` rapidly
   in foreground windowed Player and reported **stays dim for 5 seconds**.
   The transition-logging diagnostic copy reproduced this too.
5. Latest drawable-instrumented trial: the initial HDR reference was already
   dim; rapid switching remained dim. The user then accidentally selected
   channel 2 again while already on dim channel 2, and it became properly bright.
   **The user reports same-channel HDR reselection as another repair path.**
   Native attribution is not yet unique, and the trace also contains an extent
   roundtrip (details below). The latest final scene is bright, not a held
   failing endpoint.

Latest user report verbatim:

> the refernce was not bright. and switching back and forth it stayed dim. i
> accidentally switching to channel 2 while and on channel 2 while it was dim
> and then it ended up bright which is weird, so channel 2 dim swap to channel 2
> and its properly bright

Important confounds and failed comparisons:

- Returning to the Codex chat can put Lineup into Stage Manager. A miniature
  can look dimmer. One fresh-original comparison became bright after both
  focusing and fullscreening; those actions were confounded. This does not
  explain away the separately reported foreground rapid-switch failure.
- For physical trials, have the user judge **before returning to chat**. Do not
  assume selecting an app through automation makes it the real foreground app.
- Several bounded external focus traces expired before the human performed
  the sequence. Their zero foreground samples do not disprove the human report.
- Heavy and sparse diagnostic builds looked normal during slow switching.
  These were non-reproductions, not fixes or evidence logging caused the bug.
- The first diagnostic copy crashed reading a Metal-specific property from
  `presentationLayer`. This was a probe-only bug; those runs are invalid. The
  offending reads were removed. Do not repeat them.
- A proposed debugger-only pause control **never ran**: its eight-second
  foreground gate was never met. The user later found the app already bright.
  There was no sham attachment, app expression, flush or setter in that trial,
  and no causal repair result. Its controller was disarmed/stopped.
- No `CATransaction flush` intervention has been executed. No controlled
  extent/recreation intervention has been executed beyond the user's original
  Guide/fullscreen observations.

## Start with these local artifacts

Everything below is in `/tmp/lineup-visible-hdr-investigation/` on this Mac.
These local artifacts will need copying if Opus runs elsewhere. They are not
committed repository resources. Keep synthetic logs separate from private media.

### Latest drawable trial (highest-priority new evidence)

- **`opus-freeze-index.json`**: start here for the master frozen artifact index,
  hashes, current process, source identities and interpretation limits.
- `drawable-trial-identity.json`: exact original/candidate comparison, physical
  report, source/build linkage, process path and frozen log hashes.
- `drawable-trial-frozen.log`: frozen acquisition/presentation + native load
  and source/target trace. SHA-256
  `3b6bfa048e9ffd681b29ecf3ae12996ef889ca214e8e349eaac4c275072f7d21`.
- `drawable-trial-display-frozen.jsonl`: external focus/window/headroom trace;
  SHA-256 `e99034f592034e94909b58cabadc24385d1634b25fd2aefc3fecc51611a174a1`.
- `drawable-trial-parsed.json`: per-load/acquisition/callback parsed records.
- `drawable-source-identity.json`, `drawable-build-identity.json`,
  `drawable-candidate-running-identity.json` and `drawable-build.log`.
- Diagnostic-only patches: `drawable-LineupNativePlayer.mm.patch`,
  `drawable-player_core.cpp.patch`, `drawable-player_core.h.patch`.
- `phases.log`: experiment chronology; summaries are not new physical trials.

Latest candidate app:
`/private/tmp/lineup-drawable-hdr-diagnostic/build/macos/Build/Products/Debug/Lineup Desktop.app`.
Last verified PID 57541; recheck, do not assume the PID survives handoff. All
external observers and timed controllers were stopped at final freeze. No
automatic intervention remains armed.
Its native Debug dylib SHA-256 is
`1e014e8fd84276ecab4db9fa80ca77d733716ab75ebd862d32e28c270779ec38`.
Live log (use frozen copy first):
`/Users/tristan/Library/Containers/com.tjzine.lineupDesktop/Data/tmp/lineup-drawable-hdr.log`.

This copy reuses the **entire original App.framework**, Flutter engine and all
media dylibs. Original kernel SHA-256:
`85687118cee51850fd94f457c2f17bf4efc3a78d07b1d31dcba93a23eb267eeb`;
engine SHA-256:
`47329c4fec9daa4c3923dd5a4e3cbb4963da06093538e5e084fd8a73ff7d5118`.
Only native diagnostic instrumentation differs. Ad-hoc deep/strict signing and
the pinned isolated Debug build passed. This is a diagnostic copy, not a
production correction or signed-release acceptance candidate.

### Earlier reproduced failure with transition logs

- `rapid-candidate-failure-analysis.md` and `rapid-candidate-load-timeline.json`.
- `rapid-candidate-failure-frozen.log`, SHA-256
  `79ccb3decc672ed1fb735cf7a1c159afd1f8da6f51bcdb0c6ea97681fdd3052d`.
- `rapid-candidate-failure-identity.json`.
- Original uninstrumented failure: `running-app-identity.json`, `phases.log`,
  `rapid-failure-identity.json`, `rapid-failure-layer-print.log`,
  `rapid-failure-post-inspection.json`.
- `invalid-sham01-result.json` documents the control that never ran.

Earlier transition trace ends coherently on HDR load/playlist 9: accepted,
START_FILE, FILE_LOADED, then playing. Current public mpv queries read source
PQ/bt2020/VideoToolbox p010, 1920×1080, sig-peak 4.92611; target PQ/bt2020,
bgr10a2, 1600×900, same sig-peak. Layer PQ/EDR/metadata enabled, pixelFormat 94,
drawable 1600×1200, bounds 800×600 at scale 2, windowed; current and potential
headroom both 16. No newer load/stop followed. The 1600×900 target is the
letterboxed render target, **not an observed Vulkan swapchain extent**.

Native cadence is not requested-key cadence: the last SDR→HDR invocation gap
in that trace was about 3.64 seconds. Intermediate tunes can be superseded;
repeated HDR loads occurred. Do not claim sub-100ms native switching or identify
actual loaded media solely from the UI channel number. Observed/encoded stale
events and synchronous queried-current values are logged separately.

Original process model inspection was after returning to chat and debugger
attachment. It showed nominal PQ/EDR and expected extent, but attachment/getters
may perturb scheduling. No whole-memory dump or permission changes were made.

## What the latest probe actually measures

A diagnostic subclass replaces only the owned video layer's factory. Its
`nextDrawable` calls `super` exactly once on the original caller thread and
returns the exact drawable or nil. It samples public actual texture format and
size, requested layer descriptor before/after acquisition, and selected
`addPresentedHandler` callbacks with `presentedTime`/drawable IDs.

No process-wide swizzle, retry, setter, present call, GPU wait/readback or
presentation-copy Metal getter is added. Async logging blocks capture scalar
data, not the layer/texture/drawable. Still, getter/counter/callback/logging
overhead can perturb a race and must not be treated as transparent.

- `layerSerial`/`descriptorEpoch` are diagnostic values, **not Vulkan swapchain
  identities**.
- Accepted-load context at acquisition/callback is approximate context, not
  proven ownership of the submitted frame.
- A callback with `presentedTime == 0` is not positive presentation proof.
  Initial background samples had zero times; later samples contain positive
  times. Match them to the physical interval before interpreting them.
- Format/size and successful presentation do not establish framebuffer pixel
  values or final Core Animation/EDR interpretation.

Final frozen measurements (not a root-cause verdict):

- 94 selected acquisitions: zero nil returns and zero actual texture
  format/extent mismatches against requested descriptors before/after the call.
- 94 selected callbacks: 85 with positive `presentedTime`, nine with zero.
  Callback drawable IDs matched; no accepted-context crossing was observed in
  these samples. Positive presentation times occur in foreground HDR loads,
  including reference load 2; initial background load 1 had seven zero times.
- The same diagnostic `layerSerial=1` remains; `descriptorEpoch` changes 1→2→3.
- **Actual geometry confound:** during load 10 the video extent roundtrips
  1600×1200 → 425×239 → 1600×1200 over about 0.41 seconds. Model hidden/rect
  events and actual acquired textures confirm it. The route is not explicitly
  logged, so do not name it Guide or ascribe its cause. Do not claim the entire
  trial had no geometry change. Later loads 12/13/14/16/17/19 follow it.
- Final load 19 is HDR but is preceded by load 18 SDR. Native HDR→HDR pairs
  include 1→2 (initial reference), 12→13, 13→14 and 16→17. The human's physical
  report is valid, but it does **not uniquely map the repair to one such pair**.
  Final 19 is not an unambiguous same-HDR repair pair.
- Some transitions include temporary 1×1 target descriptors; distinguish them
  from acquired texture sizes. The sampled absence of descriptor mismatches
  narrows that hypothesis; unsampled transitions, pixel payload and final CA
  color interpretation remain separate gaps.

## Relevant source and independent review findings

Repository starting points:

- `macos/Runner/NativePlayer/LineupNativePlayer.mm` (host layer, rectangles,
  visibility, native events; unchanged production SHA-256
  `47f341998181a6925d89b93c6f5c2530139552b8c124e7b6ecaee76cb3fc2473`).
- `native/player_core/player_core.cpp`: actual load/stop execution, event and
  playlist identities. `lib/playback/player_coordinator.dart` serializes tunes
  and supersedes obsolete work; enqueue/playing is not frame-presentation proof.
- `tool/macos/mpv-patches/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch`.
- Exact accepted-source hashes and paths: `source-identity.json` in the artifact
  directory. Paths are relative to the checkout root.

Accepted sources exist under:

- `build/macos-runtime/src/mpv-0.41.0-1092-g3186d369f/video/out/vulkan/context_mac.m`
- the same mpv tree's `video/out/vo_gpu_next.c`
- `build/macos-runtime/src/libplacebo-7.360.1/src/vulkan/swapchain.c`
- the same libplacebo tree's `src/renderer.c`
- `build/macos-runtime/src/moltenvk-1.4.2/MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm`
- that MoltenVK tree's `GPUObjects/MVKImage.mm` and `OS/CAMetalLayer+MoltenVK.mm`.

An independent source reviewer verified the accepted identities and found:

1. mpv sends a color-space hint before starting a frame. libplacebo marks
   recreation when format/color space changes and explicitly replays cached
   nonempty HDR metadata after recreation. A universal missing reconfigure or
   simply forgotten metadata explanation is unsupported.
2. MoltenVK configures color/EDR/metadata from the rendering caller thread in
   these paths, with no explicit main dispatch/CA flush there. That keeps
   publication hypotheses open; thread location alone proves no API violation.
   A main-thread flush negative would not clear a render-thread transaction.
3. Steady frames do not continuously reapply all settings: format and metadata
   caches can make a transition defect persistent despite correct getters.
4. `MVKImage.mm` acquisition retries nil/nonzero-format failures but does not
   compare actual drawable texture format/size with the requested swapchain
   descriptor at that point. libplacebo wraps the requested format/extent;
   mpv publishes target parameters before flip/presentation. This motivated
   the latest actual-drawable probe.
5. GPU completion and actual presentation differ. MoltenVK has scheduled,
   completed and presented callbacks with different responsibilities. It
   explicitly documents missing last presented callbacks and uses drawable
   size 1×1 as a completion workaround. A fence alone proves no presentation.
6. Same-extent replacement can force 1×1. However, an old swapchain destructor
   forces it only if still the active chain; replacement sets the new active
   chain first. Do not assume every retired chain can overwrite the new extent.
7. Extent repair is nonunique: recreation changes resources/pool, applies color
   and EDR, and replays metadata; Guide also changes main-thread transactions.
   Writing A→B→A within one block may be missed by the embedding size poll, so
   such a nudge is not proof of Vulkan recreation.
8. Simple stale peak-detection history is not established. SDR/non-applicable
   paths reset peak detection, while a geometry resize does not directly flush
   that cache. It remains worth evaluating against the same-HDR-reload repair,
   but metadata/extent repair alone does not prove it.

These are source facts and hypotheses, not a root-cause verdict. Investigate
frame payload/tone mapping, drawable lifecycle and final CA/EDR interpretation
according to the evidence; do not default to a forced resize or flush workaround.

## Unrelated status — avoid conflating gates

Native Mac keyboard/fullscreen physical checks passed. macOS hosted CI at
`5740cc98` passed full portable/native, authenticated-reference, runtime embed,
app build and native tests. A separate harness fake-window `styleMask` defect
was reviewed, fixed and passed all 26 local cases plus hosted verification.

Windows CI separately found a missing Vulkan loader. Reviewed CI-only pinned
LunarG loader provisioning is committed/pushed at `b0c38b5b`; the current prior
CI run is still being observed before another dispatch to avoid cancellation.
Do not change Windows/core/provisioning policy to investigate this HDR issue.
Purchases are deferred. Licenses UI direction and release signing/legal gates
remain separate. No release readiness is claimed.

## Desired result from Opus

Give an independent assessment of the strongest supported mechanism and the
best next discriminating observation, citing exact source and trace evidence.
Clearly separate physical observations, queried descriptors, actual drawable
facts and hypotheses. If a correction is justified, explain its owner, why it
addresses the cause, adjacent behavior it could break, and the smallest honest
verification/review plan. If evidence remains insufficient, say exactly what
would distinguish the remaining explanations without repeating weak trials.
