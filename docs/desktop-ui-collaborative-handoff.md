# Collaborative desktop visual correction handoff

Active workflow requested September 9, 2026. This is a new **user-led visual
correction pass**, not a restart of the original P0/implementation campaign.
The original campaign handoff remains historical context; this document governs
agent dispatch and acceptance for this pass.

## September 12 workflow amendment — current authority

The user replaced subagents with fresh user-facing implementation tasks using
GPT-5.6 Luna / xhigh. Tasks share this existing branch/checkout; do not create
isolated worktrees. Work sequentially: root makes no parallel edits while the
implementation task holds the file lease. Supply the same bounded file ownership, current excerpts,
settled visual decisions and checks. Do not poll or monitor their progress; resume
integration after their final completion is available or the user reports done.
The older worker/subagent and no-extra-task wording below is superseded for these
explicitly requested implementation tasks. Astra retains complex contracts,
playback-state wiring, personal visual inspection and final user approval.

## Start here

Use **GPT-6 Astra as the root orchestrator and visual reviewer**, alongside the
user. Use the exposed **worker_luna** role for settled, bounded implementation.
Its repository configuration is `gpt-5.6-luna` / `xhigh`. Report the actual exposed
role/model assignment; never claim a fallback is Luna without evidence. If that
role is absent, use the documented worker/Luna override only when the runtime
supports it. Otherwise explain the limitation before assigning a substitute.
Do not change global model configuration or create additional user-facing tasks.

Read `AGENTS.md`, this handoff, the [approval ledger](desktop-ui-surface-approvals.md),
[interface system](../.interface-design/system.md), relevant
[Development](DEVELOPMENT.md) and [Architecture](architecture.md) contracts, and the
[active specification](desktop-ui-design-spec.md). Use the complete
[locked mock manifest](design/desktop-ui/README.md) to select the right variant;
read the selected HTML and relevant later refinements before dispatch. Use the
[latest readiness record](desktop-ui-readiness-review.md) for historical P0
context, not as proof of visual acceptance. The
[Muse adjudication](desktop-ui-muse-adjudication.md) explains the most recent
corrections and rejected suggestions.

Recheck HEAD, branch, status and existing edits. Preserve all unrelated changes.
The starting visual packet is tied to implementation commit
`cbf3dbd580d7c8147c1327342811c56fa4af6bfb` on `dev/desktop-ui-refinement`.
Later documentation-only commits do not invalidate its screenshots. Inspect
later code changes for visual impact and recapture only affected surfaces.

Open the [portable review packet](design/desktop-ui/review-packets/README.md).
Ask the user which surface to review first, then review it together. Do not begin
another autonomous project-wide corrective sweep or infer approval from the
user saying the comparison viewer looks good.

## Portable baseline and honest comparison

The archive contains a self-contained `comparison.html`, a manifest and supporting
reproduction material. Extract it on the other machine and open the HTML in a
browser; Flutter, Plex, a local server and a network connection are not needed to
view it. Use browser zoom 100%. Start at 1:1; Fit preview is an explicitly labeled
viewing aid and does not alter source images.

All 45 Flutter PNGs in the viewer were freshly captured at **1920×1080 physical
size, DPR 1, text scale 1**. The left panels render original HTML, not mock PNGs.
Thirty-nine entries have references; six intentionally have no matching locked
standalone mock. Labels distinguish original 1080p variants, natural-size
components, and mocks with their own responsive 1280-canvas fit function. Do not
call the latter two exact authored 1080p baselines or stretch components to
manufacture one. Synthetic names/counts, artwork, footage and some states differ.

Keep this starting archive immutable. Use local, ignored iteration captures while
working; produce a new clearly versioned packet only at a useful approved
checkpoint. Do not repeatedly commit the whole binary packet for each tweak.
The archived capture harness reproduces the starting packet; it is not an
instruction to recapture all surfaces on every iteration.

## Surface-by-surface loop

1. **Astra and user compare.** Select a surface and state by viewer ID. Inspect the
   actual locked mock and real current capture personally. Read its production
   owner. Record a short punch list: observed difference, intended correction,
   and relevant contract. Measure dimensions where comparison conditions make
   that meaningful. Separate real layout differences from different fixture
   content, browser glyph rasterization and component-reference limitations.
2. **Settle the brief.** Use the user's feedback and approved design to decide
   the correction. Routine engineering choices do not require another approval.
   Ask only about consequential new direction, typography changes, protected
   Player structure, behavior/ownership conflicts or missing reference intent.
   Give the user a concrete comparison for such choices, not an abstract question.
3. **Dispatch bounded Luna work.** Default to one active worker and one surface
   owner. Start a fresh Luna worker for each new surface family/type so unrelated
   surfaces do not accumulate in its context. Reuse that worker only for follow-ups
   within the same family. Studio surfaces 20–24 completed under the user’s
   explicit exception allowing the existing worker. Two workers are reasonable only for
   explicitly settled independent files while root has useful work to do. Give
   exclusive file leases and the detailed brief below. Do not delegate
   root's personal visual audit or launch reviewer agents for small tasks.
4. **Astra integrates and reviews.** Inspect the returned diff and behavior
   evidence. Capture only changed surfaces/states at 1080p/DPR1/text1 using real
   Flutter widgets, stable synthetic content and the same relevant state. Include
   focus/hover only when reviewing those states. No HTML/WebView application UI,
   image retouching, fake screenshots or resizing 720p PNGs into 1080p evidence.
   Correct obvious failures within scope before presenting the next candidate.
5. **User approves the surface.** Show mock/current and, when useful, the prior
   candidate. Describe remaining differences honestly. Ask whether the identified
   surface/state is acceptable to lock at 1080p. Wait for an explicit answer;
   silence, elapsed time, agent consensus and passing tests are not approval.
   If revisions are requested, keep the same surface active and repeat narrowly.
6. **Record and checkpoint.** Record the user's actual approval message, approved
   state scope, source commit (or working-tree source hashes until committed),
   capture hashes and limitations. Make a coherent conventional commit for the
   accepted surface or small related family after its required checks pass.
   Bind the evidence to the resulting commit; do not claim a different render
   was approved. No push, deployment, publishing or remote upload without a
   separate instruction.

A user-approved **1080p visual lock** is distinct from adaptive/interaction
validation. At a sensible family checkpoint, run the remaining required
720p/1440p/2160p, DPI and enlarged-text checks for affected surfaces once. Preserve
meaningful controls and normal-scale composition. Repairs that change an
approved 1080p appearance must return to the user for renewed visual approval.
Do not label the entire surface/platform accepted while those checks remain open.

## Required Luna brief

Supply concrete values for every applicable item; avoid “make it pixel perfect”
as the implementation instruction.

- Surface ID/state and purpose; latest base HEAD and working-tree context.
- Exact exclusive files and functions/widgets allowed to change. Name any shared
  owner that must remain untouched and the other current file leases.
- Locked HTML path, selected variant/state and later spec refinements; current
  screenshot path/hash, viewport/DPR/text scale, and known fixture differences.
- Root's measured/observed discrepancies and explicit desired geometry, spacing,
  alignment, hierarchy, color roles and focus treatment. Preserve the mocks'
  restrained styling rather than adding permanent outlines to every control.
- Relevant **current code excerpts**, imports/theme helpers and caller/state
  context, with file paths/line anchors. Worker verifies that snippets still match
  the file before editing; excerpts supplement source, not replace it.
- Existing behavior to preserve: callbacks, async/currentness, cancellation,
  saved values, semantics, keyboard/focus, error states and resource lifetime.
- Exact acceptance criteria and bounded verification commands. No new layout
  assertions or test framework; reuse meaningful existing behavior coverage.
- Stop conditions: unexpected ownership/behavior change, need for shared tokens,
  missing approval, dependencies, or a protected boundary. Return evidence to
  Astra rather than making a new design decision or silently reducing scope.
- Handoff: changed files, concise diff rationale, checks with observed outcomes,
  remaining concerns and explicit file-lease release. No worker commits unless
  specifically assigned; root integrates and commits coherently.

Keep architecture, contracts, scheduling, persistence, authentication and
complex focus/async changes with Astra or a bounded strong `worker`. Luna may
implement settled visual details after those seams are clear. Do not expand a
visual correction into logic cleanup or a dependency campaign.

## Quality and cost boundaries

- Ponytail full mode: simplest complete change, existing helpers and native
  controls, no speculative abstractions/dependencies. Never reduce agreed scope
  merely to make a shorter diff.
- No new tests that freeze UI layout. Preserve meaningful behavior, accessibility
  and focus coverage. Adapt obsolete selectors when necessary; delete obsolete
  UI-specific tests only with a concrete explanation of why their contract no
  longer exists. Do not delete regressions just because they fail after a change.
- Temporary production-widget capture harnesses are evidence tools, not a new
  permanent matrix suite. Existing golden baselines may be refreshed for the
  approved appearance; a baseline refresh itself never constitutes approval.
- Reuse still-current verification. Run focused checks after relevant changes,
  then required integration checks at the family commit. Repair caused failures;
  broaden only for an unresolved risk or new failure, not habit.
- Root and user perform visual review. No independent reviewer swarm or automatic
  reviewer dispatch. Recommend specialist review only for a concrete risk and
  let the user decide.
- A shared theme/token change can invalidate several locks. Identify affected
  surfaces before implementation, obtain approval for material departures, and
  revisit only those affected captures. Do not quietly modify already-approved
  surfaces while working on another one.
- Preserve approved production typography until the user explicitly agrees to a
  typography correction with a concrete example. Do not use this rule to dismiss
  a user's concern; surface the tradeoff for decision.
- Preserve protected Player OSD/Now Playing structure, focus, timing and geometry.
  A separate user-approved structural change needs matched before/after real
  Flutter renders and the existing protected-boundary process.
- Physical Windows input/focus, native video layering, fullscreen, HDR,
  DirectComposition and packaging claims require actual evidence at the tested
  commit. Cross-machine browser viewing of this packet proves none of them.

## New-session prompt

```text
Use GPT-6 Astra as root orchestrator for the collaborative desktop visual
correction pass. Begin with AGENTS.md and docs/desktop-ui-collaborative-handoff.md,
then its authority/evidence links and docs/desktop-ui-surface-approvals.md.
Recheck HEAD/status and preserve existing changes. Open the versioned 1080p
comparison packet; it is a frozen baseline, not automatically current after edits.

Work with me on one surface at a time. Personally inspect the mock and actual
current UI, take my feedback, and settle a concrete correction brief. Dispatch
small worker_luna units with exclusive files, current relevant code excerpts,
exact visual corrections, preserved behavior and bounded checks. Keep difficult
logic and contracts with Astra/strong workers. Report actual assignments.

Review results yourself before showing them to me. Use fresh affected-surface
1920x1080/DPR1/text100% captures; no upscaled screenshots or whole-app recapture
for an isolated change. Add no UI layout tests. Reuse meaningful behavior checks
and group remaining resolution/accessibility checks at appropriate checkpoints.

Wait for my explicit visual approval before marking each surface/state locked.
Record the approved evidence/commit and outstanding adaptive/Windows checks.
Make coherent conventional commits for accepted work; do not push, deploy or
publish. Do not launch independent reviewers or extra user-facing tasks unless
I ask. Start by asking which surface I want to review first.
```
