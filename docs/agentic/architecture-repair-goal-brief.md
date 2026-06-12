# Architecture Repair Goal Brief

Use this brief as the durable context file for a short Codex goal prompt that
starts a production architecture repair pass. This is not an active plan by
itself; a goal session should use it to create a reviewed Tier 3 feature/design
plan before implementation.

## Objective

Produce, review, and execute a production architecture repair program that
reduces near-term architecture risk across Lineup Desktop's largest temporary
owners before the next feature slice grows them.

Treat this as Tier 3 feature/design work through the desktop feature-quality
loop. Keep live execution state in `update_plan`.

## Non-Goals

- Do not implement new product features, RD-26 media options, broader playback
  behavior, live transport growth, new renderer workflows, or Windows proof
  closeout unless explicitly required by the reviewed repair.
- Do not do broad cleanup or rewrite files just to reduce line counts.
- Do not raise file-shape baselines to pre-authorize future growth.
- Do not add compatibility barrels, old path shims, fallback API variants,
  temporary adapters, or no-value forwarding owners.
- Do not introduce renderer privilege, token-bearing renderer state, raw
  Electron/native handles, tokenized URLs, raw Plex payloads, or privileged
  preload passthroughs.
- Do not change behavior without stable public-seam, contract, integration, or
  manual proof.
- Do not add dependencies, package changes, lockfile changes, build tooling, or
  native-helper redistribution without a reviewed dependency decision.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md`
4. `docs/architecture/CURRENT_STATE.md`
5. `docs/architecture/file-shape-guardrails.md`
6. Relevant seam docs for the chosen repair, likely playback, Plex, persistence,
   security/secret flow, renderer, or packaging docs.
7. Current code and tests for candidate owner files.

Do not depend on `.codex/review-context.md`; it is absent in this repo. Prefer
Codanna for discovery when useful. If unavailable, stale, or noisy, record
fallback to `rg` and direct reads.

## Required Skills

Use `architecture-boundaries`, `execution-plan-authoring`,
`verification-strategy`, `review-request`, `review-adjudication`,
`closeout-verification`, and any implicated boundary skill such as
`plex-integration-boundaries`, `persistence-boundaries`, or
`ui-composition-patterns`.

## Evidence Inventory

Before freezing scope, produce an architecture inventory with citations to docs,
source, contracts, tests, and call sites for:

- `src/preload/index.cts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/renderer/index.ts`
- Watch list: `src/contracts/player.ts`, `src/main/plex/streamResolver.ts`,
  `src/main/player/streamPolicy/desktopStreamPolicy.ts`,
  `src/domain/channel/channelManager.ts`,
  `src/domain/channel/channelRepository.ts`, `src/renderer/epg.ts`, and
  `src/renderer/routeDom.ts`.

For each hotspot identify:

- current owner responsibility
- privileged data or custody concerns
- public contract/API exposure
- request identity and stale/cancellation behavior
- validation duplication
- current tests protecting the seam
- line-shape status and guardrail trigger
- likely safe extraction seams
- reason to touch or not touch it in the first slice

## Prioritization And Program Shape

Rank candidate repairs by:

1. production safety risk
2. likelihood of blocking upcoming features
3. ability to preserve behavior with strong proof
4. ability to stabilize or shrink a hotspot without inventing architecture
5. reviewability as a bounded unit

The goal is to address all material hotspot areas found by the evidence
inventory, not only one owner. Sequence the work into reviewed repair packages
that can be implemented and verified one at a time without mixing unrelated
owners in a single commit.

Likely repair themes to evaluate, with final scope evidence-driven:

- Split `nativePlayerHostProcess` process/IO/NDJSON framing from host event
  validation and command execution.
- Extract `desktopPlayerAdapter` request custody/identity and host-state
  coordination from command validation/diagnostics.
- Extract `plexPlaybackRuntime` cleanup/stale-event custody before more live
  playback growth.
- Decompose preload bridge guard/channel families without broad RPC passthrough
  or sandbox breakage.
- Split `desktopPlexRuntime` server/profile orchestration from library
  operations.
- Separate renderer bootstrap/composition/action registration from
  `src/renderer/index.ts`.

The program should usually start with the highest production-risk owner, then
continue through every material hotspot package until the architecture repair
acceptance criteria are met or a reviewed replan explicitly defers an area with
owner, risk, and revisit trigger. Strong early package candidates are native
host process IO/framing extraction, player adapter request-custody extraction,
or playback runtime cleanup/stale-custody extraction. Do not choose preload
early unless evidence shows sandbox compatibility and existing parity tests can
be preserved without new bridge behavior.

## Plan Requirements

Create or update a durable active plan in `docs/plans/` only if fresh-session
handoff memory is needed. Follow `docs/agentic/plan-authoring-standard.md` and
include `## Architecture Health` before implementation-unit selection.

The plan must define scope, non-goals, files in and out, seam decisions,
invariants, verification classification, exact commands, acceptance criteria,
rollback notes, replan triggers, commit checkpoints, and review gates for the
overall program and for each repair package.

## Required Phases

1. Bootstrap and inventory.
2. Prioritized architecture repair program with all material hotspot packages.
3. Read-only plan review and adjudication.
4. Implement package 1 only after review, verify it, review it, and commit it.
5. Continue package by package until every material hotspot is repaired or
   explicitly deferred by reviewed replan.
6. Final net architecture audit, docs updates, verification, and closeout.

## Stop Or Replan Triggers

- Evidence contradicts `CURRENT_STATE.md` or file-shape guardrails.
- A package cannot stay inside clear owner seams.
- Repair requires new IPC/preload APIs, renderer privilege, token-bearing
  renderer state, or unapproved contract expansion.
- Dependency, build, package, lockfile, or native redistribution changes become
  necessary.
- Behavior must change without stable proof.
- A hotspot must grow beyond reviewed baseline without a better decomposition.
- Tests fail for unrelated reasons.
- User changes overlap planned files.
- Review finds material architecture, security, or verification blockers.
- Windows/native proof becomes necessary but unavailable.

## Expected Deliverables

- Evidence inventory.
- Prioritized repair program covering all material hotspots, rejected
  alternatives, package ordering, and any explicit deferrals.
- Active tracked plan or execution handoff.
- Implementation of approved bounded packages only after plan review.
- Architecture docs or file-shape updates if ownership truth changes.
- Verification summary with exact observed commands.
- Residual risks, completed package list, deferred package list, and any next
  recommended repair package.
