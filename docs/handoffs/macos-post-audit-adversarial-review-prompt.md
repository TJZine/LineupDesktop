# Fresh adversarial review prompt

Copy the text below into a fresh GPT Pro 6 conversation with repository access.
This requests an independent review, not automatic implementation.

---

Review the complete post-audit macOS fix round in `TJZine/LineupDesktop`.
Read `AGENTS.md` and `.agents/project.md` first. Work read-only; do not merge,
publish an upstream issue, change settings, access credentials, or implement fixes.

Repository: https://github.com/TJZine/LineupDesktop

Branch: `platform/macos`.

Review range: `fa1760872ffc69dd61644cb09e0b0a64a130f5f4..ac995ec58c92ef491098f8a5afcc1da60cd65ad0`.
Resolve the immutable candidate below rather than silently reviewing an older
cached branch. Later commits containing only verification documentation may
follow the product candidate; inspect those evidence updates too.

Product candidate: **ac995ec58c92ef491098f8a5afcc1da60cd65ad0**.

Latest Windows verification passed:
https://github.com/TJZine/LineupDesktop/actions/runs/39179621557

Verification commit `0cb331f6be11c02f877e9ebfffc39a16ce9bef74` has the product
candidate as parent and differs only in its narrowed CI workflow. Both jobs passed:
1,805 Linux tests, 694 selected Windows Dart tests, the stock Windows application
build and eight selected native/reference CTests. The prior `d56a391b` run
39178150109 also passed; its runtime evidence retains that earlier identity.
Local formatting, analysis and all 1,807 macOS Dart tests passed. These checks do
not establish physical Windows playback or complete accessibility acceptance.

The user wants you to challenge correctness, design, ownership and evidence,
including whether there is a better coherent solution. Do not accept earlier
review conclusions or the controller's preferred workaround as authority.

Start with:

- `docs/handoffs/macos-app-audit-report.md` and `macos-app-audit-plan.md`.
- `docs/handoffs/macos-post-audit-fix-report.md`.
- `docs/handoffs/macos-ax-update-investigation.md`.
- `tool/macos/ax-tooltip-repro/{README.md,main.dart,static_origins.dart,button_origins.dart,first-rejection.json}`.
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
   Review the six correction commits `3fed8fd7`, `4fdac1ab`, `22073990`, `352a74aa`,
   `d56a391b`, `ac995ec5`. Challenge the diagnoses and verification boundaries
   described below; earlier review conclusions are not authority.

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
