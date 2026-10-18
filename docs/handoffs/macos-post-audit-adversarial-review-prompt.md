# Fresh adversarial review prompt

Copy the text below into a fresh GPT Pro 6 conversation with repository access.
This requests an independent review, not automatic implementation.

---

Review the complete post-audit macOS fix round in `TJZine/LineupDesktop`.
Read `AGENTS.md` and `.agents/project.md` first. Work read-only; do not merge,
publish an upstream issue, change settings, access credentials, or implement fixes.

Repository: https://github.com/TJZine/LineupDesktop

Branch: `platform/macos`.

Review range: `fa1760872ffc69dd61644cb09e0b0a64a130f5f4..296ab90588b6d1312e7a1b992142077fed1146c3`.
Resolve the immutable candidate below rather than silently reviewing an older
cached branch. Later commits containing only verification documentation may
follow the product candidate; inspect those evidence updates too.

Product candidate: **296ab90588b6d1312e7a1b992142077fed1146c3**.

Windows verification passed:
https://github.com/TJZine/LineupDesktop/actions/runs/39170620921

Verification commit `159fd599aee9ab8c7074ca292e517116342d89b9` has the product
candidate as parent and differs only in its narrowed CI workflow. Both Dart and
Windows jobs passed; the latter includes eight selected native/reference CTests.
Local formatting, analysis and all 1,792 macOS Dart tests passed. These checks do
not establish physical Windows playback or complete accessibility acceptance.

The user wants you to challenge correctness, design, ownership and evidence,
including whether there is a better coherent solution. Do not accept earlier
review conclusions or the controller's preferred workaround as authority.

Start with:

- `docs/handoffs/macos-app-audit-report.md` and `macos-app-audit-plan.md`.
- `docs/handoffs/macos-post-audit-fix-report.md`.
- `docs/handoffs/macos-ax-update-investigation.md`.
- `tool/macos/ax-tooltip-repro/{README.md,main.dart,first-rejection.json}`.
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
7. M-04: standalone runtime diagnosis and the bounded TooltipVisibility mitigation.

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
- **Known remaining path:** showing a tooltip whose origin was excluded from
  the outset also failed in a separate stock native probe. Now Playing details
  contain cast tooltips under permanent ExcludeSemantics; track rows contain
  title tooltips inside Semantics(excludeSemantics:true). These visual hover
  features are preserved and are not repaired by the transition guards.
- The remaining cast path is confirmed in the real Release candidate too:
  guarded Guide/Player transitions logged zero AX errors; subsequent Now Playing
  cast-name hover produced the first removed-node rejection. This is explicitly
  partial mitigation, not successful general M-04 acceptance. Challenge whether
  that boundary is adequate and propose a stronger feature-preserving correction.
- Evaluate whether the bounded mitigation is worth retaining and whether
  moving tooltip origins outside those static exclusions can preserve hover
  behavior and coherent accessible names without duplicate announcements.
  Propose a concrete stronger design if justified. Do not recommend permanently
  deleting hover information simply to make logs quiet.
- Distinguish application Dart from Flutter framework/native interoperability.
  The rejecting adapter is common desktop code, not proven macOS-exclusive.
  An upstream correction could suppress unreachable framework records or adapt
  them at the bridge; challenge the ownership conclusion from actual source.
- Flutter's bridge also checks AXTree's retained error string instead of the
  current Unserialize return value. Repeated messages can contain stale errors;
  historical totals are log-message counts, not independent-rejection counts.
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
