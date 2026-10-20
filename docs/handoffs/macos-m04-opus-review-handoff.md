# M-04: Opus 5.5 review after complete Player focus recovery

Updated 2026-10-20. Review current source and evidence before proposing changes.
The authorized remaining application focus repair is implemented, independently
reviewed and verified locally, natively and on Windows CI. **M-04 and overall
accessibility acceptance stay open** for the findings and human checklist below.
This is a read-only review packet, not authorization for product/engine changes,
main merge, signing/distribution work, upstream publication or messages.

## Source, settled decisions and review scope

Repository `/Users/tristan/Software/LineupDesktop`, branch `platform/macos`.
Resolve actual HEAD/dirty state. Current product is
`829547b48859ab9654190c2b9d785b1e1446fdc9`; later evidence commits are docs only.
Previous focus product is `ffcaae6377bcdf16080ea742b40ff9960a580ed8`; Slider
interactivity is `8105f73c9b5891e880d9fa292f0b26d679238a41`, local containment
`5c6349d4cf43244da9989fb72f298ac2acb614b0`, before containment `459fd726`.
The user approved the **unlabeled enabled Slider group after OSD controls**.
Preserve Player appearance/tooltips and group/order; Gate A is resolved.

Read `AGENTS.md`, `.agents/project.md`, and the current continuation, closing
report and AX investigation in `docs/handoffs/`. The controller owns Git, builds,
CI and native-app resources. Use `orchestrate-implementation-chats` for authorized
delegation. Keep raw media labels, logs, screenshots, credentials and URLs under
`/tmp/lineup-audit/`. Keep the single checklist in
`docs/handoffs/macos-post-audit-fix-report.md`; do not create another or mark
physical/spoken acceptance from automation. No more VoiceOver synthesis.
HDR/Dolby Vision picture quality is already accepted and excluded.

## Containment, interactivity and focus implementation

Only SliderTheme/Slider is wrapped in `Overlay.wrap(clipBehavior: Clip.none)`
inside the existing 40-pixel progress Stack. Portal/origin share fade, exclusion
and retirement ancestry. The four-pixel indicator, progress Semantics and previous-
child retirement remain. Its key follows the same enabled boolean as onChanged;
interactivity flips remount the portal, while value/max/menu changes retain State.
Earlier same-source negative controls pass17/fail5 before the interactivity fix,
then22/22 after; stock native controls reject both unkeyed flip directions and
retain keyed controls. These results retain `8105f73c` identity. A production
interactivity flip was not directly observed.

The earlier `ffcaae63` focus repair covered owned OSD→none retirement. The latest
repair broadens transfer to owned bottom-panel retirement, adds a coalesced
FocusManager listener for empty/ancestor-scope focus, and explicitly schedules it
on resume. Post-frame rechecks require mounted, active, attached/requestable root,
current route and not full Guide. Menus/modal routes, surviving leaf controls and
other scopes retain ownership. The listener is removed on dispose; a frame is
requested because post-frame callbacks do not schedule one. Proactive transfer
preserves the next digit before reactive recovery can run. No global input reset,
new wrapper, visual/semantics redesign or engine patch is added.

Current source SHA-256:

| File | SHA-256 |
| --- | --- |
| `lib/playback/player_view.dart` | `22c8dc49da08d25b85375c4e7eeececc06d58cdf7741a2542cf63952595e769f` |
| `test/app/player_overlay_focus_test.dart` | `b0d20d7036e6039486c71d6efe3d18ef39502a1c46a0b6192802c0a48aac5f59` |
| `test/playback/player_slider_semantics_update_test.dart` | `0112b233bc4d5a3da18e73a86dd770165694d4159d4d43526e2bbf4914fb2aae` |

## 2026-10-20 — Remaining focus repair verified; M-04 acceptance stays open

Latest product is **`829547b48859ab9654190c2b9d785b1e1446fdc9`**,
`fix(player): recover focus after overlay retirement and resume`. Later evidence
commits change documentation only. Earlier “latest product” references below
retain their historical identities. The repair transfers owned OSD/NowPlaying
focus before retirement, coalesces recovery from empty/ancestor-scope focus,
and schedules guarded recovery on resume. It preserves current route, active
state, menus, dialogs and surviving controls; Player appearance and the accepted
unlabeled enabled Slider group/order are unchanged.

The identical final regression source produces **3 passes/7 behavioral failures**
on `17c81c72`, then **10/10** on the fix. Affected suites pass **198**, including
all **22** unchanged Slider semantics tests. Full local tests pass **1,862**,
canonical formatting checks **160 files/0 changed**, and analysis is clean.
Fresh independent reviewer `01a1580e-2494-7a30-b409-0714d8eed008` checked the
exact source, pinned focus lifecycle/autofocus and evidence with no actionable
finding before integration. The Mini Guide baseline loop stops on Escape's
failure; only the passing candidate executes both Escape and F2 iterations.

The exact canonical Release now passes the matching native comparison:

| Native observation | Old `ffcaae63` | Fixed `829547b4` |
| --- | --- | --- |
| Menu/native zoom/Escape restoration → Escape collapse → 8, fresh AX/screenshot, 9 | Remains 8 at 535 ms | Shows 89 at 573 ms |
| F2 after number-buffer retirement | Does not open Guide | Opens Guide |
| Actual Up → Mini Guide after independent menu/zoom/collapse reset | Not replayed in this baseline session | Escape closes; separate reset/F2 opens Guide |
| Coordinate Close → timed OSD hide while genuinely inactive → return/Enter | Dart regression establishes old failure | Inactive/hidden snapshots; Enter exposes OSD |

For the last row, Finder opened the existing System Settings within 2,151 ms of
pointer collapse. Passive reads confirm native active/frontmost/AX-frontmost all
false and no Slider; fresh AX confirms controls hidden before return. They are
all true after return. AX Raise and CUA Command-Tab preparation attempts left
Lineup active and are excluded from this lifecycle result. Ordinary-Tab resume,
modal return, synthetic playback error and programmatic close have retained Dart
regressions; they are not claimed as new native scenario passes. Native 89 exists
and naturally tunes; the fixture's 89 is unavailable. No direct fixed-candidate
FocusManager/HardwareKeyboard trace or physical/spoken acceptance is inferred.

Windows/Linux [CI run 39383128215](https://github.com/TJZine/LineupDesktop/actions/runs/39383128215)
completed successfully: Linux **1,860** full tests, Windows **749** selected tests,
stock Windows build and **8** explicitly selected native/reference CTests. Its
verification commit `ed42ccd780aec2fbc4ebfbcfe731869d060a7be8` is a direct child
of product `829547b4`, differing **only** in `.github/workflows/ci.yml`. No live
run was canceled. This is compilation/controlled-contract evidence, not physical
Windows media/input/HDR or package acceptance.

All **106** canonical bundle files match before/after execution, including exact
Dart identity `1@829547b48859ab9654190c2b9d785b1e1446fdc9`. The unchanged engine
and native runtime retain their previous hashes. The current native snapshot
also retains the accepted unlabeled enabled Slider AXGroup. Earlier healthy
notification callbacks retain their original product identity; no fresh callback
run or post-rejection recovery is claimed. DVR Off/channel 1/800×632 are restored;
normal quit exits **0**, all shutdown markers appear and there are **zero**
AXTree/Flutter errors. Owned Finder is closed; no app/SecurityAgent/observer
remains. The user's current VoiceOver setting was **Off** at this session's
start and remains Off; preexisting System Settings is preserved.

Raw manifests, logs, private AX/screenshots and controller transcriptions remain
under `/tmp/lineup-audit/m04-focus-followup/`. Preserve the **one existing human
checklist**, exact first-fade timing, retained-error/event recovery, rejected-batch
divergence and historical node 866. No human checkbox is marked passed. There is
no new VoiceOver synthesis, engine patch, main merge, signing/distribution or
upstream publication. M-04 and overall accessibility acceptance remain **open**.

## Exact artifact and local evidence locations

Raw controller evidence: `/tmp/lineup-audit/m04-focus-followup/controller/`:
`release-identity.json`, `release-bundle-manifest.json`, `native-fixed-observations.json`,
`fixed-final-integrity.json`, `native-baseline-observations.json`, `review-summary.json`,
`ci-source.json`, `ci-summary.json`, `ci-complete.log`, `full-test.log`, `format.log`,
`analyze.log` and `native-fixed.log`. These are local evidence, not repo fixtures.
Worker evidence is the sibling `worker/`: `summary.json`, `final-before.log`,
`final-after.log`, `affected.log`, final retained test and archived baseline.
The identical final test source is copied into the exact `17c81c72` archive;
failures are behavioral assertions, not setup/framework failures. The earlier
pumpAndSettle timeout on an endlessly animated unavailable Guide was corrected
with a bounded pump and both final before/after rerun with that same test.

| Canonical Release artifact | SHA-256 |
| --- | --- |
| 106-file manifest | `acc863c0a9b3aeed4bc78183df187945d200750cd7bf0e35b108570ededfefe2` |
| Executable | `02c67d1eca6e7e1d22e812508d0445d1d9a86017cf7a290e8145f2cf198d9c99` |
| App.framework/App | `1bfdbdcf0e75f4273ad2850381b44169c39e3c04f8a5f52d1146e56b380624f2` |
| Flutter engine | `4c12bce183913ecdb95335257cce0cd0bfd27b37a7ff4d42f7a51203e2382445` |
| Runtime BUILD-INFO | `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899` |

Pinned Flutter3.47.7/Dart3.13.5, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`, arm64 macOS27.0.1(26A434).
Build uses `dart tool/macos/build_app.dart build --release` at clean product
commit; later docs do not relabel this as a new run. No instrumentation was
added to the canonical product. Passive AX helpers only read state.

Previous VoiceOver captions stayed on “application Close, button”, including a
native AppKit control, despite guarded CGEvent trials. This may be stale panel
text and does not verify the current Close or Slider. No new VoiceOver trial was
run. Historical modifier attribution remains calibrated in the closing report:
SDK device bits0x21 mean left Control/Option; their origin is not exclusively
established. 0x20000000 is not noncoalesced; SDK noncoalesced is0x100.

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
