# Opus handoff: HDR publication and channel-join seeking

## Assignment and current contract

Verify the two production changes below and their composition, then measure
the separate `loadfile start=` proposal. The user transferred all remaining
verification to Opus and requested this single consolidated handoff. Codex
stopped new test runs, physical prompts, benchmarks and CI observation after
that direction. Preserve source and evidence identities; never merge an old
diagnostic patch or call an unperformed check a pass.

Read the repository's `AGENTS.md` and `.agents/project.md`. The checkout is
`/Users/tristan/Software/LineupDesktop`, branch `platform/macos`. The product
base for both slices is `94b459a05c963f62efdf4ec4d0bd22344efe855d`;
later pre-implementation commits only record decisions/handoffs. The current
Git state and final candidate identity are recorded at the end of this document.

The latest human decisions supersede stricter language in earlier handoffs:

- **HDR:** flush the calling thread's implicit Core Animation transaction
  after each relevant off-main setter in the adapter-owned Metal layer subclass.
  Omit a redundant acquisition barrier. Check black/wrong-color flashes and
  switch latency physically. If flashes occur, the approved fallback is the
  proven pre-acquire barrier plus setter flush only for writes on threads that
  will not acquire again; do not add it without the failure evidence.
- **Seeking:** live-TV schedule/tune/recovery joins use plain
  `absolute+keyframes`. Exact entry position does not matter. Explicit user
  seeks stay exact. Do not add a strict never-past guarantee, playback failure,
  exact fallback or paused landing guard. mpv's beginning-of-file forward
  fallback is accepted. Keep the existing elapsed ≤2-second join-seek skip.
- Log observed landed-versus-target offset passively, preserve recovery and
  stale-work contracts, and verify end-of-program rollover. Measure per-file
  `start=` only after establishing the corrected baseline.

The original Opus investigation is
`docs/handoffs/macos-hdr-root-cause-and-switch-latency.md`. Its historical status
paragraph is stale; use this handoff and `docs/macos-port-progress.md` for current
decisions and actual CI results. Preserve approved Player layout and existing
credential/reference restrictions. This is not release, main-merge, signing,
purchase, account-setup or App Store authorization.

## H1 — production HDR publication

`macos/Runner/NativePlayer/LineupNativePlayer.mm` now creates its own
`LineupMetalLayer` subclass. The five actual MoltenVK mutation selectors call
their real superclass setter first, forwarding the same value, then one helper
calls `[CATransaction flush]` only when off-main, on that setter's thread.

This publishes an implicit transaction even if its thread never acquires
another drawable, including teardown's 1×1 write. There is no dirty/TLS registry,
lock, queued main-thread flush, acquisition override, per-frame allocation/log,
diagnostic toggle or runtime patch. Main-thread mutations retain AppKit's normal
transaction boundaries. Existing opt-in presentation logs add app-active and
key-window fields for in-app headroom attribution.

This timing differs from Opus's physically proven pre-acquire diagnostic arm.
The user explicitly approved the simpler setter-only candidate, but its physical
acceptance is still open. `flush` submits an implicit transaction; it does not
force an enclosing explicit transaction closed or synchronously prove visible
HDR. Current selected MoltenVK callers have no explicit transaction grouping.

Independent adversarial source review by chat
`01a14bbe-5fce-7320-b217-e131e586574a` approved the exact H1 candidate for physical
A/B, with no material correctness/maintenance finding. The review explicitly
retained intermediate-state/teardown flash and target-runtime risks.

H1 artifacts are under `/tmp/lineup-h1-evidence/`:

- `source-manifest.json`: frozen isolated H1 aggregate
  `e442c94974fbbd811a2a6494da1ab3792b209724470a7ce2a55a5d3d1847b500`.
- `h1-production.patch`, SHA-256
  `31e91a1edb09a98ab71c530e280bf4fb838867df20c0df549c7b713c5a4a20ea`.
- `review-packet.md`, `physical-protocol.md`, `review-artifacts.json` and
  `opus-h1-handoff-status.json`.
- Native tests and build logs, arm launch/ready identities and frozen arm-A log.
  The authoritative frozen-log hash in the status JSON is
  `f5c2f7f2ba0a73c961bb3e1c96667b58a9666361af722fceab30477efdb4cc11`;
  an earlier callback transcribed it incorrectly.

Already completed before verification transfer:

- Clean isolated `94b459a0` + H1-only Debug builds; no moving L1 code compiled.
- Native run: 22 pass, one pre-existing intentional destructive-probe skip.
  Factory/boundary tests cover super-forwarding/order, writer-thread flush,
  main-thread behavior, persistent non-acquirer and inherited acquisition.
  Test substitutions establish wiring, not GPU or physical output.
- A plain-layer factory negative control failed the intended publication check.
- Matched A/B arms have identical 46-file framework sets; the only source
  difference is which layer class the factory creates. No diagnostic patch used.

### H1 physical verification still required

Archived arms, both built from the same H1-only source path:

| Arm | Bundle | Native Debug dylib SHA-256 |
| --- | --- | --- |
| A, plain layer | `/tmp/lineup-h1-apps/arm-a/Lineup Desktop.app` | `ede37db4085a244bfc5c86b85424d11cb248ef090c767702206b7addfd57b845` |
| B, production setter flush | `/tmp/lineup-h1-apps/arm-b/Lineup Desktop.app` | `51f7379209f3e8c41d9ace7e898989205e50cddf0473c539640b6387bc7e8974` |

Arm A was launched, but **no physical A result was provided**. Arm B was never
launched by H1. Last verified A PID was 471 at canonical executable
`/private/tmp/lineup-h1-apps/arm-a/Lineup Desktop.app/Contents/MacOS/Lineup Desktop`;
last known scene was windowed full Player, channel 1 SDR, OSD hidden. Recheck
current state rather than assuming that PID/scene survives. There are no armed
automatic actions or observers. Per-child `LINEUP_PRESENTATION_LOG=1` writes
`/tmp/lineup-h1-evidence/physical-arm-a.log`. No global environment was changed.

For each arm, use one exact running bundle/PID, the same display/brightness,
fixed window, synthetic fixtures and per-child logging. Bring the full window
foreground **before** the first HDR switch. Do not use Stage Manager thumbnails
or refocus/Guide/resize/fullscreen as accidental repairs during primary judging.

1. From SDR 1, enter `2 Return` and judge the HDR reference while still foreground.
2. Rapid `1 Return → 2 Return → 1 Return → 2 Return`; observe each transition
   and final HDR for five seconds without leaving the app.
3. Repeat `1 Return → 2 Return`. B must be bright immediately on each HDR
   return, without a geometry/refocus repair. Record the actual reached channels
   if input focus changes the intended sequence.
4. Pair physical judgment with **in-app** PQ/EDR/headroom facts while active,
   key and visible. B should exceed headroom 1 within about one second of the
   foreground HDR configuration; the existing poll is one second, so report
   actual sample timing/granularity. Full headroom 16 within one second is not
   required. An external observer's headroom is not this process's grant.
5. Compare new black/wrong-color flashes and qualitative switch delay with A.
   Do not turn subjective timing into a numerical speedup claim.
6. Only after primary judgments: live resize/alignment, fullscreen entry/exit
   and synchronized controls, then shutdown while playing. Check teardown,
   black/wrong-color flashes, hangs and crashes.

A not reproducing or a focus/extent change before judging makes that comparison
inconclusive. A B flash/latency/color regression blocks acceptance and calls for
the user-approved conditional fallback or a better supported correction, followed
by independent review. Preserve failed observations; do not add stacked flushes.

## L1 — keyframe joins and exact user seeks

`SeekMode.exact` is the default interface/transport behavior; `keyframes` is
explicit. Shared-core validation accepts only these modes (omission remains
exact) and sends `absolute+exact` or `absolute+keyframes` respectively.

Dart owns intent. Schedule joins and ordinary playback recovery use keyframes.
Pending/cross-part explicit user seeks and immediate retries of the unfinished
explicit operation retain exact intent. A completed past user seek does not make
later ordinary recovery exact; latest seek generation owns pending target/mode.
The existing ≤2-second skip, user pause and display holds remain. Commanded
resume intent is separate from UI/observed position.

Native logging samples an executed current-load seek only after a later
`MPV_EVENT_SEEK`/`MPV_EVENT_PLAYBACK_RESTART` pair, with matching active/event
load, non-seeking state and finite nonnegative native `time-pos`. Output is
numeric load ID, mode, target, observed position and signed offset. Stale,
overlapping, duplicate, expired, failed, stopped or overflow-ambiguous windows
are discarded rather than inventing a landing. There is no new wire event,
completion protocol, pause, retry or admission guard.

This is a **current-load post-seek restart observation**, not exact per-request
or first-frame PTS proof. mpv exposes no seek request ID, and sampled `time-pos`
may include progress before consumption. Initial restart without SEEK is not a
landing. A future `start=` experiment needs its own correctly matched observation
because its initial implicit seek differs from L1's explicit SeekCommand window.

L1 artifacts are under `/tmp/lineup-l1/`:

- **Final packet:** `report-r2.md`, `manifest-r2.json`, `frozen-r2.patch`,
  SHA-256 `b8b375fc5af227570681950d527981bf1ecf8045a2219332eef64c3f76eaa98e`.
- `review-correction.patch`, SHA-256
  `b3e6bef4e58b322eea069ac107438101c075864f61b2e627ac35b519d9f98290`,
  isolates the two-file production/error-test correction. The final one-line
  fixture setup repair is `review-fixture-r2.patch`, SHA-256
  `18e6f101f461ea794ec6c6c225da673e4517a264e0dac75045f8ab63ff6d7094`.
  Original and r1 artifacts remain for historical attribution; use r2 to verify.
- `protocol-L1.patch` owns only seek-related protocol hunks; the H1 Mac paragraph
  is preserved. The manifest's full protocol hash identifies the composed file.
- `L2-proposal.md` contains the detailed measurement plan, not an implementation.

Initial independent L1 review found a P2 diagnostic-contract gap: the common
worker `command_error` producer did not invalidate an armed landing sample.
The correction discards the sample and marks the load ambiguous before the
unchanged error event. A focused existing-fake-operations regression fails an
actual volume command after seek admission and checks that both the pending and
later same-load samples remain suppressed. Playback/error classification and
the wire contract are unchanged. Targeted re-review caught and resolved a second
fixture-only setup issue: the preceding load is now retired through the existing
End-file fixture before asserting an empty failure cache for the new case.
Production failure-cache semantics were not changed.

Independent reviewer `01a14bde-efcf-7360-be74-9d2bc2668ea8` approved the final
live source after those narrow corrections. Both P2 findings are resolved by
source inspection; there is no new passing-after execution claim. The remainder
of the reviewed 16-file L1 scope and H1 exclusions is unchanged.

Already executed before verification transfer: 493 affected Dart tests and three
portable-core suites passed; analysis and formatting passed; a wrong native
keyframe flag negative control failed as intended. Logs:
`/tmp/lineup-l1-dart-final.log`, `/tmp/lineup-l1-core-test-final.log`,
`/tmp/lineup-l1-analyze-final.log`, `/tmp/lineup-l1-format-final.log` and
`/tmp/lineup-l1-negative.log`. Portable core uses fake mpv operations, not actual
media. The two-file native correction and its new regression are **unexecuted**.
The 493-test result still binds unchanged Dart inputs; portable-native and
negative-control results bind pre-correction native source. Opus must compile
and execute the corrected native case and required suites; no passing-after
native result is claimed.

### L1 and combined verification still required

- Actual accepted libmpv and known-GOP media: schedule/tune/recovery keyframe
  behavior, first-keyframe fallback, zero/≤2-second skip, non-keyframe targets,
  explicit exact user seeks, pending/cross-part override and immediate recovery.
- Later ordinary recovery after a completed explicit seek must use keyframes;
  older completion must not clear newer explicit target/mode.
- Part boundaries, near-end joins, premature-end classification and wall-clock
  end-of-program rollover must remain correct despite a behind-target landing.
- Confirm actual numeric landed offset and that stale/ambiguous restart samples
  are dropped. A command reply or pre-seek position is not landing evidence.
- Re-run affected checks on the final source, then combined analysis/format/full
  Dart suite and Mac native build/tests. Reuse H1-only results only for unchanged
  inputs; H1's archived arms do **not** contain L1.
- Keep the required actual-runtime authenticated-reference matrix, embed
  integration and runtime/resource identity checks green; no skip or weakened
  prerequisite is acceptable. For the final Release candidate, retain the
  existing strict/deep ad-hoc signature and packaged-resource checks. These are
  distinct from team signing, distribution and older-OS acceptance.
- Build the combined real-protocol app and accept HDR behavior alongside changed
  seeking, recovery, pause, input, fullscreen, resize and shutdown.
- **Windows CI is mandatory** for the shared-core changes. Run the real adapter
  contract with the pinned CI Vulkan prerequisite, not just portable tests.

Useful commands for Opus (not run again by Codex after transfer), from the repo:

```sh
export PATH=/Users/tristan/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH
flutter pub get
dart tool/format.dart --check
flutter analyze
TZ=America/New_York flutter test
cmake -S native/player_core -B /tmp/lineup-opus-combined-core \
  -DLINEUP_MPV_INCLUDE_DIR="$PWD/build/macos-runtime/dist/arm64/include"
cmake --build /tmp/lineup-opus-combined-core
ctest --test-dir /tmp/lineup-opus-combined-core --output-on-failure
```

After preparing the current Mac project with the pinned Flutter build, the
existing native scheme invocation is:

```sh
xcodebuild test -project macos/Runner.xcodeproj -scheme NativePlayerTests \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/lineup-opus-combined-native CODE_SIGNING_ALLOWED=NO
```

Use the documented harness build and fixed synthetic media. Keep any diagnostic
or timing changes in isolated disposable variants, not in these production files.

## L2 — measure per-file start without changing the baseline semantics

No production `start=` contract or experiment has been implemented. Start from
the accepted combined H1+L1 baseline and follow `/tmp/lineup-l1/L2-proposal.md`.

Arm A loads at zero then performs the existing schedule keyframe seek. A
disposable B supplies the same target through per-file `start` **and
`hr-seek=no`**, omitting the separate join seek. Pinned mpv queues `start` with
default absolute precision, so `start` alone otherwise reintroduces exact-seek
work and is not an equivalent comparison. Explicit `absolute+exact` still wins.

Use string-valued node-map options, insertion index `-1`, preserving authenticated
header and redirect settings without URL changes. Do not also remove stop/load
serialization. Prove correctness/current-load/recovery/rollover/privacy and the
common post-join restart endpoint before timing; preserve failed/missing samples.

Measure native stages on one native monotonic clock and end-to-end intent to
matched Dart restart receipt on one Dart stopwatch. Do not subtract unrelated
epochs, use human key cadence as latency or call FILE_LOADED a completed join.
Actual presentation/photon latency is a separate claim.

Use identical representative synthetic long-GOP 4K HEVC/HDR and SDR fixtures,
targets, GOP/index, runtime, decoder, display/focus and host load. Warm both arms,
then alternate five ABBA blocks (ten completed warm trials per arm), preserving
individual values, failures, median/spread and cache/contention limits. Label
first-request data separately; no OS-cache flush or production-server mutation.
Real Plex extension must use protected account facilities without exporting
credentials/private identifiers. Opus's earlier exact/keyframe figures had
unequal cache conditions and are not a measured `start=` benefit.

Only propose production adoption after correctness and a benefit exceeding
variation. Any eventual load-contract/core change needs independent review,
authenticated-reference proof and Windows CI. Never merge its diagnostic patch.

## Runtime identities, CI status and remaining limits

Accepted immutable runtime: `build/macos-runtime/dist/arm64`. No runtime rebuild
or SDK/pin change is needed for these production slices.

- Flutter 3.47.7 at `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`;
  the default PATH Flutter is wrong.
- mpv commit `3186d369f9f090cd1363be0ac46a037824b702c6`.
- libmpv SHA-256
  `625eb842c7d9ef5e3324a0ff44733adcf4cfa82b0fabe8bb5edb73d555adc30f`.
- Runtime BUILD-INFO SHA-256
  `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.
- Synthetic media are the app-container `Data/tmp/lineup-media/sdr-long.mp4`
  and `hdr10-long.mp4`; exact hashes are in the H1 manifest. Human screenshots
  are not physical HDR luminance proof.

Windows close fix `94b459a0` is already committed/pushed and independently
reviewed, but its passing-after hosted result is pending. It checks completed
core/display release before re-queuing EndSession; the old asynchronous tail is
unchanged. The prior CI proved Vulkan provisioning and actual test startup, then
failed the old close assertion. Verify this fix with L1's shared core.

Last observed CI run `39095353188`, head
`b0c38b5be5546c4cf00a96ff6b61deaf30dd28dd`: Mac portable/native passed; Windows
loaded Vulkan/libmpv then failed the old close assertion; patched-engine/package
job was still building. Observation stopped at the human's request. Do not
infer final status or relabel that old run as proof of new H1/L1/close-fix inputs.

For eventual CI, the human previously authorized publishing `platform/macos`
and running CI. New commits on this branch do not auto-trigger its current push
filter (`main`/`flutter-mvp`); workflow dispatch is needed. Same-branch dispatch
cancels an in-progress prior run, so inspect actual status first. Report exact
run/head and never suppress a failing or missing required contract.

No combined target-runtime, physical Windows media/HDR, older-macOS, team
signing/sandbox-distribution, TestFlight or release acceptance is established by
these slices. Purchases and broader release/legal decisions remain separate.

## Final review and source identity

Both independent code reviews are closed. H1 has no remaining source finding;
L1's command-error diagnostic gap and subsequent fixture setup finding are
resolved. Corrected core SHA-256 is
`ce1e7b8743ff606b156abc355c1f3a73c264004164808e5600ced7eb66face37`;
the final reviewed core-test SHA-256 is
`bd5f9504319c057fe2cadbb0c6461031a6e02b7baf78572a9dc09ad62efe721c`.
The corrected native code/regression has not been compiled or run here.

The reviewed code is saved as **local verification-candidate commits** on
`platform/macos`:

- H1: `ce77d18d` — `fix(macos): publish off-main video layer transactions`.
- L1/combined product checkpoint:
  `8bca5171fe73bb6b7b835e415f8372d8cef93902` —
  `feat(playback): use keyframe seeks for channel joins`.

A following handoff/progress-only commit does not change these product inputs.
The source identity record is `/tmp/lineup-h1-l1-candidate-manifest.json`, covering
the final 18 composed source/test/protocol files. H1's isolated manifest uses its
pre-L1 protocol hash; the L1 r2 manifest records the composed protocol identity.
Do not mistake that intentional document composition for an unreviewed H1 code
change.

No new code or handoff commits were pushed and no CI was dispatched after the
verification transfer; the last published product checkpoint is `94b459a0`.
Local commits are fixed inputs for Opus verification, **not** physical acceptance
or release readiness. Preserve the two reviewed implementations, complete the
remaining checks above, and report exact source/runtime/artifact identity plus
results, failures and limits. Review any consequential remediation or eventual
`start=` production change independently before final acceptance/publication.
