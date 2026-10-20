# Continue the macOS post-audit fixes — 2026-10-20

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

Current integration controller: `01a1527d-78d0-71b3-9012-cd6f482f6261`, local.
Human authority: turn `01a157c1-adb9-7cf0-a0a8-29ceed163454`, user item
`01a157c1-adf6-7502-a8bf-ab8177c15b16`. Worker
`01a155a4-b198-7d50-8b96-0afd91c2df71` (project worker preset) changed only
Player and its retained focus test; controller owned integration/builds/CI/native
UI/docs. Fresh reviewer above used high reasoning and the host-default model.
The invoked orchestration skill authorizes these scoped chats and verified
callbacks; historical older controller IDs below belong to earlier campaigns.

Remaining work is the existing human checklist and explicitly open engine/
timing/historical findings. Do not reopen approved group/order, duplicate the
checklist, rerun HDR/DV picture quality or ask again for cleared Keychain prompts.
There is no outstanding authentication prompt or verification process.

## Historical acceptance sessions and source identities

## Latest acceptance session — CGEvent trial complete, VoiceOver checks open

The user's full-display screenshot proposal works through macOS Screenshot UI.
Actual caption text reads **“application Close, button”**. This supersedes the
earlier caption-unavailable limitation. Raw images/lossless reading crops and
hashed manifests remain private under `/tmp/lineup-audit/m04-caption-verification/`.
The caption panel moved between captures; the baseline crop was corrected after
full-frame inspection rather than treating a blank fixed crop as missing output.

The human explicitly authorized the guarded CGEvent helper. Its first `next`
trial recorded down/up intentions and no Player seek; a passive read after an
intervening CUA capture attempt found Control 59 held. Later independent worker
and controller reads found it clear without an attributable release. Cause is
not isolated between helper/capture/other intervening state; the exact recovery
operation **never ran**. No new product defect is inferred.

The temporary helper was corrected and independently reviewed, including both
aggregate modifier flags and individual fixed-key checks before/after commands.
The final reviewed source/binary identities and precise limits are in the report.
One trial each of **next, stop-interacting, interact and previous** passed its
recorded guards and declared release checks. Inert inspection and independent
per-key/flag reads occurred immediately after each command, **before any CUA**;
after-capture checks also passed. One independent sample retained device-side
bits `0x21` while aggregate modifier flags were clear and tested keys were up;
its significance is unestablished. Do not describe this as all flags zero or a
delivery acknowledgement.

All four post-command caption crops are byte-identical and still read Close,
including the trial with Lineup's native AppKit application menu observed open.
This establishes the captured panel text at those instants, not absence of all
transient speech/cursor movement. Actual VoiceOver command handling, Slider/group
announcement, order, useful interaction and broader accessibility acceptance
remain **unverified**. Native controls likewise supplied no positive caption
control; do not attribute the result to Flutter alone or add an app/engine fix.
Reviewer `01a155a7-84ee-7641-b56d-fceb695328e3` independently checked command
provenance, logs/inspections, original/crop hashes and the conclusion's limits.
No further bounded runtime work was requested by that review.

The same unchanged canonical `ffcaae63` Release also passes the earlier CUA
coordinate-pointer/timed-hide path: visible Close → OSD → no-input timer
retirement → Enter exposes OSD. Separate Now Playing/coordinate-Close/timer resets
confirm Escape and F2 each open Guide. The first path follows pointer menu/native
zoom/Escape dismissal/zoom restoration. Hidden states were sampled 5.148, 5.842
and 6.868 seconds after Close; these are not exact expiry latency measurements.
This is automated pointer-event/timer coverage, not physical human input, a direct
fixed FocusManager trace or first-fade timing proof.

**Cleanup is complete.** DVR Off was observed in Lineup Settings; the app quit
normally, exit 0, with all native shutdown markers and zero AXTree/Flutter errors.
All 106 canonical bundle hashes still match. The owned temporary Finder window is
closed; no app, Screenshot, Utility or SecurityAgent helper remains. The user's
already-On VoiceOver state and preexisting System Settings window are preserved;
its switch was freshly confirmed On, and the caption preference was unchanged.
Final independent checks show tested keys up and aggregate modifiers clear.
Recheck live state before another run. Keep the report's **one human checklist**
and first-fade/recovery/divergence/node-866 findings open; no engine patch, new
permission, upstream publication or product change is included.

## Native follow-up completed — bounded application repair, M-04 still open

Latest product is **`ffcaae6377bcdf16080ea742b40ff9960a580ed8`**,
`fix(player): retain focus when OSD controls retire`. Later changes are evidence/
handoff documentation only. The user cleared both genuine Keychain prompts;
there is no outstanding prompt or native session. The controller restored DVR
Off, selected channel 1 and the 800×632 main window, then quit normally. No
verification app, SecurityAgent or AXObserver helper remained running at final
inspection. Recheck current processes before any future run.

The exact canonical Release matched all 106 recorded bundle hashes before and
after its run. It exposes `AXSlider` directly beneath an unlabeled `AXGroup`,
with successful empty String title/description/value reads and only Slider in
its native child list. Successfully registered Slider observers received two
real `AXValueChanged` callbacks (95%, 97%, sampled during callback handling).
Earlier exact `8105f73c` inspection received three callbacks in one process.
The bounded native group-role and healthy notification-delivery gaps are closed;
spoken usefulness/order and post-rejection recovery remain unproved.

The input observation now has a matching native explanation. A real-shell probe
with a current program shows a preexisting focus gap on `459fd726`, `5c6349d4`
and `8105f73c`: keyboard menu dismissal restores its OSD invoker after clearing
remembered Player focus; retirement then strands focus on the route FocusScope
above both application key handlers. It is not rootScope. A disposable logging-
only native baseline independently reproduced this after menu/zoom/Escape
restoration, AX Close collapse and Escape retirement. AppKit and Flutter receive
Enter/Escape/F2, but neither Player nor shell key handler runs. Command-comma
still visibly opens Settings. Do not infer every historical event from this run.

The reviewed fix transfers focus to the existing Player root before its focused
OSD retires, guarded by ownership, current route, active app and requestable root.
Identical retained tests pass 3/fail 2 before it and 5/5 after; affected suites
pass 196 and the full local suite 1,857. Canonical format (160 files/0 changed),
analysis and fresh independent source review pass. The uninstrumented canonical
Release then independently resets/replays the same native sequence before each
key: **Enter exposes OSD; Escape and F2 each open Guide**. All hidden-Player
preconditions were observed using fresh full AX state. One canonical process
completed with zero AX/Flutter errors through normal Quit. No physical-pointer,
timer-hide or direct fixed-Release FocusManager trace is claimed.

[CI run 39321046092](https://github.com/TJZine/LineupDesktop/actions/runs/39321046092)
completed successfully: 1,855 Linux tests, 744 selected Windows tests, stock
Windows compilation and all eight selected native/reference CTests. Verification
`70df5bd9dd51e19cd3d0f868a6e05cecadb3b8ba` is the exact product's direct child
with only its isolated workflow changed; focus and Slider suites are explicitly
selected on Windows. Completed head/parent/diff/logs were checked. No live run was
cancelled. Reviewer `01a155dc-e8de-7520-9c70-e19f6be5a9bf` independently accepted
the source correction, native-baseline/CI attribution and final canonical native
evidence, with no material findings or further review work pending.

Raw identities, traces and summaries remain local under
`/tmp/lineup-audit/m04-native-closeout/`. The [closing report](macos-post-audit-fix-report.md#native-roledelivery-and-player-focus-closeout)
owns precise source/binary identities and limits. The [updated Opus packet](macos-m04-opus-review-handoff.md)
points to current source and remaining questions. Preserve the **one existing
human checklist** in the report. M-04 and overall accessibility acceptance remain
open for those physical/spoken checks, retained-error/event recovery, rejected-
batch divergence and historical node 866. No engine patch, upstream publication,
main merge, signing or distribution change is included.

## Latest Opus review — no product change

The third Opus report accepts bounded product `8105f73c` and establishes no new
defect. The controller checked current source and independently reran 29 supplied
scratch probes (11 ported, nine environment, nine combined flips) on an isolated
`871c7a3c` copy: all reported replay errors were null, the environment cases
retained State, and the combined cases reported no exception. This is forced-
semantics/fake-time evidence, not new native acceptance or a new full-suite count.
Original 22/1,852 local and completed CI/native evidence remain unchanged.

The exact shell Now Playing focus sequence was not reproduced by Opus's fixture;
its final verdict correctly leaves the cleanup observation unexplained. Pinned
focus fallback to rootScope is conditional on no replacement focus being pending.
The proposed native Command-comma/Escape comparison helps distinguish paths but
does not alone prove focus failure or absent key delivery. The closing report's
third-follow-up section records dispositions and evidence limits. No speculative
focus fix or additional permanent tests were added. M-04 remains open, including
native role, notification/spoken acceptance, input/focus, recovery and node 866.

## Interactivity follow-up — current product

The second Opus report was adjudicated against pinned source and fresh controls.
Reviewed fix **`8105f73c9b5891e880d9fa292f0b26d679238a41`** keys the Slider's
local overlay on the same boolean that controls `onChanged`. This remounts its
portal on enabled/disabled flips, preventing the old group from destroying an
un-resent grafted leaf. Ordinary value/max/menu updates retain state; the approved
visuals and unlabeled enabled group/order remain intact.

Five new tests start each transition independently healthy. Identical test source
passes 17/fails 5 on `5c6349d4`, then passes 22/22 with the fix. Existing PlayerView
tests pass 123/123; all 1,852 local tests and canonical format/analysis pass. Fresh
read-only review `01a155a7-84ee-7641-b56d-fceb695328e3` checked the implementation
and evidence before integration. Stock native controls independently reject both
unkeyed flip directions with `Nodes left pending`; both keyed controls retain
usable value updates with zero AX errors. The production baseline Next-channel
run had zero errors without an observed flip and is not a native reproduction.

Release/CI closeout for this exact product is recorded in the closing report.
The user cleared the exact canonical Release's new Keychain prompt. Two fresh
native processes completed healthy entry/Next-channel and untimed Now Playing
menu/window-resize/restoration with zero AX/Flutter errors through normal Quit.
No production interactivity flip was directly observed. Now Playing's untimed
mode removes the old auto-hide confound, but does not directly prove hidden
widget identity or the precise timed-OSD entry/lifetime cases. Cleanup synthetic
keys after collapsing Now Playing did not expose controls; a native Player click
restored usable OSD/menu. This is an unclassified input/focus observation with no
AX error, retained in the existing final human checklist. DVR Off, starting
channel and window size were restored; no verification app remains running.
[CI run 39312611152](https://github.com/TJZine/LineupDesktop/actions/runs/39312611152)
passed 1,850 Linux tests, 739 selected Windows tests, the stock Windows build and
all eight selected native/reference CTests. Verification
`6e7112e20583e65afb81023dd8e9bbf14793354a` is a direct child differing only in
the isolated workflow; completed head/parent/diff/logs were checked, and no active
run was cancelled. Recheck current processes if continuing later.
Raw follow-up evidence is local under
`/tmp/lineup-audit/m04-interactivity-followup/`. Reuse older native evidence only
with its original identity. M-04 and overall accessibility acceptance remain
open, including native/human gaps, notification/recovery, batch divergence and
node 866. Not all reparenting errors occur after mutation; a removal prepass can
fail before destruction. The completed prepass and completion-failure paths must
be distinguished. No engine patch or upstream publication was made.

## Slider containment update — current implementation

The user supplied the Opus implementation handoff and explicitly approved Gate A:
the unlabeled Slider group after the OSD controls. Reviewed fix
**`5c6349d4cf43244da9989fb72f298ac2acb614b0`** wraps only SliderTheme/Slider in
`Overlay.wrap(clipBehavior: Clip.none)`, preserving approved visuals and the
existing retirement wrapper. The handoff is retained unchanged in
`docs/handoffs/macos-m04-containment-implementation-handoff.md`; its pending Gate A
wording is historical. The progress record and closing report own the decision
and implemented state.

All 1,847 local tests passed; the final diagnostic assertion-order correction
was checked by the final 17-test file rerun. Another 198 existing affected tests,
format/analysis, and fresh independent adversarial review passed. Original-source
controls establish eleven unknown-node paths, one pending-child path and the
approved structural departure; see the distinct final logs in
`/tmp/lineup-audit/m04-containment-implementation/`.

The canonical Release is built with the exact fix identity. Four fresh logged
native processes completed with zero AXTree errors for bounded entry, retirement,
menu/actual-window-resize and rapid-show/menu sequences. Exact native first-frame
menu timing and bare group-role extraction remain unverified; see the closing
report for the precise observations and limits. The user cleared the current
Keychain prompt. DVR Off, starting channel and window size were restored, and no
test app/Inspector remains running. Recheck processes if continuing later.

[CI run 39300402918](https://github.com/TJZine/LineupDesktop/actions/runs/39300402918)
passed 1,845 Linux tests, 734 selected Windows tests, stock Windows compilation and
all eight selected native/reference CTests. Verification
`865c5c3a71981fe17f9312fdf02ee2eb4c464d20` is the
product's direct child and changes only the isolated workflow, selecting the new
regression on Windows. No live run was cancelled. M-04 and overall accessibility
acceptance remain open, including native/human limits, retained-error recovery,
rejected-batch divergence and historical node 866.

## Fourth-round update — supersedes the historical starting state below

The supplied GPT Pro report has now been adjudicated against current source and
evidence. Three accepted application defects are fixed and independently reviewed
before separate conventional commits: direct-tune presentation identity
`1a3cf7d3`, explicit Guide Close invocation/live availability `ca07e41c`, and
opening-menu dismissal priority `459fd726`. The latest application candidate is
**`459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`** on `platform/macos`.

Corrected original-source negative controls fail the intended assertions; 454
affected checks and all 1,830 local macOS tests pass, with canonical format and
analysis clean. [CI run 39201999751](https://github.com/TJZine/LineupDesktop/actions/runs/39201999751)
passed 1,828 Linux tests, 717 selected Windows tests, stock Windows compilation and
all eight selected native/reference CTests. Its verification commit
`3ba32122ffad843c037e58c87ab2340e9f7e2e94` is the product's direct child, differing
only in the narrowed workflow. No active run was cancelled. The closing report
records exact canonical Release hashes, bounded native Close/Clear/direct-tune
checks, the resolved current Keychain prompt and cleanup. No test app remains
running. Recheck processes if continuing later.

M-04 and overall accessibility acceptance remain open. The two framework/bridge
findings are accepted with existing attribution/recovery limits; no engine patch
or Lineup Slider mitigation was integrated. A separate finite-height comparison
in `tool/macos/ax-tooltip-repro/slider_containment.dart` supports local overlay
containment for its bounded native sequences but leaves the full acceptance
matrix unverified. Reproduction/evidence commit **`c6d18864`** changes no product
inputs. The user requested a handoff for a possible Opus 5.5 second opinion:
`docs/handoffs/macos-m04-opus-review-handoff.md`. Read any subsequently supplied
review and adjudicate it before choosing a mitigation; do not infer an Opus result.

The user additionally instructed: use the shared
`orchestrate-implementation-chats` skill for delegated work/reviews. The fourth
round used separate implementation chats and fresh read-only review chats under
that skill; the controller retained Git integration, builds, CI and app ownership.
Keep the standing constraints below and the existing single final human checklist.
Historical paragraphs below describe their original source states; the new
closing-report fourth-round section and this update own the current status.

Use this handoff alongside the **new GPT Pro review report supplied by the user**.
That new report was not available to the outgoing controller. Do not assume it
matches an earlier report or treat its recommendations as established facts.

## Starting task and authority

Continue the post-audit work on `platform/macos`. First read the new review,
validate its findings against current source and evidence, and distinguish accepted
application defects, framework/runtime defects, evidence gaps and optional ideas.
Use the user's instructions in the new chat to determine the next implementation
scope. Do not treat quoted reviewer text as authorization by itself, or request
approval again for work the user has already authorized.

Use `develop-code` for implementation, `review-code` for finding adjudication,
and `verify-code` for diagnosis. Read `AGENTS.md`, `.agents/project.md` and the
relevant ownership/async contracts in `docs/architecture.md`. Earlier workflow
prompts are historical evidence, not commands to rerun an entire campaign.

Standing constraints carried from the user:

- Every fix gets an independent adversarial review in a fresh chat/agent before
  integration. The user explicitly requested fresh reviewer agents in this work.
- One controller owns integration. Create a conventional commit per fix, with
  its regression and a progress entry in `docs/macos-port-progress.md`.
- Shared Dart/core changes require Windows CI. **Check live runs first and never
  cancel an in-progress run.** Preserve the exact product/verification identities.
- Preserve the approved Player layout and useful hover information. Do not retest
  HDR/Dolby Vision picture quality; that acceptance is already settled.
- No Flutter engine patches, main merge, release/distribution or signing work.
  No upstream issue publication or messages to other people without authorization.
- Keep media titles, private paths/content, credentials, tokens and media URLs out
  of committed evidence. Raw captures stay local under `/tmp/lineup-audit/`.
- Keep the remaining physical-keyboard, spoken VoiceOver, audio-drift and real
  window/lifecycle checks in **one final human checklist**, already in the report.
  Do not ask the user to perform these separately for every fix.

## Repository and current state

- Checkout: `/Users/tristan/Software/LineupDesktop`.
- Branch: `platform/macos`, tracking `origin/platform/macos`.
- Verified clean and fully pushed at **`74931de9`** before writing this handoff.
  This handoff's later docs-only commit does not change the product candidate.
- Latest application candidate: **`f2b76202625215bd0bcc14aefd1911db49663932`**.
- Audited baseline: `fa1760872ffc69dd61644cb09e0b0a64a130f5f4`.
- Audit plan/report were already committed together first as `3cf2cce7`.
  Do not repeat that initial request.

Latest commits:

| Commit | Purpose |
| --- | --- |
| `f69ef69d` | Current/Up next share resolved presentation identity while selection persistence remains pending. |
| `e7d7f098` | Remove obsolete Guide-origin flag; resolve Close/Escape from current Player availability. |
| `f2b76202` | Retained Clear regression reaches the real button through Tab instead of requesting focus directly. |
| `68bdc662` | Standalone Slider AX and keyboard reproductions plus sanitized graph comparison. No application changes. |
| `859d5f7a`, `74931de9` | Verification, investigation and post-unlock cleanup evidence. Documentation only. |

Read these existing records rather than reconstructing all earlier rounds:

1. `docs/handoffs/macos-app-audit-report.md` and `macos-app-audit-plan.md`.
2. `docs/handoffs/macos-post-audit-fix-report.md`, especially its latest round and
   final human checklist. Earlier results retain their original candidate IDs.
3. `docs/handoffs/macos-ax-update-investigation.md`.
4. `docs/handoffs/macos-post-audit-adversarial-review-prompt.md` — what Pro was asked
   to challenge; compare with the actual new report supplied now.
5. Latest `docs/macos-port-progress.md` entries.
6. `tool/macos/ax-tooltip-repro/README.md` and its minimal sources/fixtures.

Original M-01/M-05/Q-01/Q-02/Q-03 and Dart accessibility repairs are implemented,
with multiple subsequent review corrections recorded in the report. Mini Guide
initialization from presentation identity was approved and fixed as `22073990`;
there is no pending separate Mini Guide handoff to invent.

## Latest fixes and verification already completed

`f69ef69d`: current media P could appear with Up next R instead of Q while a channel
step's selection save was blocked across P's schedule boundary. A shared represented
program getter now owns both values. Unresolved B still uses B's live preview and
cannot inherit retired A media. The regression blocks persistence after readiness,
pauses P, advances the injected clock into Q, and checks P/Q before and after save
release. It failed before the correction. The exact blocked-save sequence was not
induced in the authenticated application; do not claim it was.

`e7d7f098`: after sleep removed Player while Guide remained open, the obsolete
opened-from-Player flag made the first close attempt a rejected Player navigation.
It is removed. Close/Escape now opens the existing menu when no surface remains.
Both before-fix regressions fail, then pass with menu/focus/navigation/no-tune
assertions. This corrects destination availability; the separate root-focus menu
anchor gap below remains open.

`f2b76202`: actual Tab coverage includes matching and no-match queries, Return and
keypad Enter, directly and after F2 → Escape, exact invoker restoration, useful
live input and no tune.

Fresh independent `pro_round3_adversarial` approved all five changed Dart files
before integration. A second fresh `round3_final_review` checked the latest source,
repros and evidence, then corroborated the post-unlock result. Neither review is
authority over the new Pro findings; both are recorded checks, with limits.

Completed on the latest product inputs:

- Canonical format and analysis passed; affected suites **481 passed**.
- Full local macOS suite: **1,819 passed**.
- [Windows verification run 39188166189](https://github.com/TJZine/LineupDesktop/actions/runs/39188166189):
  **1,817 Linux tests**, **706 selected Windows Dart tests**, stock Windows app
  build and all eight selected native/reference CTests passed.
- Verification `86c589573f84bd505531731dc289627270bcb4b0` is a direct child of
  product `f2b76202`, differing only in its isolated narrowed workflow. No active
  run was cancelled. Windows build/contracts are not physical Windows acceptance.

Reuse valid evidence while inputs are unchanged; do not rerun the full suite for
this handoff or other prose-only updates. New application changes invalidate their
affected evidence and need proportionate checks plus required CI/review.

## Open findings and calibrated conclusions

### M-04: Slider/zero-opacity portal case, no new mitigation applied

Actual V2 diagnostic chronology was: healthy startup/keyboard checks → query reset
→ Settings/Playback/DVR On → Back Guide → current-program tune → first AX failure
→ later real sleep timer → desktop lock/unlock and cleanup. This was **one shared
process**, not a fresh AX-only process.

First native error: raw log line 791, new node **378**. Immediately preceding Dart
batch **671** emits an empty full-window portal leaf physically at `0 → 1 → 378`.
Its child token **97** has no matching origin anywhere in the portal inventory.
Effective traversal remains `0 → 1 → 2 → 3 → 12`, without reachable missing children,
cycles or duplicate parents.

A stock continuous Slider mounted under FadeTransition held at zero reproduces
that topology and unknown-node error after healthy native AX. A fresh visible
mount exposes Slider 50% and stays healthy. A genuinely uninstrumented stock app
with an unchanged native runner independently reproduces hidden failure/visible
success. Sources: `slider_fade.dart`, `slider-first-rejection.json` and README.

Pinned Slider eagerly shows its value-indicator OverlayPortal even without hover;
zero-opacity fade elides the origin semantics while the physically separate portal
can emit. This is Flutter framework/common-desktop-bridge interoperability. The
production DVR Slider is a **strong source correlation**, not direct widget-instance
identity from the Release trace. Historical node 866 remains unattributed.

Earlier Tooltip/static-origin/Now-origin mitigations remain distinct. Do not
attribute every historical M-04 error to this Slider or declare previous mitigations
invalid without evidence. The engine also retains an old AXTree error string;
repeated messages are not independent rejection counts or proof of recovery.
Optional LLDB return-value probes had optimized-frame ambiguity and are **untrusted
and excluded**. Do not reuse their Boolean values as evidence.

The documented next experiment is coupling Slider lifetime to semantics-origin
availability, covering entering alpha zero **and retiring exclusions** while
preserving approved visuals/interaction. This is a proposal, not an approved or
verified product solution. `showValueIndicator: never` alone does not remove the
portal; `alwaysIncludeSemantics` exposes invisible controls and misses retiring
exclusions. Challenge this approach against the new report. Keep engine changes
and upstream publication out of scope.

### Keyboard: two captured mechanisms, older failures still unclassified

- Rapid F2 → Escape before menu focus transfer reached Guide's handler; the menu
  stayed/reopened, and Return activated its Guide item. Clear focus returned
  afterward, without a Clear callback for that Return. A staged settled-menu
  control cleared successfully. This is a menu/input interleaving, not proof that
  settled Clear activation fails. No race correction was integrated.
- Synthetic Command+A arrived with combined Command `0x100000`, missing sided Meta
  bits; flagsChanged used A's keyCode 0. Pinned macOS responder conversion therefore
  produced Dart A with Meta false. A stock TextField reproduced collapsed selection
  at 16 and appended replacement lengths 17/18. `keyboard.dart` is the committed
  probe. This does **not** establish a physical Command+A or Lineup shortcut defect.
  Do not add an application select-all workaround from this evidence.
- Clean stock Release passed twelve actual-Tab direct/menu Return/keypad Clear
  activations before synthetic Command+A failed. Zero AX messages during that
  sequence. Historical uncaptured keyboard failures remain unresolved.

### Close Guide with root focus: established application gap, not repaired

The real 30-minute timer expired at `2026-10-19T03:01:40.104268Z`, leaving Guide,
stopped playback, playback intent false and no pending tune. After desktop unlock,
a background native AX tap reached **live** Close Guide node 853 but did nothing.
Flutter primary focus was its root without a mounted context.

`_openAppMenuFromCurrentFocus` in `lib/app/lineup_shell.dart` requires
`primaryFocus.context`; without it there is no menu anchor. This dependency predates
the latest correction and is separate from the obsolete Guide-origin flag.
Foregrounding the same process, then activating Close once, opened the usable menu
without tuning at `03:39:37.128550Z`; Settings navigation worked.

Proposed follow-up: supply a stable explicit Close invoker context/owned focus
anchor and add a root-focus semantics-action regression. No fix for this gap is
integrated. Keep the failed background action visible in the evidence; do not
report an unconditional first-action/native AX pass.

## Toolchain, real app and private evidence

Use the pinned SDK explicitly:

```sh
export PATH="/Users/tristan/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH"
```

The default shell previously resolved Flutter 3.47.6; do not use it accidentally.
Verified inputs: Flutter 3.47.7 / Dart 3.13.5, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`; host arm64 macOS 27.0.1 (26A434).
Recheck current environment before new builds. Use the canonical identity wrapper,
not bare `flutter build macos` for Lineup:

```sh
dart tool/macos/build_app.dart build --release
```

Full test command is `TZ=America/New_York flutter test`. Consult DEVELOPMENT.md
and current workflow for native/Windows provisioning; do not create packaging jobs
just to obtain verification.

Stock app at last verification:
`build/macos/Build/Products/Release/Lineup Desktop.app`, identity
`0.1.0`, `1@f2b76202625215bd0bcc14aefd1911db49663932`. Stock and diagnostic bundle
hashes are in the report; never conflate those builds.

Raw evidence is local to this Mac, unavailable to a GitHub-only reviewer:

| Local path under `/tmp/lineup-audit/` | Contents |
| --- | --- |
| `pro-round3/` | Before/after regressions, affected/full tests, CI logs/identity/status, stock app identity and keyboard observations. |
| `pro-round3/trace/keyboard-v2-app.log` | Full private V2 trace, first AX error and final shutdown; 494 AX failure messages total, including possible stale repeats. |
| `pro-round3/trace/ax-first-node378-*.json`, `ax-replay.json` | First production graph and retained replay. |
| `pro-round3/trace/keyboard-case2-analysis.*`, `keyboard-v2-command-a-analysis.*` | Captured menu interleaving and native modifier/source correlation. |
| `pro-round3/trace/timer-runtime-result.json` | Selected expiry/background-no-op/foreground-menu/cleanup facts; supporting AX files and screenshots share the timer prefix. |
| `pro-round3/slider-fade-repro/`, `slider-fade-stock/`, `keyboard-stock-repro/` | Traced/uninstrumented reductions, build identities, native captures and controls. |
| `pro-round3/trace/temporary-trace.patch`, `README.md`, `identity-v2.json` | Disposable instrumentation, privacy/limitations and diagnostic identity. |
| `pro-round3/trace/preserved/` | Exact diagnostic V2 app and app dSYM; all 106 recorded app file hashes matched the preserved copy. |
| `pro-round2/`, `m04-static-origins/`, other earlier folders | Historical evidence; use only with its recorded identity and limits. |

The diagnostic worktree
`/Users/tristan/.codex/worktrees/macos-ax-round3-trace/LineupDesktop` was **archived**
after cleanup. It is an archived artifact on the original chat; do not assume its
path still exists. Preserved patch/binary evidence above remains local. Restore
through the managed worktree facility only if needed and accessible; otherwise use
the saved patch in an isolated checkout. No tracing was integrated into production.

Last cleanup is complete: DVR restored **Off** via the native switch, diagnostic
PID 3618 exited, and libmpv shutdown completed normally. No timer, debugger or
application verification sequence remains running from the controller. Check live
processes before assuming the user has not reopened the app since then.

User completed previous Keychain and desktop-unlock prompts. Those were real
runtime blockers and are now resolved. Do not ask again from historical context.
For a new binary, inspect the actual current state before attributing a startup
stall to authentication. If a genuine new Keychain/SecurityAgent prompt or lock
blocks progress, the audit plan assigns authentication to the user; request only
that action and continue independent work meanwhile.

## Expected next-chat outcome

Start by adjudicating the **new supplied Pro report**, not by blindly applying
this handoff's proposed workarounds. Preserve valid existing evidence, investigate
only the uncertainty needed for the accepted next scope, and implement authorized
application fixes with meaningful regressions, independent fresh review, real
Release verification and Windows CI where required. Keep open runtime/physical
acceptance explicit. Update the existing report, investigation and progress record;
finish with proper commits and a short result report, retaining the single human
checklist. Do not resume unrelated development or release work.
