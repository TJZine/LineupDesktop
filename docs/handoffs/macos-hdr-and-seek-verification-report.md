# Verification report: H1 HDR publication, L1 keyframe joins, L2 `start=`

Performed 2026-10-18 by Claude Opus 5.5, responding to
`docs/handoffs/macos-hdr-and-seek-opus-verification.md`.

- **Source verified:** `platform/macos` at `cc6dc2e2`. Product inputs are H1
  `ce77d18d` and L1 `8bca5171`. Core SHA-256 `ce1e7b87…face37` and core-test
  SHA-256 `bd5f9504…efe721c` match the handoff.
- **Runtime:** the accepted runtime (libmpv `625eb842…adc30f`), unchanged.
- **Media:** synthetic fixtures `sdr-long.mp4` (H.264, keyframes every 50 s)
  and `hdr10-long.mp4` (HEVC PQ, keyframes at roughly 10 s intervals, plus
  x8.33 s), as measured with ffprobe. Real Plex direct-play 4K channels were
  used only where stated, and only stage timings and positions were recorded.
- **Not done:** no production source was changed. No release, merge, signing
  or account action was taken.

## Verdicts

| Slice | Verdict |
|---|---|
| H1 setter flush | **Accepted (physical).** No fallback needed. |
| L1 keyframe joins / exact user seeks | **Accepted (target runtime)**, with the rollover limit below. |
| Combined H1+L1 app | **Accepted (physical):** HDR, resize, fullscreen, shutdown. |
| Windows CI for shared core and close fix | **Passed.** The package job was still running at report time. |
| L2 `start=` | **Measured benefit beyond median variation.** It needs production design, correctness work and review before adoption. |

## Automated checks (`cc6dc2e2`, pinned Flutter 3.47.7)

Logs are in `/tmp/lineup-opus-verify-logs/`.

- **Dart:** `dart tool/format.dart --check` passed; `flutter analyze` passed;
  `TZ=America/New_York flutter test` passed **1750 tests**.
- **Portable core:** ctest **3/3** passed, including the corrected L1
  `command_error` landing regression, previously unexecuted.
- **Mac native:** `xcodebuild test`, scheme `NativePlayerTests`: **22 passed**,
  plus the one existing intentional destructive-probe skip.
- **Hosted CI, run 39098816614, head `cc6dc2e2`:**
  - **Windows player job: passed.** `player_core_contract` passed, and the
    real `native_player_contract` adapter test ran against the pinned Vulkan
    loader and passed. This is the first passing-after result for close fix
    `94b459a0`. Windows Dart also passed 185 tests.
  - Dart, Windows release policy, the macOS shared-core contracts and the
    macOS portable/native build all passed.
  - "Build patched Flutter engine and package" was still in progress when
    this report was written. Check the final status before publication.
  - The superseded run `39095353188` (old head `b0c38b5b`) was cancelled by
    this dispatch. Its Windows job had already failed on the old close
    assertion.

## H1: physical A/B on the EDR display

The arms are archived as `/tmp/lineup-h1-apps/arm-{a,b}`; their native dylib
hashes match the handoff. They were relaunched fresh, foreground and windowed,
with `LINEUP_PRESENTATION_LOG=1`.

| Step | Arm A (plain layer) | Arm B (setter flush) |
|---|---|---|
| SDR→HDR reference | **dim** | **bright** |
| `1↵2↵1↵2↵` rapid, final HDR | bright (inconsistent) | **bright** |
| `1↵2↵` again | **dim** | **bright** |

The arm A log shows the bug's signature. An HDR channel ran with headroom
**1.00** while the layer model was PQ/EDR=1. The *following* SDR channel then
received the grant (headroom 1.08→16), one switch late. Arm A is therefore a
valid control.

**Flash check.** The first arm B run reported "a slight flash sometimes during
loading, maybe normal". The arm B log confirms the setter flush now publishes
MoltenVK's intermediate states at each load (`1x1` → sRGB → PQ/709 over about
100 ms), so a B-specific flash was plausible. A **blind** comparison followed:

- arm X, the pre-acquire-barrier diagnostic;
- arm Y, production arm B again.

The user saw **no flash in either**, and judged their switching speed as
similar. There is no reproducible flash regression, so per the approved rule
the fallback was **not** added. The single unconfirmed early report is kept on
record as a residual observation.

The flush costs microseconds and sits on no wait path. No numeric latency
claim is made for H1.

## L1: target-runtime behavior (combined H1+L1 harness build)

Build: native dylib `96d48392…`, accepted libmpv. Joins were driven by
automation with real key events.

**Schedule joins.** Nine joins all landed backward, within one keyframe
interval, using `mode=keyframes`:

| Fixture | Offsets |
|---|---|
| SDR (keyframes every 50 s) | −39.9, −11.8, −27.9, −40.0, −19.2 s |
| HDR | −5.9, −1.9, −4.0, −3.1 s |

**Explicit exact user seeks.** These need the DVR controls setting, which is
off by default; live mode ignores transport keys by design. The setting was
enabled for the test, then restored to off. Three seeks on the SDR file
(→/←/←) all reported `mode=exact` with **offset 0.000000**.

**Ordinary joins after a completed explicit seek** reverted to `keyframes`
(loads 8 and 9).

**Real library.** The L2 Plex run below used L1 arm A behavior. Real 4K
direct-play joins landed **0.02–1.6 s** behind target. Real keyframes are
dense, so the visible schedule offset is about 1 s.

**Not exercised at runtime:**

- **End-of-program rollover.** It is EOF-driven: `_advancePart` re-tunes with
  `endedProgram`. The harness schedules 33-minute slots on 2-hour files, so no
  EOF occurs at a slot boundary, and the 01:30 boundary produced no load as
  expected. By reasoning, a backward landing delays EOF by up to one keyframe
  interval. A delay within the 30 s catch-up tolerance starts the successor
  from its beginning; a longer one joins it mid-program. Premature-end
  classification cannot trigger falsely, because EOF moves later, not earlier.
  Existing Dart rollover and premature-end tests pass.
- Recovery, part boundaries, the ≤2 s skip and the first-keyframe fallback
  rest on the Dart and core suites, not on runtime evidence. A beginning-of-file
  fallback cannot occur with these fixtures, because each has a keyframe at 0.

**Combined physical acceptance (user, foreground):**

- HDR bright on every switch, with no flash.
- Live resize kept the video aligned and correct; the log shows a 2182×1796
  drawable with PQ/EDR and headroom 16.
- Fullscreen entry and exit with `F` and `⌃⌘F` were correct, and HDR stayed
  bright.

**Shutdown while playing,** via the app menu's Quit: `native shutdown
requested` → `libmpv shutdown complete` → `finishing native shutdown`, then
exit code 0. No new crash reports were written.

**Retracted note:** the "digit swallowed after a tune" observation in the
earlier root-cause handoff was a computer-use `type` artifact. Real key events
work.

## L2: `start=` comparison

The disposable variant is `/tmp/lineup-l2-apps/l2-diagnostic.patch`
(SHA-256 `d60dd4fc…`), built from `cc6dc2e2` in a detached worktree.
**Never merge it.**

- **Arm A:** the accepted L1 behavior.
- **Arm B:** the same target passed as per-file `start` plus `hr-seek=no`,
  as string node-map options at index −1. The authenticated header and
  redirect options are preserved, the URL is unchanged, and the coordinator
  join seek is omitted by clearing `load.target`.
- **Order:** arms alternate ABBA by join count inside one process, and the
  channels alternate, so each arm gets 5 trials on each channel. The first
  four joins are labelled warm-up.
- **Clocks:** native stages use `steady_clock`. End-to-end time runs from the
  Dart tune request to the native join `PLAYBACK_RESTART`, on the same host's
  realtime clock.
- **Endpoint:** for A, the first restart after the join `SEEK`; for B, the
  first restart after `FILE_LOADED`. Each position is recorded with mpv's
  `seeking` flag.

**An invalid first synthetic run was discarded.** Archived as
`harness-run-INVALID-armB-extra-seek.log`, it showed that native status events
overwrite `resumePosition`, so B still issued the coordinator seek. The fix
was to clear `load.target` instead. A production `start=` design must own
this explicitly.

| Run (10 warm trials/arm) | A median (range) | B median (range) |
|---|---|---|
| Synthetic local: native load → join restart | 164.7 ms (81–189) | 135.1 ms (114–152) |
| Synthetic local: tune → join restart | 206 ms (91–245) | 178 ms (155–228) |
| **Plex 4K: join stage (`FILE_LOADED` → restart)** | **398 ms (230–706)** | **159 ms (97–529)** |
| Plex 4K: native load → join restart | 494 ms (324–962) | 327 ms (181–779) |
| **Plex 4K: tune → join restart** | **597 ms (418–1074)** | **425 ms (275–875)** |

Correctness in both runs:

- zero errors;
- every landing backward onto a real keyframe; on Plex, B landed
  −0.06 to −2.7 s, comparable to A;
- no `seeking=1` position readings;
- no token or header strings in the logs;
- B issued no coordinator seeks (12 harness seeks, all in arm A).

Interpretation:

- The open stage is unchanged. The gain is the join stage: one fewer
  Dart↔native round trip, plus mpv not reading at position 0 and then
  seeking.
- On Plex the benefit is about 170 ms at the median end to end (about −29 %).
  That exceeds the median variation, but the ranges overlap and there are
  only 5 trials per cell.
- Locally it is about 30 ms and inconclusive.
- These are restart observations, not photon or first-frame latency.

The proposal's full correctness matrix was **not** run for B: near-end joins,
part boundaries, rollover, explicit seeks, synthetic authorization recovery and
the authenticated-reference matrix. It belongs to a production
implementation.

**Recommendation:** adopt `start=` + `hr-seek=no` for schedule, tune and
recovery joins, in a reviewed production change. It should:

- extend the load contract (`LoadCommand`, the protocol doc, both adapters);
- remove the coordinator's post-load join seek for those loads, owned
  explicitly rather than through `resumePosition`;
- keep explicit user seeks exact;
- give the passive landing observation a correctly matched initial-restart
  window;
- pass the proposal's correctness floor, independent review, the
  authenticated-reference matrix, Windows CI and a repeat of this Plex ABBA
  measurement.

## Evidence

All local, with no media identity.

- `/tmp/lineup-opus-verify-logs/`: the automated suite.
- `/tmp/lineup-opus-physical/`:
  - `arm-a-frozen.log` (`a42c47a1…`)
  - `arm-b-frozen.log` (`c3b0f79b…`)
  - `arm-x-barrier.log` and `arm-x-barrier-diag.log`
  - `arm-y-setter-frozen.log` (`3358c5e1…`)
  - `combined-l1-frozen.log` (`6c16f9c5…`)
  - `win-job.log`
- `/tmp/lineup-l2-apps/`:
  - `harness-run2-frozen.log` (`438529a4…`)
  - `real-run-frozen.log` (`b8ab7bec…`)
  - `analyze.py`
  - the invalid first run
  - the patch
- Disposable worktrees: `/private/tmp/lineup-opus-verify` and
  `/private/tmp/lineup-l2-variant` (both detached at `cc6dc2e2`), plus
  `/private/tmp/lineup-ca-flush-diagnostic`. Remove them with
  `git worktree remove --force <path>` when they are no longer needed.

## Remaining limits

- **Not established:** older-macOS, x86_64, team signing, sandbox
  distribution, TestFlight and release acceptance; physical Windows media and
  HDR; the CI package job result; runtime end-of-program rollover.
- **Still open:** D0 product decisions, Licenses UI, legal review and
  purchases.
