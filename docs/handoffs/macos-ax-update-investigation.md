# macOS accessibility update investigation — M-04

Status: **Flutter runtime interoperability defects reproduced standalone; bounded
application mitigations implemented, general M-04 acceptance still open.** Stock
Tooltip and Slider sequences reproduce the unknown-node rejection. A new production
first-error graph is captured; its topology matches the Slider/zero-opacity case.
The first historical production delta was not captured, so this does not attribute
every historical message to that sequence or close real-app acceptance.

## Conclusion and owning boundary

A retained `Tooltip` can remain physically mounted after an ancestor
`ExcludeSemantics` removes its origin from traversal. Changing the tooltip message
then emits an update for its now-unreachable text node. Flutter's common desktop
`AccessibilityBridge`, used by macOS, forwards that record to `ui::AXTree`, which
rejects an unknown non-root node. It does not apply the documented discard rule
for unreachable semantics nodes.

This is Flutter framework/native adapter interoperability, not an incorrect Lineup
label, missing directory boundary, or application-owned semantics node. The
reproducer uses supported stock widgets, with native accessibility already active
and healthy. It needs no media, native player, custom animation, custom render object,
forced Dart semantics handle, or startup race. The adapter is shared desktop
code; this investigation does not claim the defect is exclusive to macOS.

The application mitigation now removes tooltip overlays when an app menu excludes
its underlying route or a Player overlay retires. No engine patch was made.
M-02/M-03's Dart repairs remain separate from this runtime failure.

## Standalone reproduction and first rejection

The [standalone source and instructions](../../tool/macos/ax-tooltip-repro/README.md)
create a stock Flutter macOS project outside this repository. Activate native AX,
confirm its healthy baseline, then select:

1. **Show tooltip**.
2. **Exclude origin**.
3. **Change tooltip message**.

The final three-button source contains no tracing. Release reproduced:

```text
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: 9 will not be in the tree and is not the new root
```

IDs vary. The earlier traced prototype had one additional unused Reset button;
its [sanitized five-delta fixture](../../tool/macos/ax-tooltip-repro/first-rejection.json)
records the exact first rejection:

| Batch | Traversal state | Native result |
| --- | --- | --- |
| 1 | Complete root 0; origin 8 reachable | Accepted |
| 2–3 | Tooltip overlay 9 and text 10 grafted under origin 8 | Accepted |
| 4 | Parent 3 drops origin 8; nodes 8, 9, 10 become unreachable | Accepted |
| 5 | Only tooltip text 10 updates, still unreachable | Rejected: node 10 is not in the tree |

Before exclusion, text 10's traversal ancestry is
`0 → 1 → 2 → 3 → 8 → 9 → 10`. Overlay 9 remains physically attached elsewhere:
node 1 has hit-test children `[9, 2]` while its traversal children are `[2]`.
Removing the origin therefore removes traversal reachability without physically
detaching the overlay. Its subsequent dirty text record still reaches the engine.
The retained traversal graph is complete and acyclic; the rejected batch adds no
reachable missing child, cycle or duplicate parent. The initial native tree was
established and four accepted batches preceded the rejection.

The full animated reduction separately generated both the removed-node and
pending-node error forms. Its initial full snapshot contained a complete root
component plus disconnected tooltip nodes; the manual reduction above eliminates
that timing requirement.

## Toolchain and source evidence

| Input | Identity |
| --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 |
| Framework | `abaf9c523780a608bd46686fd5e53740a07077f8` |
| Engine | `deb287481e3ce9468f3434937ced4240a70539ca` |
| Host | arm64, macOS 27.0.1 (26A434) |
| Product source during diagnosis | `2496c45e`; app code unchanged since `1b2f64f4` |

These are paths in the pinned Flutter checkout, not application code:

- `packages/flutter/lib/src/widgets/raw_tooltip.dart:801–891`: the tooltip uses
  `OverlayPortal` and its overlay carries semantics.
- `packages/flutter/lib/src/widgets/overlay.dart:1833–1838`: overlay semantics can
  disappear with the origin's semantics while the overlay remains visible.
- `packages/flutter/lib/src/semantics/semantics.dart:4217–4269`: traversal grafting
  and physical ancestry are distinct. `SemanticsNode.detach` at 3267–3313 walks
  physical children. At 5064, `SemanticsOwner` serializes an attached dirty node;
  traversal reachability is not a prerequisite there.
- `engine/src/flutter/lib/ui/semantics.dart:1812–1815`: the public retention rule
  discards nodes unreachable from root after an update; unchanged nodes need not
  be resent.
- `engine/src/flutter/shell/platform/common/accessibility_bridge.cc:50–124`:
  `CommitUpdates` converts all supplied records and calls `AXTree::Unserialize`.
  It does not discard this unreachable record before the stricter validator.
- `engine/src/flutter/third_party/accessibility/ax/ax_tree.cc:1330–1350` rejects
  the unknown non-root node. Lines 1779–1787 reject nodes left pending.
- Android's `shell/platform/android/io/flutter/view/AccessibilityBridge.java:1582–1634`
  and iOS's `shell/platform/darwin/ios/framework/Source/accessibility_bridge.mm:199–203`
  explicitly traverse from root and remove unreachable objects. These paths are
  relative to `engine/src/flutter/` and corroborate the retention rule.

The grafted snapshot can have different physical hit-test and traversal ancestry.
The specific native traversal-grafting documentation at `lib/ui/semantics.dart:1879–1887`
permits that distinction; the framework's comment at `semantics.dart:4203–4209`
limits its same-length assumption to web. The rejected node itself has both child
lists empty. Classification rests on the accepted traversal history and the
unreachable-node retention rule, not an assumption that physical and traversal
ancestry must coincide.

There is also a logging defect: the bridge ignores `Unserialize`'s boolean return
and checks the tree's stored error string, which `AXTree::Unserialize` does not
clear on success. Repeated messages can therefore include a stale error. Counts
below are **log messages**, not counts of independent invalid updates. Capturing
the first rejection is essential.

## Verification and controls

- Final source formatting and targeted Flutter analysis passed; Release compiled.
  A fresh `flutter create` runner, copying only the final source, reproduced the
  same rejection with no native observer, pass-through builder or native changes.
- Final uninstrumented source: reachable tooltip Show → Change message control
  produced zero AX errors; fresh Show → Exclude → Change produced the rejection.
- Traced manual prototype: exclusion without a shown tooltip, and Show → Exclude
  without a later message change, produced no rejection.
- Plain synthetic Lineup routes, frequent synthetic playback updates, matching
  native window/container, startup MaterialApp replacement, 60 clipping cycles,
  and 60 tooltip show/hide cycles did not reproduce the failure.
- A separate forced-`ensureSemantics` positive was rejected as production evidence:
  it lost the initial native snapshot during late activation. The matched
  unforced control completed with zero errors. The final manual reproduction has
  no forced handle and starts from a healthy native tree.
- Two instrumented real Release runs and an unchanged Release control did not
  reproduce M-04 in this follow-up. Checks included the recorded fullscreen →
  tune → Now Playing sequence; the instrumented runs also exercised route/DVR
  transitions, directory navigation and superseding channel loads. The unchanged
  control rules out tracing as the sole explanation for these negative results.
  They do not invalidate earlier positive production evidence.
- Native engine binary hash matched the earlier failing candidate. DVR was
  restored Off. VoiceOver was restored Off after temporary activation controls.
  The real app quit normally; raw captures remain local under `/tmp/lineup-audit/`.

## Historical production evidence and limits

Original audit app `fa1760872ffc69dd61644cb09e0b0a64a130f5f4`, Release:
`/tmp/lineup-audit/app.log` contains 1,508 messages (1,218 pending-node,
290 removed-node). First at line 71: removed node 2026; last at 2066: removed
node 490. All were emitted at `accessibility_bridge.cc(114)`.

Corrected candidate `1b2f64f4`, Release: `/tmp/lineup-audit/post-fix-app.log`
contains 614 messages (373 pending-node, 241 removed-node), first at line 19
(removed node 134), last at 678 (removed node 569). Its short observed sequence
was native Guide AX capture → native fullscreen → current programme tune →
Now Playing, followed by management navigation. Visible UI continued rendering;
some AX snapshots collapsed to the application container, while other routes
recovered. The first logged error followed fullscreen/media-surface activity.

These logs contain neither the first Dart delta nor native AX activation history.
Lineup uses tooltip widgets and outgoing `ExcludeSemantics`, so the standalone
sequence is relevant to its current UI. The evidence establishes the failure
class and runtime ownership; it does not prove which historic tooltip/node or
transition produced the first production rejection. M-04 remains open for that
exact linkage and real-app acceptance. No private media data enters the fixture.

The old forced-semantics 200-swap attempt had zero errors, but native bridge
activation was not established. Its negative result is not an AX health control.

## Upstream report and bounded workaround proposal

The source, toolchain identities, controls and five-delta fixture above are an
upstream-ready report package for Flutter's desktop semantics adapter. Report
that the adapter rejects a dirty node after its traversal subtree was discarded,
while a stock Tooltip overlay remains physically attached. Include the separate
stale-error logging behavior without treating every repeat as a new rejection.
No upstream issue has been published.

The upstream correction must reconcile Flutter's retained/traversal semantics
with AXTree, including unreachable records and retained subtrees. Suppressing
unreachable framework records or adapting them in the bridge are upstream design
choices. This round does not patch the engine or select that implementation.

The user authorized testing and applying the bounded application workaround.
The same standalone source now supports `REPRO_TOOLTIP_VISIBILITY=true`:
Show → Exclude → ten message changes produced zero native AX errors. Rebuilding
the same source without the define reproduced the rejection on the first change.
`TooltipVisibility(false)` removes `RawTooltip` immediately; calling
`dismissAllToolTips()` alone leaves its reverse-animation lifetime active.

Lineup applies this policy at both app-menu route exclusions (ready and
account-onboarding) and only the retiring children of Player's `AnimatedSwitcher`.
Shell scopes combine inherited visibility with their own exclusion condition;
current Player children inherit their scope instead of overriding it with true.
Regression tests exercise immediate removal, reopening/restoration and inherited
false. Existing accessible names and the approved Player layout are preserved.
Real Release and Windows verification are recorded in the follow-up progress entry.

**Limit:** this is not global M-04 closure. A separate stock probe with the origin
excluded from the outset also rejected a newly shown tooltip. Lineup's permanently
excluded Now Playing details and track-row content still contain visual tooltips.
Their existing hover information is preserved; the transition guards do not repair
that pre-existing path. A broader correction should investigate reachable tooltip
origins or an upstream runtime repair without removing those features. The
GPT Pro review handoff explicitly includes this limitation. Historical production
causality and spoken assistive-technology acceptance also remain open.

### Release verification of the mitigation

Candidate `296ab90588b6d1312e7a1b992142077fed1146c3` was built with the canonical
wrapper and identity `0.1.0`, `1@296ab90588b6d1312e7a1b992142077fed1146c3`.
Native AX was healthy before interaction. Pointer movement exposed real tooltips:

- Guide menu tooltip → app menu: tooltip removed, menu controls accessible;
  dismissing the menu restored tooltip availability.
- Player Exit full screen tooltip → audio options: outgoing OSD tooltip removed;
  returning to OSD restored it.
- Player menu tooltip → app menu: removed while playback/background updates
  continued for five seconds; menu AX remained populated.

There were zero AX errors through these guarded transitions. The subsequent
explicit Now Playing → hover cast-name tooltip check reproduced the unguarded
static path: first error at line 24, removed node 268. The completed log contained
55 messages, including possible stale repeats. This directly confirms a remaining
production trigger, not just a hypothetical code path. It does not identify the
first historical audit delta or establish that all prior failures shared it.

The app quit normally. Raw screenshots, AX captures, stderr, runtime summary and
binary/define identities stay private under
`/tmp/lineup-audit/m04-lineup-workaround/`. No media information is copied here.
The result is **targeted transition verification passed; general M-04 acceptance
still failed at cast hover**, not a clean accessibility acceptance result.

The full local 1,792-test suite, canonical formatting and analysis passed. Windows
[verification run 39170620921](https://github.com/TJZine/LineupDesktop/actions/runs/39170620921)
also passed. Its verification commit `159fd599aee9ab8c7074ca292e517116342d89b9`
differs from the product candidate only in the isolated CI workflow, without
release/package jobs. See the progress entry for the native-check scope and limits.

## Independent review

A fresh adversarial read-only review checked all five changed files, the fixture
against the raw five-delta trace, final stock-runner identity, runtime log and
pinned source ownership. It found no material correctness, classification or
privacy issue. Its minor wording finding was corrected: the reproduction needs
no **custom** animation; stock Tooltip still has its built-in fade. The reviewer
explicitly retained the historical-production and workaround-efficacy limits.

A separate fresh review accepted the transition mitigation and its behavioral
tests before source integration, with no blocking findings. Final evidence and
GPT Pro handoff review checked the successful CI, runtime summaries and links,
retaining the confirmed cast-hover failure as an open acceptance limit.


## Pro review follow-up: static origins and recovery notifications

The Pro review correctly identified an additional consequence of the pinned
common desktop bridge's retained error string. `CommitUpdates` ignores the
boolean result of `AXTree::Unserialize` in both its reparenting prepass and main
update. Successful `Unserialize` does not clear the stored error. A later valid
main update can mutate the tree but return before `OnAccessibilityEvent` and
`event_generator_.ClearEvents`; the prepass can also stop on an old error. Thus
message totals are neither independent rejection counts nor proof of recovery.
The exact spoken consequences in historical Lineup runs remain unknown.

The proposed upstream report should include the stock reproduction and five-delta
fixture, plus a failure → valid update regression proving notification delivery
through both paths. Failure handling should use each current boolean result,
consulting the error string only to describe that failure. This recovery correction
is separate from reconciling unreachable semantics records and does not itself fix
the first rejection. No engine source was changed and no upstream issue was posted.

Before application changes, the separate stock
[`static_origins.dart`](../../tool/macos/ax-tooltip-repro/static_origins.dart)
Release comparison established healthy native AX without a forced Dart handle.
The default permanent-exclusion control rejected Show. Both repaired structures
passed Show → ten message changes → Exclude → Change → Restore → Show with zero
AX errors: a reachable tooltip outside a redundant visual leaf exclusion, and a
tooltip outside an actionable canonical row's exclusion. The row's native AX
activation incremented its counter. Full hover text and canonical labels remained
present. These are topology/lifecycle controls, not a spoken VoiceOver assessment.
Raw logs and AX snapshots are private under
`/tmp/lineup-audit/m04-static-origins/`.


## Guide Now: independently reduced missing portal origin

The clean `352a74aa` Release follow-up established healthy native AX, then rejected
an actual Guide Now tooltip hover before any menu interaction. This narrows the
previous preflight (Guide/menu/fullscreen, first removed-node error 138), whose
first action was not isolated. The node number alone does not identify a widget.

A full-shell Dart probe found the overlay physically reachable by raw child DFS,
but absent from effective accessibility traversal. Its traversal-child identifier
had no matching traversal-parent identifier. Later's tooltip retained a matching
pair. Now's Tooltip sits above a TextButton semantics boundary; its origin marker
can merge upward into a shared annotated ancestor containing another portal marker.
`SemanticsConfiguration.absorb` retains only one traversal-parent identifier. The
grafting path removes the overlay from physical traversal expecting to reattach
it at an origin that is now absent. A raw `visitChildren` walk therefore is not
sufficient proof of effective traversal reachability.

The new stock [`button_origins.dart`](../../tool/macos/ax-tooltip-repro/button_origins.dart)
contains two ordinary Tooltip/TextButton siblings beneath a shared annotated
Semantics widget. It reproduces the missing pair portably, and fresh native
Release rejects Show. Bare siblings without the shared annotation did not
reproduce this control; those discarded models are not positive evidence.
An explicit outer `Semantics(container: true, explicitChildNodes: true)` preserves
an independent origin. Native Release exposed both the canonical button and its
full hover text through ten button activations/message updates with zero AX errors.
A boundary inside Tooltip or removing `excludeFromSemantics` did not fix the
portable control. No engine source, forced Dart handle or framework patch was used.

Lineup applies that outer boundary only to the affected Now tooltip. Two full-shell
regressions cover Now and Return to live, asserting visible overlay construction,
canonical button name/action and hover-label reachability through effective root
traversal. Both fail on the original structure. This adds a framework portal-marker
merging reproduction to the upstream evidence; it does not repair Flutter's common
bridge or establish every historical failure's cause. Native equivalent-Lineup
acceptance is recorded separately in the closing report. Private controls and
probe logs remain under `/tmp/lineup-audit/m04-static-origins/` and
`/tmp/lineup-audit/m04-review-round/`.


## Final bounded application verification and separate Studio topology

Clean Release candidate `d56a391b545d5d06fd967312023516ea5da25d06` completed a fresh
native AX pass with zero update-failure messages: Now and Return-to-live hover,
exact Later invoker restoration/Enter activation through menus with/without a
visible tooltip, cast-name hover/menu exclusion/restoration, audio title hover/row
action, subtitle title and Off hover, then normal Quit. Cast-role data was not
available in the inspected programs, so its proof remains widget/stock-native.
Native track selection confirmation and spoken output were not established.
The first historical audit delta remains uncaptured. These passes cover the known
application triggers and do not repair Flutter's update/recovery implementation.
Exact build/runtime manifests and private captures are identified in the closing
report; they are not copied into shared evidence.

That run also exposed a separate M-03 integration defect: Studio's clear-search
suffix was visibly actionable but missing from native AX despite its Dart label.
Flutter TextField places `suffixIcon` beneath its own semantics node, which
absorbs RenderEditable's text-field flag. The macOS delegate maps that node to
FlutterTextPlatformNode / an NSTextField, whose native representation does not
forward these Flutter descendant buttons. A suffix boundary or another label
cannot move the action out of the native leaf. This is a Dart topology correction,
not another AXTree update rejection.

Candidate `ac995ec58c92ef491098f8a5afcc1da60cd65ad0` places the clear action as a
semantics sibling in the same trailing position, retaining the InputDecorator
suffix reservation, density-adjusted interactive width and search focus.
The root-traversal regression rejects any text-field ancestor before/during
hover; the old structure fails. Native Release now exposes the named button and
its accessibility activation clears the query. The test draft was discarded,
normal Quit completed and the entire log contains zero AX update failures.
The native Clear-hover attempt was blocked by CUA `noWindowsAvailable` before
input; opened-tooltip reachability has widget evidence. Earlier cast/track/focus
runtime results retain their `d56a391b` attribution, with unchanged relevant
product sources. No engine source, accessibility setting or upstream issue was
changed. Raw final captures stay under `/tmp/lineup-audit/m04-final-origin-round/`
and `/tmp/lineup-audit/m04-studio-final-round/`.


## Second-review candidate: residual native failure remains open

Clean Release `d5e09e0a53810c836e166d528a9224b8cfab0002` initially had a healthy
native tree. Guide Clear's sibling name, actual pointer hover and accessibility
clearing passed with zero AX error messages. Initial direct/menu Return and
keypad activation cleared the query, but later repetitions and Command+A became
inconsistent. A visible Clear focus ring disagreed with the native focused-element
field (text field). Forty repeated actual-Tab activations and Command+A passed in
a temporary full-shell macOS/no-match widget probe. Neither the native snapshot
nor that widget result resolves actual native focus/event delivery. This remains
an open keyboard acceptance observation, not a proven Dart regression.

The later route Settings → Playback → DVR On → Back to Guide → select current
program produced the first failure at the tune boundary. The unchanged engine
logged at app-log line 4:

```text
Failed to update ui::AXTree, error: 866 will not be in the tree and is not the new root
```

The native tree degraded to the application/window skeleton; the log accumulated
574 failure messages through normal Quit. Message totals do not identify distinct
failed updates, given the retained-error behavior described above. The exact first
originating node/delta was not instrumented in this clean Release run. Its error
class matches the existing investigation, but the precise application trigger and
whether another Dart-side mitigation is appropriate remain unestablished. Earlier
bounded zero-error passes retain their earlier candidate identities and do not
close this positive observation.

No engine patch is proposed from this new evidence alone. A next investigation
should capture the first semantics delta and portal/origin identities for this
exact route, reduce that topology in the existing standalone harness, and compare
healthy fresh-process controls before choosing a Dart workaround or extending the
upstream report. Do not infer that repeated key attempts or the new Clear sibling
caused the rejection without that trace. Visual playback verification continued,
DVR was restored Off, and normal Quit ended the app. Exact build/manifest identities
and the separate keyboard limit are in the closing report; private captures are
under `/tmp/lineup-audit/pro-round2/`. Accessibility sign-off remains open.


## Third review investigation: first production graph and Slider origin

Product base `f2b76202625215bd0bcc14aefd1911db49663932` was copied to an isolated
worktree for temporary diagnostic Release builds. The final V2 patch and binary
identities are recorded in the [closing report](macos-post-audit-fix-report.md).
The diagnostic binding forwards all original SemanticsUpdateBuilder arguments;
it captures final outgoing traversal/hit-test children and a bounded physical
inventory including every portal origin/child. It does not force semantics.
Native event observations are pass-through. No engine or production source patch
was made for this investigation.

V2 began with healthy native AX and keyboard/query-reset checks. Settings →
Playback → DVR On → Back to Guide → current-program tune produced the first native
error at raw line 791: `378 will not be in the tree and is not the new root`.
This is one shared process with earlier keyboard history, not a fresh AX-only run.
Immediately preceding Dart batch 671 updates nodes 1, 378 and 12. Retained replay
has no reachable missing child, cycle, duplicate parent or reparenting:

| Observation | Captured state |
| --- | --- |
| Effective root graph before/after | `0 → 1 → 2 → 3 → 12` |
| New updated node | 378, empty full-window leaf, no label/value/hint/tooltip/action |
| Physical ancestry | `0 → 1 → 378` |
| Portal marker | child token 97; no matching parent in the complete portal inventory |
| Prior occurrence | Neither 378 nor token 97 appeared earlier |
| Route/phase | Guide/idle → Player/loading, overlay none → Player/playing, OSD |

This is a newly emitted unreachable portal, rather than a retained tooltip text
mutation. The graph proves topology, not the owning widget instance. The strong
source correlation is the DVR Slider built by the entering OSD fade:

- `player_view.dart` puts newly entering overlays under FadeTransition, initially
  alpha zero; its DVR-enabled OSD contains an ordinary continuous Slider.
- Pinned `material/slider.dart:681–683` eagerly shows the value-indicator portal;
  lines 1009–1015 build it even without hover/drag. The continuous Slider's default
  discrete-only indicator can be an empty child (1057–1074).
- `rendering/proxy_box.dart:1083–1086` omits zero-alpha fade-child semantics.
  OverlayPortal's physically separate child remains capable of emitting a record
  after its origin has been elided. The common desktop bridge forwards that
  unreachable record to the stricter AXTree validator.

The new stock [Slider reduction](../../tool/macos/ax-tooltip-repro/slider_fade.dart)
starts with healthy native buttons and no Slider. Mounting a continuous Slider
inside FadeTransition held at zero produces a new full-window empty portal leaf
(node 9, child token 1, no origin) and the first unknown-node native error. A fresh
visible mount exposes the native Slider at 50% with zero errors; fading that
already-mounted control to zero also had zero errors in that bounded comparison.
A separate genuinely uninstrumented stock project with an unchanged native runner
also rejected the hidden mount after healthy AX; its fresh visible mount exposed
the Slider at 50% and logged zero errors through normal Quit. The uninstrumented
failing process logged two messages through Quit, not two established failures.
This matches the new production topology without media, a player, tooltips or
application semantics. It strongly supports the Slider mechanism for this new
failure, but does not identify historical node 866 or every M-04 occurrence.

A compact [first-error graph fixture](../../tool/macos/ax-tooltip-repro/slider-first-rejection.json)
keeps the new production graph and standalone comparison without private labels,
queries, media identities or URLs. Traced and uninstrumented stock controls retain
separate identities in the source instructions. Raw logs, full deltas and AX
snapshots remain private under `/tmp/lineup-audit/pro-round3/`.

### Recommended follow-up, not an implemented third fix

Add this stock sequence and failure graph to the existing upstream-ready package;
no upstream message has been sent. The root interoperability issue is still the
framework emitting an unreachable portal record and the common desktop bridge
rejecting it rather than applying Flutter's reachability contract. The separate
retained-error/notification issue also remains open.

For a bounded Lineup mitigation, first test coupling the Slider's mounted lifetime
to its semantics origin's availability, preserving the approved geometry and
animation through a noninteractive placeholder where needed. Cover both first
entering alpha zero and retiring menu/overlay exclusions before choosing a patch.
`showValueIndicator: never` alone does not remove the eagerly shown portal.
`alwaysIncludeSemantics` on the entering fade is only a diagnostic alternative:
it exposes invisible controls and does not solve retiring ExcludeSemantics paths.
Neither a global semantics override nor suppressing error logs is recommended.
No new Slider workaround was integrated in this round; it needs a tested policy
for hidden controls and its own regressions, Release check and independent review.

Optional LLDB probes were attempted against matching stock symbols, but optimized
inline frames made the function/return identity ambiguous. Their Boolean results
are explicitly untrusted and unused. This investigation establishes the first
logged error and preceding emitted graph, not a debugger-verified assignment of
every native Unserialize result. The retained-error source diagnosis remains
valid; successful recovery/event delivery was not established at runtime.

## Keyboard investigation alongside AX

On clean stock `f2b76202`, twelve actual-Tab direct/menu Return/keypad Clear
activations passed; synthetic Command+A then left the query unselected. Zero AX
messages occurred in that sequence. Diagnostic V1 subsequently captured a rapid
F2/Escape interleaving: Escape reached Guide before the menu acquired focus, the
menu stayed/reopened, and Return activated its Guide item. Clear regained focus
afterward but its callback did not run for that Return. A staged open-menu →
Escape → observed-close → Return control cleared successfully. This explains
that captured sequence only; older uncaptured failures remain unresolved.

Native V2 confirmed synthetic Command+A arrives while the app/key window/search
responder are active, but flagsChanged uses A's keyCode 0 and only combined
Command flag `0x100000`. The sided bits `0x8`/`0x10` are absent. Pinned
`FlutterEmbedderKeyResponder.mm:201–207,531–562,741–776` synchronizes the sided
modifier mask and cannot create Meta state from those events; Dart A therefore
has Meta false. A separate stock MaterialApp → Scaffold → TextField reproduces
selection remaining collapsed at 16 and replacement appending to 17/18. The
[stock keyboard probe](../../tool/macos/ax-tooltip-repro/keyboard.dart) preserves
only length/selection and allowlisted key-state logging; the temporary native
observer was used solely for the private event correlation.

Recommend fixing the synthetic input representation or reporting that compatibility
case at the automation/embedder boundary, with both native flags and Dart state.
A physical Command flagsChanged event normally includes sided flags and keyCode 55/54;
no physical input was captured, so this does not establish a physical macOS or
Lineup select-all defect. Do not add an app shortcut workaround from this result.
The separate rapid menu-focus race is a possible interaction follow-up; whether
Escape must dismiss the opening menu before its focus transfer needs a defined
regression and correction, rather than attributing every Clear failure to it.


### Post-unlock Close Guide: separate application focus gap

The real 30-minute timer stopped the diagnostic Release in Guide. After desktop
unlock, a background AX tap reached live Close Guide node 853, but Flutter primary
focus was its root without a mounted widget context. The existing
`_openAppMenuFromCurrentFocus` returns without an anchor in that state, leaving
the menu closed. The outgoing record confirms node 853 is the current close action;
this is not inferred from a stale native node number or a new bridge error.

Foregrounding the same process and activating Close once opened the usable menu
with stopped playback/no pending tune. Settings navigation worked, DVR was restored
Off, and normal Quit completed libmpv shutdown. The final diagnostic log contains
494 failure messages; populated later snapshots do not prove notification recovery.
This is bounded diagnostic Release evidence, distinct from the stock Release.

The root-focus no-op is an application-owned pre-existing menu-anchor dependency,
separate from the sleep-origin flag removed by `e7d7f098` and from Flutter's AX
portal failure. A follow-up should pass a stable explicit Close invoker context
and owned focus anchor, and test semantics activation after clearing primary focus
to the root. No extra product change was integrated here. The closing report and
fresh review prompt retain this open finding; raw captures remain private.

## Fourth review adjudication and bounded containment comparison

The newly supplied GPT Pro report was adjudicated against current application
source, the pinned framework/engine source and the retained evidence before edits.
Its two M-04 findings are accepted at the framework/common-desktop-bridge boundary:
unreachable portal records can trigger AXTree rejection, and checking retained
`error()` instead of the current `Unserialize` result can suppress later event
delivery/clearing. Neither is fixed by this application round. Production Slider
ownership remains strongly correlated rather than instance-identified; historical
node 866 and older uncaptured failures remain unattributed. The excluded debugger
Boolean probes and repeated-message limitations remain unchanged.

The report's local-overlay suggestion was tested outside Lineup before choosing
any product mitigation. The retained
[`slider_containment.dart`](../../tool/macos/ax-tooltip-repro/slider_containment.dart)
compares identical 40-pixel progress Stacks with the route overlay versus a local
`Overlay.wrap(clipBehavior: Clip.none)` around only SliderTheme/Slider. The visible
progress line stays outside that local overlay. No engine patch, forced semantics
or Lineup/media dependency was used. Native runners redirect stderr only; this is
explicitly distinct from the earlier unchanged-runner controls.

After healthy native AX, the default hidden mount rejected new node 13; its fresh
visible control exposed Slider 50% and logged zero errors. The local-overlay hidden
and separate visible controls logged zero AX errors through bounded value changes,
fade retirement/restoration, exclusion/restoration, rapid reversal and removal.
Visible restoration exposed the updated 60%/70% values. Exact sequence coverage,
binary/source hashes and controls are in the
[reproduction README](../../tool/macos/ax-tooltip-repro/README.md#local-slider-overlay-containment-comparison).
Raw evidence stays under `/tmp/lineup-audit/pro-round4/`.

This is promising bounded native evidence, **not M-04 closure or an integrated
mitigation**. No outgoing graph or direct notification delivery was captured in
this comparison. Slider keyboard/drag/focus preservation and geometry were not
established: the CUA screenshot was unusable, and attempted click/Right/Tab did
not prove adjustment. Menu-during-entry, route replacement, DVR insertion/removal,
text scaling and approved-layout equivalence remain to be checked. The
[Opus 5.5 handoff](macos-m04-opus-review-handoff.md) requests a second independent
assessment before a product direction is chosen. No Slider lifetime policy or
containment patch is integrated into Lineup, and no upstream publication occurred.

The separate application Guide gaps are corrected through product `459fd726`:
Close supplies its owned invocation anchor, routing reads live availability, and
an opening menu wins over Guide Back. Corrected original-source controls fail the
intended menu assertions; combined affected tests pass 454 checks, with fresh
independent review. Native Release one-action stopped-Guide Close/menu navigation
and four rapid-menu Clear sequences also passed. These do not directly prove
Flutter root focus in that binary or physical input. The closing report retains
historical failed background activation and records the new candidate separately.

## Opus follow-up: retirement, structural change and containment

The user supplied the independent Opus implementation handoff after the fourth
round. Its findings were adjudicated against the pinned source and local probe
artifacts before implementation. Gate A was then resolved explicitly by the user:
accept the unlabeled Slider group and its order after the OSD controls. No group
label was invented. The Player's approved visual geometry remains unchanged.

The retirement refinement is accepted. AnimatedSwitcher moves its previous child
under ExcludeFocus → ExcludeSemantics → TooltipVisibility without a matching
stable wrapper; the retiring OSD subtree is remounted under exclusion. This is
distinct from hiding an already-mounted Slider by fading or excluding a stable
ancestor. The existing retirement wrapper is preserved in this unit. A separate
[stock retirement control](../../tool/macos/ax-tooltip-repro/slider_retirement.dart)
starts with a visible Slider and healthy native AX, then rejects retirement with
unknown node 13 by default. The local-overlay comparison retires/restores the
Slider, reverses mid-fade and exposes updated native values without logged AX
errors. The default's two messages do not establish two independent rejections.
The [README](../../tool/macos/ax-tooltip-repro/README.md#slider-retirement-remount-discriminator)
records exact source/binary identities and the logging-only runner difference.

The excluded-leaf resize refinement is also accepted at the outgoing-update
layer: value changes need not dirty the empty portal leaf, whereas a resize while
the menu excludes the origin does. The retained regression therefore includes
that resize and the shell-equivalent real ModalBarrier/focus/exclusion structure.
The structural recorder forwards every argument in the pinned semantics API;
its replay includes bridge reparenting and parent-first ordering, destruction,
pending-child initialization and unreachable-record validation. Two opposing seed
orders are samples of native unordered-map ordering, not an exhaustive proof.
There is no event/cache/native/VoiceOver emulation or recovery claim.

The approved mitigation wraps only SliderTheme/Slider in a local
`Overlay.wrap(clipBehavior: Clip.none)` inside the existing 40-pixel progress
Stack. The separate 4-pixel visible indicator, progress semantics, styling,
callbacks and AnimatedSwitcher remain intact. The explicit group/order regression
pins actual control identities and effective emitted traversal, not allocated IDs.
New transition and interaction tests cover entry, retirement, reversal, menu
during entry, resize while excluded, route replacement, other OSD destinations,
keyboard/drag/hit testing, menu state survival and hidden noninteraction.

The rejected-batch refinement is retained with a narrower source claim than the
supplied handoff's general atomicity wording. The unknown-node error identified
here occurs during `ComputePendingChanges`, before the main structural mutation;
the bridge nevertheless clears that main batch, losing its valid updates too.
Its reparent prepass is a separate prior operation. Other `Unserialize` failures
can occur after `UpdateNode` begins mutating, including pending-child completion
failure. Therefore **not every rejected update is atomic**. There is no established
automatic full resynchronization after a discarded update, and fixing retained
`error()` checks alone would not establish recovery. No engine correction or
upstream publication is included. Historical node 866 remains unattributed.

Exact reviewed product, portable checks, fresh native Release sequences, CI
identities and remaining acceptance are recorded in the closing report. M-04 and
overall accessibility acceptance remain open; spoken group/order behavior stays
in the existing single final human checklist.

The integrated mitigation is product `5c6349d4cf43244da9989fb72f298ac2acb614b0`.
Its exact canonical Release ran in four fresh processes after healthy native AX:
entry, dismissal/restoration, menu exclusion with actual window resize, and rapid
OSD-show/menu opening. All four logs contain zero AXTree/Flutter error messages
through normal Quit. The resize changed the real outer window from 800×632 to
1728×1084 and back while the menu remained open; Slider returned afterward.
CUA native traversal places it after the OSD controls. This is bounded native
evidence, not a direct observer of bridge return values or notifications.

The rapid native sequence cannot establish the precise entry interleaving:
observation/click completed at 965/989 ms after show, compared with the ordinary
350 ms fade. The native bare group's role was not independently extracted:
Inspector could bind the process, but CUA supplied unusable transformed-thumbnail
pointer geometry. Exact first-frame interleaving remains controlled Dart proof;
native group/order and spoken behavior stay open. These are evidence limits, not
newly claimed native failures. The starting channel, original window size and
DVR Off were restored, and all test apps/Inspector are closed.

Final focused tests pass 17/17; 198 affected tests and all 1,847 local tests pass
with the diagnostic assertion-order reuse described in the report. Fresh review
`01a15549-f33f-79e0-a782-03c26f736941` reconciled the baseline evidence before
integration. Windows/Linux verification `865c5c3a71981fe17f9312fdf02ee2eb4c464d20`
passed 1,845 Linux tests, 734 selected Windows tests, stock compilation and all
eight selected native/reference CTests. This is not physical Windows AX acceptance.

## Second Opus follow-up: changing Slider interactivity

The returned second review exposed a new containment regression on `5c6349d4`:
changing a visible Slider between enabled and disabled replaces its unlabeled
semantics group, resending Slider but not its empty grafted portal leaf. The
pinned bridge only asserts that a reparented child has a pending record. In
Release it can remove/destroy that leaf in the successful removal prepass, then
reference it without initialization in the main update. This is distinct from
the earlier unreachable-node preflight failure.

The controller reproduced the outgoing missing-record condition independently,
then stock native Release controls reproduced `Nodes left pending` in separate
healthy processes for both enable and disable. The retained replay diagnoses
the absent record earlier than native Release; it does not model its partial
mutation. Both keyed stock controls exposed usable subsequent values with zero
AX errors. The [repro README](../../tool/macos/ax-tooltip-repro/README.md#visible-slider-interactivity-discriminator)
records exact variants, hashes and limits. The unchanged stock runner was shell-
launched with stdout/stderr capture, with no forced Dart semantics or engine patch.

Product **`8105f73c9b5891e880d9fa292f0b26d679238a41`** keys only the local
Overlay on the same condition that controls actual Slider interactivity. A flip
remounts Slider and portal together. Same-interactivity value/max/menu updates
retain state. Five new tests independently start healthy before each flip;
all fail on the prior product for the intended first missing-record condition,
then pass with the fix. The focused file passes 22/22 and the full local suite
1,852, with clean canonical format/analysis and fresh independent review.

The report's general statement that all "reparented" failures happen after
mutation is rejected: pinned `ComputePendingChangesToNode` can reject with
"not marked for destruction, would be reparented" before `UpdateNode`. Completion
failures such as `Nodes left pending` occur after node updates. A failing removal
prepass need not have destroyed anything; a successful prepass can already have
destroyed moved subtrees, and a retained error can then make the bridge return
before consuming/clearing pending updates. No complete resynchronization or
notification recovery has been established for the surviving bridge/tree instance.

The actual baseline product Next-channel action completed with zero AX errors
and native Slider before/after, but no enabled/disabled flip was observed. The
report's predicted production failure is therefore plausible from source, not a
captured production transition. Historical node 866 remains unattributed. Native
group/spoken/delivery and exact timing/lifetime gaps retain their evidence limits;
the closing report owns any new bounded production observations. M-04 and overall
accessibility acceptance remain open, with the existing single human checklist.

Final product `8105f73c` canonical Release verification completed after the user
cleared its new Keychain prompt. Two fresh healthy-native-AX processes completed
entry/actual Next-channel and untimed Now Playing menu exclusion/window zoom/
restoration with zero AX/Flutter errors through normal Quit. Window facts prove
800×632 → 1728×1084 → 800×632. The untimed mode removes the earlier OSD timer
confound, but no production interactivity flip or hidden widget identity was
directly observed, and exact timed-OSD entry/lifetime cases remain bounded by the
earlier limitations. Cleanup synthetic keys after collapse did not expose
controls; native Player click restored usable OSD/menu with no AX error. This
remains an unclassified input/focus observation, not attributed AXTree loss.
DVR Off, starting channel and size were restored and all test apps closed.

[CI run 39312611152](https://github.com/TJZine/LineupDesktop/actions/runs/39312611152)
passed 1,850 Linux tests, 739 selected Windows tests, the stock Windows build and
all eight selected native/reference CTests. Verification
`6e7112e20583e65afb81023dd8e9bbf14793354a` is product `8105f73c`'s direct child
with only its isolated workflow changed. Exact head/relationship/completed logs
were checked; no active run was cancelled. This is not physical Windows AX proof.

## Third Opus follow-up: no additional semantics defect established

The final returned review accepts the bounded interactivity mitigation, with no
new defect. The controller corroborated 29 supplied scratch probes on product
`8105f73c` via a `871c7a3c` archive: 11 ported probes and 18 environment/combined
cases, all reporting no replay error. Environment State identity and combined
exception reports were also checked explicitly. These remain forced-semantics,
fake-time observations, not native notification or lifecycle acceptance.

The provisional root-focus diagnosis was not reproduced. In pinned Flutter,
`_markDetached` can clear primary focus; `applyFocusChangesIfNeeded` falls back to
rootScope only if current and pending replacement focus are both absent after
autofocus processing. The application's menu close requests the live invoker or
route focus, so detachment alone does not establish that native cleanup focus
escaped these handlers. Opus's exact shell Now Playing fixture lacked a current
program; simpler successful Player/shell focus cases do not settle the captured
synthetic no-ops.

Native Settings (MainMenu.xib → AppDelegate.openSettings → method channel → shell)
bypasses Flutter focus dispatch, but still has shell/navigation guards. Comparing
Command-comma with Escape can distinguish paths; it cannot alone prove exact
Flutter focus, same-key delivery or a binary application-versus-automation cause.
Capture input/focus at recurrence before prescribing a fix. Existing native role,
notification/spoken/recovery and node 866 limits remain open. The closing report
owns detailed adjudication; the single final human checklist is unchanged.

## Final native role/delivery and application focus follow-up

Exact product `ffcaae63` now verifies the native Slider parent as an unlabeled,
enabled `AXGroup`, with successful empty String title/description/value reads and
only `AXSlider` exposed as its child. Successful Slider AXObserver registrations
receive actual `AXValueChanged` callbacks at 95% and 97%. This closes bounded
native role/healthy-delivery gaps; it does not establish spoken output or
notification recovery after a rejected batch on a surviving tree.

A separate preexisting application focus defect is now reproduced by both a
real-shell/current-program Dart fixture and a disposable logging-only native
`8105f73c` baseline. OSD retirement can strand focus on the route FocusScope above
Player/shell key handlers. AppKit and Flutter receive Enter/Escape/F2 while
neither application handler runs. Reviewed application fix `ffcaae63` transfers
focus to the existing Player root before its focused OSD retires, with owner/
route/active-app/requestability guards. The exact uninstrumented canonical
Release independently replays the matching native sequence before each key:
Enter shows OSD; Escape and F2 each open Guide. All 1,857 local tests, completed
Windows/Linux CI and bounded native execution pass; no engine patch is included.

The [closing report](macos-post-audit-fix-report.md#native-roledelivery-and-player-focus-closeout)
owns identities, negative controls, raw-evidence hashes, native limits and normal
cleanup. Physical/spoken checks stay in its existing single human checklist.
M-04/global accessibility acceptance remain open for those checks, retained-error/
event recovery, rejected-batch divergence and historical node 866. The matching
focus failure does not identify every historical cleanup event, and healthy
notifications do not repair the engine findings above.


## Caption follow-up: keyboard focus is not the VoiceOver cursor

On the unchanged `ffcaae63` Release, full-display Screenshot UI captures expose
real caption text (“application Close, button”). The same caption remains after
Flutter's gold focus moves, and through native Cocoa control attempts. A later
restart confirms the actual VoiceOver process and unchanged caption/tracking
preferences, with speech unmuted. CUA Control-Option-Right can reach Player as a
seek. These observations do not establish successful VoiceOver navigation,
Slider/group announcement or a Lineup-specific defect.

Read-only reviewer `01a155a7-84ee-7641-b56d-fceb695328e3` traced the pinned
framework/engine, rather than current main. Material InkWell's Focus and
`widgets/focus_scope.dart` semantics publish keyboard `focused`; common
`accessibility_bridge.cc:575` copies that to `AXTreeData.focus_id`.
`ax_event_generator.cc` generates `FOCUS_CHANGED`, but macOS
`AccessibilityBridgeMac.mm:286` skips that generated event. Separately,
`flutter_platform_node_delegate.cc:73` implements `GetFocus()` using
`GetLastFocusedId()`, the accessibility-focus identity set through accessibility
focus actions, rather than the tree's keyboard focus ID. Native AX focused-state
queries consult this path. The distinct platform-node mapping of a `kFocus`
event to `NSAccessibilityFocusedUIElementChanged` does not by itself show that
the skipped bridge event reaches it.

This source mechanism makes moving Dart keyboard focus insufficient evidence
for native focus notifications or VoiceOver cursor movement. It is not a runtime
attribution of the exact stale caption, a proof of no native notification or a
newly accepted engine bug. Native Cocoa control results and failed command
interception remain relevant alternative explanations. An app focus override or
engine patch is not justified by this observation alone. Actual screen-reader
command delivery and subsequent caption changes remain the distinguishing
runtime evidence. All raw screenshots stay private; the single human checklist
and retained-error/rejected-batch/historical-node findings remain open.
