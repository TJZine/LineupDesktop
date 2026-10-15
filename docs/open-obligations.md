# Open obligations and historical evidence

Status: October 15, 2026 documentation consolidation, package G integrated and reviewed.
Portable code packages are integrated and reviewed; **F is unmerged and
unverified, portable final checks/build and eligible cleanup passed, and the code-quality plan is not fully
complete**. This register routes unfinished work; it approves no implementation,
new design, branch repair, or platform-support claim.

A retained source remains the detailed contract. A historical observation applies
only to its recorded source/build, operator and environment. Later portable passes
do not convert it into current physical evidence. Review records under
`docs/reviews/` are immutable attributed history; their old links are intentionally
historical. Record exact candidate, Flutter/engine/libmpv and build hashes,
MSVC/SDK/CMake versions, hardware/display/scaling, scenario and result when new
platform work runs. Never include tokens, URLs or private media information.

## Delivery and tooling

| Obligation | Source § | Platform | Status | Evidence |
| --- | --- | --- | --- | --- |
| F restoration classifier, explicit journal ordinals and native deduplication: required native build and four CTest families before integration | [Code-quality plan](code-quality-implementation-plan.md) §§2.1.4, 7.F, 8.4; [Development](DEVELOPMENT.md#current-test-tiers-and-gaps) | Windows | Candidate `040e4a64bdc667bae9673d61a39a8d15261959c3` on `cq/F`, retained; no Windows compile/CTest executed | Parent-owned [execution record](reviews/code-quality-2026-10-15/EXECUTION.md), F delivery report in controller's local evidence. Build targets `display_dynamic_range_test`, `display_guardian_test`, `native_player_contract_test`, `runner_lifecycle_test`; CTest names `display_dynamic_range`, `display_guardian`, `native_player_contract`, `runner_lifecycle`. Use Development's exact commands and prerequisites, then parent review/rebase/recheck/integration. |
| Final stable integration gates, macOS build, G inspection/integration and accepted-task cleanup | Code-quality plan §§8.1–8.4; [closure](code-quality-implementation-plan.md#execution-closure-october-15-2026) | Portable/macOS | Completed for portable delivery: G integrated/reviewed; final checks/macOS build passed; eligible task cleanup completed | At `a620790e642d8c72fcdb2d76602a3a5f49bf16af`: pin 3.47.7, format 144 unchanged, analysis clean, 1,690 tests; combined and whole-branch review clear. [Combined review](reviews/code-quality-2026-10-15/IMPLEMENTATION_COMBINED_REVIEW.md), [final review](reviews/code-quality-2026-10-15/IMPLEMENTATION_FINAL_REVIEW.md). Parent final post-G checks at `476750d950744d6f22de99a170d4a6dfde4042d4` passed format144/analysis/full1,690 and macOS release build54.4MB; observed commands/artifact hashes are in the execution record. G itself ran documentation checks only. |
| Select the canonical toolchain before repository checks | Code-quality plan §7.H; [Development portable commands](DEVELOPMENT.md#portable-commands) | All | H integrated; ongoing contributor prerequisite | Run `dart tool/check_toolchain.dart`; `tool/flutter_version.json` is canonical. Dart version alone cannot distinguish the wrong Flutter SDK. |
| Execute H’s PowerShell pin-consistency assertion on a supported runtime | Code-quality plan §7.H; code-quality execution record | PowerShell 7.4+ | Local assertion execution unavailable in this campaign | The pin-consistency assertion is source-inspected only; no local PowerShell runtime or future CI pass is claimed. Package policy and real package execution retain their separate Development gates. |
| Keep T's original artwork failure attributed, with its unresolved cause | Code-quality execution record, package T | Portable | Unexplained original failure; repeated serialized runs subsequently passed | Original `player_view_test.dart` “OSD uses official title artwork with a text fallback” expected one loaded logo and found zero at T’s main gate (1,587 pass/1 fail). No demonstrated cause, proven flakiness or fix; later serialized passes retain their source identities in the parent execution record. |
| Repair repository default/branch history | Code-quality plan §§2.3, 7.G | Repository | Maintainer proposal only; not executed | Flutter default line, individually reviewed stale local branches and optional historical tags require maintainer action; no branch/tag/default changes by G. |

## Code-quality physical checklist

All rows below are **unobserved in this campaign**, independently of deterministic
code acceptance. W4–W6 require F's Windows CTests and subsequent integration
first. Use [Windows native validation](windows-native-validation.md) for safety,
provisioning and exact-artifact evidence.

| Obligation | Source § | Platform | Status | Evidence |
| --- | --- | --- | --- | --- |
| W1 Tune, rapid surf, Stop during load, retry (C) | Code-quality plan §10 W1 | Physical Windows | Pending | Portable coordinator proof only; actual native playback/input unobserved. |
| W2 Multipart boundary and nearby seek (C) | Code-quality plan §10 W2 | Physical Windows | Pending | No current application-path boundary observation. |
| W3 401 during playback and tune while current channel saves (B/C) | Code-quality plan §10 W3 | Windows/live Plex | Pending | Controlled failures are not real authorization timing. |
| W4 HDR hold, match, release on Stop and exit (C/F) | Code-quality plan §10 W4 | Windows/HDR display | Pending after F gates | No candidate-F CTests or physical HDR run. |
| W5 External HDR toggle, main-process kill, restart/restoration (F) | Code-quality plan §10 W5 | Windows/HDR display | Pending after F gates | Guardian fixtures do not establish hardware or power-loss behavior. |
| W6 Display target change during a session (F) | Code-quality plan §10 W6 | Windows/multiple displays | Pending after F gates | No hardware remapping observation. |
| W7 Profile/server/logout with playback; leave and return (B) | Code-quality plan §10 W7 | Windows/live Plex | Pending | Portable scope/lifetime evidence retained. |
| W8 Studio edit/save/conflict reload/undo; slow-worker Air Check (D) | Code-quality plan §10 W8 | Windows | Pending | Controller/widget and matched synthetic renders only. |
| W9 Setup review mode, removal confirmation, stale apply (E) | Code-quality plan §10 W9 | Windows | Pending | Portable review/phase and render evidence only. |
| W10 Start, play, Diagnostics; native-ready behavior unchanged (M) | Code-quality plan §10 W10 | Windows | Pending | Protocol conformance is portable, not a real engine run. |
| W11 Player keyboard/remote across overlays, badges, shell navigation (U) | Code-quality plan §10 W11 | Windows | Pending | 44 matched synthetic images and four approved badge differences are not physical input proof. |
| W12 Real-server full library scan, playlist catalog, collection membership (A/L) | Code-quality plan §10 W12 | Windows/live Plex | Pending | Parser/paging tests do not observe a real server. |

## Product plans and earlier campaigns

Keep the detailed retained plans and every product/design decision record. These
rows collect unfinished obligations without importing their historical dispatch
instructions. A backlog item is not approval to implement it. Where later source
addresses an earlier hypothesis, inspect that source and its evidence before
calling the old item open or closed.

| Obligation | Source § | Platform | Status | Evidence |
| --- | --- | --- | --- | --- |
| Transcoding/Direct Stream P0b stream/subtitle selection and true-remote evidence; P1–P5 production packages and Settings approval | [Plex transcoding plan](plex-transcoding-implementation-plan.md) §§P0b–P5, P0 results/Open issues | Windows/live PMS; Dart | Production pending; bounded P1 foundation only under a separate assignment; P3 depends on P1/P2, session start remains P0b-dependent | Retain P0 identities and headless observations. Resolve per-request versus server preference writes, seek coordinate/restart policy, HDR profile direction, Direct Play OK/HLS 400 and remote-original 503 handling, Pass/concurrency/error/relay/multipart/subtitle/bitrate coverage and Remote default before P4. No integrated playback/support claim. |
| Next-program continuation exact-app boundaries and cancellation | [Continuation plan](schedule-continuation-plan.md#physical-windows-acceptance) §Physical Windows acceptance | Windows/live Plex | Implemented; physical acceptance pending | Three direct-play boundaries and gaps; transcoded boundary when available, DVR pause >30s, Stop/Sleep near boundary, PiP/Guide and fullscreen SDR continuity. Transcoding remains a separate pending feature. |
| OSD/cursor timing, keyboard hold, pause while loading, profile timeline, collection counts/tuning/Kometa and scan budget | [OSD/collection plan](osd-autohide-and-collection-membership-plan.md) §§B1 budget, Acceptance outside this checkout; archived collaborative handoff §§1–6 | Windows/live Plex | Six units implemented; live/physical acceptance pending | Measure launch and setup separately: warm-up plus five paired runs, median added time ≤ `max(20 s, 50% of item-only median)`, each added time ≤ twice allowance; concurrent-library contention separate. Exceedance requires report/product decision before changing launch policy. |
| Live Plex tag, paging, smart-collection and portrait probes | OSD/collection plan §Acceptance; [Player/Guide plan](player-guide-polish-plan.md) §D5; archived collaborative handoff §7 | Live PMS/local and remote | Unverified hypotheses | Compare `/all` versus metadata tag lengths for 20 movies; 20 episode tag presence; collection children paging and smart `childCount`; portrait `thumb` classes for 20 movies/episodes on both endpoints and both servers. Counts/booleans only; never log source URLs, hosts or private names. |
| Deferred collection/product decisions and traces | OSD/collection plan §Recorded and out of scope | Dart/live Plex/Windows | Deferred, not silently implemented by code-quality work | Live refresh; rename/fuzzy/cross-library rebinding; TV studio/network and actor channels; Recently Added size/tie order; partial-library effects; naming collisions; smart-playlist paging; loading flash and multipart EOF duration need observation first. Stable-order shuffle separately resolved deterministically October 8. |
| Startup LIB-01/LIB-02, restoration/setup reentry and server switching | [Startup/reentry plan](setup-reentry-startup-plan.md) §§Decisions, Windows acceptance | Windows | Implemented per October 7 review; physical acceptance pending | Run full deterministic suite on Windows to establish the two `6977a0b8` quarantine-path fixture failures are fixed, then loading→Guide, regeneration/configure/review, scan/subset/server switching from all origins and no-libraries state, intact relaunch, then timing/collection campaign. |
| Player/Guide polish, cast portraits, logo cap, approved Guide information composition | [Player/Guide plan](player-guide-polish-plan.md) §§User decisions, October 7 refinements, D5, Windows acceptance | Windows/local and remote Plex | Implemented per October 7 review; physical checks pending | Up from OSD, mouse/keyboard Sleep and focus, row snapping/full-bleed/PiP alignment, search/dropdown, long synopsis; real portrait path and label/output behavior. Preserve P6 104px cap and explicit supersessions. Colors/logo redesign require separate product agreement. |
| Track labels P4, candidate visual approval and physical label-to-output/Narrator acceptance | [Track-label plan](audio-subtitle-track-label-implementation-plan.md) §§P4, Execution ledger; Player/Guide P3 supersession | Windows/AT/live Plex | P0–P3 accepted with bounded evidence; P4 pending | Exact clean candidate/patched engine, audible/subtitle cues independent of source metadata, embedded/external text/image subtitles where exposed, Off/failed/rapid switching, focus/DPI/fullscreen/composition and Narrator. Standalone mpv metadata does not prove Lineup exposure; unavailable media explicit. Update audit/guide/decision owner after acceptance. |
| Fullscreen HDR physical final-app and portable-package campaign | [HDR implementation plan](fullscreen-hdr-implementation-plan.md) §Evidence / User's final full test; [HDR spec](fullscreen-hdr-spec.md) | Windows 10/11, HDR display/package | Units 1–5 integrated; current physical acceptance pending; F is separate unmerged work | Entry, HDR↔SDR/no-change boundaries/holds, Windows initially HDR with SDR content, Stop/exit/error/retry, external toggle, guardian, second launch, Dolby Vision/HLG where available, UI/Guide/input, target change/TV power, diagnostics, borrowed Windows 11 and portable package. No automatic new acceptance from October 9 discovery. |
| Earlier HDR discovery limitations | Archived HDR discovery §Discovery result and Completion criteria (recovery below) | Windows | October 9 Win10 feasibility only | Qualitative SDR/static HDR10 Sony A90K/RTX 5080 result; no meter/TV signal info, HDMI/eARC audio, HLG or Plex HTPC; SDR manual audio unobserved, DXGI metadata source-predicted only. Final rich Plex overlays, Windows 11 and release package remain untested by that run. |
| Guide source freshness and actual membership-change policy | [Freshness investigation](guide-freshness-collection-investigation.md) §§A, B, Decision gates | Dart/live Plex/Windows | A resolved deterministically; B/live refresh deferred | Canonical media ID/duration shuffle preserves occurrences and frozen legacy cycle, with accepted one-time shift. Live permutation frequency/restart, rename/deletion/recreation/duplicates/incomplete inventory, running-across-Kometa behavior and actual-change timing/fallback policy require separate evidence/design. No fuzzy invisible rebinding. |
| Authenticated reference containment and future per-load session policy | [Reference investigation](libmpv-authenticated-reference-investigation.md) §§positive controls, Per-load feasibility, Conclusion; [Architecture](architecture.md#implemented-now) | Native Windows/live PMS | Direct Play restrictions retained; session policy not implemented | Strong positive controls require progress AND no later rejection. Preserve pinned DLL/checker evidence and `access-references=no`/`autoload-files=no`; future session override requires gated authenticated-reference tests for completion/Stop/replacement restoration. Real DASH, selected subtitles, encrypted HLS, other PMS/topologies, physical media/input/HDR/packages remain outside headless proof. |
| Remaining UX findings, command discoverability, dynamic whole-show authoring, fullscreen and source reproduction | [UX audit](ux-functionality-audit.md) §§1–7, September 14 disposition, September 19 Remaining acceptance | Flutter/Windows/live Plex | Mixed dated statuses; follow later dispositions and retained decision records | Reconcile collections/geometry/Guide paint with current fixes and exact physical evidence; series-source semantics and broad discoverability inventory/walkthrough remain product work. Live 401/403, `playlistItemID`, concurrent playlist edits and exact Windows app acceptance remain pending. Do not treat old source hypotheses as freshly confirmed defects. |
| Feature-track decisions and pending research/planning inputs | [Feature findings](feature-validation-findings.md) §§1–4, candidate register and maintainer questions; [opportunity report](feature-opportunity-report.md); [research request](opus-feature-research-request.md) | Product/Dart | Retained, not implementation approval | Recall success/scope/shortcut; versioned scoped backup/restore with preview/snapshot; track preference ownership versus Plex/transcoding; mixed/series source plus rhythm decision; favorites and in-session refresh. Preserve peer/research evidence and open questions. |
| Extended UI acceptance carried from desktop delivery/parity/scaling campaigns | Archived desktop implementation §§P8, acceptance matrix; execution §Acceptance still open; scaling §Closeout; UI parity §VPP-7 | Physical Windows | Portable campaigns complete; hardware claims pending | 720p/1080p/1440p/2160p, representative 100/150/200% display scale and enlarged text, live monitor/DPI transitions, Windows fonts/input/AT, real-video contrast/alpha/Guide aperture/OSD/Now Playing, ticker timing, confirmed tracks, timer suspend/wake, fullscreen/HDR and exact package. Synthetic images and macOS builds are not Windows acceptance. |
| Earlier review obligations outside code-quality package scope | [October 7 remediation](reviews/comprehensive-review-2026-10-07/REMEDIATION.md); [October 10 handoff](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md); [workflow](reviews/workflow-remediation-2026-10-04/REPORT.md), [maintainability](reviews/maintainability-remediation-2026-10-12/EXECUTION.md) and [audit follow-up](reviews/audit-followup-2026-10-12/IMPLEMENTATION.md) | Windows/native/filesystem/PowerShell | Retained attributed limits; not closed by G | Buffering was a hypothesis, not physical proof; inspect current source. Ancestor-junction policy, native gates, platform credential/filesystem/runtime and physical rows retain their original dispositions and identities; no fresh acceptance inferred. |

## macOS media backlog

[The code-quality plan](code-quality-implementation-plan.md) §9 and
[the protocol](native-player-protocol.md) remain live authorities. macOS is a
development surface; native playback is not yet implemented.

| Obligation | Source § | Platform | Status | Evidence |
| --- | --- | --- | --- | --- |
| Choose media engine and presentation | Code-quality plan §§9.1–9.2; TRACES T5 | macOS | Decision/spike pending | One repo/Flutter app recommended. Compare libmpv render API with AVFoundation; underlay versus Texture requires an ownership/design decision, not an implicit port. |
| Implement protocol and presentation semantics | Code-quality plan §9.3; native-player protocol | macOS | Not implemented | Exact Guide alpha on real video, logical top-left rect converted to AppKit coordinates, transformed bounds/DPR, duplicate/metrics/retry/zero-dispose behavior, rect survives load/Stop, hide when minimized, passive video with no input/focus/semantics, transition-complete fullscreen and token safety. |
| Resolve fullscreen menu, command modifiers, copy and HDR capability | Code-quality plan §9.2 | macOS | Product/protocol decisions pending | Green button/menu bypass Dart; choose runner interception or event extension. Decide ⌘/Ctrl and Preferences, Windows HDR/Diagnostics/slate wording, EDR `unavailable` versus protocol extension. U currently preserves Ctrl. |
| Distribution, sandbox and native CI | Code-quality plan §9.2; Development §macOS development app | macOS | Pending | Signing/hardened runtime/notarization/libmpv embedding, signed alpha and data-protection Keychain, sandbox browser launch and credentials, bundle-ID continuity, native target and full portable CI. Current development build is not native playback proof. |

## Archive recovery and preservation map

Every command below resolves at the full immutable pre-G commit. Run from the
repository root; it recovers the entire original document including attributed
results, rationale and source/build identities. It does not reactivate its old
workflow or make its dated claims current. Retained review files may still link
to these removed paths as historical citations.

| Historical source | Recovery command | Sections and retained owner | Reason / evidence boundary |
| --- | --- | --- | --- |
| `desktop-ui-implementation-plan.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-implementation-plan.md` | §§P0–P8, Data and operation gates, Input and state acceptance matrix; current owner: Architecture async/persistence contracts; Desktop UI design specification; Windows native validation. | Completed delivery procedure; preserve frozen source/schedule decisions and extended acceptance above. |
| `desktop-ui-execution.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-execution.md` | §§Baseline and evidence, P0 operation/recovery, P0 source/schedule, R1 adjudication, September 9 closeout; current owner: Architecture; Desktop UI design/specification, surface approvals and second-pass decisions. | Dated implementation and attributed review history, not a new execution mandate. |
| `desktop-ui-readiness-review.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-readiness-review.md` | §§Findings and adjudication, Follow-up verdict; current owner: Desktop UI design specification; Architecture. | September 8 planning review passed after corrections; not production or hardware proof. |
| `desktop-ui-scaling-progress.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/desktop-ui-scaling-progress.md` | §§Settled implementation direction, Groups 1–6, Scaling campaign closeout, Settings follow-up; current owner: Desktop UI design specification; surface approvals; second-pass F8; Windows native validation. | Portable presentation evidence; September component scaling is historical and later second-pass F8 owns the approved root scaling rule. Per-group identities/capture qualifications remain in the snapshot. |
| `ui-parity.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/ui-parity.md` | §§Provenance and authority, Prompt 3B–4E, VPP-7 physical result, August 27/30 closeouts; current owner: Architecture; Desktop UI design and decision records; dated Product Parity audit. | Historical campaign classifications, source identities and synthetic evidence are recoverable, not current support claims. |
| `fullscreen-hdr-discovery-plan.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/fullscreen-hdr-discovery-plan.md` | §§Discovery result (October 9, 2026), Pinned-source pre-analysis, Completion criteria; current owner: Fullscreen HDR specification and implementation plan; discovery summary in this register. | Completed Win10 feasibility discovery; preserve exact build identities, predictions versus observations and untested cases below. |
| `windows-collaborative-acceptance-handoff.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/windows-collaborative-acceptance-handoff.md` | §§0–7, Target and setup, Safety, Finish; current owner: OSD/collection plan; startup/reentry and Player/Guide decisions; Windows native validation. | Old copy-ready prompt archived; its scenario, measurement and probe obligations remain open above. |
| `code-quality-refactor-planning-handoff.md` | `git show d15184831213dd6403ccb80da24a3ea17ffe088c:docs/code-quality-refactor-planning-handoff.md` | §§2–3, CQ-01–09, 6–8, 10, 12; current owner: Code-quality implementation plan §§3–4, 7–10; Architecture; native-player protocol. | Assessment rationale and confidence limits retained in full; F remains governed by the active implementation plan, not closed by this archive. |

The startup/reentry and Player/Guide polish plans are **retained**: their
October 7 decisions and approved render refinements uniquely record live product
contracts and supersessions. Their stale status headings are corrected rather
than deleting approval authority. Desktop design specification, surface approvals,
second-pass decisions, fullscreen HDR spec, the interface system, feature inputs
and validation findings are retained. The code-quality plan stays active for F.

The desktop execution snapshot preserves baseline
`d221efbb0aaaa7846be2d8666254fbd78bddc738`, Flutter 3.47.0
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` / Dart 3.13.0,
737 baseline tests, R1/R2/R3 adjudications and successive checkpoint results.
Its backup-before-migration, strict legacy reads, canonical source semantics,
cycle boundary, atomic stale-base checks and privacy contracts now live in
Architecture and the retained Desktop UI specification. Later approvals live in
surface approvals, second-pass and Player/Guide records; obsolete intermediate
review statuses do not override their later corrections. Scaling/parity snapshots
retain each capture/source identity and qualification in full, rather than
promoting all intermediate claims into a new baseline.

The HDR snapshot preserves target
`50c4e9d345209a1e504b2d9b8190ee4fe2a152b0`, trace
`a1dd26933d58aae8fd8cdbd4ec6a9e8ec9578768` (discovery-only, do not merge),
Windows SDK 10.0.26100.0, Windows 10 Home 10.0.19045,
NVIDIA RTX 5080 / driver 32.0.16.1714, Sony A90K HDMI 3840×2160/120 Hz.
Baseline EXE SHA-256
`A04B5A7BE5D8062FB7DCC81CCC47D59AECFEDBF442FBDC9D48E35570577E7389`,
trace EXE `02B1DB441E0FC3ACB8AC794158879B8866CB44DF54AD5DEB03BEDFC8D953A1F5`,
and probe `1C770E4FDBDAA2D981E1510B69FC9A8F858156D06429644E6883EA19AC88C907`
identify that run only. Existing composition qualitatively passed SDR/static HDR10;
no explicit renderer refresh or FP16 was needed. API route and timing tables,
operator observations versus pinned-source predictions, and omitted cases remain
recoverable in the full snapshot. Current identities come from build metadata and
runtime provenance, never these old pins.

The code-quality assessment snapshot preserves its inspected source, confidence
limits, CQ-01–09 mechanisms and rejected alternatives. Architecture and the active
implementation plan carry its distinct request/authorization/content/native
lifetimes, observed-versus-requested track state, persistence/publication/credential
ordering, manual occurrence identity and display late-write liability. The archive
adds no generic framework, schema migration, native rewrite or feature scope.
