# macOS post-audit fix round — 2026-10-18

Source: `platform/macos`; audited baseline `fa176087`, reviewed product candidate
`1b2f64f4eaf584807f70e668a5502ab088a54537`. The audit plan/report were committed
first as `3cf2cce7`. The latest product candidate is
`ac995ec58c92ef491098f8a5afcc1da60cd65ad0`. Results for the earlier seven-fix
candidate and the `296ab905` transition mitigation retain their original source
and binary identities below.
No main merge, distribution release, signing changes or engine patch was made.

Status: **the original seven fixes and six Pro-review follow-up commits are
implemented and independently reviewed. The known tooltip triggers passed bounded
Release checks with zero AX failures; the additional Studio topology correction
passed native named-button activation. General accessibility sign-off remains
open for the human checks and the underlying Flutter AX update/recovery defects.
The latest Studio candidate and prior tooltip candidate both passed Windows CI.**

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

## Pro review corrections — latest candidate `ac995ec5`

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

## Latest Studio-only acceptance — `ac995ec5`

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

## One final human checklist

Run these once on the latest built candidate `ac995ec5`; record failures with generic descriptions.
HDR/Dolby Vision picture quality is already accepted and is excluded.

- [ ] Physical K pauses/resumes; J seeks backward; media play/pause/stop/seek keys work with DVR On and are ignored as specified with DVR Off.
- [ ] Physical ⌘ combinations, including ⌘, from relevant screens, expected Guide/Player commands, ⌃⌘F, and ignored modified Player keys; verify dirty/modal guards and native fullscreen synchronization.
- [ ] Spoken VoiceOver names, enabled/disabled states, order and focus through Channels, Now Playing, Guide toolbar, DVR transport and Studio rundown, including exact invoker restoration, canonical labels without duplicate speech and track selected/pending state; note any loss of the native accessibility tree separately as M-04.
- [ ] Listen/watch for audio drift during sustained playback and a natural rollover.
- [ ] Real live resize/minimum size, minimize/restore, Spaces/Stage Manager round trip, and sleep/wake during playback; verify video alignment, state, audio and responsive controls afterward.
