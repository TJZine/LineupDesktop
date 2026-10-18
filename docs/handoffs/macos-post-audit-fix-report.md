# macOS post-audit fix round — 2026-10-18

Source: `platform/macos`; audited baseline `fa176087`, reviewed product candidate
`1b2f64f4eaf584807f70e668a5502ab088a54537`. The audit plan/report were committed
first as `3cf2cce7`. Later evidence-only commits do not change candidate app inputs.
No main merge, distribution release, signing changes or engine patch was made.

Status: **seven code fixes implemented, independently reviewed and CI verified;
required candidate real-app acceptance remains blocked; M-04 remains unresolved.**

## Results

| Item / commit | Root cause and correction | Regression / independent review | Real Release result |
| --- | --- | --- | --- |
| M-01 · `a652c236` | The fullscreen initial display hold requested a paused load, then resumed before readiness. mpv coalesced the pause notifications; Dart projected stale requested `startPaused=true` into Paused although native pause was false. Native readiness now carries its actual pause snapshot, consumed before Dart state projection. Toggle therefore uses observed state. L1/L2 join precision and pause/display policy are unchanged. | 53 transport tests and three core CTests, including missing-notification and genuinely paused readiness. Fresh review `01a150ad-4978-7353-8ab4-18686ac7bc61`: no material findings. | Baseline failure reproduced on Release before the fix. Corrected Release built; first-fullscreen-tune and actual pause/resume acceptance blocked by Keychain. |
| M-05 · `78cf5ecd` | Back/Escape consumed Settings' origin before Player entry could be rejected. One return action resolves unavailable Player to Guide and consumes origin only on accepted navigation. | 46 navigation tests, including expiry before/while Settings × button/Escape. Fresh review `01a150a7-9075-7b52-a52a-7b8e7465da30`: no material findings. | Timer countdown not repeated; the four real-coordinator widget cases establish the route contract. Candidate UI access blocked. |
| Q-01 · `256f69cb` | Bare macOS builds omitted identity defines. Canonical build/run wrapper, CI and documented commands now supply Windows' pubspec version and numeric-build@full-HEAD defines; no runtime fallback. | Six build-wrapper tests; focused analysis. Fresh review `01a150a8-1507-7950-9c5b-592e88c70b17`: no material findings. | Corrected Release built through the wrapper. Real Diagnostics/export identity inspection blocked by Keychain. |
| Q-02 · `47ca08e4` | Steps used the last committed channel during a pending tune. Each press now publishes/accumulates requested identity; only the target after a 250 ms quiet interval enters the serialized tune queue. | 30×150 ms burst, final-only load, pending/stale load, cancellation, reentrancy and paused program-boundary coverage. Fresh review `01a150a9-448a-7781-ae3f-6a59104e9c52` caught a stale preview/program issue; corrected and re-reviewed clean. | Required real 30-press replay blocked by Keychain; simulated burst and final-only native-load regressions pass. |
| Q-03 · `1b2f64f4` | Error presentation used committed selection while Retry used latest request. Error channel/program/Up next and subsequent surfing now use Retry's target. | 297 coordinator tests, including obsolete late failures, Retry and both surfing directions; 120 PlayerView tests. Fresh review `01a150ae-7c43-7840-b703-0f404ed44396` caught the surfing-origin inconsistency; corrected and re-reviewed clean. | Controlled obsolete-failure/new-error/Retry regressions pass. No new real offline run was attempted. |
| M-02 · `b512d612` | Search semantics merged a text-field role into the directory root, making macOS hide descendant controls as a text-field leaf. Search now owns a named semantics container. | Directory ancestry/actions regression; removing only the boundary fails. Fresh group review `01a150aa-dfa2-7221-b4dd-64711c978c50`: repair accepted. | Native AX confirmation of the corrected directory is blocked by Keychain; Dart semantics and negative control are established. |
| M-03 · `0fa2606e` | Tooltip-only icons populate tooltip semantics, while macOS AX names use the separate label. Explicit names match existing tooltip/spec names across the requested controls. | Four semantics tests; 274 affected widget tests. Fresh group review caught/restored the adaptive directory-menu icon; correction re-reviewed clean. | Native AX confirmation is blocked by Keychain; labels/actions are established in semantics tests. |
| M-04 · open | Flutter's bridge rejects incremental AXTree updates. The first invalid delta and Dart-versus-engine cause remain unknown. | [Exact sanitized evidence, attempted reduction and upstream proposal](macos-ax-update-investigation.md). The media-free 200-transition attempt did not reproduce; no engine patch or unproved workaround. Evidence note independently checked. | No candidate navigation coverage yet. Zero errors at its startup is not an M-04 pass; the issue remains open. |

## Candidate and checks

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

## Exact remaining runtime gate

The corrected Release process is waiting in macOS Keychain access. A local
process sample confirms `SecItemCopyMatching` / `SecKeychainItemCopyContent`;
the app still shows its startup surface. The user-only authentication handoff
was requested; no credential workaround was used. After it clears, the controller
still needs to replay the initial-fullscreen tune and actual pause/resume, run
the audit's 30-press sequence, inspect Diagnostics/export identity, and inspect
corrected native AX trees through the affected routes. These required app checks
are **not** transferred into the human-only checklist below or marked passed.
Use the existing built bundle; do not rebuild merely for later prose commits.

## One final human checklist

Run these once on the candidate above; record failures with generic descriptions.
HDR/Dolby Vision picture quality is already accepted and is excluded.

- [ ] Physical K pauses/resumes; J seeks backward; media play/pause/stop/seek keys work with DVR On and are ignored as specified with DVR Off.
- [ ] Physical ⌘ combinations, including ⌘, from relevant screens, expected Guide/Player commands, ⌃⌘F, and ignored modified Player keys; verify dirty/modal guards and native fullscreen synchronization.
- [ ] Spoken VoiceOver names, enabled/disabled states, order and focus through Channels, Now Playing, Guide toolbar, DVR transport and Studio rundown; note any loss of the native accessibility tree separately as M-04.
- [ ] Listen/watch for audio drift during sustained playback and a natural rollover.
- [ ] Real live resize/minimum size, minimize/restore, Spaces/Stage Manager round trip, and sleep/wake during playback; verify video alignment, state, audio and responsive controls afterward.
