# Codex Handoffs (October 7, 2026)

This file holds two prompts for Codex. Use them in order.

1. **Implementation** of the two approved plans:
   [setup-reentry-startup-plan.md](setup-reentry-startup-plan.md) and
   [player-guide-polish-plan.md](player-guide-polish-plan.md).
2. **Comprehensive review.** Run it only after (1) is integrated, so the review
   doesn't spend effort on code that is about to change.

Paste each prompt into a new Codex chat in the LineupDesktop project, with high
reasoning or above. These prompts supersede the per-plan prompts at the end of
each plan file.

**Excluded:** color and theme decisions (P7). Those are decided with Claude
separately and handed over as their own plan.

---

## 1. Implementation prompt

```text
Use orchestrate-implementation-chats to implement two approved plans in this
checkout:
  A. docs/setup-reentry-startup-plan.md   (units U1, U2)
  B. docs/player-guide-polish-plan.md     (units A, B, C, D)
Dispatch each unit to a separate implementation chat. Use the executor named in
each plan's unit table (`worker` or `worker_luna`); read the current
.codex/agents/worker.toml and worker-luna.toml and map model/effort onto
create_thread. Each child sends its terminal completion or blocked report back
to this orchestrator chat. I authorize creating those child chats and their
callbacks to this chat, for this task only.

SOURCE
Use the current local LineupDesktop checkout attached to the orchestrator,
branch codex/desktop-ui-second-pass, base c5fccffe. Local execution, no
worktrees.
Preserve these untracked paths untouched and uncommitted: .claude/launch.json,
docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/,
docs/reviews/test-slimming-2026-10-02/, tool/windows/__pycache__/.
Before dispatch, make one docs commit containing exactly:
docs/setup-reentry-startup-plan.md, docs/player-guide-polish-plan.md,
docs/codex-handoff-2026-10-07.md and the modified
docs/windows-collaborative-acceptance-handoff.md.

READ BEFORE DISPATCH
AGENTS.md; relevant .agents/project.md sections; docs/architecture.md
(accepted ownership; asynchronous and persisted state); docs/desktop-ui-second-pass.md
(F1, F2/G2, F5, F6, F8, Guide, Player); .interface-design/system.md; both plans
in full.

SCHEDULE (real write-ownership dependencies; overlap everything else)
Wave 1, in parallel:  setup U1, polish A, polish B.
Wave 2, as dependencies clear:
  setup U2  after setup U1 is integrated.
  polish C  after polish B is integrated (both edit lib/guide/guide_view.dart).
  polish D  after polish A AND setup U1 are integrated (D edits player_view.dart
            like A, and lineup_controller.dart/plex_client.dart like U1).
Children write only the files their unit owns. If a unit needs another file,
the child returns to you instead of editing it. Serialize only the shared full
checks and Git integration.

CHILD PACKETS
Plan path and exact unit section; that plan's decisions (setup: D1–D6; polish:
P1–P6, G1–G5 with recorded supersessions, D5 portrait route; P7 colors
excluded); source identity; write ownership and exclusions; required tests;
targeted commands (TZ=America/New_York flutter test <paths>,
dart format <changed paths>, flutter analyze); no commit/push/edits outside
ownership; callback route.

GIT AND INTEGRATION (you own them)
Inspect each returned diff against its unit contract and decisions; adjudicate
deviations; commit each accepted unit locally on codex/desktop-ui-second-pass
with a conventional message; after each wave run
dart format --output=none --set-exit-if-changed ., flutter analyze and
TZ=America/New_York flutter test on the integrated tree. Record the polish
plan's supersessions in docs/desktop-ui-second-pass.md. Do not push, open a PR
or merge.

APPROVAL GATES (stop, show me, wait)
- setup U2: D1 loading-screen copy, library-step action layout, matched
  1920×1080 and 960×720 before/after renders (restore phases, settled library
  step, no-libraries state, one non-default theme).
- polish B: before/after Guide renders (lines removed, rows snapped, bottom
  filled, full-bleed sides with PiP alignment, hours dropdown, search) at
  1920×1080 and 1280×720 plus one non-default theme.
- polish C: C1 and C2 candidate renders first; wait for my choice; then the
  final renders before committing.
- polish D: the P6 logo comparison (128 / 104 / 96 / optical, three logo
  shapes); wait for my choice. Show P3 label, P4 codec chip and P5 portrait
  before/after renders.
No golden updates without my approval. Ask me for any decision the plans don't
settle (persisted-shape change beyond D5, new user-visible behavior, removing
protection, any color/theme change).

FINISH
After all six units: one independent read-only review of the full diff from
c5fccffe against both plans (reviewer preset or code_reviewer); adjudicate;
apply accepted findings; rerun the full checks. Final report: units, executors
and commits; check results; adjudicated findings; Windows acceptance items from
both plans as remaining work. Do not claim Windows behavior as verified.
```

---

## 2. Comprehensive review prompt (after implementation lands)

This review is meant to find the next blockers before manual testing does. The
generic production review is anchored to the defect classes that actually
reached manual testing in this cycle, and it confirms suspected bugs with
executable probes instead of reporting only code smells.

```text
Run a comprehensive, evidence-backed review of Lineup Desktop to find
user-visible bugs, latent defects and material code-quality problems before
manual testing does. Use the repo-production-review skill as the backbone
(census, evidence ledger, specialist dimensions, calibration), extended by the
flow-driven bug hunt below. This is a REVIEW: do not modify product code, tests,
docs or configs, and do not commit. Two exceptions are authorized:
  1. Throwaway diagnostic probes (real-controller or widget tests) under
     build/review-probes/ (ignored), run with
     `TZ=America/New_York flutter test --no-pub <probe path>`; never move them
     into test/.
  2. The final report at docs/reviews/comprehensive-review-2026-10-07/REPORT.md
     (plus an optional findings.json beside it).
You may create read-only investigator/reviewer child chats with
orchestrate-implementation-chats (or use code_investigator/code_reviewer
sidecars) for bounded dimension or journey packets. I authorize those child
chats and their callbacks to this chat, for this review only. Children never
write outside build/review-probes/<their packet>/.

SOURCE
Use the current local LineupDesktop checkout attached to the orchestrator,
branch codex/desktop-ui-second-pass, at the integrated tip after both
docs/setup-reentry-startup-plan.md and docs/player-guide-polish-plan.md have
landed. Record the full SHA once and keep it fixed. If either plan has not
landed, stop and tell me.

READ FIRST
AGENTS.md; .agents/project.md (all sections relevant to a finding);
docs/architecture.md; docs/user-guide.md (it is a behavioral contract: every
documented shortcut and behavior must hold); docs/desktop-ui-second-pass.md and
.interface-design/system.md (approved UI decisions; a mismatch is a finding, not
a redesign opportunity); docs/product-parity.md (claims marked PARITY must have
real evidence); the two plans above plus
docs/osd-autohide-and-collection-membership-plan.md (recent changes and their
stated contracts); docs/guide-freshness-collection-investigation.md;
docs/windows-native-validation.md.

KNOWN DEFECT CLASSES TO HUNT FOR SIBLINGS
Each of these reached manual testing this cycle. For each class, search the
whole app for other instances, not just the fixed one:
 1. Event rate mistaken for state change: timers, debounces, animations,
    saves or notifications driven by high-frequency streams (player events,
    scroll, hover, notifyListeners) instead of transitions. (OSD hide timer
    reset every frame.)
 2. Displayed availability ≠ operation eligibility: a button or state the UI
    offers that the controller then rejects, or the reverse. (LIB-01 Continue
    vs commitLibraryScan.) Enumerate every enabled action's UI precondition
    against its controller guard.
 3. Screen shown during async work contradicts the user's intent, or offers
    actions that strand them. (The setup screen during saved-lineup restore,
    with a Cancel scan dead end.)
 4. Missing exits or back routes, or cancellation that doesn't return to its
    origin. (LIB-02.) Build the navigation graph: every stage, route and
    overlay needs a way out, and every cancel returns to its origin.
 5. Overlay composition that unmounts or replaces its parent, replays
    entrances, blocks click-through, or loses focus. (Sleep picker.) Audit
    every AnimatedSwitcher key, overlay, popover, drawer, dialog and menu.
 6. Shared-component misuse: the same widget configured inconsistently (a
    DropdownButton missing selectedItemBuilder; a TextField in a fixed-height
    box with theme padding for another size). Audit every instance of each
    shared control.
 7. External-data assumptions: what Plex or mpv actually returns versus what
    the code assumes. Examples: list views omit or truncate tags; episodes
    lack show-level fields; collections are recreated by Kometa; cast thumbs
    are on varied hosts; mpv properties are descriptive strings; remote or
    relayed servers are slow. Check every parser and consumer of external
    fields.
 8. Input-mode assumptions: mouse, keyboard or remote parity; desktop
    FocusHighlightMode treating the mouse as traditional; focus restored after
    pointer actions.
 9. Key handling gated by overly narrow state checks. (Up opened the Mini
    Guide only with no overlay.) Check every user-guide shortcut in every
    overlay and stage state.
10. Platform-only failures: Windows paths, separators, file locking and
    quarantine/rename behavior, case sensitivity, path_provider locations,
    DPI and display scaling.
11. Long operations with no visible progress or phase, or progress that stalls
    while work continues.
12. Unbounded cost: full-size artwork over remote connections; per-frame
    rebuilds; repeated full recomputation in build methods; unbounded
    caches or queues.

USER-JOURNEY TRACES (follow each through code; probe what's uncertain)
J1 First run: welcome → PIN link (expiry, cancel, retry) → profile (protected
   PIN) → server → libraries (scan, partial failure, none found) → configure →
   review (each build mode) → create → Guide.
J2 Relaunch with a saved lineup: success; offline server; expired auth;
   library removed; collection deleted or recreated; playlist missing;
   corrupt or older state; quit during restore.
J3 Setup re-entry: Generate lineup in each mode; subset and rescan; cancel at
   every step; Source not found; Add as new.
J4 Switch server, switch profile, logout, relink, including during scans,
   tunes, saves and playback.
J5 Channel Studio: create, edit, delete, reorder, Air Check, failed save,
   stale base, unavailable source.
J6 Guide: keyboard, mouse and remote navigation; search; filters; visible
   hours; Now; PiP; tune; schedule failure and retry; midnight and DST; very
   long or empty lineups; text scale 150%; 16:10, ultrawide, 720p.
J7 Player: tune; channel up/down; digits; Mini Guide; Now Playing; tracks;
   sleep; fullscreen; DVR controls on and off; errors and retry; multi-part
   items; schedule-boundary advance; pause during load; OSD and cursor timing.
J8 Settings: every setting's live effect, persistence, and interaction with
   open surfaces; themes; diagnostics on and off.
J9 Lifecycle: minimize/restore, app pause and resume, window resize and
   monitor change, shutdown mid-operation, rapid repeated actions.
J10 Persistence and upgrade: every persisted shape against older builds;
   recovery and quarantine; save failure and rollback; concurrent mutations.

EVIDENCE RULES
- Prefer executable evidence. When a defect is suspected, write the smallest
  real-controller or widget probe under build/review-probes/ that demonstrates
  it, run it, and cite its output. Mark findings CONFIRMED (probe or
  deterministic trace), LIKELY (strong static evidence), or HYPOTHESIS (needs
  a live Plex or physical Windows observation, with the exact observation
  that would settle it).
- Run the full deterministic gate once and record it: dart format
  --output=none --set-exit-if-changed ., flutter analyze,
  TZ=America/New_York flutter test.
- Compare docs/user-guide.md and docs/product-parity.md claims against the
  code and tests; unsupported claims are findings.
- Use the upstream sibling Lineup checkout only as behavioral evidence for what
  users expect; it is not a compatibility target.
- No credentials, tokens, server addresses, media titles or personal paths in
  probes, logs or the report.

CALIBRATION AND OUTPUT
Apply repo-review-evidence-calibration adversarially before promoting any
finding: try to disprove it, check for existing protection, and drop
duplicates of work already planned. Then write REPORT.md with:
- Repo profile and SHA; what was read; gate results.
- Findings table: ID, title, journey/class, severity (Blocker / Major / Minor /
  Quality), status (CONFIRMED/LIKELY/HYPOTHESIS), evidence (file:line, probe
  path and output), user-visible effect, root cause, remediation direction,
  and whether it needs a product/UI decision.
- Per-journey and per-class coverage: what was traced, what was probed, and
  why there is no finding where there isn't one.
- A "needs my decision" list (product or UI choices only).
- A "needs live/physical observation" list with exact steps (fold these into
  docs/windows-collaborative-acceptance-handoff.md's style; do not edit it).
- Then, using repo-production-remediation-plan, a remediation package plan for
  the CONFIRMED and LIKELY findings that need no product decision: packages
  with owners, file ownership, required tests, sequencing, and executor
  suggestions (worker / worker_luna), written as
  docs/reviews/comprehensive-review-2026-10-07/REMEDIATION.md.

STOP after the report and remediation plan. Summarize the top findings for me
with the "needs my decision" list. Do not implement; I will approve the
remediation packages (or a subset) before implementation is dispatched.
```
