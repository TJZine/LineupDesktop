# Lineup Desktop — general production review

Review date: October 10, 2026, America/New_York. **General review complete; no implementation authorized or performed.** Windows execution and physical/live acceptance remain separate work.

## Outcome

Eight findings are retained for planning: seven CONFIRMED defects (six S2 Medium, one S3 Low), and one S3 Low LIKELY containment risk with an explicit evidence and policy gate. The portable baseline passes, but focused probes expose missing behavioral coverage. No critical/high-severity defect, new credential disclosure, demonstrated data loss, or material architecture rewrite was established in the inspected scope. These are bounded conclusions, not a certification.

The most consequential user-facing findings are a multipart seek returning to the previous part (F-007), Guide activation tuning instead of invoking a focused control (F-002), and successful protected-profile selection retaining PIN recovery after a server failure (F-001). F-006 prevents the current authenticated-reference positive controls from recognizing successful natural completion.

[Remediation plan](REMEDIATION.md) groups corrections by ownership. [Windows handoff](WINDOWS_HANDOFF.md) carries forward source conclusions and identifies separate observations. [Evidence ledger](EVIDENCE.md), [probe recipes](PROBES.md), original census, and reviewer/calibration packets preserve supporting detail. The census, dispatch and draft packets are available in [Git history](../../README.md#historical-material-in-git); the adjudicated findings, scope and limitations remain below.

## Target, boundaries and provenance

- Root: /Users/tristan/Software/LineupDesktop; local Darwin arm64 host.
- Current branch: codex/desktop-ui-second-pass.
- Full HEAD: 4fb7758034f4f47290fae13a4ea8275860ba1284.
- Target: current checkout, with no comparison base. No branch change, reset, stash, commit or publication occurred.
- Product, permanent tests and configuration had no local tracked delta. Pre-existing modified October 7 REPORT.md and REMEDIATION.md were read as historical context and preserved byte-for-byte against the initial fingerprint.
- Pre-existing untracked .claude/launch.json, comprehensive-review-prompt.md, desktop review packets, test-slimming report directory and Windows Python cache were preserved. The pasted human request and Prompt 1 govern this review; Prompt 2 was not executed.
- Authorized additions: this new review directory; unique ignored synthetic probes/logs under build/review-probes/2026-10-10-4fb77580/orchestrator-run; normal verification caches. No product fixes, implementation patches, permanent tests, golden changes, dependency updates, account changes or Docker use.
- [INPUT_IDENTITY.json](INPUT_IDENTITY.json) records every tracked SHA-256 and initial status. [ENVIRONMENT.json](ENVIRONMENT.json) records SDK/package inputs. [FINAL_IDENTITY.json](FINAL_IDENTITY.json) records final reconciliation. No tracked input changed during review.

Flutter 3.47.6 is installed at /Users/tristan/.cache/lineup-flutter/3.47.6/flutter, framework revision 5fc346839b5d0eef006ed8404392afb4dfae428d, Dart 3.13.5. Resolved packages were reused with --no-pub. PowerShell is absent from PATH; its policy command remains unexecuted.

## Repository profile and coverage

Direct Git/rg census covered 424 tracked files: 40 lib, 51 test, 24 Windows, 24 tool, 28 macOS, 212 docs, 5 third-party metadata/license files and 6 GitHub files. No index was required and no nested AGENTS.md was found. Root CLAUDE.md imports AGENTS.md. Large files guided deep sampling; size itself was not a finding.

Composition is main → LineupApp → LineupController/LineupShell. Flutter owns application state, persistence policy, scheduling and interaction. NativePlayer → WindowsNativePlayer → StandardMethodCodec → native_player.cpp owns media/platform mechanisms. The mpv worker and platform presentation thread have distinct obligations. macOS playback is explicitly unsupported.

Highest-risk owners inspected: controller and store; Plex transport/parsers/pagination; channel builder/resolver/scheduler/worker; onboarding/setup/Studio/Air Check; Guide controller/view; shell/settings/diagnostics; Player coordinator/view/adapter; native player/encoder/harnesses; engine patch, runtime metadata, launcher/release/package scripts and CI.

Current authorities included README, docs/README, user guide, architecture, DEVELOPMENT, CONTRIBUTING, SECURITY, project profile, interface system and relevant approved decisions, product-parity, Windows runtime/native validation/collaborative handoff, scheduling/setup/freshness/reference-security/continuation/transcoding/HDR records. No current DECISIONS.md, TODO.md, CHANGELOG.md, current-cli-contract.md or current-architecture.md exists. The historical CHANGELOG on upstream refs is webOS provenance, not the current desktop contract.

Opaque assets, generated registrants, vendor binary internals and caches were excluded from broad qualitative review. Release metadata, licenses and engine patch were included. Not every test and all 212 docs were read line-by-line: the census was broad, and deep inspection followed owners, history, behavior and claims.

### Reviewer work collected and calibrated

All five separate local chats used the actual reviewer preset, gpt-6.1-sol/high, with explicit read-only responsibility. No reviewer ran checks, wrote artifacts or delegated. The controller owned all execution and final adjudication. The historical `DISPATCH.md` in Git records chat IDs and verified human authorization.

| Unit | Actual deep scope | Material limitations | Independent calibration |
|---|---|---|---|
| A | State initialization/linking, profile/server lifetimes, restoration, mutation/save queues, full store/recovery, onboarding and relevant shell callers | Deep Plex algorithms, Player/native and release tools assigned elsewhere; no OS storage observation | C narrowed PIN recovery; controller real-shell probe established the retained path. A challenged B duration and C Guide findings in `CALIBRATION_A.md` (historical packet). |
| B | Plex inventories/protocol/authorization; generator, resolver, scheduler; setup and Air Check; all C04–C06 variants and sibling seams | No live Plex/scale benchmark or native playback; artwork refresh reachability unresolved | Independently calibrated controller worker race. A calibrated duration. |
| C | Guide, Studio, Channels, shell/settings, shared controls/canvas, diagnostics, input and action guards | Physical focus/remote/IME/DPI unobserved; native/release originally outside unit | A challenged both Guide findings. C calibrated PIN, package ancestor risk and credential/publication no-finding sample in `CALIBRATION_C.md` (historical packet). |
| D | All playback owners, Windows adapter/native player/header, Player inputs, encoder/reference harness, native CMake/manifest, lifecycle tests | No Windows CTest, GPU/media/display/input execution | E independently confirmed harness mismatch and multipart mapping; challenged precommit EOF in `CALIBRATION_E.md` (historical packet). |
| E | Production PowerShell, CI, engine patch/pins/licenses, package inputs/provenance, macOS setup, test tiers, docs/release claims | No PowerShell executable or Windows build/package; representative rather than exhaustive test/doc reading | C downgraded ancestor risk to S3 LIKELY with policy gate. Spelling checks not promoted. |

Some callbacks were rejected by automatic approval review because it did not accept retrieved authorization as explicit consent. The controller retrieved terminal reports directly through read_thread. All assigned reports and calibration followups are collected; none remains pending. No callback retry or further authorization is needed to finish this review.

## Evidence and verification

E-001–E-007 identify target, census and baseline. E-008–E-013 are new focused probe/source evidence. E-014 is cross-calibration and E-015 final reconciliation. Exact commands, logs, fixture limits and preparatory errors are in [EVIDENCE.md](EVIDENCE.md).

| Evidence | Result | What it establishes |
|---|---|---|
| E-003 formatter | Exit 0; 160 files, zero changes, 4.18 s, after SDK-cache permission retry | Baseline formatting at unchanged inputs, before new probes existed |
| E-004 analyzer | Exit 0; no issues, 1.9 s | Static analysis; not runtime correctness |
| E-005 full portable suite | Exit 0; 1,364 tests passed, 95 s; TZ America/New_York | Existing suite including required Guide alpha; counted once |
| E-006 PowerShell policy | Not run: pwsh unavailable | Source reviewed only; no substituted simulator |
| E-008 worker disposal | Normal build passes; disposal race unresolved after 1 s and a repeat with 5 s | Real isolate boundary plus complete missing-settlement source path |
| E-009 protected-profile recovery | Real shell/control passes without saved reconnect; failed saved reconnect retains PIN; Escape reveals Servers | Real controller/UI, synthetic store/Plex/credentials; not live account E2E |
| E-010 duration projection | Normal duration works; one/two extreme positive items build then fail projection; two overflow cycle negative | Real parser/resolver/scheduler characterization, not acceptance |
| E-011 Guide input | Pointer menu control works; actual Enter/Space tune instead; row completion trims active search | Real Guide/widget key dispatch; not physical Windows input |
| E-012 multipart/EOF | Complete metadata and ordinary postcommit EOF controls pass; incomplete later-part seek reloads prior part; synthetic precommit EOF is lost | Real coordinator with existing deterministic fixtures; native ordering not proven |
| E-013 native/package | Complete producer/consumer and path-guard source traces | Static contract evidence only; no Windows execution |

No optional goldens were run because no specific visual question required them. No native CTests, Windows build, physical media/composition, secure-store or package acceptance ran. Synthetic product-spine and UI fixtures are not real-app E2E. No CI definition or aggregate badge is treated as a current executed job.

## Calibrated findings

Severity: S2 Medium is a bounded functional/reliability/verification defect; S3 Low is lower-impact editing or conditional local containment. Status is independent of severity and confidence.

### F-001 — Protected-profile acceptance can retain the PIN recovery screen

**Confirmed defect · CONFIRMED (real-shell synthetic-boundary observation and source) · S2 Medium · High confidence.** C01/C08; J01/J04. Origin A01; independent C calibration; E-009/E-014.

**Trigger and contract:** A protected Home profile has a saved server. The correct PIN and profile persistence succeed, then saved-server connection fails before server publication. Recovery belongs to Servers after profile commit.

**Path:** [selectProfile, lines 686–752](../../../lib/app/lineup_controller.dart) persists at 715 and awaits discovery at 744. Discovery sets Servers and invokes saved selectServer at 775–776; selectServer increments epoch at 798, making outer _run's currentness result false at 2798. [Onboarding, lines 258–279 and 1537–1546](../../../lib/app/onboarding_view.dart) prioritizes local _pinUser and clears it only after true completion; the stage-keyed replacement also retires the old submitter.

**Observed:** Four actual digit keys, accepted synthetic switchHomeUser and a delayed failing selectConnection produced profile committed=true, stage=Servers, PIN sheet=1, server tiles=0. Without a saved reconnect the PIN clears. Escape after failure reveals server recovery. Real LineupShell was used because it replaces onboarding after successful server commit; a standalone onboarding fixture would overstate postcommit restoration impact.

**Limits/test gap:** This is confusing recovery, not an inescapable trap or lost profile data. Wrong-PIN retry remains correct; successful downstream restoration leaves onboarding. Existing PIN tests substitute profile completion and miss this composed path. Flutter key/mounted behavior supports the lifetime mechanism ([Widget.key](https://api.flutter.dev/flutter/widgets/Widget/key.html), [State.mounted](https://api.flutter.dev/flutter/widgets/State/mounted.html)).

**Direction/acceptance:** Separate authentication/commit outcome from downstream discovery completion and retire PIN presentation on accepted profile/stage. Preserve wrong PIN, failed-save behavior and picker origins. Portable real-shell tests should cover precommit connection/library/save failures and postcommit restoration replacement; repeat protected-profile recovery live under W-010. Package P-001.

### F-002 — Guide shortcuts consume activation intended for focused controls

**Confirmed defect · CONFIRMED (actual widget key events and pinned-framework trace) · S2 Medium · High confidence.** C08/C09/C10; J06/J08. Origin C-F01; A calibration; E-011/E-014.

**Trigger and contract:** A toolbar/menu, dropdown or row-local retry has Flutter focus while the grid retains a logical airing selection. Enter/Space should invoke the focused control.

**Path:** [Guide _key, lines 505–559](../../../lib/guide/guide_view.dart) consumes Enter/numpad Enter/Space/Select for selectFocusedProgram. Its Focus surrounds the entire Guide at 802. Ordinary button activation relies on ancestor Shortcuts; this handler consumes the event first. Relevant siblings: toolbar at 969/1178, row Retry at 1951, shared menu [app_ui.dart:96](../../../lib/ui/app_ui.dart). Pinned framework implementation and [Flutter focus propagation](https://docs.flutter.dev/ui/interactivity/focus) support this mechanism.

**Observed:** Pointer menu callback increments normally. With the real menu TextButton focused, Enter and Space each leave menu count unchanged and increment tuning. This confirms the menu instance; other affected descendants are source-supported siblings, not separately executed cases.

**Limits/test gap:** Search, global Retry and empty Setup have explicit exceptions; grid-focus tuning itself is intended. Pointer/semantics routes work. Already-open popup routes and physical remotes are not included in the observation. Existing menu coverage starts with pointer activation.

**Direction/acceptance:** Give grid activation a focus scope that agrees with Flutter focus; allow native control Actions to run. Verify menu/hours/row Retry and grid Enter positive control with real keys, plus global chords and search. W-009 covers physical keyboard/remote. P-002.

### F-003 — Guide notifications overwrite an active search edit

**Confirmed defect · CONFIRMED (widget observation and source) · S3 Low · High confidence.** C01/C09; J06/J08. Origin C-F02; A calibration; E-011/E-014.

[Guide editor listener at 355 and synchronization at 426](../../../lib/guide/guide_view.dart) compares raw editing text against [normalized matching query at 611](../../../lib/guide/guide_controller.dart) on every Guide notification. It replaces the complete editing value and collapses the caret to the end.

A user types “channel ” while a different row is loading. The raw eight-character value survives the local edit; completing that row changes it to seven characters with selection 7. Continued input can join two words. This is unrelated schedule notification overwriting raw editing state.

Normalization and explicit external search/reset synchronization are useful controls, not defects. Midpoint/case/composition consequences follow the replacement source, but actual IME malfunction was not observed and is not claimed. Whole-string enterText tests miss the interleaving. [TextEditingController's contract](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) explains programmatic editor updates.

Preserve raw text, selection and composition for local edits; synchronize explicit external changes separately from matching normalization. Verify trailing spaces across schedule updates, midpoint edits and reset behavior. W-009 adds IME/physical input observation. P-002.

### F-004 — Disposing a schedule worker during startup can strand its build future

**Confirmed defect · CONFIRMED (real-isolate reproduction plus complete source path) · S2 Medium · High confidence.** C01/C06/C11; J02/J05/J06. Controller candidate, B independent calibration; E-008/E-014.

[ScheduleWorker.build:27–43, _start:46–141, dispose:169–185](../../../lib/channels/schedule_worker.dart) keeps startup readiness in a local completer. After the post-Isolate.spawn disposed check but before the SendPort handshake, disposal kills the isolate and closes the response port. No pending build is registered yet because build awaits readiness. Disposal cannot settle that local completer. Closing the port prevents further delivered events ([Dart ReceivePort.close](https://api.dart.dev/dart-isolate/ReceivePort/close.html)).

Normal build passed. A Timer.run disposal permutation stranded a trial after 1 second, and a separate run stranded trial 131 after 5 seconds. The permanent missing-settlement claim rests on the source path, not timeout duration alone.

Real callers replace workers on inventory change (controller 1947–1963), logout (2372), runtime clear (2584), and dispose (2855). Guide's 15-second default load deadline/currentness and slot release mitigate UI impact; no permanent Guide hang is claimed. Air Check's single active queue lacks a deadline, but a persistent mounted Studio effect was not reproduced. Existing tests do not force the spawn/handshake window.

Give startup one explicit cancellation/readiness owner settled by dispose, startup error and handshake. Preserve worker retry, stale-result rejection and bounded scheduling. Acceptance requires deterministic readiness/disposal permutations plus normal/retry controls; repeated probabilistic probes supplement rather than replace the contract. P-003; no physical Windows gate for this pure Dart settlement invariant.

### F-005 — Oversized positive durations publish unusable schedules

**Confirmed defect · CONFIRMED (production-owner synthetic-input observation and source) · S2 Medium · High confidence.** C04/C05/C06/C11; J02/J03/J05/J06. Origin B02; A calibration; E-010/E-014.

[parseMediaItem:1694 and numeric bound:2070](../../../lib/plex/plex_client.dart) accept 9007199254740991 milliseconds. Positive duration and a usable Part satisfy eligibility; channelItemFor retains it. [Scheduler validation:111, sum:137–145 and projection:219–270](../../../lib/channels/scheduler.dart) reject nonpositive items but do not enforce cumulative/DateTime representability.

The real parser→resolver→scheduler probe shows 1800000 ms projects normally. One oversized item builds then throws RangeError during projection. Two create a negative loop duration and then fail. This requires grossly malformed selected-PMS metadata, not an ordinary long film or normal catalog size. Dart's representable date range is finite ([DateTime](https://api.dart.dev/dart-core/DateTime-class.html)).

The worker publishes an index without projecting it. Guide's completion at 771 caches before projection; a sibling onError does not catch exceptions from its success callback. Air Check has the analogous initial projection seam. Such errors belong to the returned future ([Future.then](https://api.dart.dev/dart-async/Future/then.html)). Exact end-user retry/render consequences were not executed. Legacy restore's outer catch preserves saved data.

Existing tests cover invalid/zero durations and large elapsed lookup, not unusable positive item/cycle values. Correction must establish checked item/cumulative/transition temporal invariants before publication, using typed invalidProgramDuration failure and responsible consumer containment. Parser-only validation leaves persisted/direct items exposed; silently shortening media or an arbitrary media cap is not prescribed. P-004; malformed synthetic metadata is sufficient for the numeric contract, live inventory behavior remains W-010.

### F-006 — Natural completion no longer finishes the authenticated-reference harness

**Confirmed defect · CONFIRMED (complete reachable native producer/consumer source demonstration) · S2 Medium · High confidence.** C07/C13; J07/J11/J12. D-F01/E04 independently found/calibrated; E-013/E-014.

[Native EOF:1174](../../../windows/runner/native_player.cpp) emits ended, correctly distinguishing natural completion from stopped. [Harness messenger:75](../../../windows/runner/authenticated_reference_test.cpp) only finishes for stopped/error. Its 12-second loop at 170–194 marks timeout and returns failure after successful short MP4/MKV completion. The [Python positive control at 201](../../../tool/windows/authenticated-reference-test.py) requires zero exit, progress and no rejection.

A later stopped event does not rescue the source path: idle=yes/keep-open=no, harness sends only initialize/load, pending-stop confirmation emits stopResult only for a Stop request, and destruction occurs after the timeout flag. Release-active messenger checks cover stopped/error but omit ended.

This breaks usable opt-in verification; it does not establish production playback failure or security bypass. The target is excluded from default builds and CI. Earlier monotonic rejection/progress controls remain valuable.

Update the harness terminal vocabulary and Release-active sequences (ended, progress→ended, error→ended), retaining rejection latching and positive/negative security controls. Actual pinned-DLL CTest repeated three times remains W-002; no native execution is claimed here. P-005 should precede relying on this harness in a later campaign.

### F-007 — Later-part DVR seeks can return to an earlier part

**Confirmed defect · CONFIRMED (real-coordinator synthetic native-boundary observation and source) · S2 Medium · High confidence.** C07/C10; J07/J08. Origin D-F02; E calibration; E-012/E-014.

[Public timing:350](../../../lib/playback/player_coordinator.dart) falls back to active-part position/duration while any part boundary remains unknown. [seekBy/seekTo:1171–1205 and _partForPosition:1018](../../../lib/playback/player_coordinator.dart) nevertheless interpret the resulting value as aggregate. Missing duration is accepted by [Plex part parser:1732](../../../lib/plex/plex_client.dart); the [user guide:281](../../user-guide.md) explicitly promises current-part fallback.

The frozen existing continuation fixture loaded part one (60 seconds), advanced to part two (unknown metadata), then supplied native position=10/duration=90. Public position was 10. seekBy(+30 seconds) caused a third load of part one at 40 seconds. With both durations known, the same control retained part two and sought locally to 40 seconds. Player keyboard/remote transport and slider at player_view.dart:1162 use this policy.

Existing tests cover unknown duration on the first part and full aggregate projection after known completion, missing the later-part/incomplete combination. No malformed input is required. Native playback behavior itself was faked; the owner/coordinate decision is real.

Align exposed timing and seek coordinates: local display means local seek in the current part; aggregate display permits cross-part mapping. Keep initial live-join interpretation distinct. Verify forward/backward/slider paths, complete-map controls, queued seeks and authorization replacement. W-003 requires physical complete/incomplete multipart acceptance. P-006.

### F-008 — Package path validation omits the build ancestor

**Inferred containment risk · LIKELY · S3 Low · Medium confidence (High for omitted check).** C12/C13; J12. Origin E01, downgraded by C; E-013/E-014.

[package.ps1:30–36 and 223](../../../tool/windows/package.ps1) constrains a logical destination under build/package, then [Get-ReparsePointPathWithin:82](../../../tool/windows/build-inputs.ps1) stops at that boundary. It omits build. A build junction may redirect new package output outside the checkout while descendants are ordinary. The Release guard checks root/descendants, also omitting ancestors; [build-release.ps1:142–160](../../../tool/windows/build-release.ps1) removes an existing marker and invokes Flutter before that inspection. [Microsoft documents junctions as directory reparse redirections](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions).

The omitted check is static fact. Windows manifestation and whether physical containment must extend through all components below the repository remain unobserved/unsettled. Commit 565bf0bd intends junction rejection, with no documented linked-build exception, but current docs describe logical paths. Hence LIKELY and S3, not a confirmed S2 security defect.

Existing destinations are refused, direct root/descendant links and tracked symlinks are checked, and provenance/runtime/artifact hashes remain effective. No arbitrary-file overwrite, remote exploit or provenance bypass was demonstrated. Existing CI junction controls target lower descendants.

W-012 must compare ordinary paths, currently rejected descendants and a build ancestor junction in a disposable clean checkout with valid artifacts. Confirm physical-containment policy before P-007 changes behavior. If linked build is intentionally supported, revise the risk/contract disposition rather than imposing a new restriction.

## Candidate adjudication and known limits

| Candidate | Disposition and reason | Next evidence |
|---|---|---|
| CAND-001 A01 PIN | Retained F-001, narrowed to pre-server-commit recovery; postcommit restoration unmounts onboarding | W-010 |
| CAND-002/003 Guide activation/editor | Retained F-002/F-003; actual keys and edit interleaving observed | W-009 |
| CAND-004 worker | Retained F-004; no permanent Guide-hang claim | P-003 focused contract |
| CAND-005 duration | Retained F-005; gross malformed input and affected schedules only | P-004 |
| CAND-006 D-F01/E04 harness | Deduplicated F-006; static confirmation, not executed CTest | W-002 |
| CAND-007 multipart | Retained F-007 after positive-control probe | W-003 |
| CAND-008 ancestor path | Downgraded to F-008 S3 LIKELY; physical policy/impact gate | W-012 and decision D-001 |
| CAND-009 precommit EOF | HYPOTHESIS for normal Windows. Synthetic sequence playing→ended before delayed load return strands at one load; postcommit EOF control advances. Native command acknowledgement/microtask ordering may prevent that interleaving | W-004; no fix package |
| CAND-010 Air Check artwork generation | HYPOTHESIS, not promoted: child caches same controller/path; actual mounted same-path refresh reachable from production UI not established. An isolated widget mutation alone would not settle reachability | W-010 bounded refresh observation |
| CAND-011 playlist aggregate cost | HYPOTHESIS: per-stream 1000-page/100k limits and concurrency four exist; large finite aggregate retained. No realistic budget violation or measured OOM/latency | W-010 measure counts/time/memory on authorized large catalog |
| CAND-012 release spelling checks | Subjective S3 suggestion rejected as material finding: brittle potential, but helper execution/negative package controls mitigate; no demonstrated current maintenance incident | Revisit only if tooling changes |
| CAND-013 small documentation drift | Informational only: freshness index overstates deferred scope; optional golden inventory stale; architecture conflates alpha with optional golden CI | Explicit doc upkeep task, no product regression |
| CAND-014 hidden Studio hand-picked draft | Rejected: Browse remains obvious recovery, retained draft is intentional; no clear contrary contract | No new action |
| CAND-015 absolute portrait query | Rejected: approved D5 permits absolute HTTP(S) query parameters; generic query acceptance alone is not leaked PMS credentials | Actual credential-bearing source needed for a privacy claim |

Existing H1 Plex Home live response shape remains HYPOTHESIS, not a mock-established incompatibility. Historical F15 native cache-wait/buffering projection remains deferred: no paused-for-cache producer mapping was found, but actual starvation/user-pause behavior needs W-005. Profile-token compensation residue, plaintext metadata, replacement-PIN cleanup semantics and multi-instance policy are recorded limitations in product-parity, not newly discovered regressions.

## History/class ledger and sibling coverage

Each row links a historical mechanism to current invariant, repo-wide siblings and disposition. Representative diffs and regression assertions were read; commit titles were not treated as proof. Unit packets contain the deeper per-owner searches.

| Class | Historical trigger/root cause → fix | Current invariant; sibling searches/deep checks | Disposition/gap |
|---|---|---|---|
| C01 stale/cancellation | 37416c1e/e3f36d00 scan work outlived scope; cancellation now reaches requests. 62bc8af1 late Studio tune navigation gains originating-route check | Epoch/currentness/abort searches across controller, Plex, worker, Guide/art, Studio and playback; disposal and resource settlement distinct from ignored result | F-001/F-004; existing scan/publication guards retained; precommit EOF parked |
| C02 persistence | 204e0648 overlapping snapshots → queued derivation; c7c393aa publication before save → commit after durability; 3fc568d9 quarantine collision → owned directory | Every controller mutation/selection/settings/save/credential barrier, strict decoding, backup/quarantine, logout and relaunch consumers inspected; blocked-save/failure tests | No new data-loss defect established; C independently sampled publication/credentials. OS storage W-011; documented token compensation not atomic |
| C03 credentials | 5598005e cloud credential wrongly used for PMS → resource-issued PMS access; a061935a redirect and 3d2014e6 nested reference risk → native restrictions | Request headers/origins/redirects; portrait/artwork descriptors; runtime-only PMS token, recovery generations, stores/export; native option/header lifetime | No new exposure established; F-006 impairs harness acceptance, not containment proof. W-002/W-010 |
| C04 external data | 7dd76763 partial inventory looked complete → strict pagination; f6bdae5b/292fc815 identity/occurrence fixes | All parser/inventory/enrichment paths, duplicate occurrences, numeric IDs, required membership and durable filters; malformed/partial tests | F-005 new positive-duration sibling. Live H1 and large catalogs remain W-010 |
| C05 policy agreement | 85aa6452 custom preservation/allocation; c732f79f/4f89dcad eligible content and strategy corrections | Builder preview/apply, shared eligibility/resolver/scheduler, all source strategies/build modes/specials/provenance/number allocation, refresh/custom preservation, Air Check | No separate policy divergence established; F-005 schedule publication invariant |
| C06 time | 7287db1c input-order cache/shuffle instability → stable revision; 6a1ec4e3 DST/Guide boundary fixes; db3978e3 schedule identity | Seed/anchor/migration, epoch arithmetic, folds/midnight tests, schedule window/projectors, worker, Guide wall-clock versus loaded playback | E-005 runs in New York; F-004/F-005; native Windows zone must be recorded, not assumed from TZ |
| C07 lifecycle | 51900b52 bounded Stop; 835ab431 cleanup despite superseded seek; 4e01d438 command versus observed track; db30c286 EOF split; 91b66b7e/cd2c08f6 live-join/readiness retention | Every Dart/native load/seek/retry/stop/track/EOF/dispose consumer; generation, cleanup and terminal contracts | F-006/F-007; CAND-009 remains ordering hypothesis; W-002–W-006 |
| C08 exits/eligibility | 9534b282 nested Back origin; 9aebd4c7 sign-out exit; 64be4860 setup ready-subset; 62bc8af1 late navigation | Stages/routes/pickers, busy guards, save/tune/leave/conflicts, retry dependency and cancellation lifecycle | Historical exits/readiness fixed; F-001/F-002 new composed recovery/input seams |
| C09 focus/timers | 6b874f35 events rearmed deadlines; b86693d9 pointer became keyboard focus; 01bda796 editor keys escaped; 0421c88e overlay guards | All key handlers/EditableText/activation/controller-value writes; shell and Player contexts, menu focus, ticker/mounted timers | Existing fixes remain; F-002/F-003 siblings. Physical keyboard/remote/IME W-009 |
| C10 geometry/accessibility | 02330deb track semantics/actions; 825070fd footer visibility; 6a1ec4e3 incidental Guide cap | Canvas/scaling/hit targets, scroll/reveal/semantics, transformed native aperture, current track rail and Guide widths | No new clipping defect established; F-002 keyboard action and F-007 timing coordinate bugs; W-008/W-009 |
| C11 bounds/progress | 4d2470c5 fatal playlist sibling abort; d6019438 enrichment budget taxonomy; 79b1a6df support facts | Concurrency/page limits, worker/caches/queues, generation eviction, deadlines, typed collection failures, diagnostic fixed vocabulary | F-004/F-005; aggregate cost unmeasured; known F15 buffering deferred |
| C12 build identity/path | d816b53b stale artifact identity → bound marker/hashes; 565bf0bd/ca56080a links → rejection; 070ab1d6 diagnostic build identity | Provision/apply/run/build/package/CMake/CI/engine patch/runtime/license inputs; marker producer/consumer and dirty source gates | F-008 conditional ancestor omission; W-001/W-012/W-013 |
| C13 verification | d6fff072 success before later rejection; 29062716 error overwritten by stop; 766ed05f/9d30daa9 negative-contract/fixture cleanup | Native positive/negative controls, Release assertions, fixture boundaries, skips, golden/alpha tiers, policy source checks, evidence identity | F-006 newer vocabulary regression; E-005 green does not cover these probes. No current native CI pass inferred |

October 7 findings were reconciled at current source: inventory, picker/sign-out exits, staged readiness/enrichment progress, OSD/focus/search, track/footer geometry, offscreen retry/settings feedback and support facts have subsequent corrections. They are not repeated as open. October 10 scheduled continuation is implemented; Plex transcoding and automatic fullscreen HDR remain planned, not newly failing product promises.

## Journey and action/input coverage

All journeys received entry→owner→boundary→outcome→recovery tracing. Existing suite E-005 is broad portable evidence; it is not individual live acceptance of every row.

| Journey | Chain, consequential guards and recovery | Evidence/result and remaining limit |
|---|---|---|
| J01 first run | Bootstrap/link polling → credentials/Plex → profile/server → staged scan/setup/apply → Guide; terminal expiry/cancel/secure cleanup and partial inventories | A/B tests/source, F-001 real-shell probe; live managed/shared/protected account W-010 |
| J02 restoration | Profile/server saved scope → required inventory/enrichment → staged readiness/migration → publish or retain saved data; scope switch/cancel | A/B source and controlled failure tests; F-004/F-005; packaged relaunch W-011 |
| J03 setup re-entry | Ready subset/added libraries → targeted scan → shared strategies/preview → replace/add/refresh durable apply | All strategies, per-library/grouped, modes/specials/variants/minimums/limits/allocation/custom preservation traced; live membership/latency W-010 |
| J04 scope | Picker origin → accepted selection save → retire authorization/runtime → nested discovery; logout waits state/credential cleanup | F-001; blocked/failing save and stale work protections retained; physical secure store W-011 |
| J05 management/Studio | Directory create/edit/duplicate/inspect → draft/source/filter/rundown/Air Check → conflict/save → optional tune/leave | Save and tune distinct; generated protection, retained missing items, delete/reorder snapshots, dirty exits and late tune origin inspected; no new independent defect |
| J06 Guide | Clock/schedule worker → visible cache/filter/domain focus → browse/Now/details/retry; hours save and offscreen identities | F-002/F-003/F-004/F-005; New York DST suite and alpha included; long-open physical/large layout W-009 |
| J07 playback | Tune intent → schedule/current descriptor → PMS auth → native readiness/seek → commit loaded program → part/successor, or retry/cleanup | F-007 and CAND-009; EOF/stop/error/tolerance/30-second boundaries, sleep/logout/supersession traced; W-003–W-006 |
| J08 controls/settings | Context/eligibility → Flutter handler/coordinator or queued settings save → observed status/rollback | DVR off suppresses transport; OSD/sleep/track contexts and shell global chords traced; F-002/F-003; W-009 |
| J09 support | Opt-in recording → bounded fixed facts → frozen view/refresh/copy → disable clears | Safe allowlist and clipboard failure inspected; build identity unavailable in dev is truthful; real package clipboard/identity W-013 |
| J10 persistence | Decode/version/legacy → migrate/quarantine exact bytes → queued replacement save → relaunch/recovery | Real IO portable tests; no new corruption defect; Windows rename/locked file/credentials W-011 |
| J11 platform | Windows startup/local media/Plex → native worker/window surface → resize/fullscreen/stop/dispose | Complete static boundary review, F-006; macOS unsupported explicit; W-002–W-009 |
| J12 release | Pinned SDK/engine/runtime → build marker → clean source/hash/license/input checks → unique package → outside-checkout launch | PowerShell source/CI inspected, E-006 unavailable; F-008; W-001/W-012/W-013 |

### Action-eligibility and navigation map

| Context/action | Visible/enabled policy → owner guard/outcome | Failure/exit/currentness |
|---|---|---|
| Link/PIN/profile/server | Pending link/secure cleanup governs relink; PIN action authenticates profile; Servers chooses discovery result | Cancel blocks new link until secure cleanup; Back tracks picker origin. F-001 hides correct server recovery after accepted PIN |
| Setup scan/review/apply | Committable ready subset and plan validity, source strategy/number availability → serialized controller apply | Targeted retries, cancel/restart, stale-plan/conflict checks; old channels retained on failure |
| Channels create/edit/duplicate/delete/reorder | Generated inspection protected; mutations use captured snapshot/base and unique identities | Confirmation, conflict refresh and durable save before publication |
| Studio Browse/rundown/Air Check/save | Source eligibility, pending/current checks, conflict base and positive current Air Check; save precedes tune | Shared requestLeave/dirty confirmation; mounted origin guards late tune. Inactive Browse draft is recoverable, not a defect |
| Guide grid/toolbar/search/retry | Logical schedule focus versus Flutter focused controls; search owns edit keys; failed rows/global retry retain identities | F-002 activation ownership; F-003 raw edit ownership; offscreen retry persists despite eviction |
| Shell destinations/menu/settings | Ctrl+G/P/comma, Ctrl+1–5, F3 consult Studio leave; Player requires playback surface | Menu focus trap/invoker restore, Settings origin, Diagnostics through Support |
| Settings changes | Edited key disabled; queued transformations rebase on committed settings | Failed save restores value, mounted error and Retry; independent settings do not revive failed snapshot |
| Player normal/Mini Guide/tracks/error | DVR policy; arrows/Page/number tune; Mini Guide persistent; track selection command+observed result; G/F2/global route chords | New intent/scope retires pending work; Stop owns cleanup; inline retry; pointer versus keyboard OSD timers remain distinct |
| Diagnostics | Off by default, safe current snapshot copy and bounded recording | Clipboard failure retains retry; disable clears events; no raw token/header/media identifiers |

This is the reviewed action map, not a claim that every overlay/editor was physically exercised. Actual key probes covered Guide menu Enter/Space and protected PIN digit/Escape recovery; search update used the real editing controller. Remaining contexts were source/assertion reviewed and included in existing suite, with physical checks queued.

### Actual command/API surface

- App CLI: lib/main.dart accepts --media= for local media; no general public CLI or server API was assumed.
- Windows commands: prepare-mpv, run, engine apply, build-release, package and verify-release-policy. run.ps1 parameters/environment resolve SDK/local engine/runtime and invoke argument arrays; full prerequisite commands are in the handoff.
- Plex: linking/profile/resource discovery and selected-PMS connection; complete library/collection/playlist inventories, metadata/parts, artwork/portraits. Headers, origin checks, redirects, cancellation, typed malformed/incomplete responses and bounded retry were reviewed.
- MethodChannel lineup/native_player, StandardMethodCodec: initialize/dispose/play/pause; load(uri, plexToken?, loadId); seek(seconds); stop(stopId); selectTrack(type,id?,loadId,requestId); setVolume(volume); setFullscreen(fullscreen); setVideoRect(left,top,width,height,scale).
- Incoming event: state(loadId,state,message,failureCode?,httpStatus?); property(loadId,name,value); stopResult(stopId,success); trackResult(loadId,requestId,success). Property vocabulary includes pause/time-pos/duration/track-list and recognized video/decoder/output facts. Native emits idle/loading/playing/ended/stopped/error; buffering is broader interface vocabulary without the current native cache producer. FIFO messaging does not itself prove a cross-direction reply/event barrier ([MethodChannel](https://api.flutter.dev/flutter/services/MethodChannel-class.html)).

## Doc/code claim matrix

Line numbers refer to reviewed inputs. Source owners/tests are concrete evidence; current physical claims remain qualified.

| Authority/line | Promise or default → owner | Evidence | Disposition |
|---|---|---|---|
| user-guide 48–52 | Secure cancellation before new link → cancelLinking/secureCancellationRequired | A credential failure/retry assertions | Agreement; real store W-011 |
| user-guide 63–79; architecture 313–335 | Scoped profile/server credentials and durable publication → controller/store queues | A deep trace, C adversarial token/save sample | Agreement with documented compensation limitation |
| architecture 338–350 | Restore readiness and picker origins → pending scan scope/retained readiness/shell | A/B recovery tests | Agreement; F-001 is an added PIN presentation seam |
| user-guide 178–190, 327–335 | Guide search/filter/Now/hours and focused input → Guide controller/view | E-011 and C/A framework trace | Implementation defects F-002/F-003 |
| user-guide 281–285 | Aggregate timing or current-part fallback → coordinator seek/display | E-012 complete/incomplete control | Implementation defect F-007 |
| user-guide 287–300; continuation plan | Natural next part/program, 30-second catch-up and priority → coordinator | Existing continuation assertions/source | Implemented; CAND-009 uncertain; physical W-003/W-004 |
| user-guide 302–309 | Focus/OSD/AT → Player view/timers/semantics | D source/widget assertions | Agreement at portable tier; W-009 |
| user-guide 407–409 | Save versus save-and-tune → Studio/controller | C mutation/late-tune tests | Agreement |
| user-guide 428–430 | Settings failure rollback → queued updateSettings and mounted feedback | C source/tests | Agreement |
| user-guide 434–440 | Opt-in safe support export → Diagnostics | C fixed producer/export tuple tests | Agreement; actual package identity W-013 |
| DEVELOPMENT 70–112 | Synthetic suite not app E2E; native opt-in CTests | CMake/CI/source | Accurate tier qualification; F-006 breaks terminal contract |
| docs/README 111 | Both freshness scenarios described as deferred | Linked investigation resolves canonical-shuffle A | Minor documentation drift, CAND-013 |
| DEVELOPMENT 180; architecture 285 | Optional snapshots inventory; “golden” CI | CI required alpha versus optional/dated track suite | Minor doc drift, not a new acceptance pass |
| README, runtime/native validation | Windows implemented but acceptance open; macOS unsupported; Vulkan system prerequisite | Native backend, PE dependency metadata/package docs | Qualified agreement; W-007/W-013 |
| Transcoding/fullscreen HDR plans | Future server transcoding/automatic Windows HDR matching | Current player direct playback and plan status | Planned; no newly failed feature requirement |
| Build/package path policy | Logical build/package destinations, junction rejection → package/shared helper | E-013, C independent policy challenge | F-008 inferred physical-boundary question, D-001 |

## Dimension conclusions and exclusions

| Dimension | Concrete inspected protections and remaining finding |
|---|---|
| Architecture/ownership | Real Flutter/native boundary, shared resolver/scheduler, controller mutation owner and store IO owner remain coherent. F-001/F-003 expose localized ownership coupling; no rewrite justified |
| Correctness/failure modes | Seven retained confirmed defects; stale scope, restore, conflict and cleanup protections checked. No broad “all paths safe” conclusion |
| Maintainability/AI debt | No independent material style/size/abstraction finding. Current complex owners have concrete obligations. Optional spelling-based tests below materiality |
| Tests/CI | Baseline robust but misses composed lifecycle/input combinations. F-006 is a direct verification defect. No coverage-percentage mandate or replacement framework recommended |
| Security/privacy | PMS/cloud separation, cancellation, origin/redirect/reference protections, private tokens and allowlisted export inspected; C independently challenged key no-finding claims. F-008 bounded local path risk; physical containment unexecuted |
| Build/release/supply chain | Pins, engine patch, runtime/header/license/artifact hashes, dirty source, CRT and Vulkan requirements traced. F-008; PowerShell and current package acceptance open |
| Operations/config/diagnostics | Defaults, safe errors, phase/progress facts, clipboard retry, runtime/build identity inspected. Known buffering projection gap remains, not duplicated |
| Performance/concurrency/reliability | Bounded queues/caches/page limits, teardown/currentness and coalescing inspected. F-004/F-005; no measured throughput, memory or OOM claim |
| Docs/DX | Current contract mapped, old findings reconciled, minor index/golden drift separated. Planned work and unsupported platform behavior preserved |

## Needs my decision

**D-001:** Before P-007 changes link handling, decide whether every build/package path component below the repository must be physically contained and free of reparse points, or an ignored linked build root is intentionally supported. W-012 can first establish facts. This uncertainty does not block P-001–P-006 planning.

No new product/UI design decision is required for the seven confirmed corrections; they restore existing contracts. “Ready for approval” in the plan is not approval to implement. This review ends without assigning fixes.

## Needs physical/live observation

The self-contained [WINDOWS_HANDOFF.md](WINDOWS_HANDOFF.md) defines W-001–W-013 with setup, action, discriminating outcome, neutral records, cleanup and classification consequences. Outstanding areas: policy execution; both native CTests; continuation/multipart/auth/replacement/seek/stop/dispose; buffering versus pause; track execution/observation; SDR/HDR/audio/codec/subtitle output; composition/fullscreen/monitor/DPI; physical keyboard/remote/AT/IME; Plex shapes/membership/latency; Windows persistence/credentials; ancestor junctions; exact package identity and clean-system Vulkan/runtime launch.

No Windows observation is silently counted as passed. General review completion does not close release acceptance.

