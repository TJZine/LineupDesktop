# Controller handoff: macOS port and L2 status

Historical handoff prepared October 18, 2026. The final controller addendum
at the end supersedes its pending work and release instructions.

Live Git/CI/chat snapshot checked at **04:22:50 EDT
(08:22:50 UTC)**. Later CI results must be read directly; this document does
not predict them. The human stopped the benchmark worker and requested this
handoff to reassess status. This turn performs status/handoff work only; do not
restart implementation or measurement merely because an old callback arrives.

**Update after that snapshot:** PR #47's Windows job `117627181538` passed;
`authenticated_reference` completed successfully at **04:27:18 EDT
(08:27:18 UTC)**. The controller independently checked the live job state and
the observer's extracted CTest report. All seven native contract suites and
the actual authenticated-reference CTest passed. Its exact source requires
all 48 cases (23 omitted + 25 nonzero) and final server teardown to succeed;
successful per-case JSON was hidden by CTest, so those individual rows and the
Windows disconnect class are not directly visible. Focused-run Dart also
passed. Mac portable/native and the original engine/package jobs are still
running at this follow-up check. No measurement was restarted or released.

**Further Mac update:** original run `39109697512` at `57f62c94` completed its
Mac portable/native job successfully. The observer directly parsed **54/54**
passing authenticated-reference rows (26 omitted + 28 nonzero), summary at
**04:30:02 EDT (08:30:02 UTC)**. Runtime validation, embedding and application
build passed. NativePlayerTests reported 23 tests, one skipped, zero failures
(not 23 executed passes). Full runtime identity and evidence are in
`/tmp/lineup-l2-ci-39109697512/macos-auth-report.json` and `macos.log`.
The original engine/package job was still running when this report arrived.
This is native/synthetic HTTPS evidence, not new physical HDR acceptance.

## Actual overall status

The macOS playback foundation is implemented. H1 HDR publication and L1
keyframe joins are accepted from Opus's target-runtime/physical verification.
The subsequent **L2 production change is implemented and independently
reviewed, but its final acceptance is incomplete**: the corrected Windows
native/authenticated-reference gate has now passed, but the requested repeat
Plex ABBA measurement has not happened. There is no valid new L2 latency result.

The whole macOS port is **not release-ready**. Team signing/App Store packaging,
older-OS and remaining hardware/distribution acceptance, legal/source obligations,
the Licenses UI, and deferred purchase decisions/work remain separate gates.
Do not equate completing L2 with completing the port.

Read these existing owners rather than importing historical worker prompts:

- `AGENTS.md`, `.agents/project.md`.
- `docs/macos-port-plan.md`: overall architecture/packages and resolved decisions.
- `docs/macos-port-progress.md`: chronological execution record; early pending
  decisions and acceptance notes are superseded by later entries.
- `docs/handoffs/macos-hdr-and-seek-verification-report.md`: Opus's accepted
  H1/L1 evidence and original L2 experiment, committed as `42ab5784`.

## Current repository and publication state

Repository: `/Users/tristan/Software/LineupDesktop`.

| Ref/state | Exact identity |
| --- | --- |
| Checked-out branch | `platform/macos` |
| Local HEAD | `359afb385268bad653ec26ca37bb4646fca2a896` |
| `origin/platform/macos` at snapshot | `57f62c9422556fd1f4b1ba8d870adc228061a841` |
| `origin/dev/l2-windows-fixture` | `359afb385268bad653ec26ca37bb4646fca2a896` |
| Draft PR | [#47](https://github.com/TJZine/LineupDesktop/pull/47), `dev/l2-windows-fixture` → `platform/macos`, open, not merged |
| Existing dirty file before this handoff | `docs/macos-port-progress.md`, controller-owned status notes |
| This handoff | New uncommitted file; preserve it and the dirty progress notes |

Local `platform/macos` already contains the fixture correction. The remote
`platform/macos` does not yet contain its final two commits. No merge to `main`,
release, App Store submission or signed distribution was performed.

Important commits since the Opus handoff:

| Commit | Implementation |
| --- | --- |
| `770396e1` | L2 production initial-load joins, 18 files |
| `7cb730f8` | Mac/Windows authenticated-reference start profiles and CI wiring, seven files |
| `d116ad7a` | Passive landing observation no longer treats cached error detail as a current playback failure |
| `fa43f41c` | Separate eight-line CI repair: preserve pinned depot_tools and engine toolchain across workflow steps |
| `a1875fc2` | Windows fixture disconnect/error handling plus eight focused controls, two files |
| `359afb38` | Latest committed progress record; documentation only |

Other intervening commits update the execution record. The fixture PR diff
against remote `platform/macos` contains the two Python fixture/control files
and progress documentation, with no playback or engine changes.

## What is implemented

### Earlier port foundation

The execution record attributes integration and reviews for the shared core,
macOS adapter/presentation, accepted self-built runtime with GPL-object
exclusions and notices, asynchronous quit/close, synchronized native fullscreen,
Mac command shortcuts, runtime embedding/resources/ad-hoc signing, and macOS
native/portable/authenticated-reference CI. This handoff does not independently
repeat all those historical checks.

Opus accepted H1 (`ce77d18d`, setter-thread `CATransaction flush` in the owned
layer subclass) and L1 (`8bca5171`, ordinary joins use keyframes and explicit
user seeks remain exact). Its combined physical checks covered HDR switching,
resize, fullscreen and clean quit. **HDR remains accepted; the user explicitly
does not want another brightness-testing loop.** The one early flash report
was not reproducible in a blind comparison; no barrier fallback was adopted.

### L2 production behavior

- Dart load API carries optional `startPosition`; wire carries finite,
  nonnegative `startSeconds` only when present.
- The shared core sends `loadfile` with index `-1` and a string-valued node-map
  containing per-file `start` and `hr-seek=no`, alongside the existing header
  and redirect policy. The media URL is unchanged.
- Immutable `_PlaybackLoad.nativeStartPosition` owns the initial join. The
  coordinator omits the post-load join seek by that ownership, not by mutable
  `resumePosition`, which native telemetry can overwrite.
- Schedule/tune/ordinary recovery use the load start. Explicit user intent
  remains exact, including pending same-target/latest overrides, cross-part
  seeks and unfinished exact-intent recovery. Completed explicit intent does
  not make later ordinary recovery exact. The existing ≤2-second skip remains.
- Passive landing logging matches the initial `START_FILE` → `FILE_LOADED` →
  restart window; explicit seeks use their seek/restart window. Existing load
  identity, ambiguity, deadline, invalid/seeking-position and failure guards
  remain. Actual landed-versus-target offset is logged.
- `d116ad7a` removes only the observer's cached-failure predicate. Classified
  mpv logs retain detail for a later failed `END_FILE`; successful fallback to
  AVFoundation can coexist with that cache. Actual command/terminal/lifecycle
  errors still retire observations. The cache is neither cleared nor hidden.

The user clarified that “never past” is not a strict requirement. Plain
keyframe semantics are approved; do not add an exact fallback, paused landing
guard or new playback error for a missing predecessor keyframe.

### Verification infrastructure changes

- Auth fixtures now support valid byte ranges and verify nonzero-start
  keyframes. The original server's all-200 responses made input unseekable.
- Test-only paused initial observation separates actual landing from delayed
  queries, then releases playback and requires real progress. Production pause
  policy is unchanged.
- Windows uses a real plaintext secondary listener and a deliberate synthetic
  token-leak sensitivity control. CI explicitly builds/runs the auth target.
- CI-only FFmpeg tools are pinned and downloaded outside packaged runtime
  inputs. No production runtime/library substitution was made.
- The reviewed Windows fixture repair accepts narrow peer-disconnect types,
  keeps unexpected errors sticky/fatal, and records bounded sanitized error
  codes/categories. It also checks sticky TLS faults after listener teardown.
  It does not weaken authentication, redirect/reference, landing or progress
  predicates. Its eight focused controls are **local/manual tests, not wired
  into CI**; the full 48-case matrix is the required Windows runtime gate.

## Evidence already obtained and its limits

| Evidence | Result / attribution |
| --- | --- |
| Full local Dart suite for L2 | 1,758 passed; pinned Flutter; host Eastern timezone. Later observer/fixture-only changes did not alter Dart inputs. |
| Portable shared core | Three suites passed; observer regression fails before its correction and passes after. Fake libmpv contracts, not media proof. |
| Actual Mac authenticated matrix | 54/54 passed, 26 omitted-start + 28 nonzero-start. Executed frozen dirty source recorded as base `42ab5784`; integrated equivalence was checked. Do not relabel as a later exact commit run. |
| Real Mac coordinator probe | 14 cases, 22 loads, nine exact seeks, two actual last-part EOF→successor transitions, four recoveries. Two initial HTTP401 failures real; two same-load timing signals injected, with actual replacement playback. |
| Corrected Windows fixture controls | Eight passed on local Python 3.15 and 3.11, including real peer reset/bad-CA paths and a deterministic late-error control. This does not prove Windows exception behavior. |
| Final foreground benchmark smoke | Four of four passed; exact running app activated through computer use, fixed geometry/foreground, matched landings, healthy AVFoundation and advancing audio/video. Development smoke only, no counted timing summary. |

Coordinator limits remain explicit: active display hold is Dart proof on this
Mac route; natural first-part→second-part EOF was not exercised by that probe.
Actual last-part→next-program rollover was exercised. No physical Windows,
older-macOS or signed-distribution acceptance follows from these results.

Evidence directories:

- `/tmp/lineup-l2-production/`: frozen production packet, full Dart log;
  `runtime-acceptance/` contains the coordinator report/cases/manifest.
- `/tmp/lineup-l2-auth/macos-matrix-corrected/` and
  `/tmp/lineup-l2-auth/parent-integration-equivalence.json`.
- `/tmp/lineup-l2-fresh/observer-fix/`: source correction, red/green and manifest.
- `/tmp/lineup-l2-ci-repair/`: old timeout evidence and separate CI repair.
- `/tmp/lineup-l2-windows-fixture-fix/`: reviewed revision-two fixture, manifest,
  red/green controls; `revision-1/` preserves the earlier candidate.

Independent fresh reviewers approved production L2, the auth/CI correction,
the observer correction, the separate toolchain repair and the Windows fixture.
The fixture reviewer found one P2 late-error race; revision two closed it and
received focused re-approval. No review finding is knowingly left unaddressed;
runtime gates remain open.

## CI snapshot — do not call this green

| Run / source | Actual state at snapshot |
| --- | --- |
| [39098816614](https://github.com/TJZine/LineupDesktop/actions/runs/39098816614), `cc6dc2e2` | Terminal cancelled. Six other jobs passed. Package job annotation explicitly says maximum execution time of 3h exceeded; it rebuilt the engine after switching Ninja 1.11.1→1.13.2. Root waited for terminal before any push/dispatch. |
| [39109697512](https://github.com/TJZine/LineupDesktop/actions/runs/39109697512), `57f62c94` | Follow-up: Dart/core/release-policy/input detection and Mac portable/native passed, including directly parsed Mac auth 54/54. Windows player job remains failed; engine/package still running. |
| [39111084372](https://github.com/TJZine/LineupDesktop/actions/runs/39111084372), PR #47 head `359afb38` | Follow-up: Windows native/auth and Dart passed; Mac core/release-policy/input detection passed. Mac portable/native still running. Engine/package correctly skipped by existing fixture-only change filters. |

Run `39109697512` Windows job **actually passed seven native contract suites**,
then ran all 48 authenticated-reference cases: **44 passed, four failed**.
Both bad-CA cases set `server_error`; two later nonzero delayed controls inherited
that sticky failure despite expected landing/progress results. There were no
timeouts or unexpected token leaks. The old fixture swallowed exception details,
so its exact Windows exception is **unknown**, not an observed reset type.
The reviewed fixture repair is proposed as the cause-based correction, but
the later passing Windows CTest establishes the corrected fixture gate without
identifying the swallowed original exception. Report:
`/tmp/lineup-l2-ci-39111084372/windows-report.json`.

The focused PR uses a distinct concurrency group to preserve the original
engine/package build. **Do not dispatch another same-branch run that cancels
the still-needed package evidence.** Check live status first. Do not raise
timeouts, bypass checks or relabel the failed run as passing.

Useful read-only commands:

```sh
gh run view 39109697512 --json status,conclusion,headSha,jobs,url
gh run view 39111084372 --json status,conclusion,headSha,jobs,url
gh pr view 47 --json state,isDraft,baseRefName,headRefName,headRefOid
git status --short
```

CI evidence is under `/tmp/lineup-l2-ci-39109697512/` and
`/tmp/lineup-l2-ci-39111084372/`. The CI observer was still active at snapshot;
do not assume stopping the benchmark worker cancelled CI or its observer.

Evidence visibility limit reported by the observer during handoff: CTest uses
`--output-on-failure`. If the new auth test passes, its successful per-case JSON
and disconnect categories may remain only in runner `LastTest.log`, which the
current workflow does not upload. A genuinely executed successful CTest plus
the exact source's strict 48-case/all-pass checks establishes that gate; it
does **not** establish a directly observed Windows exception category from
the public log. State that distinction; do not invent the swallowed old cause
or expand the workflow solely to claim an unnecessary diagnostic detail.

## Benchmark state and exact remaining measurement

**No counted synthetic or protected Plex campaign has run.** The earlier Opus
diagnostic reported a Plex benefit; it is historical motivation, not verification
of this production L2 implementation.

Use only `/tmp/lineup-l2-fresh/benchmark-next/` for the prepared new harness:

- Frozen manifest SHA-256:
  `91d14f236cd2507e4093e5e1a923b224dda9d5b28baa9ae9dbcb3c4399ed42e5`.
- Build ID `185368181381652`, source baseline includes `d116ad7a`.
- Exact disposable app:
  `/tmp/lineup-l2-fresh/benchmark-next/source/build/macos/Build/Products/Debug/Lineup Desktop.app`.
- Final valid development smoke: `runs/foreground-03/`, `smoke03-report.md`.
- `release-smoke.json` permits smoke only: `allowCounted=false`,
  `allowProtectedPlex=false`, `windowsNativeAuthRun=null`.
- The worker was interrupted while preparing a supplemental equivalence report
  for the newer CI/test/doc commits. **That report is not complete.** Existing
  frozen source/app identity must be verified before reuse; do not change the
  frozen manifest silently or assume every tracked file remains identical.

Prepared method: same-process immutable A/B arms, A is accepted L1 load-then-seek,
B is per-file start without coordinator join seek. Four warmups then five ABBA
blocks, ten counted trials per arm, five per arm/channel cell. End-to-end metric
is Dart tune→matched restart receipt, not first-frame/photon latency. Native
stages use a monotonic clock. Output/current-load/foreground/lifecycle/audio-video
progress checks must pass; a passive landing packet alone is insufficient.
All failures/warmups are retained. No cherry-picking or timing summary from
partial/failed campaigns.

Only after actual Windows native/auth acceptance and source-equivalence checks,
the controller may authorize the exact manifest's counted release file and run
`run.py --phase counted-synthetic`, then `--phase counted-plex`, using the
existing README/report for the precise arguments. The internal release file is
a harness guard, not a request for renewed human permission.

The protected Plex loader has **not been executed**. It intends read-through
of existing store/Keychain with mutations diverted to memory. If access/signing
fails, report the actual issue; never invent credentials or weaken sandboxing.
Keep media IDs/titles/URLs/tokens/raw private logs out of evidence.

All app interaction belongs to computer use. Multiple app copies share the
bundle ID: verify PID/executable and use Finder's exact bundle Open action to
activate the already running probe; generic app binding can choose another
copy. Do not query an exited app object because that can relaunch it. The
last passing probe exited; no later app launch was assigned during preparation.

**Never merge** `/tmp/lineup-l2-apps/l2-diagnostic.patch`,
`benchmark-next/NEVER-MERGE-benchmark.patch`, old trace/benchmark patches or the
coordinator correctness probe. Earlier failed smokes remain failed evidence.

## Chat ownership at snapshot

Prior integration controller: this chat,
`01a14bbc-51cd-76e0-8274-37c69f04cf17` on `local`. A replacement controller
must explicitly take Git/CI/app ownership and recheck live state.

| Chat | State / responsibility |
| --- | --- |
| `01a14dc2-e884-7700-a324-b34616408fa1`, “Diagnose L2 benchmark observation failures” | Idle; latest turn interrupted by user. Do not restart without the new controller's direction. Supplemental equivalence preparation incomplete. |
| `01a14df1-7784-7001-8a1a-744b791ee9d1`, “L2 separate CI diagnosis — Ninja rebuild” | Active read-only observer of both CI runs. No Git/CI-control/app authority. Can still send authorized callbacks. |
| `01a14e0d-afa6-73b3-a65f-1415a5ad5fe7`, “Repair Windows authenticated fixture…” | Idle, completed/frozen; writes stopped. |
| `01a14e12-eadf-7d43-b94d-d66d2932aec7`, “Review Windows authenticated fixture…” | Idle, approved revision two; read-only. |

Fresh separate chats are required for independent adversarial reviews. Focused
re-review of an existing finding reused its independent reviewer. Do not start
a new review campaign or unrelated feature work merely to resume this handoff.

## Remaining steps for the controller

1. Recheck both CI runs. Preserve the now-passing Windows seven-suite and
   authenticated-reference result at `359afb38`, with its source-enforced
   48-case count and hidden successful per-case output distinguished. No
   further Windows fixture repair is currently indicated by that gate.
2. Obtain the original run's package result: same pinned Ninja wrapper/child
   identity at both build stages, no build-log reset, valid incremental refresh,
   completed application/provenance/package checks. Retain exact source attribution.
3. Reconcile draft PR #47 and local/remote `platform/macos` under one Git owner.
   Local already contains its commits; avoid duplicate cherry-picks or an
   unintended merge to `main`. Do not cancel the active package run to do this.
4. Complete supplemental benchmark source/runtime equivalence. Once the Windows
   native/auth gate is genuinely green, run the frozen synthetic and Plex ABBA
   campaigns through computer use. Report measured gain, no gain or inconclusive
   honestly. No new latency claim exists yet.
5. Record the final L2 verdict and exact evidence. Then return to the overall
   port plan; do not keep reopening accepted HDR or expanding the timing harness.

## Product and release decisions to preserve

Approved: Apple Silicon first release, current bundle ID
`com.tjzine.lineupDesktop`, current macOS 12.0 deployment target (older-OS
compatibility unproven; only macOS 27 tested), native Command shortcuts,
Settings via Command-comma, and one synchronized native fullscreen state.
Preserve the approved Player layout.

The human chose **finish playback first; defer purchases**. Purchase model,
free-channel limit, entitlement/upsell UI and source visibility are not approved
by an implementation prototype. Overall remaining release gates include:

- R1 team-identity signing/signed archive, sandbox/TestFlight installation and
  account/credential/network/link behavior, user-accessible license presentation.
- Legal/source/license/Plex obligations and approvals before submission.
- Older-OS compatibility and applicable multi-display/scale/physical Windows
  acceptance; exact signed-build acceptance must not be inferred from debug probes.
- Deferred B1/B2 purchase design/implementation if retained in the release plan,
  then A1/TestFlight and App Store submission. These are not complete.

## Why this took so long

The production design did not repeatedly change. Verification exposed several
real shortcomings: unseekable all-200 fixtures; cached backend error detail
suppressing passive timing observations; incorrect probe generation matching;
an engine rebuild caused by cross-step Ninja versions; and Windows fixture
disconnect/finalization handling. Earlier failed attempts are preserved rather
than counted as success. The controller acknowledged that verification expanded
too far before producing the requested final measurement. The remaining L2
scope is the Windows gate, existing package evidence and the counted comparison,
not another broad infrastructure or HDR investigation.


## Final controller addendum — October 18, 2026

Replacement controller chat `01a14e20-5cfd-7a61-ac19-6819dad1cd16` took
exclusive Git/CI-decision/app ownership after live recheck at local
`359afb38`. The latest human instruction bounded closure to the two existing
CI runs, Git reconciliation, one protected Plex campaign and the final record.
It explicitly skipped counted synthetic and prohibited reopening design/HDR
or adding verification infrastructure. Those instructions supersede the
historical remaining-steps list above.

The actual PR #47 Windows native/auth job passed: seven native suites and
strict 48-case authenticated-reference CTest, 39.80 seconds, zero failures.
Its declared source is `359afb38`; tested merge ref `741a2dbe` has that exact
head as second parent and matching auth-relevant blobs. Successful per-case
JSON/categories are not public, so no exact swallowed Windows exception is
claimed. Final CI evidence belongs to `/tmp/lineup-l2-ci-39109697512/` and
`/tmp/lineup-l2-ci-39111084372/`; `/tmp/lineup-l2-final-ci/` retains supplemental
initial observer evidence. See the final progress entry.

The original run `39109697512` Mac portable/native job `117622978001`
passed, including **54/54 authentication cases**, at exact source `57f62c94`.
Its failed Windows-fixture result remains distinct from PR #47's corrected
passing Windows gate.

The one protected Plex campaign ran with verified unchanged manifest
`91d14f236cd2507e4093e5e1a923b224dda9d5b28baa9ae9dbcb3c4399ed42e5` and build
`185368181381652`. Supplemental equivalence is
`/tmp/lineup-l2-fresh/benchmark-next/final-controller-equivalence.json`.
Run `protected-plex-final-01`, ID `196382485489006`, completed all 24 rows,
but 17 failed acceptance (14 output-health, one late rejection, two foreground
failures). The fixed dimension threshold rejected a widescreen cell; two
initial audio-PTS samples were unavailable; later foreground was interrupted.
The analyzer withheld timing summary. **Final measured Plex verdict is
inconclusive; no gain or no-gain claim.** No retry, counted synthetic run,
harness change, product change or HDR experiment followed. Protected store
files remained unchanged and the app exited. Detailed numeric evidence and
hashes are in the run's `controller-verdict.json`; no private raw logs or
media/account identities are copied into tracked documentation.

L2 is implemented and reviewed, with the Windows gate passed; performance
benefit remains unestablished. This does not reopen accepted H1/L1 and does
not establish macOS release readiness. The final progress record owns the
complete evidence and limits. Stop after the authorized Git closure; do not
resume a campaign from this historical handoff or an old callback.


The human's latest `orchestrate-implementation-chats` instruction moved waiting
out of the controller turn: its subagent was stopped, and existing separate
observer chat `01a14df1-7784-7001-8a1a-744b791ee9d1`, “L2 separate CI diagnosis — Ninja rebuild”,
was explicitly continued as GPT-6 Luna/low. It completed read-only waiting and
sanitized CI evidence, with waits between queries and no unchanged callbacks.
Its completion callback targets replacement controller
`01a14e20-5cfd-7a61-ac19-6819dad1cd16` on `local`, under the verified human
skill invocation in turn `01a14e21-3297-74e2-8f56-e27ebd2b6b53`, message
`01a14e2a-6ff2-7481-9556-f893ef3c1503`. The controller yielded and resumed on
its terminal completion callback. Final live recheck confirmed PR run
`39111084372` SUCCESS and original `39109697512` FAILURE solely from its
preserved old Windows fixture result. Original engine/package job
`117623036312` SUCCESS, with unchanged Ninja 1.11.1 wrapper/child identities,
unchanged v5 build log and second invocation `no work to do`. All package and
provenance guards passed. Artifact `LineupDesktop-windows-x64`, ID
`12131893342`, digest
`sha256:79ecdb41b1413d0bbcaaec81efa9b5d0287db5166df8fa608758907daae978eb`,
is attributed to `57f62c94`; no independent inner-ZIP download or physical
acceptance is implied. PR Mac job also passed, with directly observed
54/54 cases at merge source `741a2dbe`, whose whole tree equals `359afb38`.

After both runs were terminal, the controller pushed local `platform/macos`
to `359afb38`. GitHub automatically marked PR #47 merged at 09:39:30 UTC
(05:39:30 EDT), with exact merge identity `359afb38`. No duplicate merge was
performed. The progress and handoff documents are committed together as the
final documentation closure; `main` remains `022b05aa`. Detailed final evidence
and limits are in the final progress entry and
`/tmp/lineup-l2-ci-39109697512/final-terminal-report.md`, whose evidence hashes
the controller checked. L2 correctness/gates are complete as attributed;
Plex performance remains **inconclusive**. The bounded task is complete and
all workers/observers have stopped. Do not resume measurement, design, HDR,
CI remediation or release work from this historical handoff.
