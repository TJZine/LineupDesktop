# macOS accessibility update investigation — M-04

Status: **Flutter runtime interoperability defect reproduced standalone; bounded
application transition mitigation implemented.** A small stock-widget sequence reproduces the same
removed-node rejection as M-04. Its exact delta and rejecting owner are now known.
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
