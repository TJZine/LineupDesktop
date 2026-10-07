# Fullscreen HDR Discovery Plan

**Status:** Focused evidence-gathering plan. It does not authorize production
implementation or establish an HDR-support claim.

**Purpose:** Determine whether the existing composited Player renders SDR and
HDR correctly across a supported, reversible Windows display-state change,
identify the minimum mpv refresh required, and then produce the implementation
plan.

**Starting point:** `dev/desktop-ui-refinement` at `cda27a86` was inspected on
September 13, 2026. Resolve and record the actual target commit before every
instrumented build or physical run.

## Fixed direction and product contract

Preserve the existing libmpv `gpu-next` / D3D11 child presentation and patched
Flutter DirectComposition path unless focused evidence proves an actual
renderer/composition blocker. Flutter must retain the protected Player OSD,
overlays, focus, input, and accessibility behavior. Do not begin with exclusive
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

The setting's default and rollout gate are later implementation/acceptance
decisions.

## Discovery boundary

Discovery answers only:

1. Does the unmodified composited Player render known SDR and HDR10 correctly
   when Windows is already in the corresponding display state?
2. Can it survive one supported SDR-to-HDR and HDR-to-SDR transition with video,
   audio, protected overlays, input, and geometry intact?
3. Which supported Windows operation and minimum mpv refresh, if any, make the
   renderer converge?
4. Which correlated observations are sufficient to establish and diagnose a
   safe output path?

Do not build a substantial throwaway controller. Full lifecycle/currentness,
controlled stale-result and worker-failure testing, crash-helper fault
injection, multi-display and multi-instance behavior, broad hardware coverage,
and packaged-release acceptance belong in implementation and acceptance. Add a
discovery experiment only when a named unknown would change the architecture.

## Sequenced discovery

### 1. Freeze the target

1. Select and record the full target SHA from a clean checkout; preserve
   unrelated local work.
2. Confirm the refined Player surface is stable enough for bounded
   instrumentation. If not, complete Steps 1 through 3 and wait before editing.
3. Record the pinned Flutter framework/engine, Windows SDK, libmpv, FFmpeg, and
   libplacebo identities.
4. Store untracked evidence under
   `build/native-acceptance/<full-sha>/fullscreen-hdr-discovery/`.
5. Maintain one `run-manifest.csv`. Each row records the source SHA,
   instrumentation identity, package hash/build identity, Windows build, GPU
   driver, display/connection, and evidence paths.

After every instrumentation change, record a new immutable source identity,
rebuild, record a new package identity, and add a manifest row. Never combine
observations from different binaries under one result identity.

**Gate:** Stop if the exact source/runtime combination cannot be reproduced.

### 2. Inventory only capabilities needed by the probe

Against the pinned runtime:

1. Verify effective values for `target-colorspace-hint`,
   `target-colorspace-hint-mode`, `d3d11-output-format`,
   `d3d11-output-csp`, and `d3d11-output-mode`.
2. Check `video-dec-params`, `video-out-params`, `video-target-params`, relevant
   renderer events, and supported refresh operations.
3. Identify the supported Windows query/set route on the target OS. Distinguish
   unsupported API/display, access failure, stale topology, rejected request,
   and accepted-but-not-observed state.
4. Establish the minimum unambiguous mapping from the Player window to its
   active DisplayConfig target.

Direct swap-chain telemetry is optional. Its absence is not grounds for
changing presentation architecture. Valid FP16/scRGB and RGB10/PQ paths can
both satisfy HDR; observe the actual path instead of requiring one format.

Record this in a single `discovery-report.md` under **Capability inventory**.

**Gate:** Continue when one supported query/set route and the candidate mpv
observation/refresh behavior are understood well enough for supervision.

### 3. Prepare one controlled physical environment

1. Select one known SDR and one static HDR10 sample with independently verified
   transfer, primaries, bit depth, and mastering facts.
2. Select SDR/HDR patterns that expose clipping, crushed or raised blacks,
   incorrect reference white, highlight loss, banding, and obvious
   gamut/transfer errors. Ordinary footage alone is insufficient.
3. Record the Windows build, GPU/driver, Sony A90K connection chain, resolution,
   refresh rate, scaling, HDR state, and any AVR.
4. For each run correlate:
   - verified source characteristics;
   - Windows target and observed HDR state;
   - mpv renderer target when available;
   - display signal information when available; and
   - visual-pattern results plus video/OSD appearance.
5. Redact credentials, tokens, token-bearing URLs, private titles/media paths,
   and unsafe raw logs.

Two HDR-status indicators do not establish correct HDR rendering. Correlated
rendering/display facts and appropriate visual patterns are required.

Plex HTPC comparison is optional and only clarifies observed behavior on the
same machine. Defer the broader OS/GPU/display matrix until acceptance for the
configurations proposed as supported.

### 4. Establish the unmodified composited baseline

Run the exact target with the pinned patched Flutter engine and bundled libmpv.
Do not add a setter, force a surface format, or change mpv output mode.

| Windows state | Source | Required observation |
| --- | --- | --- |
| SDR | SDR | Correct SDR patterns, video, overlays, input, and geometry |
| SDR | HDR10 | Actual fallback; do not assume tone mapping |
| HDR | HDR10 | Correct HDR patterns and protected composition |
| HDR | SDR | Actual SDR-in-HDR and reference-white behavior |

Windowed playback is optional comparison evidence. Packaged-release testing is
not part of discovery.

Record software events separately from human measurements: source facts,
Windows state observed, renderer target if available, software first-frame or
reconfiguration events, and visually measured readiness after blanking or
resynchronization. Do not turn a human observation into a software timestamp.

If existing observations are insufficient, add only read-only development
telemetry for source transfer/primaries, renderer target when exposed, selected
Windows target/capability/state, and normalized observation failures. Report
missing optional telemetry as unavailable; do not infer 10-bit output from the
source format. Give the instrumented build a new source/package identity and
repeat only affected rows.

**Gate:**

- Correct HDR with protected composition intact proceeds to the setter probe.
- Missing optional telemetry does not block progress when correlated evidence
  establishes a safe output path.
- Visibly incorrect HDR with Windows HDR active permits focused inspection and
  routine correction inside the preferred architecture. An evidence-backed
  renderer/composition blocker is the stop-and-escalate point.

### 5. Meet setter-probe safety prerequisites

No display mutation occurs until:

1. A physical operator is present and can restore Windows HDR manually.
2. The exact source/package identity and controlled environment are recorded.
3. The Player maps unambiguously to one active target; mirrored or ambiguous
   mappings fail closed.
4. A fresh query confirms support and captures the observed initial state.
5. The setter/re-query path is supported and bounded, with one mutation in
   flight.
6. A handled normal-restoration path is installed before mutation for probe
   completion, handled error, fullscreen exit, and normal close.
7. The record states whether crash-time protection is absent or armed. Without
   armed recovery, do not deliberately terminate the process, inject a crash,
   disconnect the target, or run unattended.
8. The probe is development-only and cannot be mistaken for production.

Verified normal restoration and crash-time protection are different claims.
Discovery establishes the former. Process-death testing waits until a recovery
owner has been implemented and armed before mutation.

**Gate:** If any prerequisite fails, do not mutate the display.

### 6. Run one reversible setter/refresh probe

Use the smallest supported action inside the real app, not the production
lifecycle controller. For SDR-to-HDR and HDR-to-SDR:

1. Re-query and capture the initial state; arm handled normal restoration.
2. Request the new state and record the API return.
3. Re-query until the state is observed or a bounded deadline expires.
4. Observe whether mpv converges unaided. If not, try only the single minimum
   supported refresh candidate from Step 2.
5. Validate source/render/display correlation, visual patterns, and protected
   Player behavior.
6. Restore the initial state and re-query to verify normal restoration.

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

Do not run process-death, helper-failure, stale-result, multi-display, or package
tests here. Implementation must use controlled fakes or explicit fault-injection
hooks for stale results and worker/setter/restore failures after the responsible
currentness and recovery mechanisms exist.

**Gate:** The preferred architecture passes when both directions produce a safe
observed output path, correct correlated rendering, protected composition, and
verified handled normal restoration.

### 7. Decide feasibility and produce the planning handoff

Consolidate the manifest, capability inventory, environment, baseline,
instrumentation delta, probe results, normal-restoration result, timings,
limitations, and redacted evidence references in `discovery-report.md`.

Classify the result:

1. **Existing composition passes:** plan production around the current renderer
   and proven Windows/mpv behavior.
2. **Narrow correction required:** identify the failing layer and plan only the
   supported correction demonstrated by evidence.
3. **Actual renderer/composition blocker:** stop and escalate with evidence and
   explicit alternatives before changing presentation architecture.

Once the Windows operation and mpv refresh behavior are understood, produce the
implementation plan. Do not wait for broad lifecycle or acceptance work. The
plan must place these in implementation/acceptance:

- the setting, eligibility, truthful source/renderer/display diagnostics, and
  separate playback/matching outcomes;
- one native presentation owner with bounded transitions, load/fullscreen/output
  currentness, and reconciliation after late successful writes;
- controlled fault injection for stale results and worker/setter/restore
  failures;
- conservative ownership and stale-journal recovery rules;
- crash protection armed before any deliberate process-death test, with normal
  restoration and crash recovery reported separately;
- full lifecycle, multi-display, disconnect/reconnect, multi-instance policy,
  packaged helper/provenance, and packaged-release acceptance; and
- the hardware/OS/GPU matrix for configurations proposed as supported.

Routine implementation and verification inside the approved architecture and
contract do not require another approval loop. Escalate only an evidence-backed
renderer/composition blocker or a product-contract change.

## Consolidated evidence row

| Field | Value |
| --- | --- |
| Source SHA/instrumentation identity | |
| Package/build identity | |
| Windows build/GPU driver | |
| Display target/device path/connection | |
| Source transfer/primaries/bit depth | |
| Starting/requested/observed HDR state | |
| Setter result | |
| Renderer target or unavailable | |
| Surface format, only if observed | |
| Software convergence timestamps | |
| Visual-pattern result/readiness | |
| Video/audio/OSD/input/geometry | |
| Handled normal restoration | |
| Matching outcome | |
| Playback outcome | |
| Normalized limitation/failure | |

## Completion criteria

Exact-source/build evidence must establish:

1. correct controlled SDR and HDR10 presentation in the existing composition;
2. one supervised reversible transition in each direction;
3. the supported Windows operation and minimum mpv refresh;
4. the correlated evidence establishing a safe path and optional telemetry gaps;
   and
5. verified handled normal restoration, with crash protection deferred unless
   already implemented and armed before testing.

Independent review is specifically recommended for the later native
transition/currentness and recovery design, but remains user-controlled.

## Authorities

- [Fullscreen HDR presentation specification](fullscreen-hdr-spec.md)
- [Windows presentation ownership](architecture.md#windows-presentation-and-ownership)
- [Windows native acceptance](windows-native-validation.md)
- [Development workflow and verification](DEVELOPMENT.md)
- [Windows runtime provenance](windows-runtime.md)
- [Protected Player design baseline](../.interface-design/system.md#player-protected-baseline)
- [Microsoft Advanced Color guidance](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range)
- [Microsoft DisplayConfig device information](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_device_info_type)
- [mpv stable manual](https://mpv.io/manual/stable/)
