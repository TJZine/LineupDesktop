# M-04: independent Opus 5.5 investigation

Review M-04 independently in `TJZine/LineupDesktop`. Challenge the diagnosis and
the proposed application mitigation; earlier reviewers' agreement is evidence,
not authority. Work read-only and return findings before implementing anything.

## Source and scope

- Repository: <https://github.com/TJZine/LineupDesktop>, branch `platform/macos`.
- Immutable application candidate reviewed by GPT Pro:
  `f2b76202625215bd0bcc14aefd1911db49663932`.
- Standalone reproductions: `68bdc6626c16780108cd7fa3051be1bb6284fb84`.
- Evidence through `74931de95fa6f03977bdf0ba6ea05b5adba46021`; continuation
  handoff at `c439d9ba`. These later inputs do not alter that application candidate.
- The controller is now fixing three separately adjudicated application defects:
  direct-tune presentation identity during persistence, rapid Escape before menu
  focus transfer, and root-focus/live-availability Guide Close routing. They are
  outside this M-04 assignment. Resolve any newer source identity explicitly.
- At this handoff's creation, **no Slider containment product patch is applied**.
  The controller is preparing an isolated comparison. Do not infer its outcome.

Read `AGENTS.md`, `.agents/project.md`, then:

1. `docs/handoffs/macos-post-audit-continuation.md`.
2. `docs/handoffs/macos-ax-update-investigation.md`, particularly the static
   origins/recovery section and third-review Slider investigation.
3. `docs/handoffs/macos-post-audit-fix-report.md`, especially third-round evidence
   and the single final human checklist.
4. `tool/macos/ax-tooltip-repro/README.md` and `main.dart`, `static_origins.dart`,
   `button_origins.dart`, `slider_fade.dart`, `first-rejection.json`, and
   `slider-first-rejection.json`.
5. `lib/playback/player_view.dart` (entering/retiring OSD and progress Slider),
   `lib/app/lineup_shell.dart` (menu exclusion/tooltip visibility).

The new GPT Pro report is supplied separately by the user. On the controller's
Mac it is available as the attached `Pasted text.txt`; a remote reviewer must ask
for that attachment rather than assume access. Its principal M-04 recommendation
is summarized below so this packet is independently usable.

## Established observations and limits to challenge

Pinned tools: Flutter **3.47.7**, Dart **3.13.5**, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`. Observed host: arm64 macOS
**27.0.1 (26A434)**. Inspect that exact source, not today's Flutter main.

1. With native AX active and healthy, stock Tooltip → exclude its origin →
   change its message emits an attached but traversal-unreachable text record.
   The common desktop bridge forwards it to AXTree, which rejects it. The
   committed fixture describes four accepted batches and the first rejection.
   Physical children and effective traversal children are different graphs.
2. Existing application repairs coordinate tooltip retirement with exclusions,
   keep static tooltip origins reachable while excluding only redundant visual
   leaves, and isolate Guide Now's outer origin from semantics absorption. They
   preserve useful hover information and canonical actionable labels. Retain
   them unless a specific counterexample establishes a defect.
3. In diagnostic V2, after earlier healthy keyboard work, DVR On → Guide → tune
   produced first error node 378 after batch 671. A new empty full-window portal
   leaf is physically at `0 → 1 → 378`, child token 97, with no matching origin.
   Effective traversal stays `0 → 1 → 2 → 3 → 12`, complete and acyclic. This was
   one shared process, not a fresh AX-only trial.
4. A stock continuous Slider freshly mounted under zero-alpha FadeTransition
   reproduces that topology and native rejection after healthy AX. A fresh
   visible mount exposes Slider 50% without errors. A genuinely uninstrumented
   stock runner independently reproduces hidden failure/visible success.
   The production DVR Slider is strongly source-correlated, **not directly bound
   to a named widget instance by the Release trace**. Historical node 866 is
   unattributed; do not assign all M-04 failures to Slider.
5. Separately, the pinned common bridge ignores both `Unserialize` return values
   and checks retained `AXTree::error()` instead. Success does not clear that
   string. Later valid tree mutation can therefore skip event delivery and
   `ClearEvents()`; a reparenting prepass can also stop early. This is established
   source control flow, **not native recovery/notification acceptance**.

Useful pinned framework/engine locations:

- `packages/flutter/lib/src/material/slider.dart`: eager value-indicator
  OverlayPortal controller and portal construction (including empty indicators).
- `packages/flutter/lib/src/widgets/overlay.dart`: OverlayPortal semantics,
  `Overlay.wrap`, its owned entry and bounded layout.
- `packages/flutter/lib/src/rendering/proxy_box.dart`: fade's rounded-alpha
  semantics omission at effective alpha zero.
- `packages/flutter/lib/src/semantics/semantics.dart`: physical attachment,
  traversal-parent grafting, origin absorption and dirty update serialization.
- `engine/src/flutter/shell/platform/common/accessibility_bridge.cc`: both
  `Unserialize` paths, error handling, events and clearing.
- `engine/src/flutter/third_party/accessibility/ax/ax_tree.cc`:
  `AXTree::Unserialize`, retained error and unreachable-node validation.

Raw captures are private and local under `/tmp/lineup-audit/pro-round3/`.
GitHub reviewers cannot access them. Use the sanitized fixtures as fixtures;
do not invent raw native return values, traces or widget identity. Optimized-frame
LLDB Boolean probes were ambiguous and are **excluded/untrusted**. Repeated
error messages can repeat a retained error; they are not independent failures.
Quiet logs or populated snapshots do not prove notification recovery.

## Question for the second set of eyes

GPT Pro proposes testing **`Overlay.wrap(clipBehavior: Clip.none, child:
SliderTheme(... Slider ...))` around only the existing Slider**, inside the
approved finite-height 40-pixel progress Stack. The visible 4-pixel progress
indicator remains outside that local overlay; Player layout stays intact.

The hypothesis is that Slider's portal and origin then share fade/exclusion
ancestry, so both leave physical/semantics scope together. Slider stays mounted,
preserving focus, state, callbacks and gestures without a separate lifetime state
machine. This is an **unverified hypothesis**, not an approved product fix.

Please assess:

- Does this contain the portal under **all relevant** entering, retiring, menu
  exclusion and restoration paths? Check actual overlay selection and semantics
  grafting rather than raw descendant DFS.
- Does the small overlay alter paint order, indicator geometry, clipping,
  composited positioning, pointer hit testing, focus, text scaling or overlap?
  Does the continuous/no-value-indicator case differ from an active indicator?
- What is the smallest coherent mitigation preserving approved behavior? If
  containment fails, would lifetime gating be justified, and what state/gesture
  obligations must it carry? Its alpha rule must match Flutter's rounded alpha.
- Are any conclusions about the underlying framework or retained-error recovery
  overstated? Identify exactly which additional observation would settle them.

`showValueIndicator: never` and disabled interaction do not remove the eager
portal. `alwaysIncludeSemantics` exposes invisible controls and misses other
exclusions. `TooltipVisibility` should remain tooltip policy rather than become
a generic control-lifetime signal. A blanket native rule dropping unknown IDs
can discard legitimate new nodes; any upstream bridge design needs batch-level
creation/reparenting/pruning/restoration and notification tests.

## Required experiment evidence before a mitigation can be accepted

Compare default and contained variants on the pinned stock framework, restarting
after any native rejection. Establish healthy native AX **before** each trigger;
a forced Dart semantics handle does not establish native bridge activation.

- Separate fresh hidden and visible mounts; visible → hidden → restore;
  exclusion/restoration; rapid fade reversal.
- Menu opening during entry, route replacement, DVR-driven insertion/removal.
- Keyboard adjustment, active drag, focus survival, hidden-control noninteraction.
- Effective root traversal **and outgoing updates**, then bounded native AX
  activation and notification checks. State exactly which layer was observed.
- Matched real-Flutter geometry/visual and hit-test checks at relevant sizes/text
  scaling before any material UI departure. Preserve approved visuals.

Any product mitigation needs regression evidence, a fresh independent adversarial
review before integration, a conventional fix commit with a progress entry, real
Release verification and Windows CI for shared Dart changes. Never cancel a live
CI run. Existing Windows build/CTest evidence is not physical Windows AX proof.

No engine patches, upstream publication/messages, main merge, release/signing or
distribution. Do not retest accepted HDR/Dolby Vision picture quality. Keep private
media labels, paths, URLs, credentials and raw diagnostics out of shared evidence.
Keep physical keyboard, spoken VoiceOver, audio drift and window/lifecycle checks
in the existing **single final human checklist**. M-04 and overall accessibility
acceptance remain open.

Return prioritized actionable findings with source identity, location, trigger,
mechanism and evidence; separate established defects, evidence gaps and optional
ideas. Explain the best coherent direction and its tradeoffs. Clearly identify
what you executed versus source-derived reasoning and unavailable acceptance.
