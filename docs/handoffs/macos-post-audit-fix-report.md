# macOS post-audit fix round — 2026-10-18

Source: `platform/macos`; audited baseline `fa176087`, reviewed product candidate
`1b2f64f4eaf584807f70e668a5502ab088a54537`. The audit plan/report were committed
first as `3cf2cce7`. The latest product candidate is
`ffcaae6377bcdf16080ea742b40ff9960a580ed8`. Results for the earlier seven-fix
candidate and the `296ab905` transition mitigation retain their original source
and binary identities below.
No main merge, distribution release, signing changes or engine patch was made.

Status: **the application corrections are committed and independently reviewed.
Latest product `ffcaae63` passes all 1,857 local tests and completed Windows/Linux
CI. Its exact canonical Release passes the native retirement/key comparison,
exposes the accepted unlabeled `AXGroup`, receives real Slider value-change
callbacks and quits normally with zero AX/Flutter errors. Audit settings are
restored and no verification process remains. The matching baseline native
failure is now attributed to focus leaving both application key-handler paths.
M-04 and overall accessibility acceptance remain open for the existing human
checklist, retained-error/notification recovery, rejected-batch divergence and
historical node 866. No engine fix is included. Earlier results retain their
original source and binary identities below.**

## Original results (historical candidate identities)

| Item / commit | Root cause and correction | Regression / independent review | Real Release result |
| --- | --- | --- | --- |
| M-01 · `a652c236` | The fullscreen initial display hold requested a paused load, then resumed before readiness. mpv coalesced the pause notifications; Dart projected stale requested `startPaused=true` into Paused although native pause was false. Native readiness now carries its actual pause snapshot, consumed before Dart state projection. Toggle therefore uses observed state. L1/L2 join precision and pause/display policy are unchanged. | 53 transport tests and three core CTests, including missing-notification and genuinely paused readiness. Fresh review `01a150ad-4978-7353-8ab4-18686ac7bc61`: no material findings. | Fresh first-fullscreen tune showed Playing; K paused at a fixed position for 10.34 seconds, then resumed advancing playback. The subsequent manual step tune also played with correct state. |
| M-05 · `78cf5ecd` | Back/Escape consumed Settings' origin before Player entry could be rejected. One return action resolves unavailable Player to Guide and consumes origin only on accepted navigation. | 46 navigation tests, including expiry before/while Settings × button/Escape. Fresh review `01a150a7-9075-7b52-a52a-7b8e7465da30`: no material findings. | Timer countdown not repeated. Four real-coordinator timer-expiry widget cases establish the Back/Escape route contract. |
| Q-01 · `256f69cb` | Bare macOS builds omitted identity defines. Canonical build/run wrapper, CI and documented commands now supply Windows' pubspec version and numeric-build@full-HEAD defines; no runtime fallback. | Six build-wrapper tests; focused analysis. Fresh review `01a150a8-1507-7950-9c5b-592e88c70b17`: no material findings. | Technical details and copied export both showed `0.1.0` and `1@1b2f64f4eaf584807f70e668a5502ab088a54537`. The inspected export contained no observed credential/URL/private-path leak. |
| Q-02 · `47ca08e4` | Steps used the last committed channel during a pending tune. Each press now publishes/accumulates requested identity; only the target after a 250 ms quiet interval enters the serialized tune queue. | 30×150 ms burst, final-only load, pending/stale load, cancellation, reentrancy and paused program-boundary coverage. Fresh review `01a150a9-448a-7781-ae3f-6a59104e9c52` caught a stale preview/program issue; corrected and re-reviewed clean. | 30 native Page Down presses over 3.97 seconds advanced channel 1 to 31. Native load IDs advanced only 1→2, establishing final-only loading for this burst. Immediate per-press display behavior is covered by the regression. |
| Q-03 · `1b2f64f4` | Error presentation used committed selection while Retry used latest request. Error channel/program/Up next and subsequent surfing now use Retry's target. | 297 coordinator tests, including obsolete late failures, Retry and both surfing directions; 120 PlayerView tests. Fresh review `01a150ae-7c43-7840-b703-0f404ed44396` caught the surfing-origin inconsistency; corrected and re-reviewed clean. | Controlled obsolete-failure/new-error/Retry regressions pass. No new real offline run was attempted. |
| M-02 · `b512d612` | Search semantics merged a text-field role into the directory root, making macOS hide descendant controls as a text-field leaf. Search now owns a named semantics container. | Directory ancestry/actions regression; removing only the boundary fails. Fresh group review `01a150aa-dfa2-7221-b4dd-64711c978c50`: repair accepted. | Native directory tree exposed management/filter/row controls (22 buttons, 14 named row menus), replacing the audit’s search-only tree. Search still appeared as a bare native text field in the tool snapshot; spoken output remains a human check. |
| M-03 · `0fa2606e` | Tooltip-only icons populate tooltip semantics, while macOS AX names use the separate label. Explicit names match existing tooltip/spec names across the requested controls. | Four semantics tests; 274 affected widget tests. Fresh group review caught/restored the adaptive directory-menu icon; correction re-reviewed clean. | Native snapshots exposed Previous channel, Pause, Next channel, Lineup menu, Exit full screen, Guide Earlier/Later and directory action names. Studio rundown names have semantics-test evidence; spoken/native per-surface acceptance remains bounded by M-04. |
| M-04 · `296ab905`, bounded; open | A retained Tooltip can emit an unreachable node after its traversal origin is excluded; Flutter's common desktop bridge rejects it. TooltipVisibility now removes overlays at both shell menu exclusions and Player retirement. Permanently excluded content is not repaired. | [Stock repro, five-delta fixture, controls and source diagnosis](macos-ax-update-investigation.md). Five new behavioral regression cases; full 1,792-test suite, analysis and formatting passed. Fresh adversarial review accepted the bounded mitigation, retaining its static-tooltip limitation. | Visible Guide/menu and OSD/audio-options tooltip removal/restoration passed with zero AX errors. Subsequent cast-name hover reproduced the remaining static path: first removed-node error at line 24, node 268. General M-04 acceptance remains failed/open. |

## Original seven-fix candidate and checks

Release `lib/main.dart`, Flutter 3.47.7, accepted arm64 runtime; macOS 27.0.1.
Bundle manifest SHA-256: `d5417b6ae680ab203001791897321b053b6dd91c14818d71d160482eb900efce`.
Runtime BUILD-INFO SHA-256: `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.
Raw logs/screenshots/exports remain only in `/tmp/lineup-audit/`.

Final local checks: canonical formatting, analysis, **1,787 Dart tests**, all three
portable native CTests, and the real Release build passed. Portable/fake-boundary
tests establish contracts, not physical Windows media/presentation behavior.

Windows CI: [verification run 39163235848](https://github.com/TJZine/LineupDesktop/actions/runs/39163235848), **passed** (Dart verification and Windows build/native job).
Verification commit `685eec76645510e59bdbc9f3dc542be73e62ebb3` has exactly the
candidate's product source; its only difference is a temporary narrowed CI
workflow on `dev/macos-audit-verification`. It retains canonical Dart and Windows
build/native checks, adds affected Dart suites, and excludes release/package jobs.
The workflow was independently checked; no in-progress run was cancelled.

## Real-app evidence and remaining limit

The user completed Keychain approval, clearing the earlier runtime blocker.
The same built bundle/PID was used: no rebuild or product change occurred.
Private evidence is in `post-fix-first-*`, `post-fix-k-*`, `post-fix-paused-held.*`,
`post-fix-30-press-actions.json`, `post-fix-burst-*`, `post-fix-technical-details.txt`,
`post-fix-diagnostics-export.txt`, and `post-fix-*-ax.txt` under the local evidence
directory. The runtime summary records observed positions, native load IDs and
AX error counts without media labels. DVR was restored Off and native Quit
completed libmpv shutdown normally. No picture-quality reassessment was made.

The earlier M-04 candidate log lines 19–678 contain 373 pending-node and 241
removed-node messages. The later stock reduction reproduced the failure, including
a healthy native tree before the first rejected unreachable-tooltip update.
Runtime ownership is now established for that mechanism; the exact first
historical delta remains uncaptured. Counts may include stale error repeats.

The later mitigation candidate `296ab905` passed the standalone comparison,
regressions and targeted real Release transitions described above. It also
confirmed a remaining real cast-tooltip failure. See the linked investigation
and latest progress entry for the new candidate's Windows CI and full evidence.
No engine patch, speculative reset or upstream message was made. The human-only
checks below remain separate from the automated/native-tool evidence.

The mitigation's [Windows verification run 39170620921](https://github.com/TJZine/LineupDesktop/actions/runs/39170620921)
passed Dart verification, affected Windows UI suites, Windows compilation and eight
native/authenticated-reference CTests. Commit `159fd599aee9ab8c7074ca292e517116342d89b9`
has exactly product candidate `296ab905`'s inputs except for its narrowed workflow.
No active run was cancelled. The [GPT Pro review prompt](macos-post-audit-adversarial-review-prompt.md)
requests an independent review of the full fix round and the remaining cast/track
tooltip design question.

## First Pro review corrections — candidate `ac995ec5`

The user-approved follow-up contains six independently reviewed correction commits:

| Item / commit | Cause and correction | Regression and review | Final Release observation |
| --- | --- | --- | --- |
| M-03 · `3fed8fd7`, `ac995ec5` | Studio's clear-search icon lacked a label, then native verification showed its suffix topology hid it inside a text-field leaf. The named action is now a semantics sibling in the same trailing position; an empty suffix retains space and an owned focus node preserves search input. | Extended existing test checks label/action, root traversal with no text-field ancestor before/during hover, pointer and Tab+Enter clearing/focus. Old suffix fails ancestry check; Studio 79 passed. Fresh `studio_label_review_v2` and `studio_clear_topology_review`: no material findings. | On `ac995ec5`, macOS exposed the named button; native accessibility activation cleared the query and removed the button. Zero AX failures, draft discarded, normal Quit. Real Clear hover could not be performed because CUA coordinate operations returned `noWindowsAvailable`; opened-tooltip regression passed. |
| Focus · `4fdac1ab` | TooltipVisibility recreated implicit Guide button focus nodes. Six controls now have Guide-owned nodes; the shell rejects detached, removed or unfocusable invokers. | Eight full-shell regressions; parity 15 and Guide 63 passed. Fresh `focus_review_v2`: no material findings. | Later retained exact focus through menu open/close, both with and without a visible tooltip; Enter advanced the Guide by 30 minutes, without tuning. Verified by focus-ring/window screenshots, not the native container's focused-element field. |
| Mini Guide · `22073990` | Browse started from committed A while the visible failed or pending target was B. It now reuses presentation identity, without changing committed playback or Retry. | Coordinator 302 passed; old initializer fails both B regressions. Fresh `mini_guide_review_v2`: no material findings. | Failed-target/pending-preview behavior has controlled-boundary evidence; no induced real media failure or separate real Mini Guide acceptance claim. |
| M-04 static origins · `352a74aa` | Cast and track tooltips were inside permanent semantics exclusions. Their origins now remain reachable while canonical summary/row semantics own labels/actions. | Stock native Release controls passed before Lineup edits. Player 122 passed; all four opened-tooltip traversal regressions fail on the old structure. Fresh `static_review_v2`: no material findings. | Cast-name hover, menu exclusion/restoration, audio title hover/action, subtitle title and Off hover all produced zero AX failures. Native canonical row actions remained exposed. Actual cast-role data was unavailable; that path has widget/stock-native evidence only. Native track selection confirmation was not established. |
| M-04 Now origin · `d56a391b` | Sibling portal origins could merge into one annotated ancestor; one identifier was lost, leaving Now's overlay unreachable. An explicit outer semantics boundary keeps its origin separate. | Faithful stock native default rejects Show; corrected variant survives ten activations/updates. Two full-shell Now/Return-to-live regressions fail before and pass after. All 80 shell/Guide tests passed. Fresh `now_origin_review`: no material findings. | Healthy startup → Now hover → Return to live hover passed, then the remaining Guide/Player transitions above passed. Zero AX failures through normal Quit. |

The following full tooltip pass belongs to clean candidate `d56a391b`; it is
retained evidence, not relabeled as a run of the later Studio-only correction.
Its canonical Release build used version `0.1.0` and build
`1@d56a391b545d5d06fd967312023516ea5da25d06`; generated Dart defines were checked.
Flutter/framework `3.47.7` / `abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`, Dart `3.13.5`, macOS `27.0.1 (26A434)`,
arm64. The sorted relative-path/file-hash/symlink-target JSON manifest SHA-256 is
`d9c9ad25f4051df7eb5996ac3016be51051c053a199720a5eb9022977d180c8d`;
executable SHA-256 `71ecac5dca04d48c569ef261f62327fd1a82173c14703e21544f6bc06707bbe0`;
runtime BUILD-INFO SHA-256
`b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.
Private build records, complete manifest, AX snapshots, screenshots, runtime summary
and logs remain in `/tmp/lineup-audit/m04-final-origin-round/`. The final process
quit normally; the complete app log contains **zero AX update failure messages**.
No picture-quality reassessment or spoken VoiceOver check was made.

Full local canonical formatting, analysis and **1,807 macOS Dart tests passed**
on `d56a391b` and again after the Studio correction on `ac995ec5`.
Windows [run 39178150109](https://github.com/TJZine/LineupDesktop/actions/runs/39178150109)
passed **1,805 Linux tests**, **694 selected Windows Dart tests**, the stock-engine
Windows application build, and all eight selected native/reference CTests:
track-list encoder, playback state, core contract, codec conversion, display dynamic
range, display guardian, native player contract and authenticated reference.
Verification commit `1d98cf822ecf76fb10537b1ca6b069eaf586258c` is a direct child of
the product candidate; only its narrowed CI workflow differs. Live runs were checked
before dispatch; none was cancelled. These checks establish portable contracts and
compilation, not physical Windows media/accessibility acceptance.

Historical candidate `352a74aa` first rejected during a mixed Guide/menu/fullscreen
preflight (node 138); a fresh same-binary pass then isolated Now hover before any
menu. That led to the faithful shared-ancestor reduction and fifth fix. Bare
unannotated sibling models did not reproduce and are not positive controls.
The final clean pass verifies the known application triggers, not all historical
causes or general M-04 closure. Flutter's unreachable-update and retained-error
notification defects remain upstream candidates; no engine patch or issue was
published. See the [investigation](macos-ax-update-investigation.md) and updated
[fresh Pro review prompt](macos-post-audit-adversarial-review-prompt.md).

## Studio-only acceptance — `ac995ec5`

The clean canonical Release build uses `0.1.0` and
`1@ac995ec58c92ef491098f8a5afcc1da60cd65ad0`. Generated defines were verified.
Toolchain/host/runtime identities match the earlier tooltip run above. Bundle
manifest SHA-256: `b91f240ae6a59e4ac71cb1eb1013c0e92be05ace00998dd84f101f75a47b9e9f`;
executable SHA-256: `5a4bc9ecc9a51a0151c7aa462f8f3bde1525636cb6e380b87ed599c8c66d37d5`.
The 112-entry manifest, clean source record, build log, native AX captures, boundary
counts and runtime summary stay private in `/tmp/lineup-audit/m04-studio-final-round/`.
Only one Release app process was running. Named-button exposure and native
activation passed; the draft was discarded, Quit completed, and the complete
log has zero AX failures. A Guide Now activation/menu navigation smoke check also
passed. Cast/audio/subtitle/focus runtime evidence remains attributed to `d56a391b`;
those product sources were unchanged by the Studio correction. No fresh real
Clear-hover claim is made because the CUA pointer operation failed before input.

Latest [Windows run 39179621557](https://github.com/TJZine/LineupDesktop/actions/runs/39179621557)
passed both jobs: **1,805 Linux tests**, **694 selected Windows Dart tests**,
stock-engine Windows application compilation and all eight native/reference
CTests listed above. Verification commit `0cb331f6be11c02f877e9ebfffc39a16ce9bef74`
is a direct child of `ac995ec5`, differing only in its narrowed workflow.
No active run was cancelled. The final evidence review verified identities,
source equivalence, logs, native observations, privacy and links; no findings remained.

## Second Pro review corrections — candidate `d5e09e0a`

The second Pro review identified three defects addressed by two localized commits:

| Commit | Cause and correction | Regressions and independent review | Release / Windows verification |
| --- | --- | --- | --- |
| `1bacc5b5` | Before a deferred tune has a native load, observed stopped/retired-playing state cannot determine the pending toggle. That phase now uses pause intent and avoids unscoped native commands. Ready playback continues to use observed state. Button icon, tooltip and action name reuse the same decision as K. | Four before-fix failures cover completed/pending stop × one/two toggles. Added supersession from paused playback, ready-state authority during blocked persistence, sleep expiry, and K/button/icon/name agreement. Both playback suites: 432 passed. Fresh `pro_round2_adversarial` approved the complete seven-file round-two diff before either commit, with no material findings. | Windows CI passed. Release step + one K ended Paused with a stable position; step + two K ended Playing with advancing position. Exact Dart input phase and native AX names were not established in this run. |
| `d5e09e0a` | Guide Clear was hidden inside a native text-field leaf, and the enclosing field handler consumed Enter/NumpadEnter. A sibling action outside that scope preserves suffix space, density geometry, persistent focus and the TapRegion; clearing restores search focus. | Before-fix ancestry and keyboard regressions fail. Effective traversal before/during tooltip display, direct and F2 → Escape activation with both Enter keys, live input focus and no-tune assertions pass. Guide/parity: 81 passed; editable field navigation preserved. Same fresh combined review: no material findings. | Windows CI passed. Native name, real pointer hover, accessibility clearing and useful input focus passed. Initial Return/keypad/menu activation passed, then repeated key attempts became inconsistent; native keyboard acceptance remains open. |

Canonical formatting (152 files, zero changes), analysis and all **1,816 macOS
Dart tests passed**. The reviewed source diff SHA-256 is
`04894278b54133347b5fd59517ff9d2edc38cf0431c55afdfa55bca828583d7e`.
The clean Release build uses `0.1.0` and
`1@d5e09e0a53810c836e166d528a9224b8cfab0002`; generated defines were verified.
Toolchain, host and runtime BUILD-INFO identities match those recorded above.
Bundle manifest SHA-256:
`bda92d186246bc3a900cb93f006071f0d9c141fd7b20ead558d6417be556ece2`;
executable SHA-256:
`00f078611a400d1f44ccf0d03a6deab7dd415ffd0e1cc32f3a42712a641b56f4`.
Private logs/manifests and regression evidence stay in `/tmp/lineup-audit/pro-round2/`.

[Windows run 39183100595](https://github.com/TJZine/LineupDesktop/actions/runs/39183100595)
passed **1,814 Linux Dart tests**, **703 selected Windows Dart tests**, the
stock-engine Windows build and all eight selected native/reference CTests named
above. Verification `5877120d6fe87ca46f102a602ce9451a936ce697` is a direct child of
`d5e09e0a`, differing only in its isolated narrowed CI workflow. Live runs were
checked before dispatch; no active run was cancelled. These checks establish
portable behavior/contracts and compilation, not physical Windows acceptance.

On that clean Release binary, Guide Clear appeared as a separate named native
button. Actual pointer hover exposed its tooltip, accessibility activation cleared
the query, and immediate typing reused the live search input. Initial Return,
F2 → Escape → Return and keypad Enter activations cleared the query. Later repeated
keypad/menu and ordinary Return attempts left it unchanged, despite a visible
Clear focus ring; the native focused-element field reported the text field.
Command+A also failed to select the query during those later attempts. All these
Guide checks had zero AX failure messages. A temporary macOS full-shell probe with
the same no-match query passed 40 actual-Tab direct/menu Return/keypad activations
and Command+A after every retype. The discrepancy does not establish a new Dart
bug or a clean native pass: actual focus/event delivery remains unresolved.

The later sequence Settings → Playback → enable DVR → Back to Guide → select a
current program produced the first AX failure at the tune boundary (log line 4:
`866 will not be in the tree and is not the new root`). The native tree then
collapsed to the application/window skeleton. There were **574 failure messages**
through normal Quit; these are messages, not independent rejected updates, because
Flutter can retain an earlier error. The exact originating node/delta was not
captured, so this run cannot attribute a new Dart trigger or prove that earlier
mitigations caused it. See the updated [investigation](macos-ax-update-investigation.md).
M-04 remains open; no engine changes were made.

Visual Release checks continued after AX degradation. A Page Down + K call pair
completed in 23 ms and the final target showed Paused with a Play icon, remaining
at 43:39 across observations about 12 seconds apart. After resuming, Page Down +
K + K completed in 34 ms and the final target showed Playing with a Pause icon;
its position advanced 09:17 → 09:28. CUA completion times do not prove when Dart
handled each event or isolate the pre-load phase; the deterministic regressions
establish that phase-specific contract. No native AX-label acceptance is inferred
from these screenshots. DVR was restored to its original Off setting and normal
Quit ended the recorded process. No media quality or spoken VoiceOver test ran.
Private runtime summaries, boundary snapshots, screenshots and logs remain under
`/tmp/lineup-audit/pro-round2/`.

The independent final evidence review corroborated the committed diff, all 112
bundle entries, CI logs, native screenshots and AX message counts, and checked
privacy and local links. It found no actionable documentation issues while
retaining the unresolved runtime observations above.

## Third Pro review corrections — candidate `f2b76202`

| Commit | Root cause and correction | Regressions / independent review | Runtime limit |
| --- | --- | --- | --- |
| `f69ef69d` | During a pending step/save, current metadata represented resolved P while Up next used the requested channel's advancing wall clock, potentially showing R instead of Q. Both now share represented-program authority; an unresolved target still uses its own live preview. | A blocked-save, paused P → Q clock-boundary regression fails before the repair and passes after, before and after save release. Relevant preview/continuation/navigation coverage remains passing. Fresh `pro_round3_adversarial` approved all five changed Dart files before integration, with no material findings. | The exact blocked-persistence/clock sequence is controlled-boundary evidence; it was not induced in the authenticated app. |
| `e7d7f098` | Guide retained an obsolete opened-from-Player flag after sleep removed the surface. One Close/Escape now uses current availability and opens the existing usable menu immediately when Player is unavailable. | Both Close and Escape fail before the repair; after expiry they open the menu, disable Player, start no tune and allow keyboard navigation to Channels. All 48 navigation tests passed. Same fresh independent review approved this fix. | Real expiry and the first foreground Close opened a usable menu without tuning. A background AX activation with root focus did nothing; see the separate focus gap below. This uses the diagnostic Release, not the clean stock binary. |
| `f2b76202` | The retained Clear regression requested focus directly and did not establish traversal. It now uses actual Tab for matching/no-match queries and both Enter keys, directly and after F2 → Escape. | All 18 parity checks pass, including exact invoker restoration, useful live input and no tune. Same independent review approved the coverage change. | Twelve stock Release direct/menu Return/keypad activations passed; this is bounded evidence, not closure of every historical keyboard failure. |

Canonical formatting and analysis passed; affected suites passed **481 tests**, and
all **1,819 local macOS tests passed**. [Windows run 39188166189](https://github.com/TJZine/LineupDesktop/actions/runs/39188166189)
passed **1,817 Linux tests**, **706 selected Windows Dart tests**, the stock Windows
application build and all eight selected native/reference CTests named above.
Verification commit `86c589573f84bd505531731dc289627270bcb4b0` is a direct child of
`f2b76202`, differing only in its narrowed workflow. Live runs were checked before
dispatch and no active run was cancelled. These are contract/build checks, not
physical Windows acceptance.

The clean stock Release candidate was built with the canonical wrapper and
verified identity `0.1.0`, `1@f2b76202625215bd0bcc14aefd1911db49663932`.
Its 106-entry bundle manifest SHA-256 is
`ea8c97ebf139c3bbba022ca846bc97bccae9eed743be08705c1149fd7a977e17`;
executable SHA-256
`db2d9a16e0f5b2d11c0fd9510ed1bbd7969e8db941a036c98e936d93a2907067`.
The pinned Flutter, engine, host and runtime BUILD-INFO match the earlier round.
On this binary twelve actual-Tab Clear activations passed before synthetic
Command+A left the query unselected. These checks had zero AX error messages;
normal Quit ended the process. Raw evidence is private in
`/tmp/lineup-audit/pro-round3/`.

### Keyboard findings and limits

A separate temporary diagnostic Release build from `f2b76202` added pass-through
native event observations, existing FocusNode identity tracing and outgoing
semantics tracing, without an engine patch. Its V2 source patch SHA-256 is
`d4666d8c00c931c057543a2bee05b3a9a16d4b4aa5447e7177b92decba6c0a12`;
bundle manifest SHA-256
`1dc7ab0da42af4795dda31929afcd980ad2d7c4535ff42d8408082b02e5baafb`;
executable SHA-256
`12ce4509a24feda0cb6076795c3c0a3e555654947fe1c4d00fdd6054aa2a290f`.
This diagnostic binary is distinct from the clean stock Release above. Tracing
adds overhead and cannot turn a negative timing-sensitive probe into acceptance.

The captured rapid Tab → F2 → Escape → Return sequence reached Escape before the
menu acquired focus. Guide's Escape handler reopened/kept the menu; Return then
activated its Guide item. Clear focus was restored afterward, and no Clear callback
ran for that Return. A staged control observing the menu open/closed before Return
cleared successfully. This establishes an input/menu-focus interleaving, not a
settled Clear activation failure. Historical failures without event history remain
unclassified. Whether to make Escape dismiss an opening menu before focus transfer
is a separate interaction correction to consider; no speculative fix was added.

For synthetic Command+A, native V2 recorded the active key window and
FlutterTextInputPlugin responder. Injected flagsChanged used keyCode 0 (A), and A
had combined Command `0x100000` without the sided Meta bits. The pinned macOS
responder synchronizes sided modifier bits, so Dart received A with Meta false.
A fresh stock MaterialApp → Scaffold → TextField reproduced this: selection stayed
collapsed at 16, and replacement input appended to lengths 17/18. The problem
therefore reproduces without Lineup. This is an observed synthetic-event/Flutter
conversion compatibility condition, not proof of a physical Command+A defect.
Recommend correcting the automation input representation or reporting that
compatibility case; do not add a Lineup select-all workaround on this evidence.

The authenticated diagnostic Release was left in Guide with a confirmed real
30-minute timer. At `2026-10-19T03:01:40.104268Z`, the trace records Guide,
`playerState=stopped`, `playbackIntent=false`, `menuOpen=false` and no pending tune.
macOS locked before the next native UI capture. After user unlock, the first
background accessibility activation of Close Guide delivered a tap to live node
853 but left the menu closed. Flutter primary focus was its root, with no mounted
widget context; `_openAppMenuFromCurrentFocus` therefore had no invoker context.

After foregrounding the same process, one Close Guide activation opened the menu
at `03:39:37.128550Z`, with playback still stopped and no tune pending. Native AX
exposed Channels and Settings plus Player's unavailable hint; Settings navigation
worked. Thus the foreground sleep-expiry destination correction passes this real
check, but background/root-focus AX activation is a separate remaining Dart focus
gap. It predates this round's correction: the existing no-playback Guide-close path
also depended on current primary focus. Recommend an explicit stable Close Guide
invoker context/focus anchor, with a root-focus semantics-action regression, in a
follow-up rather than treating this as another bridge rejection.

DVR's native switch was restored to Off. Normal Quit ended PID 3618, and the log
records completed libmpv shutdown. The final log has 494 AX failure messages,
including possible retained-error repeats; later populated snapshots do not prove
notification recovery. Exact captures and selected facts remain private in
`trace/timer-runtime-result.json`. The blocked-persistence metadata sequence above
remains controlled-boundary evidence, not a claimed real-app reproduction.

### AX findings and remaining acceptance

The diagnostic V2 process had healthy AX through keyboard checks, then Settings →
Playback → DVR On → Back Guide → current-program tune produced its first error
at line 791, node 378. The immediately preceding outgoing batch 671 introduces a
new full-window empty portal leaf, physically attached at `0 → 1 → 378`, with no
matching origin; effective traversal remains `0 → 1 → 2 → 3 → 12`. This is a
shared-process history, not a fresh-process AX-only run. A stock continuous Slider
mounted under zero-opacity FadeTransition reproduces the same topology and native
unknown-node error; mounting it visibly is healthy. The hidden/visible result also
repeats in a separate uninstrumented stock app with an unchanged native runner. See the
[investigation](macos-ax-update-investigation.md) for controls, portable evidence,
source ownership and recommended follow-up. This narrows the newly captured
production failure; it does not retroactively identify historical node 866.

The native debugger's optimized-frame return probes were not validated and are
excluded from conclusions. Repeated bridge messages remain message counts, not
independent failures or proof of notification recovery. M-04 remains open; engine
changes and upstream publication remain outside this round. Standalone sources
and the sanitized graph fixture are separately committed as `68bdc662`, following
fresh adversarial review; that commit changes no product/build inputs. A second
fresh adversarial reviewer checked the complete latest source range, repros and
final evidence, finding no additional issues in the reviewed fixes or evidence.
It corroborated the timer-stop record and the post-unlock foreground/menu result,
and confirmed that the documented root-focus anchor gap predates this correction.
That application gap remains open alongside the runtime verification limits.

## Fourth Pro report: adjudication and application corrections

The newly supplied report was read and adjudicated against current source and
retained evidence before edits. Its five findings are accepted with these bounds:

| Finding | Decision and owner |
| --- | --- |
| P1 excluded Slider portal | Established stock framework/common-desktop-bridge failure. Production correlation remains strong, without exact widget-instance identity. M-04 stays open. |
| P1 retained AXTree error and notification recovery | Pinned source confirms both ignored `Unserialize` results and early-return event/clearing paths. Native notification recovery remains unverified; engine correction is outside scope. |
| P2 ready direct tune / blocked selection save | Application defect confirmed: production saves before publishing, while the older blocking helper publishes first. Fixed using the existing requested identity model and a real-store gate. |
| P2 rapid Escape / opening menu | Application defect under the existing top-overlay Back contract, not an unresolved design choice. Fixed in the shell's existing Guide decision. |
| P2 context-null Close / stale availability | Application-owned invocation/timing defects, distinct from AX rejection and the removed origin flag. Fixed with an explicit Close anchor and live availability. |

No new defect was established in the retained observed-pause correction,
pending-intent toggle, step serialization, existing represented-program successor,
Clear topology, persistent focus or feature-preserving tooltip repairs. Synthetic
Command+A remains a compatibility condition between the captured event shape and
the pinned embedder; no application select-all workaround was added. Duplicate
spoken tooltip information remains a human speech question, not a demonstrated
duplicate announcement. Earlier positive failures and original binary identities
are preserved above.

| Commit | Correction and regression evidence | Independent review |
| --- | --- | --- |
| `1a3cf7d3` | Direct tuning uses its requested identity before persistence, preserving step precedence/error/orphan behavior. Tune identity/overlay are coherent before display-hold retirement notifies. Actual store-gated tests retain committed A while current/next/Mini Guide present ready B, then check success, paused P/next Q, supersession and failed-save Retry. Four new regressions fail original source for stale identity/overlay. | Fresh `01a15281-65ac-7a00-a046-dbb6477ecc2d`: no material findings. |
| `ca07e41c` | Close supplies its own mounted context/persistent node; keyboard retains its actual surviving invoker with a Guide fallback. The shell reads current availability. Corrected root-focus CURRENT-node semantics tap and Close/Escape before rebuild all fail original source at the missing-menu assertions, then pass. | Fresh `01a15281-6b19-7962-9314-b4d5ad33bb41`: no material findings, including actual visual-fixture callback migration. |
| `459fd726` | Existing/opening menu dismissal wins before Guide route selection. Real-Tab tests distinguish direct, settled and no-frame opening-menu timing for both Enter keys and matching/no-match queries, exact restoration, one clear, useful input and no tune. Both new opening variants fail original source, then pass; settled coverage remains. | Same fresh Guide review covers the coherent routing change before integration. |

The first root/live test attempt failed harness setup (root request descended to
remembered focus; a tooltip finder was cast as IconButton; semantics cleanup ran
too late). Those failures are excluded from product evidence. Corrected controls
use `requestScopeFocus`, the actual button, and in-test handle disposal. Corrected
affected suites passed **454 tests**; canonical formatting, analysis and all
**1,830 local macOS tests** passed. Logs stay private under
`/tmp/lineup-audit/pro-round4/`.

[Windows/Linux run 39201999751](https://github.com/TJZine/LineupDesktop/actions/runs/39201999751)
passed **1,828 Linux tests**, **717 selected Windows Dart tests**, the stock Windows
application build and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract` and `authenticated_reference`.
Verification `3ba32122ffad843c037e58c87ab2340e9f7e2e94` is the direct
child of product `459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`, differing only in its
narrowed verification workflow. Live runs were checked first; no run was cancelled.
The completed logs and source identity were inspected. These are portable/build
and controlled native/reference results, not physical Windows acceptance.

### Canonical Release observations — `459fd726`

Built with `dart tool/macos/build_app.dart build --release`, pinned Flutter 3.47.7 /
Dart 3.13.5, unchanged framework/engine and arm64 macOS 27.0.1 (26A434).
Bundle version/build is `0.1.0` / `1`; its AOT binary contains canonical Dart identity
`1@459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`. The 106-entry bundle manifest SHA-256
is `cdb224d18a06897dcf1f1341461d0ead53b5ae7856adc3ed62410e10025861fe`, executable
SHA-256 `db8348d9c21acf0d2a8ef14d8f3b1d067251d293803cc0d52ac340b0e47306c7`.
Runtime BUILD-INFO SHA-256 remains
`b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.

The user cleared the current Keychain prompt; startup then completed. One live
native AX Close in stopped Guide opened the usable menu with Player unavailable;
Tab/Return reached Channels. Four actual-Tab rapid F2/Escape/Clear sequences
passed: Return and keypad Enter, matching and no-match synthetic queries. Search
cleared and retained a usable live input connection. A normal direct tune then
opened Player and Mini Guide represented the same channel as watching. No blocked
store was induced in the real application. Normal Quit ended the exact Release
process; no test timer or altered DVR setting was left behind.

These are bounded native observations. They do not establish the exact Flutter
root-focus condition or absence of an intervening OS frame; controlled widget
regressions establish those cases. No new product outgoing trace or complete
stderr capture was taken, so this sequence carries no zero-AX-error or native
notification-recovery claim. Physical keyboard and spoken/window acceptance remain
in the single checklist below. The old failed background Close remains recorded.

### M-04 experiment and second opinion

No Lineup Slider patch was chosen. The isolated finite-height comparison in
[`slider_containment.dart`](../../tool/macos/ax-tooltip-repro/slider_containment.dart)
reproduces default hidden-mount AX rejection after a healthy baseline, with a
healthy fresh visible control. Local `Overlay.wrap` controls logged zero errors
for the bounded hidden/visible, fade, exclusion/value-update/restoration, rapid
reversal and removal sequences recorded in the
[README](../../tool/macos/ax-tooltip-repro/README.md#local-slider-overlay-containment-comparison).
It uses stock widgets/framework/engine with native stderr redirection only.
This is distinct from earlier uninstrumented controls, and not complete mitigation
evidence: outgoing graph, direct notifications, keyboard/drag/focus/geometry,
menu/route/DVR transitions and integrated acceptance remain unverified.
The [Opus 5.5 handoff](macos-m04-opus-review-handoff.md) retains the hypothesis,
controls, uncertainty and requested independent challenge. M-04 and overall
accessibility acceptance remain open; no engine change or upstream publication.
The retained experiment/evidence was independently reviewed in fresh read-only
chat `01a15289-3744-77d1-a477-b4032e9eb694` before commit `c6d18864`; source,
native logs, hashes and chronology matched, with no material findings. That
review did not establish the unverified acceptance conditions above.

## M-04 containment implementation after Opus review

Product **`5c6349d4cf43244da9989fb72f298ac2acb614b0`** implements the mitigation.
The supplied Opus handoff was adjudicated against current source and the retained
scratch evidence. The user explicitly approved Gate A: keep the Slider in an
unlabeled group after the OSD controls. The implementation wraps only the existing
SliderTheme/Slider in `Overlay.wrap(clipBehavior: Clip.none)`. The progress container,
visible indicator, progress semantics, theme, callbacks and AnimatedSwitcher
retirement wrapper are unchanged. No lifetime gating, broad semantics override,
tooltip policy change or engine patch is included.

The new recorder forwards every argument of the pinned outgoing semantics API.
Its structural replay models the common bridge prepass and parent-first ordering,
recursive destruction, pending-child initialization and unknown-node checks. It
samples two opposing sorted seed orders and flags unsupported disagreements; it
does not exhaust native unordered-map permutations or model native roles, caches,
events, notification delivery or recovery. The harness uses real PlayerView and
the shell-equivalent ModalBarrier/focus/exclusion structure, with forced Dart
semantics and fake time. These limits are not native AX acceptance.

The final original-source control passes **4** tests and fails **13** as expected:
eleven first unknown-node transition failures, one pending-child menu-restoration
failure and one failure of the newly approved group/order contract. Required entry,
retirement, resize-while-excluded and menu-during-entry controls expose the first
unknown-node error. Earlier baseline artifacts masked the resize error behind a
missing-Slider assertion; the diagnostic assertion was moved earlier and distinct
final before/after logs retained. The corrected structure passes **17 focused
tests**, including the approved emitted group/order, hit testing, keyboard/drag
seeking, menu isolation/state survival and hidden noninteraction. **198 existing
affected tests** also pass, with canonical format/analysis clean.

The full local suite passed **1,847 tests** on the same product and approved
structure assertions. After the diagnostic-only assertion reorder, the final
17-test file and its analysis/format checks passed again; the full suite was not
repeated for that assertion-order correction. Raw logs, exact source hashes and
`final-diagnostic-evidence.json` remain local under
`/tmp/lineup-audit/m04-containment-implementation/`.

The independent native retirement discriminator also starts from healthy native
AX with a visible Slider. Default retirement produces a new unknown-node error;
the contained fresh process retires/restores, updates native values and reverses
mid-fade with zero AX error messages through Quit. Native runners redirect stderr
only; source and binary hashes are in the
[README](../../tool/macos/ax-tooltip-repro/README.md#slider-retirement-remount-discriminator).
This supports that bounded stock-widget mechanism without identifying historical
production node 866 or establishing native notifications/spoken behavior.

The investigation retains the rejected-batch divergence refinement narrowly:
this unknown-node failure occurs in preflight, but other AXTree failures can occur
after mutation. The separate retained-error/event-delivery defect remains open;
correcting one trigger does not establish recovery after an earlier rejection.
M-04 and overall accessibility acceptance remain open.

Fresh independent read-only review chat
`01a15549-f33f-79e0-a782-03c26f736941` challenged the recorder/model, exact negative
controls, other OSD destinations, interaction/paint/focus and common Windows
bridge implications. It found no remaining material issues after the S5 evidence
correction, and verified the final source/log identities before integration.
The full suite passed on the same product and approved structure assertions;
the final targeted rerun covers the diagnostic-only assertion reorder.

The canonical Release wrapper built `5c6349d4`, version/build `0.1.0` / `1`, with
full Dart identity `1@5c6349d4cf43244da9989fb72f298ac2acb614b0` present in AOT.
The 106-entry bundle manifest SHA-256 is
`681337fe95702d9113cead06a24e554494a020061c35b8be8d666e955dbf01c8`;
executable SHA-256
`43fe0b049a0da44b6c1bd2efd35266d18c5e32ade093d07d4b88d8f4175f9496`;
App.framework SHA-256
`c2b65189429b5b9924ffb48cc65a09b781fb0fea4e3ae3d8fd7bb7c88f0835b0`.
Pinned Flutter/framework/engine, arm64 macOS 27.0.1 (26A434) and runtime BUILD-INFO
SHA-256 `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`
are unchanged. The user cleared the current Keychain prompt; later fresh
processes of the same binary started without another prompt.

[Windows/Linux run 39300402918](https://github.com/TJZine/LineupDesktop/actions/runs/39300402918)
passed **1,845 Linux tests**, **734 selected Windows Dart tests**, the stock
Windows application build and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract` and `authenticated_reference`.
Verification `865c5c3a71981fe17f9312fdf02ee2eb4c464d20` is a direct
child of product `5c6349d4`, differing only in its isolated narrowed workflow.
The new Slider semantics regression is explicitly included in Windows selection.
Live runs were checked first, and no active run was cancelled. Completed logs and
the source identity were inspected. These are portable/build and controlled
native/reference checks, not physical Windows AX or playback acceptance.

### Fresh native Release checks — `5c6349d4`

Each process began in Guide with healthy native AX before its trigger, without a
forced Dart semantics handle. The unchanged runner's existing presentation log
flag was enabled for window facts; stdout/stderr were captured privately.

| Fresh process | Observation through normal Quit |
| --- | --- |
| Entry | Actual DVR On in Settings → Guide → tune exposes native Slider; visible OSD traversal places it after the controls. Zero AXTree error messages. |
| Retirement | Tune → visible OSD/Slider → Escape removes the OSD and native Slider → Return restores both. Zero AXTree error messages. |
| Menu and resize | Visible OSD → live Lineup menu excludes Player → native window zoom resizes the actual outer window from 800×632 to 1728×1084 while the menu remains open → Escape/Return restores Slider. Original window size restored. Zero AXTree error messages. |
| Rapid show/menu | After a real tune/dismissal, Return shows OSD and the freshly observed live menu control opens its usable menu. Zero AXTree error messages. Observation finished at 965 ms and click completed at 989 ms after show; the ordinary fade is 350 ms, so **this does not establish menu opening during entry**. |

The resize sequence proves an actual window resize while the menu excludes
Player, not a live pointer-drag resize or continuous OSD lifetime during the menu;
the auto-hide timer could run. Exact S5/S6 frame/lifetime interleavings remain
controlled outgoing-update evidence. CUA's native traversal confirms Slider after
the controls but does not independently expose the bare group's AXRole.
Accessibility Inspector bound to the exact process, but no target element was
selected: the CUA screenshot was an unusable transformed thumbnail for pointer
geometry. Therefore native group-role extraction and spoken group/order behavior
remain acceptance steps; no additional label was invented.

All four logs contain zero Flutter `[ERROR:]` messages and no native shutdown
timeout message. This is bounded log/tree/action evidence, not direct observation
of every `Unserialize` result or notification delivery/recovery. The starting
channel, original window size and DVR Off were restored; no timer, debugger,
Inspector or test app remains running. Raw logs, per-process result manifests,
exact bundle identity and `native-summary.json` stay private under
`/tmp/lineup-audit/m04-containment-implementation/`. The single final human
checklist remains below. M-04, retained-error recovery, rejected-batch divergence
and historical node 866 remain open.

## M-04 follow-up: visible Slider interactivity

The second Opus report exposed a containment regression on `5c6349d4`: changing
a visible Slider between enabled and disabled replaces its unlabeled semantics
group but does not resend its empty grafted portal leaf. The controller
independently reproduced the missing-record batch in pinned Dart tests. The
bridge's removal prepass can destroy the old leaf, then its main Release update
references that leaf without initializing it. This is distinct from the earlier
unreachable-node error during preflight.

Reviewed product **`8105f73c9b5891e880d9fa292f0b26d679238a41`** derives one
`sliderInteractive` boolean for both `onChanged` and `ValueKey` on the local
Overlay. A flip remounts Slider/portal together. Same-interactivity value/max
updates and menu exclusion retain state; the 40-pixel container, separate visible
indicator, callbacks, retirement wrapper and approved unlabeled enabled group
after the controls remain intact. No new label, lifetime state machine or engine
patch was added.

Five new tests independently start healthy and cover duration disappearing,
duration arriving, unsupported/restoration, focus loss/disabled noninteraction,
reenabled Tab/Right seeking, same-interactivity state retention and active-drag
cancellation. Identical test source passes **17/fails 5** on `5c6349d4`/`7a496450`,
with every new case first rejecting the intended absent reparented-child record;
the fix passes **22/22**. Existing PlayerView tests pass **123/123**. The final
local suite passes **1,852 tests**, canonical format reports **159 files/0 changed**,
and analysis is clean. On historical `459fd726`, the five added cases have no
replay rejection: two pass, while three later fail only the newer approved group
assertion. Do not report five complete historical passes or reuse the old 4/-13
baseline as a run of this revised harness.

Fresh independent read-only reviewer `01a155a7-84ee-7641-b56d-fceb695328e3`
checked source, before/after logs, focus/gesture consequences, stock discriminator
and exact artifact hashes before integration. No material issue remained. Its
review did not execute native actions or establish full accessibility acceptance.

The report's broad statement that all "reparented" failures occur after mutation
is rejected: the pinned engine's `ComputePendingChangesToNode` can reject with
"not marked for destruction, would be reparented" before `UpdateNode`. Completion
failures such as `Nodes left pending` occur after node updates. A removal prepass
may itself fail preflight without destroying anything; a successful removal can
already have destroyed moved subtrees. The retained error can make the bridge
return even after a successful prepass, before consuming/clearing pending updates.
There is no established full resynchronization or notification recovery for the
surviving bridge/tree instance. Replay's absent-record guard rejects earlier
than native Release and does not simulate partial mutation.

### Controlled stock native comparison

The committed `slider_interactivity.dart` uses stock widgets and the same local
progress-overlay structure, without Lineup imports, forced semantics, tracing or
native-runner modifications. All four Release processes began with healthy
native AX and Slider 50%; stdout/stderr were captured by the launching shell.

| Fresh process | Observation through normal Quit |
| --- | --- |
| Unkeyed, initially enabled | Disable → first `Nodes left pending by the update: 12`; one AX error message. Quit after rejection. |
| Unkeyed, initially disabled | Enable → same first pending-node error; one AX error message. Quit after rejection. |
| Keyed, initially enabled | Disable → value 60% → Enable → value 70%. Zero AX/Flutter error messages. |
| Keyed, initially disabled | Enable → value 60%. Zero AX/Flutter error messages. |

Exact source/binary hashes and controls are in the
[repro README](../../tool/macos/ax-tooltip-repro/README.md#visible-slider-interactivity-discriminator).
All four share the pinned stock engine and the same nonfatal sandbox-extension
launch warning; neither error-free controls nor populated native values establish
notification delivery/recovery or spoken behavior.

The actual `5c6349d4` production baseline also ran healthy DVR Slider → the OSD's
Next channel → visible Slider, with zero AX errors through cleanup and Quit.
No enabled/disabled flip was observed. This does not reproduce the report's
predicted production failure or refute the controlled transition. Source shows
the condition can change, but every channel change need not expose it.

### Exact follow-up Release and CI

Canonical Release built product `8105f73c`, version/build `0.1.0` / `1`, with AOT
identity `1@8105f73c9b5891e880d9fa292f0b26d679238a41`. Executable SHA-256:
`b8a5f25b95b650d8714119b66efc38e0d4980f6476c1ee34b6b8b0a873b8ea6d`;
App.framework `fd606f666077872ed44aaf350c77a3fcfca1e8927f891cd0e72f13634902acf8`.
The 106-entry bundle manifest SHA-256 is
`14da8ccdc19c274c11d38d351ebf38e41ba6415b71b76d9aee842bf56a65fbb6`
(compact JSON mapping relative paths to hashes, sorted keys, UTF-8, no trailing
newline). Runtime BUILD-INFO SHA-256 remains
`b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`;
pinned framework/engine, arm64 and macOS 27.0.1 (26A434) are unchanged.

The user cleared this binary's new Keychain prompt. Two fresh processes began
with healthy native AX in Guide, without a forced Dart semantics handle:

| Final product process | Observation through normal Quit |
| --- | --- |
| Entry and Next channel | DVR On in Settings → Guide → tune exposes native Slider → actual OSD Next channel → native Slider after tuning. Zero AX/Flutter errors; no enabled/disabled flip was directly observed. |
| Untimed Now Playing/menu/resize | Tune the starting channel → I opens Now Playing (its Close collapse control and Slider are present) → live menu excludes Slider → native window zoom changes 800×632 to 1728×1084 while menu remains open → Escape restores Slider and Now Playing Close → zoom restores 800×632. Zero AX/Flutter errors. |

`showNowPlaying()` uses `timed: false`; this avoids the earlier timed-OSD auto-hide
confound for this bounded resize check. It does not directly inspect hidden
widget identity or establish the exact timed-OSD lifetime/first-entry interleaving,
native group role, notifications or spoken behavior.

During cleanup after collapsing Now Playing, synthetic Escape/Return/F2 did not
expose controls. Native AX then showed the video-only Player without overlay
controls; a native Player-container click restored OSD, and live menu/Settings
actions worked. This is an unclassified input/focus observation, not established
AXTree loss or a regression attributable to the interactivity fix. No AX/Flutter
error or exception was logged. `resolvePlayerKey` maps these keys to Guide/OSD
actions, so the synthetic no-ops remain unexplained; the sparse tree only
describes the absent overlay controls. Physical focus/input acceptance remains in the
existing checklist. DVR Off, starting channel and original window size were
restored; both processes ended normally, with no native shutdown timeout, and no
verification app/Inspector/SecurityAgent remained running at final inspection.

[CI run 39312611152](https://github.com/TJZine/LineupDesktop/actions/runs/39312611152)
passed **1,850 Linux tests**, **739 selected Windows Dart tests**, the stock
Windows build and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract`, `authenticated_reference`. Verification
`6e7112e20583e65afb81023dd8e9bbf14793354a` is the exact product's direct child
differing only in the isolated workflow. The updated Slider suite is explicitly
selected on Windows. The successful head, parent relationship, workflow-only
diff and completed logs were inspected. Live runs were checked before dispatch;
no active run was cancelled. CI does not establish physical Windows AX/playback.

Raw follow-up artifacts stay private under
`/tmp/lineup-audit/m04-interactivity-followup/`: worker before/after logs and
source hashes, full tests/format/analysis, `stock-native-summary.json`, preserved
stock bundles, production baseline log/result, two final production logs and
`native-final-summary.json`, `release-identity.json`, bundle manifest, build log,
CI identity, full logs and final checks. M-04, overall accessibility acceptance,
native group/spoken/delivery gaps, exact timed-OSD entry/menu/lifetime limits,
the unclassified cleanup input/focus observation, retained-error recovery,
rejected-batch divergence and node 866 remain open. The single human checklist
below is retained.

## Third Opus follow-up — no new application defect

The returned review inspected `871c7a3c`, documentation-only over product
`8105f73c`, with all four source hashes matching the packet. Its final verdict
accepts the bounded mitigation and keeps M-04/overall accessibility acceptance
open. The controller checked its claims against current source and scratch
artifacts before making this documentation-only update. No new application fix,
engine patch or permanent regression was warranted.

### Corroborating evidence and limits

The controller exported `871c7a3c` into a disposable copy and reran the supplied
ported and sweep sources with pinned Flutter 3.47.7, forced Dart semantics and
fake time: **29 scratch probes completed** (11 ported, nine environment and nine
combined-flip probes). Their printed results were explicitly parsed: all reported
replay errors were null, all nine environment cases retained Slider State, and
all nine combined-flip cases reported no exception. Runner success alone was not
used as proof, since these sources principally print exploratory observations.

The environment inputs cover text scale, accessibility flags, dispatcher
brightness/locale, pixel ratio and simulated lifecycle. This does not establish
effective German localization, a full dark-theme comparison or native lifecycle
acceptance. Combined cases cover menu-open/close flips, retirement, first entry,
hover, coalesced flips, resize, Now Playing and disabled DVR insertion/removal.
These are additional scratch observations, not 29 new retained tests or a new
full-suite count. The unchanged 22 focused/1,852 full local results and final
native/CI evidence above remain attributed to their original runs.

Opus also reported its own 22-test rerun and focus experiments. It could not
replay the exact real-shell Now Playing sequence because its shell fixture had
no current program. Its successful plain-Player and simpler real-shell focus
checks do not reproduce or resolve the native cleanup observation. The controller
inspected the focus appendix/source but did not rerun that appendix or launch a
new native process for this adjudication. Local scratch sources are under
`/tmp/lineup-audit/opus-m04-round3/`; controller outputs, parsed facts and hashes
are under `/tmp/lineup-audit/m04-opus-round3-adjudication/`.

### Adjudication of recommendations

| Claim/recommendation | Disposition and evidence |
| --- | --- |
| No new defect in the interactivity fix | Accept within the reviewed scope. Observed: the key matches `onChanged`, Slider max remains positive, unchanged product hashes, and the corroborating scratch results. This is not exhaustive runtime acceptance. |
| Root-scope focus explains the cleanup keys | Needs validation. Observed pinned source clears detached primary focus and falls back to `rootScope` only if neither current nor pending replacement focus exists after autofocus processing. That is a plausible mechanism, not a captured cause; Opus's final experiments did not trigger it. Its intermediate claim to have explained the bug is not accepted. |
| Command-comma versus Escape conclusively classifies the issue | Accept with modification as a discriminator, not a binary diagnosis. Observed: MainMenu.xib → AppDelegate.openSettings → `lineup/app_menu` → shell Settings bypasses Flutter focus dispatch, while retaining mounted/setup/modal/navigation guards. One chord working establishes that path at that moment; it does not prove Escape delivery or the exact Flutter focus. Both failing does not by itself prove no events were delivered. Capture actual key delivery and focus alongside the native key-window/application state when the observation recurs. |
| Native group role, notification delivery and spoken acceptance | Accept as remaining evidence gaps. A role dump can establish role, an observer can establish healthy notification delivery, and spoken checks establish announcement/order. None substitutes for the others or proves recovery after rejection. No such new native evidence was obtained in this review. |
| More exact native entry/menu timing or forced production flip | No additional product change justified. Stock controls and Dart cases support the bounded mitigation. The native cases remain unverified where already recorded; no standing requirement is marked passed or silently waived. |
| Promote combined scratch flips to retained regressions | Defer. No new defect or additional discriminating before-fix failure was demonstrated. Existing interactivity regressions remain intact; scratch observations are retained locally. |
| Engine and historical claims | Accept with the existing calibration: preflight and completion failures differ; a successful prepass can mutate separately; retained-error claims apply to the surviving bridge/tree instance. Full recovery remains unverified and node 866 remains unattributed. |

The highest-value remaining input observation is a capture at the actual failure,
not a speculative focus workaround. Existing native role/delivery/spoken gaps and
the one final human checklist remain open. No new user checklist was created.

## Native role/delivery and Player focus closeout

The user's explicit native follow-up ran on the exact unmodified `8105f73c`
Release after all 106 bundle hashes matched its recorded identity. The passive,
PID-scoped Swift helper used AX attribute reads and real AXObserver registrations;
it changes no UI attributes/events and received existing accessibility trust
without a new grant. All app actions remain separate from this observer.

**Native group role:** Slider's direct parent is `AXGroup`, with successfully
read empty String title, description and value. Its exposed native child list is
`[AXSlider]`; the empty portal leaf is not exposed as a native child. This is an
actual native role/empty-text observation, not an inference from Flutter semantics.
It does not establish spoken group usefulness or announcement/order acceptance.

**Healthy notification delivery:** explicit successful value-change subscriptions
on discovered Slider elements received three real `AXValueChanged` callbacks in
two streams in the same native process, with callback-time values 22%, 31%, 33%.
CFEqual identity tied each receipt to a discovered Slider with successful
registration; application focus notifications and aggregate callback counts were
not counted as Slider value receipts. These are bounded delivery observations,
not every-update coverage, event-payload values, separate-process repetitions,
VoiceOver output or recovery after rejection. The unchanged app quit normally
with zero AX/Flutter error messages.

Raw typed-role snapshots, observer streams, helper source/binary hashes and the
parsed `native-role-notification-summary.json` are local under
`/tmp/lineup-audit/m04-native-closeout/`. Helper review
`01a155a7-84ee-7641-b56d-fceb695328e3` checked API attribution/privacy and limits.
Read failures, unsupported attributes, traversal limits or failed subscriptions
cannot be interpreted as proof of absent elements/focus/events. The helper's
native AX focus is not Flutter FocusManager state or key-delivery evidence.

### Reproduced application focus defect

The separate real-shell probe supplies the schedule/current program absent from
the earlier Opus fixture and uses the actual shell-owned coordinator/tune path.
Keyboard Escape closes the Lineup menu and restores its invoker after menu
ExcludeFocus has removed Player from remembered focus history. Pointer Close
collapse, or Escape collapse followed by video hover, allows timed OSD hide.
Retiring/remounting its focused control then leaves focus on the modal-route
scope above both Player and shell key handlers. HardwareKeyboard receives
Enter/Escape/F2 but neither handler routes them. This is a demonstrated Dart
application defect, not the unproven rootScope hypothesis.

The same final scratch source at 800×632 and 1600×1000 yields eight passing
controls/twelve intended key failures on current `8105f73c`, `5c6349d4` and
`459fd726`. It predates both Slider changes. Pointer menu dismissal preserves
Player focus and keys; Escape collapse with no pointer activity intentionally
keeps keyboard auto-hide suspension, so it is not a failing hidden-state case.
An adjacent menu-restored Slider disable retains Player routing and needs no
broader focus reset.

Product **`ffcaae6377bcdf16080ea742b40ff9960a580ed8`** transfers focus to the
existing root before actual OSD → none retirement only when the focused control
belongs to this Player, its root still owns and can request focus, the app is
active and the modal route is current. No new focus wrapper, arbitrary-update
reset, UI/semantics departure, invoker policy change or engine patch was added.
Identical final retained tests first pass **3/fail 2** for delivered-key behavior
on `8105f73c`, then pass **5/5**; they independently exercise Enter/Escape/F2 and
protect menu/modal/background ownership. Existing affected suites pass **196**
including all **22** Slider semantics tests. All **1,857** local tests pass;
canonical format reports **160 files/0 changed**, and analysis is clean. Fresh
read-only reviewer `01a155dc-e8de-7520-9c70-e19f6be5a9bf` checked exact source,
negative controls and ownership/lifecycle guards before integration, finding no
material issue. Private source/log identities are in
`focus-investigation/implementation/summary.json` under the native-closeout root.

### Final canonical Release and CI verification

The exact `ffcaae63` canonical Release is built, AOT identity
`1@ffcaae6377bcdf16080ea742b40ff9960a580ed8`, version/build `0.1.0` / `1`.
Executable SHA-256 is
`f80598ce711746192e1c3811c5a6a7c3ba7b1368554ec1b396e029993b66edda`;
App.framework `2d32192b440a7de131f06b655db6320cdf57e0b02a80799696d96861f9b6c0ed`;
106-entry compact sorted JSON bundle-manifest SHA-256
`9da64b5b3f99c1e5c53c7a84bd81db7c1dbce1658618139e5da10d95d5d0527a`.
Pinned engine and runtime BUILD-INFO hashes remain unchanged. All 106 bundle
hashes matched both before launch and after normal Quit; no diagnostic logging
is present in this canonical candidate.

[CI run 39321046092](https://github.com/TJZine/LineupDesktop/actions/runs/39321046092)
completed successfully with **1,855 Linux tests**, **744 selected Windows tests**,
stock Windows compilation and all **eight** selected native/reference CTests.
Completed head is `70df5bd9dd51e19cd3d0f868a6e05cecadb3b8ba`, the product's direct
child differing only in its isolated workflow. Both focus and Slider semantics
files are explicitly selected on Windows; parent/diff/head/completed logs were
checked. Canonical format (160 files/0 changed) and analysis pass. No run was
cancelled. Raw logs/status and `ci-summary.json` remain in the local evidence root.

### Native input/focus attribution

A diagnostic baseline exports `3a0bba29`/product `8105f73c` with passive Dart
focus/key and local AppKit event logging only, marker `m04-focus-trace@8105f73c`.
It uses the pinned stock engine and unchanged runtime. After the user cleared its
Keychain prompt, actual Now Playing → Lineup menu → window zoom → Escape menu
dismissal → zoom restore returned focus to the Player's OSD invoker. AX Close
collapsed Now Playing to OSD without a Dart pointer event or keyboard-mode reset;
timed hide stayed suspended. After showing/collapsing Now Playing again, Escape
retired OSD immediately. Enter/Escape/F2 then visibly did nothing.

The trace establishes AppKit local keyDown codes **36/53/120** and Dart
HardwareKeyboard keyDowns **Enter/Escape/F2**, while primary focus is the route
FocusScope (not rootScope), outside Player, above both application key handlers.
Neither Player nor shell key handler receives those failed keys. Command-comma
then visibly opens Settings through the available native menu shortcut. A later
Dart Comma event has `meta=false`; do not infer that this specific event opened
Settings. This is a matching native retirement/focus failure under passive
instrumentation, consistent with the Dart cause, not proof of every historical
cleanup event. The separate exact canonical fixed-Release comparison follows below.

The local monitor returns the original event; it reads allowlisted key codes,
own-app event types/window flags and responder types. Dart logs normalized focus
ancestry, handler entry, pointer and overlay states without media labels or typed
text. Logging can perturb timing. Missing monitor lines cannot prove no OS
delivery; handler entry alone does not establish routing. Two CUA coordinate
attempts failed with `windowNotFoundAtPosition`; these establish no physical
pointer/timed-hide reproduction. The diagnostic quit normally, with all native
shutdown markers and zero AXTree errors. Raw log hash is
`bfd9947757e9ff41197a252e18c2cc706d422869382bd7433a09a5c7a7b09011`;
normalized trace hash is
`57c4111eb7f353d7609e5610e1104551c2e89be89f3050926f401c5908ab48c0`.
Source/patch/identity and `native-diagnostic-summary.json` stay under the local
native-closeout root. No tracing or engine change is integrated.

### Fixed canonical native comparison and closeout

The user cleared the exact fixed Release's distinct Keychain prompt. One fresh,
uninstrumented canonical process (PID 315) independently reset to Guide/current
program and replayed the observed native baseline sequence before each key:
Now Playing → AX Lineup menu → actual window zoom → Escape menu dismissal →
zoom restore → AX Close → I → AX Close → Escape retirement. Fresh full AX state
confirmed the hidden Player precondition each time. **Enter exposed OSD;
independent Escape and F2 each opened Guide.** These are successful observed
native routes, not a direct fixed-Release FocusManager trace. The same ownership/
route guard applicability is source-supported, not directly logged at runtime.
AX Close is an accessibility action, not physical pointer/timer-hide evidence.

Native Slider's parent is again an enabled **`AXGroup`**, with successful empty
String title/description/value reads and exposed child list `[AXSlider]`. The
passive observer received two real known-Slider **`AXValueChanged`** callbacks,
tag 1 at **95%** and tag 6 at **97%**, each following a successful same-tag value
subscription. Values were sampled during callback handling. These two receipts
close the bounded healthy delivery check on the exact fixed product; they are
not every-update coverage, spoken output or notification recovery after a
rejection. The earlier three receipts remain attributed to `8105f73c`.

The canonical process quit normally (exit 0) with all native shutdown markers,
zero AX/Flutter error messages and no observed exception; the observer completed
normally (exit 0). DVR **Off**, selected channel **1** and main window
**800×632** were restored. Final process inspection found no verification app,
SecurityAgent or observer. No unresolved authentication prompt remains. Raw
`native-fixed-summary.json` records identities, limits and hashed evidence:

| Local evidence file | SHA-256 |
| --- | --- |
| `native-fixed-cua-observations.json` | `5e4ba9e105cf5ae991831339da9ab9618a62af69945a14ac435175ab3eda1177` |
| `native-fixed-slider-role.jsonl` | `18ee96039644bf8706b7cf453d56b4d96240c30ae3bef91480a4f7d34b71e927` |
| `native-fixed-notifications.jsonl` | `d6db6cb4a1d2811360de830ccdb94cb75f258fa2a191ebdb255f99f3ccadf05b` |
| `native-fixed-cleanup-window.json` | `176feb64accbbc6c10e8a2c465245a07f68a526e0f6a026dab5311726c9b5c00` |
| `native-fixed-release.log` | `071f49c764b2b33cb5ca8429e66ceff05c6cff1282865a9659209712c8479672` |

CUA observations are an explicit controller transcription of sanitized outputs,
not an independent engine event trace. Source/evidence reviewer
`01a155dc-e8de-7520-9c70-e19f6be5a9bf` accepted the source fix and independently
checked native-baseline causality, CI and all five final canonical evidence
hashes with no material findings. It independently rehashed the entire final
106-file bundle against the recorded manifest and checked the actual parent CUA
helper/action arguments, including independent key-path resets. No further
bounded review work is pending.

**Disposition:** native group-role and healthy notification delivery are verified;
a matching native input/focus failure is explained and repaired for the observed
sequence. No speculative focus reset or engine change was added. The physical
pointer/timed-hide variants and spoken usefulness/order stay in the single
existing human checklist. M-04 and overall accessibility acceptance remain open
for that checklist, retained-error/event recovery, rejected-batch divergence and
historical node 866. Healthy callbacks do not close post-rejection recovery, and
the matching diagnostic does not retrospectively identify every cleanup event.

## One final human checklist

Run these once on the latest product candidate `ffcaae63`; record failures with generic descriptions.
HDR/Dolby Vision picture quality is already accepted and is excluded.

Acceptance session started 2026-10-19 on unchanged canonical product `ffcaae63`.
No human listening/navigation result was supplied. The user's full-display
Screenshot UI approach exposes actual VoiceOver captions, superseding the first
attachment attempt's tool limitation. Text includes **“application Close, button”**.
Raw full-screen images, lossless reading crops and hashes stay private under
`/tmp/lineup-audit/m04-caption-verification/`; the moved panel's baseline crop was
corrected from full-frame inspection rather than counted as missing output.

The user explicitly authorized the guarded CGEvent helper. An initial next
attempt logged down/up intentions, exit 0 and no Player seek; a subsequent read
**after intervening CUA Screenshot activity** found Control 59 held. Later worker
and controller passive reads independently found it clear without an attributable
release. This does not isolate the cause. Exact `release-owned-control` recovery
was never executed. The helper was corrected locally and independently reviewed;
no product or engine source changed. Final tested helper identities:

| Local helper artifact | SHA-256 |
| --- | --- |
| `guarded-voiceover-input.swift` | `f9028e04ebbd9e86aa8c0a0d0d5239cea634edeb681aae9517170e5e829769c3` |
| `guarded-voiceover-input` | `8a089907f03b1c76164daa504ddc801232f0c601b62b115b677bb51731f29b5c` |

Final bounded trial: one each **next, stop-interacting, interact, previous**.
All recorded permission/exact-foreground guards and declared release checks pass.
Each command is followed by inert inspection and an independent fixed-key/flag
read **before any CUA action**, then another inspection after capture. All tested
per-key states are up and aggregate modifier flags clear. One independent sample
retains device-side bits `0x21`; its significance is unknown. Do not shorten these
observations to all flags zero, guaranteed release across every representation
or confirmed VoiceOver delivery. CGEvent posting has no delivery acknowledgement.

All four post-command caption crops are byte-identical, hash
`920aec6b61570ca2989d084de03c523bab7ee4511338623e6284d2415fdd73f7`, and read
**“application Close, button”**. The previous trial includes a controller-observed
native AppKit application menu open before/after the command and before capture.
This is the captured text at those instants, not proof of no transient speech or
cursor movement. Actual command interception, Slider/group announcement, order,
entry/exit, useful interaction and broader spoken checks remain **unverified**.
The native control supplied no positive caption result, so this is not an
accepted Flutter-only or Lineup-only defect. Fresh System Settings inspection
still shows VoiceOver On. Reviewer `01a155a7-84ee-7641-b56d-fceb695328e3`
independently checked final source, actual command provenance, all four logs/
inspections, original/crop hashes and these proof limits, with no further material
finding. `cg-final-observations.json` retains the bounded result.

Additional automated native coverage, same canonical process 14195: visible
coordinate Close → OSD → no-input timer retirement → Enter reopens OSD. Two
separate Now Playing/coordinate-Close/timer resets establish Escape and F2
opening Guide. The first Close follows pointer menu/native zoom/Escape menu
dismissal/zoom restore. Hidden states were sampled 5.148, 5.842 and 6.868 seconds
after Close, not exact timer expiry measurements. This adds automated pointer
and timer coverage to the earlier AX-action path; physical hardware acceptance
remains pending. `pointer-timer-observations.json` is a controller transcription
of timestamped CUA states, not an independent engine trace.

Cleanup completed: DVR Off was observed in Settings; normal Quit exited 0 with
all native shutdown markers and zero AXTree/Flutter error lines. All 106 bundle
hashes match. The owned Finder window is closed, no verification app/Screenshot/
Utility/SecurityAgent remains, and final independent checks show tested keys up
and aggregate modifiers clear. Preserve the user's already-On VoiceOver state,
unchanged caption preference and preexisting System Settings window. Raw log
`native-human-session.log` SHA-256 is
`7f7519a62ba89aac81e04d5c946d3b28803d5d464dbbf3cb18bfa694e26aa41f`;
`cg-cleanup-summary.json` records the final state.

**No human checkbox is marked passed.** Exact first-fade timing, retained-error/
event recovery, rejected-batch divergence and historical node 866 remain open
engineering findings. Keep all results and partial coverage in this one checklist.

- [ ] Physical K pauses/resumes, including during rapid channel changes; J seeks backward; media play/pause/stop/seek keys work with DVR On and are ignored as specified with DVR Off.
- [ ] Physical Guide search → Tab → Clear → Return/keypad Enter, including repeated F2 → Escape restoration and Command+A in the search field; record actual focus when activation fails.
- [ ] Physical left- and right-⌘ combinations, including ⌘, from relevant screens, expected Guide/Player commands, ⌃⌘F, and ignored modified Player keys, including focus after Now Playing collapse and menu/window resizing, and physical pointer collapse/hover followed by timed OSD hide; verify dirty/modal guards and native fullscreen synchronization.
- [ ] Spoken VoiceOver names, enabled/disabled states, order and focus through Channels, Now Playing, Guide toolbar, DVR transport and Studio rundown, including exact invoker restoration, canonical labels without duplicate speech (cast name/role and Now), track selected/pending state and subtitle Off; verify the approved unlabeled native OSD Slider AXGroup follows the controls and its group announcement is useful, including OSD/menu transitions. Note any loss of the native accessibility tree separately as M-04.
- [ ] Listen/watch for audio drift during sustained playback and a natural rollover.
- [ ] Real live resize/minimum size, minimize/restore, Spaces/Stage Manager round trip, and sleep/wake during playback; verify video alignment, state, audio and responsive controls afterward.
