# M-04: implement local Slider overlay containment — Codex handoff

Prepared 2026-10-19 from an independent Opus 5.5 review of M-04. This
handoff carries that review's findings and a proposed implementation plan.
It is **evidence and a recommendation, not authority**: adjudicate it
against current source before you dispatch work. Treat GPT Pro's report, the
earlier reviews and this one as inputs of equal standing.

Use the shared `orchestrate-implementation-chats` skill for delegated
implementation and review, as the user instructed for this campaign. The
controller (you) owns scope, Git integration, builds, CI, native runs and
completion.

## Source identity and starting state

- Repository `/Users/tristan/Software/LineupDesktop`, branch `platform/macos`.
- The review read HEAD `a51ea124` (docs-only on top of product
  **`459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`**). Recheck `git status`, HEAD,
  origin and live CI before editing; resolve any newer source explicitly.
- Pinned toolchain: Flutter **3.47.7** / Dart **3.13.5**, framework
  `abaf9c523780a608bd46686fd5e53740a07077f8`, engine
  `deb287481e3ce9468f3434937ced4240a70539ca`, at
  `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`. Default shell `flutter`
  resolves **3.47.6**. Export the pinned `bin` on `PATH` first.
- Host: arm64 macOS 27.0.1 (26A434).
- No Slider mitigation is integrated. The review made no repository change.

Read first: `AGENTS.md`, `.agents/project.md`,
[the continuation handoff](macos-post-audit-continuation.md) (fourth-round
update and standing constraints), the M-04 sections of
[the investigation](macos-ax-update-investigation.md), the
[review packet](macos-m04-opus-review-handoff.md), and
[the repro README](../../tool/macos/ax-tooltip-repro/README.md).

## Review evidence and its limits

**Executed** (Dart/framework layer, pinned SDK): a `git archive a51ea124` copy
in a scratch directory used the real `PlayerView`, the existing
`player_view_test.dart` fixtures, and a scratch-only switch that wraps the
existing `SliderTheme`/`Slider` in `Overlay.wrap(clipBehavior: Clip.none)`.
A test binding wrapped `createSemanticsUpdateBuilder()` to record every outgoing
`updateNode`. A model then replayed each batch through the pinned common bridge's
reparent prepass and parent-first ordering
(`accessibility_bridge.cc` `CommitUpdates`/`GetSubTreeList`). It applied
`ui::AXTree` structural rules: an unknown non-root node, reparenting an existing
node, nodes left pending, and subtree destruction for removed children.

**Limits:** semantics were forced with `ensureSemantics()` under
`flutter_tester` and fake time. The AXTree model is simplified: no events, no
unignored caches, and an approximate rule for an existing child of a new node.
Its harness shell copied `LineupShell`'s `ExcludeSemantics`/
`TooltipVisibility`/`ExcludeFocus` wrapper but omitted the real menu's
`ModalBarrier` (`lineup_shell.dart:512`). This is **not native AX acceptance**.
The model's credibility rests on the default variant reproducing V2's exact
first-error shape: a two-node batch `[1, leaf]`, an empty full-window leaf with
`traversalParent -1`, and parent node 1 emitting traversal and hit-test children
`[2]`.

Local artifacts (this Mac, not committed):
`/tmp/lineup-audit/opus-m04/`. It contains the probe source appendix
(`m04_probe_appendix.dart.txt`), the scratch switch diff, full scenario output
(`probe-results.txt`), the DVR-off semantics dump, and the contained full-suite
log. Its README lists the exact scratch edits. **Source-derived** statements
below are labelled as such.

### Scenario results (outgoing updates through the model)

| Scenario | Default (route overlay) | Contained |
| --- | --- | --- |
| S1 fresh hidden entry: overlay none → `showOsd()` | Rejected on the first fade frame: new empty full-window leaf, no origin | Accepted; Slider reachable after fade |
| S2 fresh visible mount (OSD at first build) | Accepted | Accepted |
| S3 visible → `closeOverlay()` → restore mid-fade → settle | **Rejected at `closeOverlay()`**: new leaf | Accepted |
| S4 rapid show/close reversal, one frame each | Rejected (entry) | Accepted |
| S5 menu exclusion while visible → position update → **window resize** → close | Open and position update accepted; **resize while excluded rejected** | Accepted |
| S6 menu opens during entry fade | Rejected (entry) | Accepted |
| S7 DVR removal/insertion while visible | Accepted | Accepted |
| S8 retire + position update + resize | Rejected at `closeOverlay()` | Accepted |
| S9 route replacement while visible | Accepted | Accepted |
| S10 route replacement during entry fade | Rejected (entry) | Accepted |
| S11 resize while visible | Accepted | Accepted |

Behaviour comparison, default against contained, with real-Flutter rendering:

- The Slider, progress line and OSD rects were identical at 1920×1080,
  1280×720 and 800×600 at text scale 1.0, and at 1280×720 and 800×600 at
  text scale 2.0.
- `captureImage(PlayerView)` RGBA bytes were **identical (0 differing)** in all
  five configurations. These are settled frames, not mid-transition frames.
- Hit-testing at the Slider centre reaches `_RenderSlider` in both variants.
  Tab reaches the Slider after six presses in both. Arrow-key, drag and tap each
  issued one seek in both. State survived menu exclusion and restoration, and
  the Slider lost primary focus while the menu was open, in both.
- With `--dart-define` switching the scratch copy to contained, the full
  existing suite passed (**1,830**). Existing tests therefore pin neither
  the old nor the new semantics shape around the Slider.

## Findings

### F1 — Established (Dart layer): OSD dismissal is a second, independent trigger

`player_view.dart:359–375` wraps each AnimatedSwitcher `previousChild` in
`ExcludeFocus → ExcludeSemantics → TooltipVisibility`. The current child has no
such wrapper and no shared key, so at dismissal the Stack cannot match the
retiring child's element. The whole retiring OSD subtree is **remounted**
(probe: `sameState=false` across `closeOverlay()`). The Slider is therefore
freshly mounted under `ExcludeSemantics`. Its eager portal
(`material/slider.dart:681–683`, `1009–1015`) emits a new leaf with no reachable
origin. In the default structure that rejects on **every OSD dismissal with DVR
on**, not only on entry.

Consequences:

- The production "retiring exclusion" path is a fresh hidden mount, not the
  exclusion of an already-mounted control. The standalone
  `slider_containment.dart` "Exclude origin" control and the earlier
  "fade an already-mounted Slider to zero" observation model menu exclusion,
  not production retirement. Neither discriminates this path natively.
- The remount pre-dates M-04 and is not itself in this scope (see optional
  ideas). It means retirement gating would cost no Slider state.

### F2 — Established (Dart layer): containment is not semantics-neutral

Visible OSD with DVR on, in emitted traversal order under the whole-Player node:

| Variant | Children of the Player node |
| --- | --- |
| Default | empty full-window leaf, **Slider**, channel bug, OSD controls group, progress |
| Contained | channel bug, OSD controls group, **unlabeled group → [Slider, empty 40-px leaf]**, progress |
| DVR off (reference) | channel bug, OSD controls group, progress |

- Contained adds an **unlabeled group node** around the Slider. Likely
  mechanism (source-derived): the local portal leaf's `traversalChildIdentifier`
  is incompatible with its sibling origin marker
  (`semantics.dart:6749–6751`). That sibling conflict makes the marker an explicit
  node instead of absorbing into the Player node. The pinned bridge maps a
  childful node without flags to `kGroup` and marks it focusable
  (`accessibility_bridge.cc:356–361`, `376–384`). The empty leaf (no children,
  no text) becomes ignored static text in both variants.
- Traversal order changes. In the default, the Slider sorts **first**, likely
  because the full-window empty leaf overlaps every sibling vertically. That
  inference has not been traced through `_childrenInTraversalOrder`. The
  contained order matches the DVR-off order with the Slider group inserted
  geometrically.
- This is an accessibility-structure change: an extra native AXGroup and a
  different VoiceOver order. It needs an explicit decision (Gate A below),
  native Accessibility Inspector observation, and spoken checks in the existing
  final human checklist.

### F3 — Established (Dart layer): menu exclusion alone does not reject until the leaf changes

With the default structure, opening the menu over a visible Slider and updating
its value were accepted. Rejection required the portal leaf itself to become
dirty while excluded. A window resize did that: a new leaf was emitted while
its origin was excluded. Native controls that only toggle exclusion therefore
cannot distinguish default from contained on this path. Include a leaf-dirtying
step, such as a window resize, while the menu is open.

### F4 — Source-derived refinement: a rejected batch is discarded atomically

`AXTree::Unserialize` returns at `ComputePendingChanges` before any mutation
(`ax_tree.cc:973–974`, `1342–1348`). The bridge still clears all pending updates
(`accessibility_bridge.cc:107–114`). Valid nodes in the rejected batch are lost
natively, such as V2 batch 671's nodes 1 and 12, or node 1 in S1. Flutter never
resends unchanged nodes. Native and Dart trees therefore diverge, independent of
the retained `error_`. Confirmed in source: `error_` is never cleared. Because of
that, every later commit logs and returns early, and the reparent prepass can
skip its main update. Recovery would need batch-level resynchronisation, not only
correct error handling. This refines the upstream-ready report; it is not a
Lineup task. No engine change.

### Calibration of existing claims

- The handoff's "retiring exclusions" should read "retirement remounts under
  `ExcludeSemantics`" (F1). The existing native exclusion and fade-out controls
  are healthy for both variants by construction.
- The framework/bridge diagnosis stands. Precisely, the framework emits a
  physically attached node with no traversal parent and also drops it from its
  physical parent's child lists (`semantics.dart:4065–4078`). The bridge
  forwards it to AXTree instead of applying the documented reachability
  retention rule.
- Historical node 866 remains unattributed. F1 makes dismissal a plausible
  additional source, but this is not evidence about that run.
- Containment mechanism (source-derived, consistent with the executed results):
  `OverlayPortal` targets the nearest `Overlay` (`overlay.dart:1989–2010`,
  `2089–2118`). The local `_RenderTheater` visits portal children right after its
  entry for semantics (`overlay.dart:1565–1575`). Fade alpha 0
  (`proxy_box.dart:1083–1086`) or `ExcludeSemantics` therefore elides the origin
  and the leaf together.

## Gate A — decision required before product implementation

The containment changes VoiceOver structure (F2). It is a material
accessibility departure and needs user agreement. Ask **once** if the user has
not already decided in the chat that hands you this document:

1. **Accept containment's structure (recommended).** The Slider sits in an
   unlabeled group after the OSD controls, matching geometric and DVR-off
   order. Pin that order in the regression.
2. **Containment plus a group label.** Give the new group a meaningful
   container label only if native inspection shows the bare group is
   confusing. This is a further design choice; do not invent the label.
3. **Reject containment and use lifetime gating** (fallback below). This keeps
   today's structure, including the default's leaf-distorted order, at a much
   larger plumbing cost.

Do not proceed to product edits until Gate A is resolved. The regression unit
below can start in parallel, because its harness is needed either way.

## Implementation plan

### Unit 1 — regression harness and fix (one implementation chat, `worker`)

One conventional fix commit containing the regression, the fix and a progress
entry. Write ownership: the files listed here only.

1. Add a reusable test support file, for example
   `test/support/semantics_update_recorder.dart`. It holds the recording
   `SemanticsUpdateBuilder` (forward every argument to the real builder) and the
   AXTree structural model described above, including prepass and parent-first
   ordering. Adapt the probe appendix in `/tmp/lineup-audit/opus-m04/`; do not
   copy its print-based reporting. The test file must construct its recording
   binding before any `testWidgets` (one binding per test isolate).
2. Add a focused test file, for example
   `test/playback/player_slider_semantics_update_test.dart`, using real
   `PlayerView` with DVR on, a shell-equivalent menu exclusion wrapper, and
   assertions on the first rejection (none expected):
   - S1 entry (overlay none → `showOsd()`), S3 dismissal and mid-fade restore,
     S4 rapid reversal, S5 menu exclusion → **resize** → restore, S6 menu
     during entry, S8 dismissal plus position update plus resize, S10 route
     replacement during entry.
   - After restoration: the Slider is reachable from the root through emitted
     traversal children, with its expected value.
   - The **Gate A order**: the emitted traversal order under the Player node,
     and the group shape around the Slider.
   - Interaction preservation in the contained structure: Tab reaches the Slider,
     Right arrow seeks, drag seeks, Slider `State` survives menu
     exclusion/restore, and the hit test at the Slider centre reaches the Slider.
     Reuse existing `player_view_test.dart` fixtures or their pattern; do not
     duplicate existing coverage that already proves these.
   - Run it on the original source first. Record that S1, S3, S5 (resize) and
     S6 fail for the intended reason (unknown non-root node), then apply the fix.
3. Product change in `lib/playback/player_view.dart`: wrap only the existing
   `SliderTheme(… Slider …)` inside the progress `Stack` with
   `Overlay.wrap(clipBehavior: Clip.none, child: …)`. Keep the 4-pixel
   `LinearProgressIndicator`, the 40-pixel `Positioned`, the
   `Semantics(label: 'Playback progress' …)` wrapper, the theme and the callbacks
   unchanged. Add a short comment explaining why (portal and origin must share
   fade, exclusion and remount ancestry). Do not touch the AnimatedSwitcher
   wrapper.
4. Progress entry in `docs/macos-port-progress.md` with source identity,
   regression evidence and limits.

Proof the worker returns: before/after failure output, the affected test files,
`dart tool/format.dart --check`, `flutter analyze`, and the affected suites.
The controller runs the full suite once.

### Unit 2 — fresh adversarial review (separate read-only chat, `reviewer`)

Give it the diff, this handoff and the Gate A decision. Ask it to challenge:

- model fidelity against `accessibility_bridge.cc` and `ax_tree.cc`;
- whether the regression fails on the original structure for the right reason;
- untested portal paths (other overlays retiring the OSD: tracks, Mini Guide,
  channel number; `fullGuide`; sleep picker open);
- paint, hit-test and focus regressions;
- the Windows bridge, which is the same common bridge.

Reconcile its findings before integration.

### Unit 3 — optional standalone discriminator (parallel, `worker_luna`)

Only if the controller wants native discrimination of F1 outside Lineup. Add a
stock control to `tool/macos/ax-tooltip-repro/`: a visible continuous Slider
inside an `AnimatedSwitcher` using Lineup's `previousChildren` wrapper, then
switch child to retire it. Expected: the first native error at retirement by
default, none when contained. Update that README. No Lineup imports. The
controller performs the native runs. This must not block Unit 1.

### Controller verification after integration

- Canonical format and analysis, the full local suite once
  (`TZ=America/New_York flutter test`), and the Release build via
  `dart tool/macos/build_app.dart build --release`. Record exact identities.
- Native Release in **fresh processes**, establishing healthy native AX before
  each trigger (not a forced Dart handle), with an Accessibility Inspector tree
  and log scan:
  1. DVR On → Guide → tune (entry);
  2. OSD visible → dismiss (F1);
  3. OSD visible → open app menu → **resize the window** → close (F3);
  4. menu during entry;
  5. the Slider group and order as decided in Gate A.

  Restart after any rejection. Quiet logs do not prove notification delivery;
  state exactly which layer each step observed.
- Windows CI for the shared Dart change. **Check for live runs first; never
  cancel one.** Windows build or CTest is not physical Windows AX proof.
- Update [the investigation](macos-ax-update-investigation.md),
  [the closing report](macos-post-audit-fix-report.md) and the progress record.
  Add spoken VoiceOver order and group announcement for the Player OSD to the
  existing **single final human checklist**; do not create a separate request.

M-04 and overall accessibility acceptance stay open until native and human
checks pass; F4 and historical node 866 remain open regardless.

## Fallback — lifetime gating, only if Gate A rejects containment

The Slider paints nothing visible: transparent tracks, `noThumb`, `noOverlay`.
The visible bar is the separate `LinearProgressIndicator`. A same-size
`SizedBox` placeholder is therefore visually identical. Mount the real Slider
only while its origin is emitted:

- **Entry:** gate on the same animation value the `FadeTransition` reads,
  after the curve, using Flutter's rounded rule
  `ui.Color.getAlphaFromOpacity(value) != 0` (`proxy_box.dart:1054`, `1084`),
  that is opacity ≥ 0.5/255. The animation lives in `transitionBuilder` and
  must be plumbed to `_Osd`.
- **Retirement:** never mount the Slider in a retiring copy. It is already a
  fresh remount (F1), so no state is lost.
- **Menu exclusion:** requires a new explicit shell-owned signal. Do not
  repurpose `TooltipVisibility`. Unmounting a live Slider while the menu is open
  drops focus (already removed by `ExcludeFocus`) and may cancel a
  keyboard-interrupted drag. Seeks were already issued per `onChanged`, and
  the value is controller-derived.

The same regression matrix applies, except that the order assertion pins today's
structure.

## Out of scope and optional ideas

- Do not change the AnimatedSwitcher remount (F1) in this unit. A keyed, stable
  wrapper would avoid rebuilding the whole OSD on every dismissal. It would also
  change which M-04 paths reject in the default structure, so it needs its own
  assessment.
- Observation, not M-04: the non-container `Semantics(label: 'Playback
  progress', value: …)` merges into the whole-Player tappable node. The Player
  node itself is announced with that label and value. Raise it separately if
  wanted.
- No engine patch, upstream publication or message, main merge, release,
  signing or distribution. Do not retest accepted HDR/Dolby Vision picture.
  Keep private media labels, paths, URLs, credentials and raw diagnostics out of
  committed evidence; raw captures stay under `/tmp/lineup-audit/`.
