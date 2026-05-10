# Agentic Development Workflow

This is the operating runbook for Lineup Desktop.

## Authority And Document Roles

- [`AGENTS.md`](../AGENTS.md) is the concise entrypoint map and always-on
  defaults surface.
- This file is the single operating runbook for workflow, precedence, routing,
  verification, review, and where to look next.
- [`docs/agentic/external-guidance.md`](./agentic/external-guidance.md) records
  the official agentic, Electron, and production-engineering guidance baseline
  used by this control plane.
- [`docs/agentic/plan-authoring-standard.md`](./agentic/plan-authoring-standard.md)
  owns the required shape for durable tracked plans.
- [`docs/agentic/codanna-playbook.md`](./agentic/codanna-playbook.md) owns
  Codanna discovery and fallback expectations.
- [`docs/agentic/skill-strategy.md`](./agentic/skill-strategy.md) owns the
  Desktop role and project skill topology.
- [`docs/architecture/CURRENT_STATE.md`](./architecture/CURRENT_STATE.md) is
  current architecture truth.
- [`docs/roadmap/desktop-port-roadmap.md`](./roadmap/desktop-port-roadmap.md)
  owns the ordered port roadmap, reuse map, and global gates between tracked
  plans.
- [`docs/architecture/desktop-repo-genesis-adr.md`](./architecture/desktop-repo-genesis-adr.md)
  owns accepted repo-genesis decisions.
- [`docs/architecture/import-ledger.md`](./architecture/import-ledger.md) owns
  provenance for copied or adapted upstream Lineup code and docs.

## Document Precedence

When tracked docs conflict, use this order:

1. this runbook for operating workflow, routing, review, verification, and
   closeout rules
2. `AGENTS.md` for always-on defaults and entrypoint links
3. `docs/agentic/session-prompts/README.md` for launcher routing and invocation
4. `docs/agentic/plan-authoring-standard.md` for active tracked plan structure
5. `docs/agentic/skill-strategy.md` for project skill topology and role policy
6. `docs/agentic/codanna-playbook.md` for Codanna query and fallback practice
7. `docs/architecture/CURRENT_STATE.md` for current architecture claims
8. task-specific architecture docs and active plans named by the task
9. `docs/roadmap/desktop-port-roadmap.md` for sequencing the next major port
   slice after the current active plan is reviewed, implemented, or explicitly
   superseded

Active plans own the current execution unit. The roadmap owns sequence, reuse
strategy, and global gates between plans; it must not override exact scope,
protocol, IPC, security, or verification decisions in the active plan unless a
reviewed replan updates that plan.

Historical upstream Lineup cleanup program artifacts are not Desktop authority.
If a useful lesson from them matters, promote the lesson into a Desktop doc
instead of importing old package state or detector tokens.

## Default Read Order

1. [`AGENTS.md`](../AGENTS.md)
2. this workflow runbook
3. [`docs/agentic/session-prompts/README.md`](./agentic/session-prompts/README.md)
4. [`docs/agentic/skill-strategy.md`](./agentic/skill-strategy.md) when role or
   project-skill routing matters
5. [`docs/agentic/plan-authoring-standard.md`](./agentic/plan-authoring-standard.md)
   when authoring or reviewing a durable plan
6. [`docs/architecture/CURRENT_STATE.md`](./architecture/CURRENT_STATE.md)
7. the active plan in [`docs/plans/`](./plans/README.md), when one exists
8. [`docs/roadmap/desktop-port-roadmap.md`](./roadmap/desktop-port-roadmap.md)
   when choosing what comes after the current active plan
9. task-specific architecture docs named by the plan or launcher

Keep always-loaded guidance short. Put detailed task workflow in launchers,
project skills, architecture docs, or tracked plans so sessions load only what
they need.

## Goals

- keep agent context explicit, inspectable, and reproducible in fresh sessions
- keep the control plane small but not under-specified
- preserve the original Lineup workflow lessons that prevent low-quality code:
  evidence before planning, decision-complete plans, bounded implementation,
  observed verification, and adversarial review
- keep renderer, preload, main, helper, Plex, storage, UI, and packaging owners
  narrow from the first implementation slice
- use verifiers and review loops as part of the harness, not as optional
  cleanup after implementation
- keep code health improving over time by rejecting avoidable complexity,
  unjustified dependencies, hidden configuration, and unreviewable change size

## Fresh Chat Bootstrap

When starting a new Codex chat in this repository:

1. Confirm the workspace is rooted at `/Users/tristan/Software/LineupDesktop`
   or another checkout of this repository.
2. Read `AGENTS.md`, this runbook, the session-prompt README, skill strategy,
   current architecture state, and the active plan or handoff named by the user.
3. Use project skills from `.agents/skills/` when they match the task. They are
   thin launchers into tracked docs, not hidden policy stores.
4. Run `git status --short --branch` before planning edits so pre-existing
   changes are not mistaken for agent work.
5. For workflow, launcher, project-skill, architecture-reference, or plan edits,
   expect `npm run verify:docs` before closeout. For source or scaffold work,
   follow [Verification Routing](#verification-routing).

Do not depend on the original Lineup repo's local skill context being present in
a fresh Desktop chat. Desktop carries forward the relevant guardrails through
this runbook, launcher docs, `.agents/skills/`, verifier checks, and desktop
architecture references.

## Guidance Baseline

This workflow follows the current official guidance summarized in
[`docs/agentic/external-guidance.md`](./agentic/external-guidance.md):

- durable repo instructions belong in `AGENTS.md`, with specialized guidance
  referenced from task docs or skills
- complex or ambiguous work plans before edits and records success criteria,
  constraints, verification, and stop conditions
- agentic coding work needs explicit orchestration, bounded tool/subagent use,
  test expectations, review, and acceptance criteria
- context is finite; delegate bounded research or review to sidecars when it
  preserves main-thread context and improves reliability
- agent systems should stay simple and composable, adding loops, skills, hooks,
  or automations only when they demonstrably improve outcomes
- verifiers and review loops are part of the harness, not optional afterthoughts

When official guidance changes materially, update
[`docs/agentic/external-guidance.md`](./agentic/external-guidance.md), this
runbook, launchers, project skills, and verifier tests in one reviewed pass.

## Production Engineering Guardrails

Every non-trivial code change should improve or preserve long-term code health,
not merely make the next check pass.

- Keep changes self-contained and reviewable. Separate broad refactors,
  dependency swaps, generated output, and feature behavior unless an approved
  plan explains why a single atomic change is safer.
- Do not introduce unused public APIs, placeholder abstractions, speculative
  extension points, or framework scaffolding without a near-term caller and a
  verification path.
- Dependency changes must name the runtime owner, why the package is needed now,
  lockfile impact, licensing/provenance risk, security posture, and verification
  command. Prefer no new dependency when existing platform or repo code is
  adequate.
- Configuration, credentials, app paths, diagnostics, logs, and generated
  artifacts are architecture surfaces. Do not hide environment-specific behavior
  in constants, renderer storage, checked-in local files, or unredacted logs.
- Tests should protect stable behavior and public seams with actionable failure
  output. Avoid brittle private probes, broad snapshots, or tests that only
  bless current implementation shape.
- Keep every committed checkpoint buildable and reversible. If a sequence of
  commits depends on ordering, each committed step must preserve the verified
  architecture boundary or record an approved exception and rollback trigger.

## Routing

All desktop delivery routes as `feature/design` unless this repository later
creates its own reviewed maintenance backlog. Do not import upstream cleanup
program state, score artifacts, detector issue ids, package fields, or package
mechanics as active desktop authority.

## Discovery

Use Codanna first when symbol, ownership, or repo-doc discovery matters. Follow
[`codanna-playbook.md`](./agentic/codanna-playbook.md) for query shaping,
impact analysis, and fallback logging.

Generated Codanna indexes and model caches are local-only. Do not commit
`.codanna/`, `.fastembed_cache`, or generated project ids.

Use the smallest tier that keeps the work reliable:

- Tier 1: one-session small docs, harness, or contract changes with
  risk-matched verification. Use review when the surface appears in
  [Review Before Closeout](#review-before-closeout), when the plan requires it,
  or when the change could weaken a desktop feature quality guardrail.
- Tier 2: serious feature/design work uses
  `feature-plan -> feature-review -> feature-implement -> feature-review`.
- Tier 3: cross-boundary or multi-session work uses a task-specific run bundle
  plus the desktop feature-quality loop in
  [`feature-quality-loop.md`](./agentic/session-prompts/feature-quality-loop.md).

Tier 3 is required by default for Electron IPC/security, native playback,
storage/secrets, packaging/release, broad upstream imports, or any change where
implementation would otherwise need to invent ownership or verification policy.

## Default Workflow

1. Start with the relevant project skills.
   - Use `architecture-boundaries` for process ownership, shared contracts,
     module boundaries, or cross-surface wiring.
   - Use `persistence-boundaries` for app paths, secure storage, credentials,
     selected server state, local files, or browser storage.
   - Use `plex-integration-boundaries` for Plex auth, discovery, library, stream
     resolution, subtitles, selected server state, tokens, or playback URL setup.
   - Use `ui-composition-patterns` for renderer UI, focus, keyboard/remote
     behavior, motion, accessibility, or media presentation.
   - Use `verification-strategy` before freezing proof depth when the correct
     test/manual/static proof is not obvious.
   - Use `execution-plan-authoring` for serious plans and bounded execution
     briefs.
2. Run an evidence sweep before freezing scope.
   - Prefer Codanna for symbols, ownership, and repo-doc discovery.
   - Use `semantic_search_with_context`, `semantic_search_docs` or document
     search, and impact analysis when shared/public symbols or risky owners are
     involved.
   - Fall back to `rg` and direct reads when Codanna is unavailable, stale, or
     not the right tool, and record that fallback in the plan.
   - Use official docs for external framework, Electron, packaging, signing,
     native player, or agent-control claims.
3. Load the right source-of-truth docs.
   - current architecture: `docs/architecture/CURRENT_STATE.md`
   - ordered port roadmap: `docs/roadmap/desktop-port-roadmap.md`
   - security and secrets: `docs/architecture/security-and-secret-flow.md`
   - playback: `docs/architecture/playback-architecture.md`
   - packaging and release gates: `docs/architecture/packaging-release-gates.md`
   - copied/adapted source provenance: `docs/architecture/import-ledger.md`
4. Choose the smallest reliable tier before editing.
   - Tier 1 stays in one session with risk-matched verification and review when
     the change affects a review-required surface.
   - Tier 2 uses `feature-plan -> feature-review -> feature-implement ->
     feature-review`.
   - Tier 3 uses a task-specific run bundle when repeated handoff memory is
     likely and the desktop feature-quality loop for plan, review,
     implementation, implementation review, and closeout.
5. Plan explicitly before multi-step work.
   - Keep live state in `update_plan`.
   - Create or refresh a tracked plan in `docs/plans/` only when durable fresh
     session memory is needed.
   - Serious tracked plans must satisfy
     `docs/agentic/plan-authoring-standard.md`.
   - Do not freeze a plan while ownership, security, IPC, playback, persistence,
     packaging, import, or verification policy is still unresolved.
6. Implement narrowly.
   - Execute one approved unit at a time.
   - Keep implementation inside the approved files, owner, and seam.
   - Prefer small durable owners over broad helpers, no-value forwarding,
     compatibility wrappers, or framework setup that cannot be reviewed for
     behavior.
   - Do not add old upstream path shims or fallback API variants unless the
     approved plan names the owner, reason, verification, and removal trigger.
7. Verify based on risk.
   - Run the commands named by the plan and read the output.
   - Use `npm run verify` for source, scaffold, IPC/security, runtime, or
     implementation closeout unless an approved plan names a narrower proof.
   - Use `npm run verify:docs` for docs, workflow, launcher, skill, plan, or
     reference changes.
   - Add manual, smoke, visual, or browser evidence when automation cannot prove
     the behavior.
8. Review before closeout.
   - Use `review-request` to send bounded packets to read-only reviewers.
   - Use `review-adjudication` before acting on review findings.
   - Do not advance while material plan or implementation findings remain.
9. Update the right memory surface in the same pass.
   - Update current-state or architecture docs when ownership changes.
   - Update the import ledger before or with copied/adapted upstream Lineup code.
   - Update active plans, handoffs, or run-bundle summaries when they are the
     next fresh-session surface.
10. Close workflow/control-plane changes deliberately.
   - Keep launchers, skill strategy, verifier tests, and this runbook aligned.
   - Do not claim a workflow-quality improvement from prose alone; pair it with
     verifier coverage and read-only adversarial review.
   - Commit workflow/control-plane changes separately from product
     implementation when practical.

## Desktop Feature Quality Guardrails

For every non-trivial code change, check the planned diff and final diff against
these regression categories:

- hotspot growth: composition roots, Electron main, preload, player host,
  scheduler, and Plex owners must not absorb unrelated feature policy
- compatibility residue: no migration barrels, old-path wrappers, compatibility
  re-exports, fallback API variants, or temporary adapters unless an approved
  plan names a removal trigger
- boundary leakage: renderer code must not gain persistent secrets, raw Electron
  APIs, native handles, tokenized URLs, Plex transport policy, secure-storage
  policy, or packaging policy
- contract drift: keep one public shape per operation, one owner for shared
  literal unions, explicit redaction behavior, and aligned public/concrete
  signatures
- test debt: prefer public-seam behavior, contract, integration, or manual proof
  over brittle private probes and broad snapshots
- source signal: avoid generated-looking scaffolding, no-value forwarding,
  broad helper names, stale comments, and unrelated cleanup mixed into a feature
  unit
- release debt: do not weaken licensing, signing, update, diagnostics, or binary
  provenance gates to accelerate a private spike

Intentional exceptions need an approved plan note with one owner, reason,
verification, and removal or revisit trigger.

## Feature-Quality Loop

The full Tier 3 controller lives in
[`feature-quality-loop.md`](./agentic/session-prompts/feature-quality-loop.md).
The invariant is simple: plan with a tracked planner, review read-only, implement
one approved bounded unit with a tracked worker, review read-only again, and do
not advance while material findings remain.

Use `docs/runs/` only for gitignored local run bundles. Promote durable
decisions into tracked docs instead of committing raw run logs.

## Multi-Agent Usage

Use multi-agent support only when it improves reliability, context hygiene, or
throughput. Do not replace the default workflow with always-on delegation.

- Keep immediate critical-path work local when the next action depends on it.
- Use `explorer` for bounded read-only source and repo-doc discovery.
- Use `docs_researcher` for official external documentation checks with a clear
  deliverable.
- Use `planner` for durable planning artifacts and execution-ready handoffs.
- Use `worker` only for approved, bounded implementation units with disjoint
  write scopes.
- Use `reviewer` for read-only adversarial review of plans, diffs, workflow
  artifacts, and handoffs.
- Use `monitor` for waits, polling, and long-running verification status.
- Keep read-only roles read-only. Do not route edits through explorer,
  docs_researcher, reviewer, or monitor.
- Do not let a worker invent architecture seams, broaden scope, or choose
  verification depth.
- Once a delegated planner is active, do not draft a competing local plan unless
  the planner blocks, fails, or is explicitly abandoned.
- Keep delegation shallow; do not spawn nested worker trees.
- Wait on a sidecar only when the next critical-path decision depends on its
  result.

Use `parallel-sidecars` for optional read-only sidecars and
`bounded-worker-execution` for approved implementation slices.

## Implementation Rules

- Keep renderer code unprivileged.
- Keep preload APIs narrow, typed, and validated.
- Keep persistent secrets and token-bearing operations in Electron main and/or a
  privileged helper.
- Treat helper-hosted libmpv as a hypothesis until a Windows spike proves video
  surface, overlay, fullscreen, focus, track list, crash recovery, and redaction
  behavior.
- Treat external `mpv` IPC as a private disposable POC only.
- Record every copied/adapted upstream Lineup slice in the import ledger before
  or with the import.
- Do not add compatibility barrels or old-path shims just to mirror upstream
  paths.
- Prefer small, verifiable units over broad framework setup that cannot be
  reviewed for behavior.

## Verification Routing

- Docs, workflow, launcher, architecture, or plan changes: `npm run verify:docs`.
- Source, contract, or architecture-boundary changes: `npm run verify:architecture`.
- Contract, IPC payload, or security-boundary changes: `npm run typecheck`,
  `npm run test:contracts`, and `npm run verify:redaction`.
- Any scaffold or implementation closeout: `npm run verify` unless an approved
  plan names a narrower verified surface.
- Electron runtime, native playback, persistence/secrets, or packaging work must
  expand verification before implementation begins.
- UI work must include visual or browser evidence when layout, focus,
  interaction, media surface, or accessibility behavior could regress.

Verification claims require observed command output or recorded manual proof.
Do not hide a failed required check behind unrelated passing checks.

## Review Before Closeout

Use read-only adversarial review for:

- workflow/control-plane, launcher, project skill, or verifier changes
- Electron IPC/security boundaries
- native playback or player contract changes
- persistence/secrets changes
- packaging/release changes
- copied/adapted upstream Lineup imports
- Tier 3 plan and implementation gates

Reviewers should lead with findings, cite files and lines, prioritize security,
boundary, verification, and scope issues, and state explicitly when no blockers
remain. The owning session adjudicates reviewer findings before editing.

## Session Handoffs

Planner, reviewer, implementer, and controller sessions should end with a
pasteable handoff whenever another session is expected. Prefer one exact next
step over several possible next actions.

Include model guidance only when the user asks for it or when the outgoing
handoff is Tier 3 or high risk because it touches Electron IPC/security, native
playback, storage/secrets, packaging/release, broad imports, or multiple owner
boundaries.

Use this optional block immediately before the handoff when the trigger applies:

```text
MODEL_SUGGESTION
PLANNER: <model or "n/a">
IMPLEMENTER: <model or "n/a">
REVIEWER: <model or "n/a">
WHY: <short reason tied to the risk signals>
```

Use this handoff shape:

```text
NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: <launcher skill name or "normal repo workflow">
TASK: <short task title>
TASK_FAMILY: feature/design
TIER: <Tier 1|Tier 2|Tier 3>
PLAN: <plan path or "none">
ARTIFACT: <reviewed artifact, diff target, or "none">
FILES:
- <key file or artifact path>
BLOCKERS: <none or short blocker summary>
MESSAGE:
<pasteable next-session message>
```

Rules:

- If review findings block progress, route the handoff to the session type that
  must resolve them.
- For Tier 3 roadmap work, make `TASK` name the whole roadmap item and the loop
  objective, for example `Complete RD-10 ... Through Quality Loop`. The
  `MESSAGE` should name the current phase, current execution unit when one has
  been selected, remaining required units, and the platform-proof requirement.
- Mid-item handoffs route back to the same roadmap item. Route to the next
  roadmap item only after the current item's exit gates, review gates,
  verification, memory updates, and platform-proof requirement are complete or
  explicitly blocked/deferred by a reviewed replan.
- If no further session is needed, say so instead of emitting a fake handoff.
- Keep the block short enough to paste directly into a fresh session.
- Keep `TASK`, `PLAN`, `ARTIFACT`, and `FILES` concrete enough that the next
  session does not need to reconstruct scope from prose.

## Redaction Rules

Never put raw Plex tokens, tokenized URLs, raw auth headers, native media logs,
crash dumps with secrets, or secret-bearing fixtures into renderer-facing
surfaces, persisted logs, diagnostics, tests, docs, or Codex output.

## Memory Surface Updates

- Update current-state or architecture docs when ownership changes.
- Update the import ledger before or with copied/adapted upstream Lineup code.
- Update project skills under `.agents/skills/` only when a reusable workflow
  actually changes.
- Keep raw `docs/runs/` bundles local and ignored unless the workflow later
  explicitly promotes a curated summary into a tracked doc.
- Commit workflow/control-plane changes separately from product implementation
  when practical.

## Quality Loop

- Plan, review, implement, verify, review, close out.
- Treat verifier failures, reviewer blockers, and contradicted architecture
  assumptions as stop conditions, not as notes to work around.
- Keep run bundles local and promote only durable conclusions into tracked docs.
- Periodically review completed plans and workflow failures for reusable
  lessons; update the runbook, plan standard, skills, launchers, or verifier
  tests in the same pass.
- When this repo adds a repeated workflow failure mode, add a small Desktop
  eval or verifier rule before relying on prose guidance alone.
