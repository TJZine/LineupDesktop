# Fresh adversarial review prompt

Copy the text below into a fresh GPT Pro 6 conversation with repository access.
This requests an independent review, not automatic implementation.

---

Review the complete post-audit macOS fix round in `TJZine/LineupDesktop`.
Read `AGENTS.md` and `.agents/project.md` first. Work read-only; do not merge,
publish an upstream issue, change settings, access credentials, or implement fixes.

Repository: https://github.com/TJZine/LineupDesktop

Branch: `platform/macos`.

Review range: `fa1760872ffc69dd61644cb09e0b0a64a130f5f4..f2b76202625215bd0bcc14aefd1911db49663932`.
Resolve the immutable candidate below rather than silently reviewing an older
cached branch. Later commits containing verification documentation and standalone
reproductions follow the product candidate; inspect those evidence updates too.
Reproduction commit: `68bdc662`; it changes no application or build inputs.

Product candidate: **f2b76202625215bd0bcc14aefd1911db49663932**.

Latest Windows verification (passed; inspect source identity and logs):
https://github.com/TJZine/LineupDesktop/actions/runs/39188166189

Verification commit `86c589573f84bd505531731dc289627270bcb4b0` has the product
candidate as parent and differs only in its narrowed CI workflow. This run passed
1,817 Linux tests, 706 selected Windows Dart tests, the stock Windows build and
eight selected native/reference CTests. No active run was cancelled. Prior
`ac995ec5` results retain their original identity in the report. Local formatting,
analysis and all 1,819 macOS Dart tests passed on the new combined source. These
checks do not establish physical Windows playback or complete accessibility
acceptance.

Current evidence on `f2b76202` remains bounded; accessibility sign-off stays open:

- Clean stock Release: twelve actual-Tab direct/menu Return/keypad Clear
  activations passed. Synthetic Command+A then left the query unselected; zero
  AX failures during this check, normal Quit. Exact stock/diagnostic binary
  identities are in the closing report; do not conflate the builds.
- Diagnostic V1 captured rapid F2 → Escape before menu focus transfer: Escape
  reached Guide, the menu stayed/reopened, Return activated its Guide item, then
  Clear focus was restored without a Clear callback. A staged settled-menu control
  cleared correctly. Challenge this race independently; it does not explain every
  earlier uncaptured keyboard failure.
- Diagnostic V2 captured active native app/key window/search responder and
  synthetic Command+A events with keyCode 0 and combined Command `0x100000`, but
  no sided modifier bits. Pinned Flutter's responder does not create Dart Meta
  state from these. A stock TextField reproduced collapsed selection at 16 and
  appended replacement lengths 17/18. Challenge the source mechanism and boundary
  classification; physical Command+A was not tested. A Lineup shortcut workaround
  is not supported by this evidence.
- The real 30-minute timer expired in the authenticated diagnostic Release at
  03:01:40 UTC with Guide/Stopped, playback intent false and no pending tune.
  After unlock, background AX Close delivered a live-node tap with root Flutter
  focus and did nothing: the existing menu path has no current invoker context.
  Foregrounding the same process then activating Close once opened the usable
  menu without tuning. DVR Off and normal Quit were confirmed. Challenge the
  separate pre-existing root-focus menu-anchor gap; no repair for it is included.
  Do not describe this as an unconditional first-action/native AX pass.
- The same V2 process later followed Settings → Playback → DVR On → Back Guide →
  current-program tune. First error at line 791 named new node 378. Immediately
  preceding outgoing batch 671 emits an empty full-window portal leaf, physically
  `0 → 1 → 378`, child token 97 without a matching origin. Effective traversal
  remains `0 → 1 → 2 → 3 → 12`; no missing reachable child/cycle/duplicate parent.
- Stock Slider under FadeTransition held at alpha zero reproduces this topology
  and unknown-node error after healthy AX. A fresh visible mount stays healthy.
  Challenge whether the production correlation is sufficient: exact widget
  instance ownership is source-supported, not directly named by the Release trace.
  Do not retroactively attribute historical node 866 to the Slider.
- Review the committed minimal sources and compact graph fixture. The report
  proposes testing a Slider-lifetime mitigation for both entering/retiring origins;
  no new workaround or engine patch was integrated. Challenge layout, hidden
  controls, lifecycle and semantics risks, and propose a better coherent solution
  if appropriate. `showValueIndicator: never` does not remove the portal;
  alwaysIncludeSemantics exposes invisible controls and misses retiring exclusions.
- Native Boolean debugger probes were unvalidated due to optimized-frame ambiguity
  and excluded from conclusions. Repeated bridge messages remain message counts,
  not independent rejection counts or recovery evidence. The old retained-error
  source finding remains separate. Raw traces are local and unavailable via GitHub.

The user wants you to challenge correctness, design, ownership and evidence,
including whether there is a better coherent solution. Do not accept earlier
review conclusions or the controller's preferred workaround as authority.

Start with:

- `docs/handoffs/macos-app-audit-report.md` and `macos-app-audit-plan.md`.
- `docs/handoffs/macos-post-audit-fix-report.md`.
- `docs/handoffs/macos-ax-update-investigation.md`.
- `tool/macos/ax-tooltip-repro/{README.md,main.dart,static_origins.dart,button_origins.dart,slider_fade.dart,keyboard.dart,first-rejection.json,slider-first-rejection.json}`.
- The latest entries in `docs/macos-port-progress.md` and the Windows CI run
  linked there. Check what was actually tested and the source identity.

The fix round includes:

1. M-01: paused state reported while media played. Inspect macOS observed-pause
   snapshots at load readiness, actual toggle behavior, and interactions with
   L1/L2 start-of-load pause, display holds, startPaused and join/seek behavior.
2. M-05: Settings return destination after the sleep timer stops playback.
3. Q-01: macOS version/build Dart defines use the canonical Windows identity
   mechanism, with no fallback identity.
4. Q-02: rapid Page Up/Down accumulates every press immediately and loads only
   the final target while retaining tune serialization and stale-load rejection.
5. Q-03: superseded failures show the channel that Retry will actually tune.
6. M-02/M-03: directory semantics boundaries and explicit icon action names.
7. M-04: standalone runtime diagnosis, transition TooltipVisibility mitigation,
   and the subsequent feature-preserving static-origin repair.
8. Pro follow-up: persistent Guide invoker focus, Studio clear-search explicit
   naming, and user-approved Mini Guide initialization from presentation identity.
   Review the six first-review correction commits `3fed8fd7`, `4fdac1ab`,
   `22073990`, `352a74aa`, `d56a391b`, `ac995ec5`, plus the two second-review
   corrections below. Challenge the diagnoses and verification boundaries; earlier review conclusions are not authority.

9. Second Pro review correction `1bacc5b5`: toggle pending intent while a tune
   awaits its first native load, without unscoped native commands. Observed state
   remains authoritative once ready, including while selection is saving. Button
   icon/tooltip/accessibility name share K's decision. Challenge phase boundaries,
   readiness/currentness, supersession, repeated input, sleep expiry and tests.
10. Second Pro review correction `d5e09e0a`: Guide Clear is now a semantics sibling
    outside the field-only Enter/Escape scope, retaining persistent invoker focus,
    suffix reservation, density-aware hit area and TextFieldTapRegion. Validate
    Enter/NumpadEnter directly and after menu restoration, useful search focus,
    effective traversal before/during hover, no unintended tune and preserved
    editable-field navigation. Both changes received a fresh combined adversarial
    review before integration; do not treat that approval as authority.

11. Third Pro correction `f69ef69d`: current and next metadata share the represented
    program while selection persistence is blocked. Validate unresolved target
    preview isolation, paused resolved P after the wall clock enters Q, and next Q
    rather than R, before/after save release. No playback/schedule rewrite.
12. Third Pro correction `e7d7f098`: after sleep removes Player while Guide is
    open, one Close/Escape opens the usable menu immediately. Validate current
    surface authority, no extra tune and usable keyboard focus. This removes an
    obsolete origin flag; it is separate from Settings return routing.
13. `f2b76202` strengthens the retained Clear regression to use actual Tab for
    matching/no-match queries and direct/menu Return/keypad activation. Review
    the test's fidelity without equating it with physical keyboard acceptance.

The three latest commits received a fresh combined adversarial source review
before integration. Treat it as a recorded check, not authority for your verdict.

For M-04, independently trace this distinction:

- A stock Flutter app, with native AX initially healthy, shows a tooltip,
  excludes its origin, then changes its message. The tooltip overlay remains
  physically attached while its traversal subtree was discarded. A later
  update for the unreachable text node is rejected by the common desktop
  accessibility bridge. The fixture records four accepted batches followed by
  that first rejection; it came from an instrumented prototype with an unused
  Reset button, so its IDs differ from the final three-button source.
- The default repro still fails. Compiling with
  `--dart-define=REPRO_TOOLTIP_VISIBILITY=true` removes the tooltip overlay when
  its origin is excluded; native Release passed ten subsequent message changes.
- Application guards cover both shell app-menu exclusions and retiring Player
  AnimatedSwitcher children. Shell scopes preserve inherited visibility=false;
  current Player children must not override it with true. Verify disposal timing,
  restoration, focus, active tooltips, explicit names and the regression tests.
- The prior product candidate `296ab905` still failed on a cast-name hover;
  those historical observations retain their earlier identity. The new candidate
  replaces broad Now Playing exclusions with visual-leaf exclusions, and moves
  track tooltips outside canonical row exclusions (including Off). Both name
  and role tooltips preserve full hover text and the canonical summary.
- Before application edits, `static_origins.dart` native Release comparisons
  reproduced the default static exclusion rejection and passed both repaired
  structures through ten changes, exclusion/restoration and reopening. Row AX
  activation worked. Player regressions open tooltips and traverse from the root;
  all four fail on the original structure and pass with the repair.
- Challenge topology, canonical names/actions/selected/pending state, visual
  layout, hover-target implications and possible duplicate spoken tooltip text.
  Do not delete useful hover information merely to make logs quiet.
- Candidate `352a74aa` isolated a real Guide Now hover rejection before any
  menu. `button_origins.dart` faithfully reduces two Tooltip/TextButton siblings
  under a shared annotated Semantics ancestor. One traversal-parent identifier
  is lost during semantics absorption; the overlay is physically attached but
  absent from effective traversal. Bare unannotated sibling models do not fail.
  Challenge the mechanism from actual framework source; raw DFS is insufficient.
- Before applying the Now correction, the stock native default rejected Show,
  while an explicit *outer* origin boundary passed ten activations/message updates.
  An inside boundary and removing excludeFromSemantics failed portable controls.
  Now and Return-to-live full-shell regressions fail on the old structure.
- Final clean candidate `d56a391b` passed native Now/Return-to-live hover, exact
  Later focus/menu restoration with and without a tooltip, cast-name/menu
  exclusion/restoration, audio title/action, subtitle title/Off hover, and normal
  Quit with zero AX failure messages. This is bounded runtime evidence, not a
  general accessibility sign-off. Real cast-role data was unavailable; native
  selection confirmation and failed-B real Mini Guide behavior were not established.
- The named Studio suffix button was still hidden by the native text-field leaf
  on `d56a391b`. `ac995ec5` makes it a real semantics sibling while preserving the
  trailing placement, InputDecorator suffix reservation, density-adjusted hit area
  and field focus via TextFieldTapRegion/owned FocusNode. The strengthened existing
  test fails the original ancestry and checks root traversal, opened hover text,
  pointer and Tab+Enter behavior/focus. The field/editable/button/icon rects matched
  before and after at the tested Canvas scale; challenge broader assumptions.
- On clean Release `ac995ec5`, native AX exposed the named Clear button and its
  accessibility action cleared the query and removed the button. Draft discarded,
  normal Quit, zero AX failures. CUA pointer operations returned noWindowsAvailable,
  so real Clear hover was not verified; the widget opened-tooltip test passed.
  Other tooltip/focus runtime checks retain their explicit `d56a391b` identity;
  these product inputs did not change in the Studio-only correction.
- The focus correction gives six Guide tooltip-owned buttons persistent nodes,
  and rejects stale/removed/unfocusable shell invokers. Verify exact surviving
  invoker restoration and activation with/without an open tooltip. A fallback
  route alone would not meet that contract. Review the full-shell tests.
- Distinguish application Dart from Flutter framework/native interoperability.
  The rejecting adapter is common desktop code, not proven macOS-exclusive.
  An upstream correction could suppress unreachable framework records or adapt
  them at the bridge; challenge the ownership conclusion from actual source.
- Flutter's bridge also checks AXTree's retained error string instead of the
  current Unserialize return value. Repeated messages can contain stale errors;
  historical totals are log-message counts, not independent-rejection counts.
  A retained error can also skip accessibility-event delivery and event-generator
  clearing after a later successful tree update. No engine correction is included.
- The first historical production delta remains uncaptured. Negative follow-up
  real-app sequences do not invalidate earlier positives or prove full closure.

Constraints: preserve the approved Player layout and useful tooltip behavior;
do not retest HDR/Dolby Vision picture quality, patch the engine, merge to main,
perform distribution/signing work or expose private media data. Shared Dart
changes require Windows CI, which is distinct from physical Windows acceptance.
Never cancel an in-progress CI run.

Committed evidence is sanitized. Raw `/tmp/lineup-audit/` captures are local to
the controller's Mac and will not be available through GitHub. Do not infer their
contents. Ask for specific sanitized evidence if a conclusion needs it.

Return prioritized actionable findings with severity, exact location, trigger,
mechanism and supporting evidence. Separate established defects, unresolved
questions, and optional improvements. For a better solution, explain the
tradeoffs and a concrete verification plan. State the material limits of your
review; do not turn a green test suite into a claim of physical accessibility
or complete M-04 acceptance.
