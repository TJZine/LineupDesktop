# M-04: Opus 5.5 review after native verification and the focus fix

Updated 2026-10-19. Review the current integrated mitigation and bounded native
closeout against actual source/evidence. Return findings before implementing
anything. **The requested native role/delivery checks and matching input/focus
investigation are complete; M-04 and overall accessibility acceptance remain
open for the specific findings below.**

The latest continuation/report also record readable full-display VoiceOver
captions and successful automated coordinate-pointer/timed-hide key routes.
The human authorized the guarded CGEvent trial. Four final commands pass declared
aggregate/per-key release checks, but captured captions remain identical on Close,
including a native AppKit-menu control. Genuine VoiceOver handling/Slider
announcements remain unverified; no new product defect is established. The first
ambiguous held-Control sample followed intervening capture, later cleared without
an attributable release, and the recovery operation never ran. Cleanup is complete
with DVR Off, normal exit 0, unchanged bundle and the user's VoiceOver On preserved.
Keep the report's single human checklist and all remaining engine findings open.

## Source, assignment and settled constraints

- Repository: <https://github.com/TJZine/LineupDesktop>, branch `platform/macos`;
  checkout `/Users/tristan/Software/LineupDesktop`.
- Current product: **`ffcaae6377bcdf16080ea742b40ff9960a580ed8`**,
  `fix(player): retain focus when OSD controls retire`. Later revisions update
  documentation only. Resolve current HEAD/dirty files explicitly; do not infer
  a newer product identity from a documentation commit or relabel historical runs.
- Earlier products: Slider interactivity `8105f73c9b5891e880d9fa292f0b26d679238a41`,
  local containment `5c6349d4cf43244da9989fb72f298ac2acb614b0`, before containment
  `459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`.
- The user approved the **unlabeled enabled-Slider group after OSD controls**.
  Gate A is resolved. Preserve approved Player visuals and useful hover information;
  do not request approval again, invent a group label or broaden the layout.
- This packet authorizes read-only review/investigation, not product/engine edits,
  main merge, distribution/signing changes, upstream publication or messages.
  The controller owns scope, Git, builds, CI and native-app resources. Do not
  rerun HDR/Dolby Vision picture-quality acceptance.
- If delegated work is useful, use the user's `orchestrate-implementation-chats`
  skill and existing authorization. Do not start a broad audit or a fixed panel.
- Keep raw/private logs, media labels, screenshots, credentials and URLs out of
  shared evidence. Local raw evidence is under `/tmp/lineup-audit/`.
- Preserve the **single existing human checklist** in the closing report. Do not
  create a second checklist or mark physical/spoken checks passed from automation.

Read `AGENTS.md`, `.agents/project.md`, and:

1. [Closing report: native closeout](macos-post-audit-fix-report.md#native-roledelivery-and-player-focus-closeout),
   its earlier containment/interactivity sections, and its one human checklist.
2. [Current continuation](macos-post-audit-continuation.md), current update first.
3. [Engine/AX investigation](macos-ax-update-investigation.md), including static
   origins, retained errors, rejected-batch calibration and production node 378.
4. `lib/playback/player_view.dart`: `_changed`, `_key`, pointer/keyboard mode,
   `_Osd`, keyed local Slider overlay and retirement wrapper;
   `lib/app/lineup_shell.dart`: menu dismissal/invoker focus, exclusion, native
   menu callbacks and global key routing; `player_key_resolver.dart` and
   `player_coordinator.dart`: overlay/key behavior.
5. `test/app/player_overlay_focus_test.dart`,
   `test/playback/player_slider_semantics_update_test.dart`, and
   `test/support/semantics_update_recorder.dart`.
6. [Stock repro README](../../tool/macos/ax-tooltip-repro/README.md), particularly
   the containment/interactivity/retirement controls and rejection fixtures.

Pinned tools: Flutter **3.47.7**, Dart **3.13.5**, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`. Host: arm64 macOS
**27.0.1 (26A434)**. Local SDK:
`/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`; default shell Flutter
previously resolved 3.47.6. Inspect pinned source, not current Flutter main.

## Integrated behavior

Containment wraps only SliderTheme/Slider in
`Overlay.wrap(clipBehavior: Clip.none)` in the existing 40-pixel progress Stack.
The portal and semantics origin share fade/exclusion/retirement ancestry. The
separate four-pixel indicator, progress Semantics, theme/callbacks and previous-
child retirement wrapper remain intact. Its unlabeled group/order is approved.

The interactivity correction keys that local overlay with the same boolean that
controls `onChanged`: positive duration and supported playback. Enabled/disabled
flips remount the portal, preventing the old group from destroying an un-resent
empty grafted leaf. Ordinary value/max/menu changes retain State. Same-source
negative controls pass 17/fail 5 before the correction, then 22/22 after it; stock
native controls reject both unkeyed flip directions with `Nodes left pending`,
while both keyed controls retain usable value updates. A production interactivity
flip was not directly observed. These earlier results retain `8105f73c` identity.

The new focus repair is separate and preexisting. A real-shell/current-program
fixture shows that keyboard menu dismissal clears remembered Player focus and
restores its OSD invoker. When its focused OSD retires, focus can land on the route
FocusScope above both Player and shell key handlers. Delivered Enter/Escape/F2
then do nothing. Identical 20-case scratch results on `459fd726`, `5c6349d4` and
`8105f73c` establish that this predates the Slider changes. It is not rootScope.
Pointer Close or Escape collapse plus video hover permits timed retirement;
Escape collapse without pointer activity deliberately suspends auto-hide.

`PlayerView._changed` now requests the **existing Player root** before actual
OSD → none retirement only if the focused control belongs to this Player, its
root still owns and can request focus, the app is active and its modal route is
current. It adds no wrapper, global reset, arbitrary-update focus request or
visual/semantics change. The same guard handles timed and explicit retirement.

## Local verification and independent review

The final retained focus test source passes **3/fails 2** on `8105f73c` for the
intended delivered-key assertion, then passes **5/5** with `ffcaae63`. The real
shell/schedule paths independently exercise Enter/Escape/F2 and protect active
menu, current modal and background ownership. Affected existing suites pass
**196**, including **22** Slider semantics and **123** PlayerView tests. The full
local suite passes **1,857**, canonical format **160 files/0 changed**, analysis
clean. No new source change invalidates these results.

Final source SHA-256:

| File | SHA-256 |
| --- | --- |
| `lib/playback/player_view.dart` | `37676b813de217b35b0cf1c2280f86cf4e2e6b0f4688f52d7eafce019810c021` |
| `test/app/player_overlay_focus_test.dart` | `f15b16549962d6e3c75814e6f1368252e6a237d800d657a5a2e082de8e039f7e` |
| `test/playback/player_slider_semantics_update_test.dart` | `0112b233bc4d5a3da18e73a86dd770165694d4159d4d43526e2bbf4914fb2aae` |
| `lib/app/lineup_shell.dart` | `d930a4192b276ff92e9234f1f2126a3b246b5730ac6b052ac938ec7d6cec0269` |

Fresh read-only reviewer `01a155dc-e8de-7520-9c70-e19f6be5a9bf` accepted exact source,
negative controls, ownership/lifecycle guards and local evidence before
integration, with no material findings. It subsequently independently checked the
native baseline trace, completed CI evidence and final canonical artifacts,
including all five evidence hashes, the entire 106-file final bundle and the
actual CUA helper/action arguments. No material finding or further bounded review
work remains. Earlier helper/interactivity review is
`01a155a7-84ee-7641-b56d-fceb695328e3`.

## Native focus comparison

Local root: `/tmp/lineup-audit/m04-native-closeout/`. The diagnostic baseline is
an isolated export of `3a0bba29`/product `8105f73c` with passive logging only,
marker **`m04-focus-trace@8105f73c`**. It is not canonical product acceptance.
Patch/identity and `native-diagnostic-summary.json` record its exact provenance.
No diagnostic or engine change was integrated.

The actual baseline sequence is current program → I Now Playing → AX menu →
window zoom → Escape menu dismissal → zoom back → AX Close → I → AX Close →
Escape retirement. AX Close does not create a Dart pointer event or reset
keyboard mode; timer hide stays suspended, so the final Escape explicitly
retires OSD. The trace then shows:

- AppKit local keyDown codes **36/53/120** and Dart HardwareKeyboard
  **Enter/Escape/F2**, including their key-up events.
- Primary focus on the route FocusScope, **not rootScope**, outside Player and
  above both application key handlers; neither handler receives those failed
  keys, and the UI visibly stays on hidden Player.
- Command-comma subsequently visibly opens Settings. A later Dart Comma event
  has `meta=false`; do not attribute Settings to that exact event or invent a
  native menu-channel trace that was not captured.

This establishes a matching native focus-routing defect, not OS key nondelivery.
The exact `_Osd.controller`/`ModalRoute.isCurrent` guard values are not directly
logged; applicability is source-supported inference from this invoker/route.
Logging can perturb timing. Two CUA coordinate attempts failed with
`windowNotFoundAtPosition`; they establish no pointer delivery. Do not infer the
exact cause of every historical cleanup event from this matching failure.

After the user cleared its distinct Keychain prompt, the **uninstrumented exact
`ffcaae63` canonical Release** independently reset/replayed that same sequence
before each key, with fresh full AX state confirming hidden Player each time:

| Key after retirement | Diagnostic baseline | Canonical fixed product |
| --- | --- | --- |
| Enter | Delivered; no application handler/route | OSD appears |
| Escape | Delivered; no application handler/route | Guide opens |
| F2 | Delivered; no application handler/route | Guide opens |

This is one canonical process with three independently reset paths, not three
fresh processes or a direct fixed-Release FocusManager trace. Physical pointer,
timer-hide and physical keyboard acceptance remain in the existing checklist.
The canonical process and observer quit normally, exit 0, with zero AX/Flutter
errors through shutdown. DVR **Off**, selected channel **1** and main window
**800×632** were restored. No app, SecurityAgent or observer remained running.

## Native Slider role and healthy notifications

Both unmodified `8105f73c` and exact fixed `ffcaae63` expose `AXSlider` directly
beneath an enabled **`AXGroup`**. Parent title/description/value are successfully
read empty Strings; its exposed native child list is `[AXSlider]`. The empty
portal is not exposed as a native child. Native order after controls is observed;
spoken announcement/usefulness is still human acceptance.

The passive PID-scoped AXObserver uses existing trust, native attribute reads and
successful explicit subscriptions. It performs no UI actions, attribute setters,
input synthesis/taps or permission requests. CFEqual identity matches callbacks
to discovered Slider elements. `8105f73c` received three value callbacks across
two streams in one process (22%, 31%, 33%). Exact `ffcaae63` received two real
`AXValueChanged` callbacks: **tag 1 at 95%, tag 6 at 97%**, each after a successful
same-tag subscription. These close bounded native group-role/healthy-delivery
gaps. Values are sampled when handling callbacks, not event-payload values.
Missing/failed reads or subscriptions cannot prove absence. Healthy callbacks
prove neither every-update coverage, spoken output nor post-rejection recovery.

`native-fixed-summary.json` records all final local evidence hashes. Its CUA
observation file is explicitly a controller transcription of sanitized tool
outputs, not an engine event trace. Exact final native log SHA-256:
`071f49c764b2b33cb5ca8429e66ceff05c6cff1282865a9659209712c8479672`.

## Exact Release and completed CI

AOT **`1@ffcaae6377bcdf16080ea742b40ff9960a580ed8`**, version/build **0.1.0 / 1**.
All **106** bundle hashes matched before and after native execution.

| Release identity | SHA-256 |
| --- | --- |
| Executable | `f80598ce711746192e1c3811c5a6a7c3ba7b1368554ec1b396e029993b66edda` |
| App.framework | `2d32192b440a7de131f06b655db6320cdf57e0b02a80799696d96861f9b6c0ed` |
| Flutter engine | `4c12bce183913ecdb95335257cce0cd0bfd27b37a7ff4d42f7a51203e2382445` |
| Runtime BUILD-INFO | `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899` |
| Compact sorted JSON bundle manifest | `9da64b5b3f99c1e5c53c7a84bd81db7c1dbce1658618139e5da10d95d5d0527a` |

[CI run 39321046092](https://github.com/TJZine/LineupDesktop/actions/runs/39321046092)
completed successfully: **1,855 Linux tests**, **744 selected Windows tests**,
stock Windows compilation, and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract`, `authenticated_reference`.

Verification **`70df5bd9dd51e19cd3d0f868a6e05cecadb3b8ba`** is the product's direct
child, differing only in its isolated workflow, explicitly selecting focus and
Slider suites on Windows. Completed head/parent/diff/logs were checked; no live
run was cancelled. Windows-hosted tests establish selected portable behavior
(the focus file selects macOS TargetPlatformVariant), plus stock compilation/
native contracts; they do not establish physical Windows input/media/HDR/package
acceptance. `ci-summary.json` and raw completed logs retain the evidence.

## Remaining findings and focused review questions

1. **Human accessibility/input acceptance.** Spoken group usefulness, names,
   states, order, invoker restoration and physical keys/modifiers remain in the
   report's existing checklist. Physical pointer/timed-hide variants and exact
   first-entry menu timing remain unproved; the earlier 989-ms attempted click
   did not establish a 350-ms first-fade case. Do not convert healthy native tree
   traversal or synthetic routes into spoken/physical acceptance.
2. **Retained-error/event recovery: source-established, no engine repair.** The
   pinned common bridge ignores both `Unserialize` return values and checks
   retained `AXTree::error()`; successful updates do not clear it. Later mutations
   can skip event delivery/`ClearEvents()`. A retained error after a removal
   prepass can return before consuming/clearing pending updates. Calibrate to the
   surviving bridge/tree instance. Healthy-process callbacks above do not prove
   recovery, and changing the check alone would not restore lost data.
3. **Rejected batches/divergence remain open.** Unknown non-root failures here
   occur in `ComputePendingChanges` before that main update mutates structure;
   valid updates in the rejected batch are still discarded. A successful removal
   prepass is a separate earlier mutation and can already destroy moved subtrees.
   A failing prepass need not mutate. Not every rejection is atomic, and not every
   reparenting error is post-mutation: the destruction-mark check can fail before
   `UpdateNode`; `Nodes left pending` completion failure occurs after updates.
   Replay's early missing-record check establishes invalidity, not exact native
   mutation timing. No complete resynchronization or notification recovery exists
   in the evidence.
4. **Historical attribution remains bounded.** Captured production node 378 has
   an empty full-window leaf at `0 → 1 → 378`, token 97 without an origin, after
   batch 671; effective traversal was complete/acyclic. Stock reproduction and
   matching graph evidence support the Slider path. Historical node **866** and
   older uncaptured failures remain unattributed. The matching focus diagnostic
   does not retroactively trace every earlier cleanup key event.
5. **Review current fixes for concrete defects.** Challenge key/portal lifetime,
   recorder/replay assumptions and focus ownership guards against pinned source.
   Separate a demonstrated defect from missing evidence or an optional idea.
   Do not add another mitigation, global focus reset or permanent test solely
   because this packet lists a question. Return a small distinguishing observation
   if a material remaining uncertainty can actually change the verdict.

Return accepted/modified/rejected findings with source references and exact proof
limits. State explicitly whether any new concrete application defect exists.
Keep application mitigation, engine findings and human acceptance separate; do
not close M-04 globally from passing bounded checks or reopen resolved Gate A.
