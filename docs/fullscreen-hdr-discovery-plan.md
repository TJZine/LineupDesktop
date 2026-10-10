# Fullscreen HDR Discovery Plan

**Status:** Windows 10 discovery completed on October 9, 2026; see
[Discovery result](#discovery-result-october-9-2026). The result is
feasibility evidence for planning. It does not authorize production
implementation or establish an HDR-support claim.

**Purpose:** Determine whether the existing composited Player renders SDR and
HDR correctly across a supported, reversible Windows display-state change,
identify the minimum mpv refresh required, and then produce the implementation
plan.

**Platform scope:** Discovery and the first supported configuration target
Windows 10 22H2 (`10.0.19045`), the only physical HDR test machine currently
available. Windows 11 24H2 and later remain an open route (see
[Windows version scope](#windows-version-scope)); this plan produces no
Windows 11 evidence or support claim.

**Starting point:** Amended on October 7, 2026 against
`codex/desktop-ui-second-pass` (`ebc1b4e0` plus this amendment). The earlier
`dev/desktop-ui-refinement` `cda27a86` inspection is historical. Resolve and
record the actual target commit before every instrumented build or physical
run.

## Discovery result (October 9, 2026)

**Classification: existing composition passes** (Step 7, outcome 1) for SDR
and static HDR10 on the tested Windows 10 / Sony A90K configuration. No
renderer/composition blocker or required correction was found; no
presentation-mode change is justified. The full redacted report and evidence
remain untracked on the test machine under the identities below.

**Identities.** Frozen target `50c4e9d345209a1e504b2d9b8190ee4fe2a152b0`
(`codex/desktop-ui-second-pass`). The read-only trace was the only change:
`a1dd26933d58aae8fd8cdbd4ec6a9e8ec9578768` on `codex/hdr-discovery-win10`,
touching `windows/runner/native_player.cpp`. That branch is discovery
evidence and must not be merged. Debug EXE SHA-256: baseline
`A04B5A7BE5D8062FB7DCC81CCC47D59AECFEDBF442FBDC9D48E35570577E7389`, trace
`02B1DB441E0FC3ACB8AC794158879B8866CB44DF54AD5DEB03BEDFC8D953A1F5`. Pinned
Flutter, patched engine, libmpv, FFmpeg, and libplacebo identities matched
[build metadata](../tool/windows/build-metadata.psd1) and
[runtime provenance](windows-runtime.md). The application build selected
Windows SDK `10.0.26100.0`. Standalone probe SHA-256:
`1C770E4FDBDAA2D981E1510B69FC9A8F858156D06429644E6883EA19AC88C907`.

**Environment.**
- Windows 10 Home `10.0.19045`, NVIDIA RTX 5080 with driver `32.0.16.1714`.
- Sony A90K directly over HDMI at 3840×2160, 120 Hz. A second HDR monitor was
  connected, but the Lineup window still mapped to exactly one active target.
- Audio played through computer speakers, so there is no HDMI/eARC audio
  evidence.
- Stimuli were synthetic BT.709 SDR and PQ/BT.2020 HDR10 (1000-nit mastering)
  patterns with a continuous tone, plus local SDR, HDR10, and Dolby Vision
  profile 8.1 footage.
- Visual results are qualitative operator judgments; no meter was used and TV
  signal information was not recorded.

**Windows 10 route.**
- `GET_ADVANCED_COLOR_INFO` and `GET_SDR_WHITE_LEVEL` succeeded.
  `GET_ADVANCED_COLOR_INFO_2` returned 87 (`ERROR_INVALID_PARAMETER`).
- All four `SET_ADVANCED_COLOR_STATE` writes returned 0, and re-queries
  verified each requested state.
- Each synchronous set call took about 350 ms, and display messages could
  arrive before it returned.

**Renderer.** Every [pinned-source prediction](#pinned-source-pre-analysis)
that was observed held:
- The binary used the predicted defaults for all six options.
- HDR10 on an HDR display rendered as PQ/BT.2020 in `rgb10a2`.
- HDR10 on an SDR display used a gamma 2.2/BT.709 `rgb10a2` fallback.
- SDR on an HDR display was placed in PQ/BT.2020 `rgb10a2`.
- FP16 was not needed.
- The renderer converged with **no explicit refresh**, both while playing and
  while paused.
- DXGI colorspace enums and HDR-metadata writes were not instrumented and
  remain source predictions.

**Rows.**
- All four static rows passed qualitatively.
- Manual HDR10 transitions passed in both directions while playing and while
  paused, with normal resume.
- The SDR manual row passed visually; its audio was not observed.
- Programmatic HDR→SDR and SDR→HDR, each followed by restoration, passed, with
  handled normal restoration physically verified.
- Dolby Vision profile 8.1 decoded as PQ/BT.2020, and the current `isHdr` check
  reports it as HDR.
- No HLG sample was available. Plex HTPC was not run.
- Overlay, input, and geometry were good in the local-media rows. Rich Now
  Playing with Plex was not exercised, and composition remains provisional
  until the second-pass Player work lands.

**Timings.** Software timings below were taken from the polling state sample
or the request; blanking times are human estimates.

| Measurement | Result |
| --- | --- |
| Manual, playing: Windows state → renderer target | 0.85–1.22 s |
| Manual, paused: Windows state → renderer target | 3.39–4.03 s |
| Manual: Windows state → `WM_DISPLAYCHANGE` | 0.16–0.80 s |
| Programmatic: request → state observed (switch / restore) | ≈1.12–1.13 s / ≈0.35 s |
| Programmatic: request → renderer target | 1.20–1.38 s |
| Visible blanking and audio interruption (estimate) | ≈1–3 s |

**Notifications.** A hidden top-level window received `WM_DISPLAYCHANGE` and
later, often repeated, `WM_SETTINGCHANGE` messages. No single message proves
the resulting HDR state or who changed it; treat a message as a reason to
re-query. Receipt by the Lineup window and attribution of external changes
were not measured.

**Implications for the implementation plan.**
- Plan around the current `gpu-next`/D3D11/DirectComposition composition and a
  capability-selected legacy Windows 10 route. No mpv refresh operation is
  required.
- Run the synchronous setter off the platform/UI thread so it cannot stall
  input or have display messages handled in the middle of the call.
- Detect external changes by re-querying on `WM_DISPLAYCHANGE` or
  `WM_SETTINGCHANGE`, with bounded polling as a backstop.
- Resolve the [product questions](#product-questions-for-the-implementation-plan).
  The transition policy (question 1) depends on the not-yet-implemented
  continuation to the next scheduled program, described as a known limitation
  in the [user guide](user-guide.md#known-limitations).

**Still open for acceptance.**
- The Windows 11 route.
- HLG, other Dolby Vision profiles, and HDR10+.
- HDMI/eARC audio behavior during transitions.
- TV signal information and meter verification.
- The SDR rows the operator declined to repeat on the trace build.
- Rich Now Playing over Plex, and the final second-pass Player UI.
- Lifecycle, currentness, user override, and failure reconciliation.
- Crash recovery, which is currently absent.
- Driver-hang bounds.
- Multi-display and disconnect behavior.
- The packaged release.

## Fixed direction and product contract

Preserve the existing libmpv `gpu-next` / D3D11 child presentation and patched
Flutter DirectComposition path unless focused evidence proves an actual
renderer/composition blocker. Flutter must retain the Player OSD, overlays,
focus, input, and accessibility behavior. Do not begin with exclusive
fullscreen, a replacement renderer, Vulkan, forced FP16, a new player process,
registry changes, or Settings UI automation.

- Matching applies only to eligible fullscreen video presentation.
- When enabled, the display matches HDR content with HDR presentation and SDR
  content with SDR presentation.
- The display state captured before the fullscreen presentation is restored
  when that presentation ends; restoration is not unconditionally SDR.
- HDR-to-HDR replacement must not bounce through SDR.
- An observed user display-state change suspends matching for that fullscreen
  session instead of being immediately reversed.
- Matching failure and playback failure are separate outcomes. Playback may
  continue through a correct fallback for the display state actually observed.
- Initial scope is SDR and static HDR10. HLG, Dolby Vision, HDR10+, refresh-rate
  switching, and resolution switching remain separate unless focused evidence
  shows one blocks the initial scope.
- The dynamic range used for matching comes from the stream libmpv actually
  decodes, not Plex source metadata. Under the
  [transcoding plan](plex-transcoding-implementation-plan.md), an HDR10 source
  may arrive as tone-mapped SDR H.264 or as HEVC with HDR preserved.

The setting's default and rollout gate are later implementation/acceptance
decisions.

### Windows version scope

Windows 10 exposes only the original DisplayConfig advanced-color route:
`DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO`,
`DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE`, and
`DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL`. On Windows 10,
`advancedColorEnabled` corresponds to the HDR setting.

The newer `GET_ADVANCED_COLOR_INFO_2`, `SET_HDR_STATE`, and `SET_WCG_STATE`
values belong to the Windows 11 24H2 generation, in which HDR is separated from
automatic color management for SDR displays. Expect the legacy
"advanced color enabled" bit not to mean "HDR active" on those systems. Treat
Windows 11 semantics as unverified until a Windows 11 machine is tested; also
record there whether an OS-level automatic HDR video option exists, because it
would appear to Lineup as an external display-state change.

Consequences:

- Windows 10 discovery proves only the legacy route.
- The implementation selects a route from the capability actually observed on
  the machine, not from an OS-version comparison, so a Windows 11 route can be
  added without redesign.
- Until Windows 11 evidence exists, matching must not be offered or described
  as supported on Windows 11.
- The app's Windows SDK is not pinned (the patched engine uses
  `10.0.22621.0`). Record the SDK used for each build. Do not rely on headers
  for the newer values; a later implementation either pins a sufficient SDK or
  owns the required definitions.

### Product questions for the implementation plan

Discovery measurements inform these questions; they do not block discovery.

1. **Program boundaries while fullscreen.** Lineup changes programs on its
   schedule, so HDR↔SDR replacement during continuous viewing is the common
   case. A display transition blanks the television, and HDMI may resynchronize
   audio. Decide whether playback holds during the transition (drifting from
   the schedule) or continues (the viewer misses those seconds).
2. **HDR already active before an SDR program.** The contract switches to SDR.
   Confirm or revise this after the Plex HTPC observation in Step 3.
3. **Out-of-scope HDR families.** `PlayerTelemetry.isHdr`
   (`lib/playback/native_player.dart`) treats HLG as HDR, and Dolby Vision
   material commonly decodes with a PQ transfer. Decide what matching does for
   HLG and Dolby Vision before enabling it.
4. **Windows 11 availability** until its route is verified.
5. **Multiple Lineup instances.** The runner has no single-instance
   enforcement. Decide whether to enforce one instance or serialize display
   ownership.

## Discovery boundary

Discovery answers only:

1. Does the unmodified composited Player render known SDR and HDR10 correctly
   when Windows is already in the corresponding display state?
2. Does it survive SDR-to-HDR and HDR-to-SDR display transitions, first made
   manually in Windows Settings and then through one supervised programmatic
   request, with video, audio, overlays, input, and geometry intact?
3. Which supported Windows operation and minimum mpv refresh, if any, make the
   renderer converge, both while playing and while paused?
4. Which notification, if any, signals an external HDR change to the app
   (`WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE`, a stale DXGI factory, or only
   polling)? This determines how an observed user override is detected.
5. Which correlated observations are sufficient to establish and diagnose a
   safe output path?

Do not build a substantial throwaway controller. Full lifecycle/currentness,
controlled stale-result and worker-failure testing, crash-helper fault
injection, multi-display and multi-instance behavior, broad hardware coverage,
Windows 11, and packaged-release acceptance belong in implementation and
acceptance. Add a discovery experiment only when a named unknown would change
the architecture.

## Pinned-source pre-analysis

Static reading of the pinned sources on October 7, 2026: mpv
`3186d369f9f090cd1363be0ac46a037824b702c6` and libplacebo base
`92b5ac6db79f4d680eb656692f7bf51e9606f42a`. The shipped libplacebo build is
recorded as `-dirty`, so confirm behavior on the binary. These are predictions
to verify, not physical evidence. The
[October 9 discovery](#discovery-result-october-9-2026) confirmed every
prediction it observed on the binary.

1. **Defaults.** Lineup sets none of the HDR-related options. The effective
   defaults are `target-colorspace-hint=auto`,
   `target-colorspace-hint-mode=target`, `target-colorspace-hint-strict=yes`,
   `d3d11-output-format=auto`, `d3d11-output-csp=auto`, and
   `d3d11-output-mode=auto`. Composition mode is used only when explicitly set
   to `composition`, so the current `wid` path uses window mode
   ([vo_gpu_next.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo_gpu_next.c#L232-L245),
   [d3d11/context.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/d3d11/context.c#L73-L107)).
2. **Per-frame display query.** For every rendered frame, `gpu-next` asks the
   D3D11 context for the target colorspace. The context resolves the monitor of
   mpv's window and reads `IDXGIOutput6::GetDesc1`, recreating its DXGI factory
   when `IsCurrent()` is false. In `auto`/`target` mode the swapchain is hinted
   with the display's current colorspace
   ([vo_gpu_next.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo_gpu_next.c#L1436-L1480),
   [d3d11/context.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/d3d11/context.c#L210-L221),
   [d3d11_helpers.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/gpu/d3d11_helpers.c#L1000-L1060)).
3. **Swapchain reselection.** libplacebo re-picks format and colorspace when the
   hint changes and resizes buffers for a format change. An HDR display yields
   `R10G10B10A2_UNORM` with `G2084_NONE_P2020` and HDR10 metadata; an SDR
   display yields 10-bit `G22_NONE_P709` with tone mapping. FP16/scRGB is used
   only when requested
   ([swapchain.c](https://github.com/haasn/libplacebo/blob/92b5ac6db79f4d680eb656692f7bf51e9606f42a/src/d3d11/swapchain.c#L277-L420)).
4. **Expected convergence.** While frames render, the renderer should converge
   after a Windows HDR change without a Lineup refresh. While paused, no frame
   renders; whether mpv's `WM_DISPLAYCHANGE` handling produces a redraw is
   unknown and must be tested
   ([w32_common.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/w32_common.c#L1664-L1666)).
5. **Renderer telemetry.** `video-target-params` reports the transfer,
   primaries, and surface format of the last rendered frame and is refreshed on
   playback ticks. It supplies renderer-target and surface-format facts without
   `display-swapchain` or composition mode
   ([vo_gpu_next.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/video/out/vo_gpu_next.c#L1762-L1772),
   [command.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/player/command.c#L4895-L4903)).

If physical evidence contradicts a prediction, the evidence governs; record
the contradiction in the report.

## Sequenced discovery

### 1. Freeze the target

1. Select and record the full target SHA from a clean checkout; preserve
   unrelated local work.
2. Record the Player-surface status. As of October 7, 2026 the
   [desktop UI second pass](desktop-ui-second-pass.md) is active and Player OSD
   and Now Playing structure may still change. Discovery may nevertheless
   proceed: the baseline uses the unmodified app, the only instrumentation is
   native and read-only (Step 4), and the setter probe runs outside the app
   (Step 5). None of these edits Player UI. Treat overlay/composition
   observations as provisional and repeat them after the second-pass Player
   changes land. Renderer and display findings do not depend on OSD layout.
3. Record the pinned Flutter framework/engine, libmpv, FFmpeg, and libplacebo
   identities, plus the Windows SDK actually used for the application build.
4. Store untracked evidence under
   `build/native-acceptance/<full-sha>/fullscreen-hdr-discovery/`.
5. Maintain one `run-manifest.csv`. Each row records the source SHA,
   instrumentation identity, build identity, probe-script SHA-256 when used,
   Windows build, GPU driver, display/connection, and evidence paths.

After every instrumentation change, record a new immutable source identity,
rebuild, record the new build identity, and add a manifest row. Never combine
observations from different binaries under one result identity.

**Gate:** Stop if the exact source/runtime combination cannot be reproduced.

### 2. Inventory only capabilities needed by the probe

Against the pinned runtime on the Windows 10 machine:

1. Confirm the pre-analysis defaults on the binary through the Step 4 trace,
   which logs the six effective option values once at initialization.
2. Confirm that `video-target-params` and `video-params` are observable through
   libmpv in the current window-output path.
3. Record the Windows 10 route results: `GET_ADVANCED_COLOR_INFO`
   (`advancedColorSupported`, `advancedColorEnabled`,
   `advancedColorForceDisabled`, `wideColorEnforced`, encoding, bits per
   channel), `GET_SDR_WHITE_LEVEL`, and the return code for
   `GET_ADVANCED_COLOR_INFO_2` on this OS. Distinguish unsupported API or
   display, access failure, stale topology, rejected request, and
   accepted-but-not-observed state.
4. Establish the mapping from the Lineup window to its active DisplayConfig
   target: `MonitorFromWindow`, then `GetMonitorInfoW`, then the
   `QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS)` path whose source GDI device name
   matches. Exactly one active target must match; a cloned or ambiguous mapping
   fails closed.

Direct swap-chain telemetry is optional. Its absence is not grounds for
changing presentation architecture. Valid FP16/scRGB and RGB10/PQ paths can
both satisfy HDR; observe the actual path instead of requiring one format.

Record this in a single `discovery-report.md` under **Capability inventory**.

**Gate:** Continue when the Windows 10 query/set route and the mpv observation
behavior are understood well enough for supervision.

### 3. Prepare one controlled physical environment

1. Select one known SDR and one static HDR10 sample with independently verified
   transfer, primaries, bit depth, and mastering facts (for example, from
   `ffprobe` or MediaInfo). Add one HLG and one Dolby Vision sample for
   classification only (Step 4); they are not support targets.
2. Select SDR/HDR patterns that expose clipping, crushed or raised blacks,
   incorrect reference white, highlight loss, banding, and obvious
   gamut/transfer errors. Ordinary footage alone is insufficient.
3. Record the Windows build, GPU/driver, Sony A90K connection chain,
   resolution, refresh rate, scaling, HDR state, SDR content brightness, any AVR
   or eARC audio path, and the audio output format.
4. For each run correlate:
   - verified source characteristics;
   - Windows target and observed HDR state;
   - mpv renderer target when available;
   - display signal information when available; and
   - visual-pattern results plus video/OSD appearance.
5. Redact credentials, tokens, token-bearing URLs, private titles/media paths,
   and unsafe raw logs. Prefer the local-media entry point
   (`tool/windows/run.ps1 -MediaPath`) so discovery needs no Plex sign-in.
6. **Plex HTPC observation (recommended).** Parity with the official Plex HTPC
   app is the user's stated bar. On the same display chain, record its version
   and HDR-related settings, and observe whether it:
   - switches HDR on for HDR10;
   - switches HDR off for SDR when HDR was already active;
   - restores the prior state on exit; and
   - pauses or continues playback during a switch.

   Also record its blanking duration. These observations inform the product
   questions; do not infer Lineup implementation details from Plex HTPC.

Two HDR-status indicators do not establish correct HDR rendering. Correlated
rendering/display facts and appropriate visual patterns are required.

Defer the broader OS/GPU/display matrix until acceptance for the configurations
proposed as supported.

### 4. Establish the unmodified composited baseline

Run the exact target with the pinned patched Flutter engine and bundled libmpv.
Do not add a setter, force a surface format, or change mpv output mode.

**Static rows:**

| Windows state | Source | Required observation |
| --- | --- | --- |
| SDR | SDR | Correct SDR patterns, video, overlays, input, and geometry |
| SDR | HDR10 | Actual fallback; do not assume tone mapping |
| HDR | HDR10 | Correct HDR patterns and protected composition |
| HDR | SDR | Actual SDR-in-HDR and reference-white behavior |

**Manual transition rows.** The operator toggles HDR in Windows Settings
(System → Display → Windows HD Color settings → Use HDR) during fullscreen
playback, while the Step 5 probe script runs only in its read-only watch mode. Windows owns the state change
throughout, so no restoration code is required.

| Start | Action | Playback | Required observation |
| --- | --- | --- | --- |
| HDR on, HDR10 | Turn HDR off | Playing | Converges to correct SDR fallback; audio/OSD/geometry |
| HDR off, HDR10 | Turn HDR on | Playing | Converges to correct HDR |
| HDR off, SDR | Turn HDR on, then off | Playing | SDR remains correct in both states |
| HDR on, HDR10 | Turn HDR off, then resume | Paused | Whether the paused frame updates; whether resume converges |
| HDR off, HDR10 | Turn HDR on, then resume | Paused | Same |

For each transition record:

- the time of the human toggle;
- the window-message notifications and their times;
- the observed Windows state time;
- the first renderer-target change in the trace;
- the visually measured time to a correct picture;
- the blanking duration; and
- whether audio dropped, recovered on its own, or required restart.

**Classification rows.** Play the HLG and Dolby Vision samples once and record
the `video-params` transfer and primaries and what `isHdr` would conclude. Make
no presentation claim.

Windowed playback is optional comparison evidence. Packaged-release testing is
not part of discovery. If the target commit includes the second-pass OSD
transparency levels, record their legibility on the HDR rows as input to that
pass's physical gate, under this run's identity.

Record software events separately from human measurements. Do not turn a
human observation into a software timestamp.

**Read-only trace instrumentation.** Because renderer-target facts are not
currently surfaced, make one dev-only, read-only change on a discovery branch.
Gate it behind the `LINEUP_HDR_DISCOVERY_TRACE=1` environment variable in
`windows/runner/native_player.cpp`. When enabled it:

- logs the six effective option values once after initialization;
- observes `video-target-params` and `video-params`; and
- writes normalized, timestamped lines with the `[lineup-hdr]` prefix to stderr
  for changes in transfer, primaries, and surface format.

It must not emit paths, URLs, titles, or raw mpv messages, and must not change
any option or display state. Give the instrumented build a new source/build
identity and repeat only the affected rows. Report missing optional telemetry
as unavailable. Do not infer 10-bit output from the source format.

**Gate:**

- Correct HDR with protected composition intact proceeds to the setter probe.
- Missing optional telemetry does not block progress when correlated evidence
  establishes a safe output path.
- If manual transitions converge while playing, the minimum refresh during
  playback is "none". Carry any paused-state gap into Step 6 as the only
  refresh question.
- Visibly incorrect HDR with Windows HDR active permits focused inspection and
  routine correction inside the preferred architecture. An evidence-backed
  renderer/composition blocker is the stop-and-escalate point.

### 5. Meet setter-probe safety prerequisites

Run the programmatic setter from a small development-only PowerShell 7 probe
script, kept untracked in the evidence directory with its SHA-256 recorded in
the manifest. Do not add it to Lineup. The renderer observes the identical
Windows display change regardless of which process requests it. The script
exercises the same DisplayConfig route the native player will later call, and
a Lineup crash cannot strand the display because the script owns restoration.
Calling from inside Lineup is part of implementation acceptance.

The script needs three modes:

- **`query`:** one-shot state, white level, and mapping report.
- **`watch`:** read-only. Polls state every 100 ms and logs `WM_DISPLAYCHANGE`
  and `WM_SETTINGCHANGE` from a hidden top-level window, with ISO-8601
  timestamps.
- **`toggle`:** captures the initial state, requests the opposite state, waits
  a bounded time for the new state to be observed, holds for an
  operator-confirmed observation, then restores the initial state and
  re-queries.

The script resolves the Lineup window as the single top-level
`Lineup Desktop` window owned by `lineup_desktop.exe`.

No display mutation occurs until:

1. A physical operator is present and can restore Windows HDR manually through
   Settings → System → Display → Windows HD Color settings. Win+Alt+B is not a
   reliable Windows 10 route. An HDR change made through DisplayConfig persists across reboots
   like the Settings toggle, so an unrestored change remains until someone
   reverses it.
2. The exact source/build identity, probe-script hash, and controlled
   environment are recorded.
3. Exactly one Lineup instance is running, and the window maps unambiguously to
   one active target; mirrored or ambiguous mappings fail closed.
4. A fresh query confirms support and captures the observed initial state.
5. The setter/re-query path is supported and bounded, with one mutation in
   flight.
6. Restoration runs from a `finally` path covering probe completion, handled
   errors, timeout, and Ctrl+C.
7. The record states that crash-time protection is absent. Without armed
   recovery, do not deliberately terminate a process, inject a crash,
   disconnect the target, or run unattended.
8. The probe is development-only and cannot be mistaken for production.

Verified normal restoration and crash-time protection are different claims.
Discovery establishes the former. Process-death testing waits until a recovery
owner has been implemented and armed before mutation.

**Gate:** If any prerequisite fails, do not mutate the display.

### 6. Run one reversible setter/refresh probe

With fullscreen Lineup playing, run the reversible setter/refresh controls for
both SDR-to-HDR and HDR-to-SDR:

1. Re-query and capture the initial state; arm handled normal restoration.
2. Request the new state and record the API return.
3. Re-query until the state is observed or a bounded deadline expires.
4. Observe whether mpv converges unaided while playing. If Step 4 found a
   paused-state gap, add a paused reproduction for each affected direction.
5. For each paused reproduction, try the ordered candidates below one at a
   time. Each candidate attempt starts again from the observed paused gap,
   requests the new state, and stops at the first candidate that works:
   1. render a new frame (temporarily resume, or use `frame-step`, then restore
      pause);
   2. a one-pixel resize of the video host (which reconfigures the D3D11
      swapchain);
   3. VO reinitialization through a supported mpv property or command
      confirmed in Step 2.
6. After every candidate attempt, restore pause and observe that the correct
   output persists. If it fails, re-establish the observed paused starting
   state before the next attempt so a prior resume or resize cannot contaminate
   the result.
7. Validate source/render/display correlation, visual patterns, and protected
   Player behavior, then restore the initial state and re-query to verify
   normal restoration.

Record setter request/return, Windows state-observed, renderer-observed, and
software frame/reconfiguration timestamps separately from visually measured
readiness and blanking duration.

Fallback follows the observed display state:

- Failed HDR enable with SDR still observed requires an SDR output/fallback.
- Failed HDR disable with HDR still observed must continue rendering for HDR;
  it must not claim SDR selection.
- Unknown or contradictory state fails closed and requires manual verification
  before another mutation.

In every case, report **display matching failed** separately from playback
success or failure.

Current state matching Lineup's last write does not prove continued ownership.
An observed external override relinquishes ownership; Lineup must not restore
over it. Ambiguous attribution is recorded as a limitation. A stale journal or
matching bit alone may not authorize later restoration over a possible user
choice.

Do not run process-death, helper-failure, stale-result, multi-display, or
package tests here. Implementation must use controlled fakes or explicit
fault-injection hooks for stale results and worker/setter/restore failures
after the responsible currentness and recovery mechanisms exist.

**Gate:** The preferred architecture passes when both directions produce a safe
observed output path, correct correlated rendering, protected composition, and
verified handled normal restoration.

### 7. Decide feasibility and produce the planning handoff

Consolidate the manifest, capability inventory, environment, baseline, manual
and programmatic transitions, notification findings, instrumentation delta,
Plex HTPC observations, timings, limitations, and redacted evidence references
in `discovery-report.md`.

Classify the result:

1. **Existing composition passes:** plan production around the current renderer
   and proven Windows/mpv behavior.
2. **Narrow correction required:** identify the failing layer and plan only the
   supported correction demonstrated by evidence.
3. **Actual renderer/composition blocker:** stop and escalate with evidence and
   explicit alternatives before changing presentation architecture.

Once the Windows operation and mpv refresh behavior are understood, produce the
implementation plan. Do not wait for broad lifecycle or acceptance work. The
plan must resolve the
[product questions](#product-questions-for-the-implementation-plan) and place
these in implementation/acceptance:

- the setting, eligibility, decoded-stream classification, truthful
  source/renderer/display diagnostics, and separate playback/matching outcomes;
- one native presentation owner with bounded transitions, load/fullscreen/output
  currentness, and reconciliation after late successful writes;
- external-change detection based on the notification findings;
- controlled fault injection for stale results and worker/setter/restore
  failures;
- conservative ownership and stale-journal recovery rules;
- crash protection armed before any deliberate process-death test, with normal
  restoration and crash recovery reported separately;
- capability-selected Windows routes, with the Windows 11 24H2+ route verified
  on Windows 11 hardware before any Windows 11 claim;
- full lifecycle, multi-display, disconnect/reconnect, multi-instance policy,
  packaged helper/provenance, and packaged-release acceptance;
- repeated overlay/composition rows after the second-pass Player changes land;
  and
- the hardware/OS/GPU matrix for configurations proposed as supported.

Routine implementation and verification inside the approved architecture and
contract do not require another approval loop. Escalate only an evidence-backed
renderer/composition blocker or a product-contract change.

## Consolidated evidence row

| Field | Value |
| --- | --- |
| Source SHA/instrumentation identity | |
| Build identity / probe-script hash | |
| Windows build/GPU driver/SDK | |
| Display target/device path/connection/audio path | |
| Source transfer/primaries/bit depth | |
| Starting/requested/observed HDR state | |
| Transition method (static, manual, probe) | |
| Setter result | |
| Notifications observed | |
| Renderer target or unavailable | |
| Surface format, only if observed | |
| Software convergence timestamps | |
| Visual-pattern result/readiness/blanking | |
| Video/audio/OSD/input/geometry | |
| Handled normal restoration | |
| Matching outcome | |
| Playback outcome | |
| Normalized limitation/failure | |

## Completion criteria

Exact-source/build evidence on Windows 10 22H2 must establish:

1. correct controlled SDR and HDR10 presentation in the existing composition;
2. manual transitions in each direction, while playing and paused;
3. one supervised reversible programmatic transition in each direction;
4. the supported Windows 10 operation, the minimum mpv refresh, and the
   external-change notification behavior;
5. the correlated evidence establishing a safe path and optional telemetry
   gaps; and
6. verified handled normal restoration, with crash protection deferred unless
   already implemented and armed before testing.

Windows 11 behavior, the final overlay composition after the second pass, and
packaged-release behavior remain explicitly open.

Independent review is specifically recommended for the later native
transition/currentness and recovery design, but remains user-controlled.

## Codex handoff (Windows 10 machine)

```text
You are working in TJZine/LineupDesktop on the physical Windows 10 22H2 HDR
test machine (Sony A90K chain). Task: execute the fullscreen HDR discovery in
docs/fullscreen-hdr-discovery-plan.md. This is discovery, not production
implementation.

Target: <full-40-character-commit-sha containing this plan>. Require a clean
checkout at that SHA and record it. Create the local branch
codex/hdr-discovery-win10 from it for the read-only trace commit only. Do not
merge or push unless the user asks.

Read AGENTS.md, .agents/project.md (relevant sections),
docs/fullscreen-hdr-discovery-plan.md (all of it), docs/fullscreen-hdr-spec.md,
docs/DEVELOPMENT.md (Windows native player: development launcher), and
docs/windows-native-validation.md (Responsibilities and safety; sections 1-2
for the machine baseline).

Execute plan Steps 1-7 in order:
1. Freeze the target, write run-manifest.csv, and record pinned identities and
   the Windows SDK used.
2. Write the untracked probe script described in Step 5 (query/watch/toggle)
   under build/native-acceptance/<sha>/fullscreen-hdr-discovery/. Run only
   query and watch until Step 5's prerequisites are recorded as met.
3. Run Step 4 static and manual-transition rows on the unmodified build via
   tool/windows/run.ps1 -MediaPath with operator-supplied local samples. Then
   commit the LINEUP_HDR_DISCOVERY_TRACE instrumentation on the discovery
   branch, record the new identity, and repeat the affected rows.
4. Run Step 6 only after the operator confirms each Step 5 prerequisite.
5. Produce discovery-report.md with the feasibility classification.

The human operator performs HDR toggles in Settings, judges the patterns and
TV signal info, measures blanking/readiness, observes audio, and optionally
runs Plex HTPC. Ask the operator for each observation and never invent one.
Never mutate the display without the operator present. Never run process-kill,
disconnect, multi-display, or package tests.

Keep tokens, URLs, private titles, and media paths out of all evidence. The
trace must emit none of them.

Stop and report on: a non-reproducible target, an ambiguous display mapping,
a failed restoration (the operator restores manually first), or an
evidence-backed renderer/composition blocker.

Final response: target and build identities, changed files (the trace commit
only), a per-row results summary, timings, notification findings, which
pinned-source predictions held or failed, the feasibility classification, open
limitations, and a redacted copy of discovery-report.md suitable for pasting
back to the planning chat.
```

## Authorities

- [Fullscreen HDR presentation specification](fullscreen-hdr-spec.md)
- [Windows presentation ownership](architecture.md#windows-presentation-and-ownership)
- [Windows native acceptance](windows-native-validation.md)
- [Development workflow and verification](DEVELOPMENT.md)
- [Windows runtime provenance](windows-runtime.md)
- [Desktop UI second pass](desktop-ui-second-pass.md), which supersedes parts
  of the [protected Player baseline](../.interface-design/system.md#player-protected-baseline)
- [Plex transcoding plan](plex-transcoding-implementation-plan.md) for
  delivered dynamic range
- [Microsoft Advanced Color guidance](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range)
- [Microsoft DisplayConfig device information](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_device_info_type)
- [mpv manual at the pinned commit](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/DOCS/man/options.rst)
