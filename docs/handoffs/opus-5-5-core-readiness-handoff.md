# Opus 5.5 handoff: stabilize Lineup core and prepare TV expansion

Prepared October 20, 2026 for a manual handoff to **Claude Opus 5.5**.
This document does not claim that Opus has run or reviewed anything yet.

## Task and desired outcome

The maintainer wants Lineup's macOS version and shared application core polished,
reliable and usable before expanding to **Android TV / Google TV**, **Android-based
Fire TV**, and possibly **Apple TV if feasible**. The immediate request is a
reconciled backlog and a concrete next-work handoff, not another indiscriminate
whole-repository rewrite or a port implementation.

The backlog has been reconciled into **[docs/open-obligations.md](../open-obligations.md)**.
That is the single current unfinished-work register. Keep its B/V/I/F/R identifiers
in subsequent planning; do not create a competing issue ledger. Distinguish:
confirmed defects, missing evidence, unresolved investigations, new features and
release engineering. An old audit's “pending” label does not outrank a later
implemented source or recorded passing result.

Your first deliverable should be a prioritized, decision-ready core-stabilization
plan using the existing register, with a bounded first implementation package,
clear acceptance conditions and explicit product choices. Confirm current source
and challenge this handoff where evidence warrants it. Implementation of newly
selected features/platforms, distribution and account/device operations need their
own actual human authorization; this document is context, not that authorization.
The human has already deferred the accessibility acceptance session until later.
Do not make that deferred session the only useful next action.

## Repository and exact starting point

- Repository: `/Users/tristan/Software/LineupDesktop`.
- Branch at reconciliation: `platform/macos`.
- Engineering closeout HEAD:
  `ac4c3a1724796314cc7a721bf54b0b2f0f94ff22`.
- Working tree was clean before this documentation reconciliation; these new
  documentation changes follow that HEAD. Resolve actual HEAD/status when starting.
- Local branch was 15 commits ahead of its **last fetched** tracking ref. No fresh
  remote-state assertion, push, PR, main merge, tag or branch cleanup is implied.
- Pubspec version: `0.1.0+1`; source/build identity is essential because this
  marketing version is shared by many different candidates.
- Flutter pin: `3.47.7`, framework
  `abaf9c523780a608bd46686fd5e53740a07077f8`, engine base
  `deb287481e3ce9468f3434937ced4240a70539ca`, Dart `3.13.5`.
  Read `tool/flutter_version.json` and current Development commands again before
  executing. Bare PATH Flutter has previously selected the wrong SDK.
- Known pinned SDK on this Mac:
  `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`.
  Its stock binary cache was deliberately preserved.

Start with `AGENTS.md`, `.agents/project.md`, `docs/architecture.md`,
`docs/DEVELOPMENT.md`, `docs/native-player-protocol.md`, the current register and
`docs/handoffs/macos-post-audit-fix-report.md`. Historical prompts do not select
today's branch, prescribe a fixed model roster or authorize new work.

If you do not have filesystem access, obtain the register and named evidence
records as attachments/context. Do not assume the local `/tmp` artifacts are
available remotely, durable or reproducible from their path alone.

## What Lineup is today

One Flutter/Dart desktop app, with Windows and macOS runners. Plex sign-in/Home
profiles, server/library selection, channel generation/editing, deterministic
schedules, Guide/PiP, Player/Now Playing/Mini Guide, tracks, optional DVR transport,
sleep timer, persistence/recovery and credential-safe diagnostics are implemented.
This is a functioning pre-release product, not an empty UI prototype, but no
supported public installer/release has been accepted.

**Shared ownership:** Dart owns Plex networking, account/content scopes,
application state, persistence policy, scheduling, playback decisions, focus,
semantics and visible interactions. `native/player_core/` owns platform-neutral
libmpv lifetime, commands, bounded queues, correlation, token handling and native
telemetry. Platform adapters own channel/codec, presentation and OS lifecycle.
Do not move product policy into native code to avoid a difficult Dart contract.

**macOS:** native playback is implemented. The Objective-C++ adapter uses the
shared core; patched self-built LGPL libmpv, libplacebo and MoltenVK present under
Flutter through a host CAMetalLayer. Runtime embedding, generated notices,
ad-hoc development signing, native fullscreen observation, Mac command shortcuts,
async quit/close, native tests and authenticated-reference proof exist. H1 HDR
publication and L1 keyframe-join/exact-user-seek behavior have recorded physical/
target-runtime acceptance. The user accepted HDR/Dolby Vision picture quality;
do not reopen the same brightness investigation as routine acceptance.

L2 initial-load `start` behavior is also **implemented and reviewed**, with
correctness/auth/native gates completed at their attributed sources. Its final
protected Plex performance comparison was **inconclusive**. Do not plan L2 as an
unimplemented optimization or claim a measured speedup. Read the final addendum
of [the L2 handoff](macos-l2-controller-status-handoff.md#final-controller-addendum--october-18-2026),
not its earlier pending paragraphs.

The approved first Mac target is **Apple Silicon** with deployment target
**macOS 12**. Only macOS 27 has recorded runtime coverage here. Targeting12 does not
prove12–26 compatibility. Intel/universal is outside the first target. Team-signed
sandbox/TestFlight/public release acceptance remains unfinished.

**Windows:** libmpv playback, DirectComposition presentation, HDR matching/
restoration and package tooling are implemented. The macOS shared-core extraction
and fixes received later Windows CI. Current code explicitly runs eight native/
reference CTests after a stock-engine application build. That is distinct from a
usable patched-engine player, physical Windows media/HDR/input or exact package
acceptance. `runner_lifecycle` remains a separate unobserved gate in these records.

**Other platforms:** `createPlatformNativePlayer` selects a method-channel player
only for Windows/macOS; other platforms explicitly report unsupported playback.
There are no Android/iOS/tvOS targets or player adapters in this checkout. Linux
CI/tests do not imply Linux playback support. This user's current Android request
is TV, not a newly approved phone/tablet release.

## What the audits actually fixed

Read the closed/superseded map in the register before proposing repairs. In
particular, do not reopen these as unimplemented:

- October 10 confirmed findings: protected-profile/PIN recovery, Guide control
  activation and raw search ownership, schedule-worker disposal readiness,
  schedule/persisted-duration arithmetic validation, authenticated-reference
  natural completion and incomplete-multipart seek coordinates.
- October 12 audit/maintainability: repeated track-label computation, retained
  artwork handles, stale Home publication, setup projection/eligibility,
  immutable ownership, native command/lifecycle and duplicated build authorities.
- October 15 code-quality work: shared policy/data/lifetime refactors integrated
  and reviewed. Native F was **already merged** at `4f3b144a`; later CI exercises
  three of its four required suite families. That historical merge commit is not
  an ancestor of this branch, but all nine restoration/admission/guardian/recovery/
  handle files match it byte for byte; player/encoder code subsequently moved to
  the shared core. Check source equivalence, not ancestry alone. Do not propose
  another blind merge or say no native testing ever happened.
- Recent macOS audit: truthful native pause/readiness state, accumulated rapid
  channel-step requests, current error-slate identity, Settings return after timer
  expiry, build diagnostics identity, directory accessibility topology and icon
  names. Later reviews also corrected tooltip/portal origins, Guide Clear, menu
  Back, metadata/selection authority and Player focus recovery after retirement.

These closures have differing deterministic/native/physical proof. They do not
mean every related Windows or human scenario is passed. Detailed identities and
limits stay in the [closing report](macos-post-audit-fix-report.md).

## Latest engine repair and evidence

The common Flutter desktop bridge retained inconsistent state after failed
AXTree updates. The repair owns reachable semantics, reconstructs moved subtrees,
stages updates in a private tree and publishes only successful commits. Failed
batches/events are discarded while the last published tree/delegates stay valid;
a later valid update can recover. Native object identity/lifetime is preserved.
The design copies/walks retained trees; no latency/throughput improvement is claimed.

| Input/artifact | Exact identity |
| --- | --- |
| AX patch | `tool/flutter_engine/0002-desktop-accessibility.patch`, SHA256 `2c843a56499dbdebcbbabd6f178b17bc84d13d0192b1e039318caf13cf18f89a` |
| Apple linker patch | `tool/flutter_engine/0003-macos-apple-linker.patch`, SHA256 `de9e69ff64b52d389d58ed73874da174b4e3e8d5f2a8489c006e0a4d1405b313` |
| Implementation commits | `831c28fc` engine/tooling, `76b5d513` Apple-linker/no-LTO correction, `0208982e` signed-binary comparison normalization |
| Canonical app source | `0208982e89f2ec9e46dd19d5670578db66d9e9e5`; later closeout commits change documentation only |
| Canonical compiled Dart | SHA256 `4990868c15423a3e3fce66b9c6bf68eea46d1472dead12d08a2a74b139dabf11` |
| Built arm64 Release engine | SHA256 `6a2a93f01e014168d4ea2728fc6fda587d992fde413441129d8d8fb3633a53d0` |
| Re-signed bundled engine | SHA256 `6261f09e8b641cbc45e873a4ddb303dcb60220c0f66c80eb0b0ec890ec95b938` |
| Signature-normalized comparison | SHA256 `c0b28df55df5f92667e170a1b2a87a693f0fec5c3cb259490fc076960346560c` |

Preserved canonical pair:
`/tmp/lineup-audit/m04-engine-recovery/canonical/Lineup Desktop-0208982e-repaired-engine.app`.
Rollback pair:
`/tmp/lineup-audit/m04-engine-recovery/rollback/Lineup Desktop-829547b4-stock-engine.app`.
Do not overwrite stock SDK caches or silently relabel an old app by current HEAD.

Actual evidence, not a new run by this handoff:

- **1,869 Dart tests**, clean analysis, canonical format 160 files/0 changes;
  **20 Python build-tool tests**, including real signed-Mach-O controls.
- Seven identical API-compatible regressions each fail the pinned baseline;
  repaired common suites pass **242 Debug  / 240 Release**, all ten recovery tests.
  Count difference is project-switch cases, not missing recovery coverage.
- Focused macOS bridge/delegate tests: **12/12 per mode**.
- Disposable native run4: three actual AXTree failures in one bridge, retained
  Slider 60/no failed callback, then one later valid update delivers actual native
  value 80 while the object remains alive. This is one recovery after accumulated
  failures, not three separate recovery demonstrations. The Dart engine was stopped
  in that fixture; it does not prove playback, spoken output or custom-action focus.
- Canonical app PID18742 actually mapped the exact bundled engine. Menu/zoom/
  collapse digit/F2, independent Mini Guide Escape/F2 and sampled true inactive
  hide/resume/Enter observations pass within their recorded bounds. Normal Quit
  completed shutdown, but its exit code was not captured.
- Separate logging-only diagnostic app is base `76b5d513` plus patch
  `4a899d05813235d0050223f0472feb737af88f333b2dc142ed2e0e7ab3025320`,
  compiled Dart `0a74b3cd…`, not canonical Dart. Three current routes did not
  reproduce node 866; all observed mounted Sliders were already interactive.
  Pointer seek 33%→50% produced a real AXValueChanged callback and native exact
  landing 1919.292s for target 1919.293s. Final diagnostic Quit exited0. No fresh
  loaded-engine-map claim is made for that diagnostic PID.

The opt-in macOS builder verifies exact sources, consumed artifacts, a successful
build receipt and every bundle entry. Re-signing comparison uses disposable copies
and deterministic signature allocation normalization, not a weakened code check.
Fresh isolated SDKs need stock `flutter precache --macos` first to populate SDK
packages; local-engine selection still comes from the verified explicit recipe.
Apple linker builds use `--no-lto` because the installed Apple linker cannot consume
the bundled LLVM bitcode. Keep Debug/optimized Release evidence distinct.
Read [the engine README](../../tool/flutter_engine/README.md) before provisioning.

**Important integration gap:** Windows launch/release/package validation currently
expects the DirectComposition-only source. It does not accept the new combined
AX-patched source; repair that integration and run the actual Windows engine
suites before claiming Windows delivery of the repair. Stock macOS builds likewise
do not silently acquire this opt-in engine. R-01/V-02 own this work.

## Limits that must remain visible

The register owns the unfinished rows; the following prevents common misreadings:

- B-01 is repaired locally but M-04/overall accessibility acceptance stays open.
  First-fade timing is unachieved after bounded attempts; natural same-presenter
  Slider enabled/disabled flip was not observed. Historical866 is unattributed,
  not proof of a newly reproduced failure.
- Canonical runtime had six resize-timeout warnings; final diagnostic had one
 875 µs backward frame timestamp clamp. Each warning class has a stock-engine
  precedent. Causes/indirect scheduling effects are unresolved. No matched
  performance comparison or additional app defect was demonstrated.
- No verification app/observer remains. DVR restored Off, channel 1, VoiceOver Off
  unchanged; preexisting windows preserved; both 112-entry bundles unchanged.
  Startup authentication was handled directly by the human; no prompt is pending.
- The human explicitly chose to leave the existing six-item physical/spoken
  checklist open for later. **Zero boxes passed.** Preserve it as the only Mac
  human checklist. Do not synthesize VoiceOver/global modifiers or ask for more
  unlock/timing assistance merely to keep an engineering campaign running.
- Stock CI, fake native tests, a populated AX tree and a successful compile each
  prove different things. None establishes signed delivery or physical TV behavior.

## How to choose the next work

Use this sequence as a recommendation, with independent work overlapped when
ownership/resources permit. Keep one integration/build/runtime owner.

1. **Agree the core beta contract.** Establish whether the next deliverable is a
   reliable Direct Play macOS private beta or a broader remote-playback feature
   release. Default recommendation: stabilize the existing Direct Play product
   first. Do not turn all F rows into prerequisites without a product reason.
2. **Close actionable engineering gaps.** R-01/V-02 for a combined Windows engine
   recipe; V-03 runner lifecycle/exact package; V-06 older-OS compatibility or a
   revised support commitment. Finish R-02/R-03 before signed distribution.
   Physical steps need an available human/device; continue independent work if
   unavailable, preserving the unexecuted gate.
3. **Use a bounded core validation pass.** Trace representative real application
   routes for account/scope changes, save/recovery, schedule/part/program boundary,
   superseded tune/Stop/retry/track commands, truthful pause/buffering and app
   shutdown. Reuse meaningful fixtures and existing native checkers. Promote a
   fresh finding only with a trigger, failing owner contract and useful red/green
   evidence; do not build a new E2E framework just for ceremony.
4. **Choose resilience/features deliberately.** Versioned backup/restore is a
   valuable data-protection candidate before adding persisted fields. Transcoding
   is the largest new playback capability and may matter for TV codec/network
   compatibility; it has real P0b/design/security prerequisites. Whole-show/mixed
   authoring, refresh and preferences have distinct product decisions. Get those
   decisions before implementing, preserving approved Player layout.
5. **Run TV feasibility as bounded spikes.** Set an actual device/OS/media matrix,
   remote navigation and lifecycle proof, and decide a backend from observed
   behavior. The spike should return a go/no-go, uncovered contracts, maintained
   dependencies and realistic shared-code scope before a production port plan.

A stable-core exit should mean the selected release scope has no demonstrated
blocking bug left untreated, meaningful contract checks pass, available target
scenarios have exact-candidate evidence, data remains recoverable, and missing
platform/human gates are stated. It does not mean every research idea is built or
all hardware claims are certified. Define release support separately from source
coverage.

## TV expansion feasibility

Research checked October 20, 2026 against the primary sources below. This is a
planning assessment; no SDK/device spike or playback proof was performed.

### Android TV / Google TV and Android-based Fire TV

Flutter officially lists Android deployment; that is not proof that this desktop
app, its dependencies or its native player already work on Android TV. Google
requires TV remote/D-pad operation and appropriate TV navigation. Treat shared
Dart models, scheduling, Plex policy and much interaction code as **reuse
candidates**. The checkout still needs an Android host, dependency/secure-store/
linking/persistence audit, a media adapter, surface composition and device proof.

Evaluate native **Media3/ExoPlayer** against a maintained Android libmpv approach
using the current protocol requirements: headers/token/redirect safety, native
observed state, parts/EOF, exact versus live-join seeking, subtitle formats,
HDR/Dolby Vision, hardware decoding, audio output, track confirmation and bounded
shutdown. Media3 provides a Player abstraction; it is a candidate, not a selected
backend. Do not require sharing the desktop C++ implementation when a platform
player can satisfy the contract more faithfully, or duplicate product scheduling
inside it.

The TV spike should include D-pad-only sign-in/PIN/Guide/Player/settings and
recovery, no pointer/keyboard dependency, Back/select/media-key ownership,
readable 10-foot focus and UI, rendering above video, low-memory behavior, activity
recreation/background/foreground, suspend/network interruption and secure token
storage. Decide which channel-authoring tasks belong on TV versus a companion
surface. Desktop Player approval does not automatically approve a materially
changed TV layout; discuss the TV interaction direction separately.

For Fire TV, target only **Android-based Fire OS** in the requested first scope,
without assuming Google Play Services. Amazon documents Fire OS as an Android
fork and lists Fire TV devices using both Fire OS and **Vega OS**. Vega uses a
separate toolchain/package; an Android APK is not a universal Fire TV port.
Record device model/OS/ABI and choose the supported set explicitly. A Vega port
would need a separate product/engineering decision.

### Apple TV

Apple TV is technically a candidate, but **feasibility is unproven for this app**.
Flutter's current official deployment list does not include tvOS. macOS AppKit/
CAMetalLayer integration and a macOS dynamic-library bundle cannot simply be
reused as a tvOS target.

Compare a demonstrably maintained tvOS Flutter embedder and its upgrade/plugin/
remote/rendering burden against a native SwiftUI/UIKit tvOS client with AVPlayer/
AVKit or another validated playback route. Apple documents native tvOS media and
focus facilities; that does not establish the current Plex/container/subtitle/HDR
matrix on AVPlayer. Test those requirements, including whether transcoding is
needed. Quantify what Dart/domain logic can genuinely be shared or extracted
without building a speculative universal framework. Do not select a fork, rewrite
the app or promise Apple TV until a device spike establishes viability and upkeep.

### Primary research sources

- [Flutter supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms)
  — Android is listed; tvOS is not.
- [Google TV navigation](https://developer.android.com/training/tv/get-started/navigation)
  and [TV controllers](https://developer.android.com/training/tv/get-started/controllers)
  — D-pad/Back behavior and remote-first operation.
- [Android Media3 ExoPlayer](https://developer.android.com/media/media3/exoplayer)
  — native player capabilities to evaluate, not a Lineup integration result.
- [Amazon Fire OS overview](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html)
  — Android-derived Fire OS and per-device OS distinctions.
- [Amazon Vega development](https://developer.amazon.com/apps-and-games/blogs/2026/07/guide-to-building-for-fire-tv-on-vega-os)
  and [submission/package distinction](https://developer.amazon.com/docs/vega/latest/app-submission)
  — separate Vega development and binaries.
- [Apple tvOS](https://developer.apple.com/tvos/) and
  [Apple TV focus](https://developer.apple.com/documentation/uikit/about-focus-interactions-for-apple-tv)
  — native media/UI/focus facilities.

## What to return to the maintainer

Return a short assessment of what is working now and the few highest-priority
unfinished obligations, referring to existing register IDs. Then give a practical
package sequence: scope, owner, actual dependency, acceptance proof, platform/
human prerequisites, data migration/rollback if relevant and unresolved decisions.
Identify the first package that can proceed on the current Mac without pretending
Windows/TV devices are present. Challenge stale evidence with exact source or
recorded later results; keep historical records intact.

Do not promise core completeness from a test count, schedule every optional
feature, reopen accepted HDR/UI decisions, erase remaining acceptance, push or
publish. Preserve credentials/private media and keep raw diagnostic logs outside
tracked handoffs. If separate agents are later authorized, resolve actual presets
and supported settings, use disjoint ownership and one integration/resource owner;
this handoff does not request a particular orchestration roster.
