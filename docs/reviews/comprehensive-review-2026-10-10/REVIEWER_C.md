Unit C review is complete for the coverage below. I retained two Guide findings and independently narrowed the protected-profile PIN candidate. No files were changed and no tests, probes, builds, or cache-writing commands were executed by this reviewer.

Reviewed identity: `codex/desktop-ui-second-pass`, HEAD `4fb7758034f4f47290fae13a4ea8275860ba1284`. Final `git diff --name-only -- lib test` was empty. Pre-existing documentation/untracked changes were preserved.

**C-F01 — Guide grid shortcuts intercept activation of focused controls**

Type: confirmed defect. Status: **CONFIRMED by reachable source and pinned framework trace**, not runtime execution. Severity: **S2 Medium**. Confidence: **High**. Classes C08/C09/C10; journeys J06/J08.

Evidence:

- [guide_view.dart:505](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:505): `_GuideViewState._key` handles descendant key events.
- [guide_view.dart:559](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:559): Enter, numpad Enter, Space, and Select call `selectFocusedProgram`, potentially tuning its channel.
- [guide_view.dart:802](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:802): this handler surrounds the complete Guide, including toolbar, controls, PiP, rows, and feedback.
- [app_ui.dart:96](/Users/tristan/Software/LineupDesktop/lib/ui/app_ui.dart:96): the Lineup menu is an ordinary `TextButton`.
- [guide_view.dart:969](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:969): Close Guide is an ordinary `IconButton`.
- [guide_view.dart:1178](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:1178): Earlier/Now/Later controls use ordinary button activation.
- [guide_view.dart:1951](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:1951): row-local Retry uses `LineupInlineLink`, without the global Retry focus exception.

Trigger: navigate with Tab to a Guide toolbar button, hours/library dropdown, PiP action, or row-local Retry, then press Enter or Space.

Path: the focused control’s `InkWell` registers activation actions but does not insert a local activation `Shortcuts` widget. The key propagates to the surrounding Guide Focus handler, which returns `handled` before reaching `WidgetsApp`’s ancestor activation shortcuts. The grid’s logical program focus is distinct from the focused toolbar widget. The requested action is therefore suppressed, and an airing grid program can tune instead.

Pinned Flutter evidence: `/Users/tristan/.cache/lineup-flutter/3.47.6/flutter/packages/flutter/lib/src/material/ink_well.dart:1386`, `material/dropdown.dart:1756`, and `widgets/app.dart:1263,1346,1820`. Both relevant desktop shortcut maps contain Enter/Space activation. Flutter’s [focus documentation](https://docs.flutter.dev/ui/interactivity/focus) confirms propagation stops at a handler returning `handled`; [defaultShortcuts](https://api.flutter.dev/flutter/widgets/WidgetsApp/defaultShortcuts.html) establishes the platform-selected ancestor bindings.

Counterpoints:

- Search has a deliberate exception.
- Global schedule Retry and empty-lineup Setup have explicit activation handling.
- Pointer and semantics activation invoke the correct callbacks.
- Grid-focus tuning itself is intended.
- This does not establish a native Windows input failure.

Existing evidence gap: `desktop_navigation_test.dart:95` opens the Guide menu by pointer, then checks trapping/restoration. `guide_view_test.dart:2932` checks search keys, not activation of other focused controls. The exceptions protect specific controls, not the surrounding route.

Correction direction: scope grid navigation/activation to grid focus, preserving focused controls’ activation and global destination chords. Include row-local Retry and tab-focused program/channel cells in the ownership decision; domain focus and Flutter focus must agree before an activation tunes.

Minimal controller-owned probe:

1. Mount real `GuideView` or `LineupShell` with a synthetic ready airing program.
2. Focus `guide-app-menu`; send Enter and Space separately.
3. Assert menu opens once and tuning remains zero. Pointer tap is a positive control.
4. Focus `guide-hours`; send Enter; assert its popup appears.
5. Focus row-local Retry in a mixed ready/error viewport; activate it and assert only that schedule retries.
6. Retain grid-focus Enter as a tuning positive control.

Physical follow-up: repeat through the packaged Windows application with keyboard and supported remote Select, recording actual focus, action, and unintended tune behavior.

**C-F02 — Guide notifications rewrite an active search editor**

Type: confirmed defect. Status: **CONFIRMED by source trace**. Severity: **S3 Low**. Confidence: **High**. Classes C01/C09; journeys J06/J08.

Evidence:

- [guide_view.dart:355](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:355): every editor notification calls `setSearchQuery`.
- [guide_controller.dart:611](/Users/tristan/Software/LineupDesktop/lib/guide/guide_controller.dart:611): that owner trims and lowercases the query.
- [guide_view.dart:426](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:426): every Guide notification compares raw editor text with the normalized query, replaces its complete `TextEditingValue`, and collapses selection to the end.
- Schedule completions, lineup/settings reconciliation, and live program transitions can independently notify the same listener.

Triggers:

- Type a lowercase word followed by a space, pause while a row completes or a setting notification arrives, then type the next word.
- Insert an uppercase character at a selected position within an existing query.

Consequence: an unrelated notification can delete the separating space; case normalization can move the caret to the end. Continued input can produce the wrong channel-name query. The replacement also discards the composing range, but **actual IME malfunction remains unobserved and should not be promoted as confirmed**.

Counterpoints: normalization is useful for matching, and external controller changes should synchronize the editor. Existing tests intentionally verify that `guide.setSearchQuery('CHANNEL 1')` updates displayed text. The problem is treating normalized matching state as authoritative raw editing state during ordinary notifications.

Existing evidence gap: `guide_view_test.dart:2932` supplies complete text using `enterText`; it does not retain trailing whitespace across a schedule completion or edit at a nonterminal selection.

Correction direction: preserve raw editor text, selection, and composition for locally originated edits. Synchronize only a real external search change, such as content-scope reset or an explicit controller command; continue normalizing the matching query separately.

Flutter’s [TextEditingController documentation](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) confirms programmatic controller updates modify the field and cautions against composing-range modification inside listeners.

Minimal probe: use the existing Guide fixture, enter `channel`, then `channel `, retain selection, complete another pending row load, and assert raw text/selection survive. Continue with the second word and verify the intended multiword channel remains matched. Separately insert uppercase text at a midpoint. External search/reset synchronization is the negative control.

**Independent calibration of Unit A’s protected-profile PIN candidate**

Recommendation: **keep a narrowed S2 Medium candidate**. Static confidence is High for the state/key mechanism; use **LIKELY** for the user-visible failure until the controller’s real-shell probe supplies observations.

Decisive references:

- [lineup_controller.dart:686](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:686): `selectProfile` includes credential/state commit and subsequent discovery.
- [lineup_controller.dart:766](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:766): discovery sets Servers stage.
- [lineup_controller.dart:775](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:775): saved-server reconnect calls `selectServer`, which advances the operation epoch.
- [lineup_controller.dart:2786](/Users/tristan/Software/LineupDesktop/lib/app/lineup_controller.dart:2786): `_run` returns current-operation identity, not a separately recorded PIN acceptance result.
- [onboarding_view.dart:258](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:258): stage changes alter the keyed screen.
- [onboarding_view.dart:279](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:279): `_pinUser` overrides the stage and continues projecting PIN.
- [onboarding_view.dart:1537](/Users/tristan/Software/LineupDesktop/lib/app/onboarding_view.dart:1537): the original submitter clears `_pinUser` only after `true`, and ignores completion when unmounted.

Reachable narrow trigger: correct protected-profile PIN, a saved server discovered, then a delayed/failing **connection, library enumeration, authorization refresh, or precommit server save**. While pending, the Servers-stage notification can replace the submitting PIN widget with a new empty PIN widget. The old submitter eventually cannot clear `_pinUser`; the new widget has no local failure feedback. Server recovery UI remains hidden behind PIN.

Important counterpoints and correction to broad wording:

- **Back remains available** on the replacement PIN widget once the controller is idle. This is confusing recovery, not a demonstrated permanent trap.
- Normal discovery with no saved reconnect can complete before a frame replaces the submitter.
- Successful server selection moves the real shell to setup or restoration.
- [lineup_shell.dart:662](/Users/tristan/Software/LineupDesktop/lib/app/lineup_shell.dart:662) replaces onboarding with `LineupRestoreView` or setup once restoration/channel setup starts. A failure after that replacement ordinarily creates a fresh onboarding state with `_pinUser == null`.
- Therefore a standalone `UpstreamOnboardingView` probe that retains PIN throughout channel restoration can overstate production reachability.

Required discriminating probe: use **real `LineupShell`**, correct synthetic PIN, persisted server selection, and a gate before server commit. Pump while connection/library enumeration is pending; then fail it. Record visible PIN, controller stage/busy/error/profile, server-picker visibility, and Back recovery. Separately gate inventory restoration after commit and verify whether the shell replacement prevents the proposed effect.

Corrective direction: represent profile/PIN acceptance independently of later server discovery/reconnect, and make UI presentation follow committed profile/stage rather than a stale PIN overlay.

**Actual coverage and evidence limits**

Wide scan included assigned source owners, corresponding widget/controller/settings/diagnostic/UI tests, approved interface/design records, user-guide and architecture claims, October 7 findings, and relevant Git history. No nested delegates were created.

Deep source samples included:

- Complete `GuideController`: filters, identities, live/browse/inspection state, window geometry, retries, schedule/artwork queues, deadlines, generation checks, reconciliation, eviction, disposal.
- Guide view: key/editor handlers, lifecycle clock, viewport/reveal/scroll snapping, toolbar/control actions, error recovery, row/program semantics, showcase artwork currentness, details, timeline geometry.
- Complete shell/settings logic: destination selection, Studio leave guard, account pickers, menu focus/semantics exclusion, global keys, return origins, all setting controls, pending transformations, save feedback.
- Studio: source ownership, draft signatures, source changes, filter/browse/rundown pending state, retained manual entries, move/remove/undo, live-source validation, Air Check currentness, save/conflict/rebase, duplicate, tune and dirty-leave callers.
- Channels: entry/leave/generated setup, deletion snapshots, reorder conflict recovery, schedule-health queues/cache/signatures, focus pruning/restoration.
- Diagnostics owner and view: opt-in/clear/disposal, retention, fixed export vocabulary, snapshots, clipboard failure/retry, frozen event reading, technical facts and responsive layout.
- Shared canvas/focus/control primitives, top bar/content widths, row/selection semantics, logo fallback/currentness, ticker timers/generation/disposal.

Existing tests inspected as source included meaningful samples from `guide_controller_test`, `guide_view_test`, `channel_studio_view_test`, `channels_view_test`, `desktop_navigation_test`, `desktop_settings_test`, `desktop_diagnostics_test`, `diagnostics_test`, `lineup_canvas_test`, and theme/focus tests. **No passing execution claim is made.**

| Dimension | Disposition |
|---|---|
| Correctness/recovery | Retain C-F01/C-F02; PIN calibration narrowed. Studio save/conflict/reconfirmation and directory mutation guards inspected without another promoted defect. |
| Ownership/maintainability | No material finding. Matching normalization versus raw editor ownership explains C-F02; large files and defensive validation duplication alone were not defects. |
| Operations/config/diagnostics | No new finding. Defaults, save feedback, unknown playback method, explicit unavailable stream handling, bounded/fixed export and clipboard recovery were inspected. |
| Performance/concurrency/reliability | No new finding. Guide caches/concurrency/deadlines, viewport pruning, health generations, artwork tokens, ticker and mounted timer cleanup inspected. No latency measurement performed. |
| Security/privacy | No new finding in this scope. Support export independently allowlists producer tuples and recognized facts; controller/raw Plex/native security owners remain other units’ responsibility. |
| Tests/evidence | Actual-key coverage misses the retained activation seam; whole-value text entry misses raw editor synchronization. Widget geometry evidence remains separate from Windows input/composition acceptance. |
| Docs/design | Current Guide, settings, menu and diagnostics contracts were mapped. Approved layout decisions were not reported as aesthetic defects. |
| Build/release/dependencies | Not independently reviewed in Unit C; assigned to the controller/other units. |

**History reconciliation and sibling searches**

Representative diffs, not titles alone, were inspected for `62bc8af1`, `6a1ec4e3`, `0421c88e`, `02330deb`, `825070fd`, `79b1a6df`, `c7c393aa`, `29e4de52`, and `328a6fd5`.

| Class | Historical mechanism and current disposition |
|---|---|
| C01 | Studio late tune navigated after leaving; `62bc8af1` now checks mounted originating Studio identity. Guide schedule/artwork generations and content invalidation checked. No recurrence promoted. |
| C02 | Selection publication preceded save in historical controller paths; persist-before-publication fix inspected. Current `updateSettings` derives changes inside the global queue and publishes after save. No new settings persistence defect. |
| C08 | Inactive source picker/selection blocked terminal Studio actions; source transitions now retire pending tasks. Save/tune/leave/conflict exits checked. C-F01 adds a distinct focused-control recovery seam. |
| C09 | Historical editor keys escaped and Player contexts suppressed valid actions. Guide search exception is present, but toolbar/row activation remains intercepted. Repository searches covered key handlers, `EditableTextState`, activation intents and controller-value writes. |
| C10 | Historical track semantics/footer and Guide width cap fixes inspected. Current shared canvas, Guide geometry, scaling/semantics and corresponding test samples checked. Player’s current overlay implementation remains Unit B’s scope. |
| C11 | Historical collection/portrait facts were omitted from support export. `79b1a6df` adds exact producer tuples and failure values; both are present with tests. Guide/health/artwork payloads remain bounded. |

October 7 F09–F14 and F16 were checked against current fixes rather than repeated. F09’s unmodified-search-key fix does **not** resolve C-F01’s sibling activation path. Planned transcoding/HDR behavior was not treated as a regression.

Searches also found a potentially hidden pending hand-picked selection after switching Browse library → Channel programs. I did **not** promote it: the Browse tab remains an obvious recovery route, inactive draft retention is intentional, and the contract does not decisively require cancelling selection on this internal tab change.

**Navigation, action and claim map**

All entries below are source-traced, not interactively executed.

| Journey/action | Owner/guard and observed source disposition |
|---|---|
| J05 create/edit/inspect/duplicate | Channels selects Studio mode; generated source remains protected; duplicate receives a new identity/number. |
| Studio Save/save-and-tune | Busy/pending/identity/programming/current Air Check guards, then controller save; failure retains draft; tune follows save. |
| Studio conflicts | Use saved/replace require confirmation; captured fresh base is passed back to controller. |
| Studio Back/menu navigation | Shared `requestLeave`, saving exclusion, dirty confirmation; late tune navigation checks originating Studio. |
| Directory delete/reorder | Confirmed channel snapshots/full reorder base; persistence/conflict recovery preserves newer state. |
| J06 grid/search/filter/Now | Guide controller owns schedule/domain focus; editor owns Escape/Enter; matching state affects visible channels. C-F01/C-F02 affect input ownership. |
| Guide retry | Failed identity survives row eviction; retry-all includes offscreen/filtered failures. Row-local keyboard activation falls under C-F01. |
| Guide hours | Settings queue persists first; route-local mounted feedback reports failure and offers Retry. |
| J08 destinations | Shell owns Ctrl+G/P/comma, Ctrl+1–5 and F3; Player requires a playback surface; Studio leave is consulted. |
| Settings/Diagnostics Back | Settings captures origin; Diagnostics returns through Support; menu traps focus and restores invoker. |
| Settings changes | Edited key disabled; independent optimistic transformations rebase over committed settings; mounted failure restores value. |
| J09 support | Recording off by default; disable clears events; display stays frozen until refresh; copy takes an allowlisted current snapshot. |

Doc/code agreements: user-guide lines 178–190 map to Guide search/filter/Now/hours; lines 327–335 map to shell/grid shortcuts with the retained activation qualification; lines 407–409 map to Studio save/tune separation; lines 428–430 map to mounted Settings save/rollback; lines 434–440 map to diagnostic opt-in/redaction. Architecture’s shared canvas/currentness/input ownership descriptions were checked. Media telemetry is explicitly distinguished from physical HDR output.

Remaining acceptance: controller-owned focused probes above; Windows keyboard/remote/IME/assistive-technology behavior; mixed-DPI/fullscreen/PiP input alignment; real Plex shapes/latency and OS clipboard failures. Native playback, release packaging, secure-store behavior, and physical media/composition were outside this reviewer’s executed evidence.

Automatic approval review rejected the cross-chat callback, citing missing trusted authorization despite the retrieved original human authorization reference. No retry was attempted. This terminal report remains in this chat for the parent to retrieve.
