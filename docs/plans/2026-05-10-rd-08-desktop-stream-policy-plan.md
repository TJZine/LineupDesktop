# RD-08 Desktop Stream Policy Plan

**Plan Status:** complete

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** done

**Verification classification:** new regression/contract test required

## Goal

Define the first Desktop stream-policy implementation unit after RD-07:
`desktop-stream-policy-fixture-core`.

This unit must create deterministic, fixture-driven policy decisions for
Plex-like media, part, and stream candidates without contacting Plex or wiring
runtime playback. The policy must choose direct play, direct stream, transcode,
or unsupported outcomes from explicit capability profile inputs, safe candidate
fixtures, audio fallback, subtitle fallback, HDR and Dolby Vision handling,
decision reasons, and explicit unknowns.

The first implementation target is Mac-hosted development and review. The
result must stay platform-neutral enough for later Windows/native-helper proof,
but it must not claim Plex HTPC parity, production helper behavior, or live Plex
server compatibility.

## Non-Goals

- Do not contact Plex or require a Plex server, Plex account, credentials,
  selected server, library runtime, network request, or production transport.
- Do not add secure storage, Plex auth, discovery, library runtime, selected
  server persistence, renderer UI, channel scheduling, playback orchestration,
  PMS cleanup, or production native helper code.
- Do not change preload APIs, renderer-facing player IPC, renderer UI, Electron
  shell behavior, package scripts, dependencies, lockfiles, packaging, signing,
  or installer behavior.
- Do not launch native playback, bind libmpv, add native binaries, add native
  handles, or connect stream decisions to `NativePlayerHostProcess`.
- Do not copy or adapt original Lineup Plex stream resolver or policy source in
  this unit. Treat original Lineup behavior only as reference evidence unless a
  later reviewed implementation imports or adapts source and updates
  `docs/architecture/import-ledger.md` before or with that import.
- Do not expose privileged playback setup material, Plex transport fields,
  source payloads, stream identity internals, native internals, Electron/Node
  objects, or secret-bearing diagnostics in renderer-facing contracts, logs,
  docs, tests, fixtures, or Codex output.
- Do not make final codec, subtitle, audio, HDR, Dolby Vision, transcoding, or
  Plex HTPC parity claims beyond the fixture cases and explicit unknowns tested
  by this unit.

## Parent Architecture Alignment

`docs/architecture/CURRENT_STATE.md` and
`docs/architecture/playback-architecture.md` say RD-07 completed the
main-owned player adapter, player IPC/preload delivery through a
development/smoke fake host, and native-host process seam. Production commands
still return renderer-safe unsupported failures, and there is no Plex stream
setup, renderer UI wiring, secure storage, or production native helper.

RD-08 advances a pure policy seam only:

- Policy ownership lives in a new main-owned player policy module, not renderer,
  preload, Electron main composition, Plex auth/discovery/library runtime, or
  native-host process code.
- Inputs are deterministic safe fixtures: capability profiles plus normalized
  media, part, audio, subtitle, video, and HDR/Dolby Vision candidate facts.
- Outputs are safe policy decisions with selected opaque candidate references,
  renderer-safe media/track summaries where needed, decision kind, fallback
  reason codes, explicit unknowns, and redacted diagnostics.
- Privileged playback setup material and Plex transport details remain outside
  this unit. Later RD-10/RD-12 plans must own real Plex input normalization,
  playback setup, PMS cleanup, and adapter handoff.
- Existing renderer-facing contracts in `src/contracts/player.ts` may be used
  for safe capability and track vocabulary, but RD-08 must not broaden public
  renderer contracts unless a reviewed replan proves the local policy type
  cannot safely carry the first unit.

Chosen architecture seam: `src/main/player/streamPolicy/*` owns deterministic
Desktop stream-policy decisions behind main/player. `DesktopPlayerAdapter`,
`NativePlayerHostPort`, and `NativePlayerHostProcess` remain out of the policy
decision path for this unit.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/session-prompts/feature-review.md`
5. `docs/agentic/session-prompts/feature-implement.md`
6. `docs/agentic/plan-authoring-standard.md`
7. `docs/architecture/CURRENT_STATE.md`
8. `docs/architecture/playback-architecture.md`
9. `docs/architecture/security-and-secret-flow.md`
10. `docs/architecture/upstream-behavior-guardrails.md`
11. `docs/architecture/import-ledger.md`
12. `docs/roadmap/desktop-port-roadmap.md`
13. `docs/plans/2026-05-08-rd-02-source-reuse-inventory-import-strategy-plan.md`
14. `docs/plans/2026-05-08-rd-03-player-contract-capability-model-plan.md`
15. `docs/plans/2026-05-08-rd-04-upstream-behavior-guardrails-plan.md`
16. `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`
17. This plan
18. `src/contracts/player.ts`
19. `src/contracts/ipc.ts`
20. `src/main/player/desktopPlayerAdapter.ts`
21. `src/main/player/nativePlayerHostPort.ts`
22. `src/main/player/nativePlayerHostProcess.ts`
23. `src/__tests__/contracts.test.ts`
24. `package.json`

Freshness gate: rerun `git status --short --branch` before implementation.
Stop for plan update and re-review if architecture docs, roadmap status, RD-03
contracts, RD-07 player files, verifier behavior, package scripts, or this plan
changed materially after this planning pass. The current worktree already has
unrelated dirty docs and untracked prior plans; leave them untouched unless a
later user request explicitly changes scope.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3
  feature/design planning pass and handoff.
- `execution-plan-authoring`: freezes the policy seam, first bounded unit,
  verification, rollback, and replan triggers without routine implementation
  pseudo-code.
- `architecture-boundaries`: applies because stream policy sits between
  renderer-safe player contracts, main-owned playback policy, future Plex input
  normalization, and native-player handoff.
- `plex-integration-boundaries`: applies because policy uses Plex-like stream
  evidence while keeping Plex transport, credentials, source payloads, and
  privileged playback setup outside renderer-facing surfaces.
- `verification-strategy`: requires new fixture/contract-style tests for stable
  policy behavior and redaction invariants.
- `review-request`: next gate is read-only adversarial plan review before
  implementation.
- `review-adjudication`: required before acting on review findings.
- `closeout-verification`: required before staging, committing, or calling the
  implementation complete.

Plan-review adjudication:

- Accepted finding: the first review correctly found that `npm run
  verify:redaction` is only a baseline credential-pattern scan and does not
  prove all RD-08 fixture/result constraints. This plan now requires a scoped
  RD-08 fixture/result invariant and source audit in addition to the existing
  verifier.

Windows closeout adjudication:

- Accepted finding: the Mac-first fixture core did not lock a Windows
  RD-06/RD-07 capability/sample matrix. The closeout pass added a conservative
  Windows matrix derived from the available player capability facts and
  redacted native-presentation proof. Because the Windows proof does not
  establish exact container, codec, audio, subtitle, HDR, Dolby Vision, direct
  stream, transcode, or Plex HTPC parity support, the Windows sample matrix
  keeps those outcomes explicit unknown or unsupported instead of promoting the
  generic policy fixture facts to Windows capability truth.
- Accepted finding: unsupported outcomes dropped fallback-selection reason
  codes in one path. The policy now preserves base fallback reasons on
  unsupported decisions, so failed audio/subtitle fallback attempts remain
  deterministic and reviewable.

## Evidence And Discovery

- `semantic_search_with_context`: attempted in this planning controller.
  Codanna reported an index with semantic search enabled, but returned stale
  `src/modules/plex/*` results such as old stream resolver, policy, and library
  symbols that are not present in this checkout.
- `semantic_search_docs` or repo-doc search: attempted and returned the same
  stale `src/modules/plex/*`-shaped context rather than authoritative Desktop
  docs for this checkout.
- Impact analysis: not used because the available Codanna semantic results were
  stale for the requested owner. Direct reads and `rg` are authoritative for
  this plan.
- Direct reads / `rg`: read the required workflow docs, plan standard, current
  architecture, playback architecture, security/secret flow, upstream behavior
  guardrails, import ledger, roadmap, RD-02/RD-03/RD-04/RD-07 plans, player and
  IPC contracts, player adapter, native host port/process, contract tests, and
  package scripts. Direct filesystem checks showed `src/modules/plex` is not
  present in this checkout; current source under `src/**` contains only the
  shell/contracts/main-player scaffold relevant to RD-08.
- Official docs: not required for this unit because it does not change
  Electron, Node runtime behavior, native player APIs, external Plex APIs,
  package/dependency behavior, packaging, or signing. A later implementation
  that changes native playback, network transport, Electron IPC, dependencies,
  or Plex API behavior must perform fresh official-doc research under a
  reviewed replan.

Evidence conclusions:

- RD-03 provides renderer-safe capability, media, track, diagnostic, error, and
  forbidden-field vocabulary, but it does not define a stream-policy decision
  model or HDR/Dolby Vision facts.
- RD-07 provides adapter/process boundaries and stale-event handling, but it
  intentionally does not resolve streams or connect Plex to playback.
- RD-04 requires RD-07/RD-08 player and stream behavior to preserve or
  intentionally diverge from original Lineup behavior through tests, fixtures,
  source audit, or explicit rationale.
- RD-08 should therefore create a pure policy owner and fixtures before any
  runtime Plex import, secure storage, production helper, or renderer UI work.
- Windows closeout proof used the existing RD-06/RD-07 facts without contacting
  Plex: RD-06 native-presentation evidence on `win32`/`x64` records dummy local
  and dummy HTTP playback, only the approved non-secret dummy header, no
  forbidden header observation, native-boundary fullscreen/composition, helper
  crash detection, cleanup, and track behavior not proven by the dummy visual
  sample. RD-07 production player behavior remains renderer-safe unsupported.
  RD-08 therefore treats Windows container, codec, audio, subtitle, track
  switching, direct stream, transcode, HDR, Dolby Vision, and parity support as
  unknown/unproven in the Windows sample matrix.

## Impact Snapshot

Expected blast radius for `desktop-stream-policy-fixture-core`:

- Owners that may change:
  - `src/main/player/streamPolicy/desktopStreamPolicy.ts`
  - `src/main/player/streamPolicy/types.ts`
  - `src/main/player/streamPolicy/fixtures.ts` or a test-only fixture file if
    the implementer keeps fixtures out of product source
  - `src/__tests__/desktopStreamPolicy.test.ts`
  - this plan for factual closeout notes only
- Public contracts that may change: none expected. `src/contracts/player.ts`
  is read-only unless plan review finds the existing capability vocabulary
  cannot support a safe local policy input without duplicating contract truth.
- Dependencies, build tools, configuration, lockfiles, and package scripts: no
  changes allowed.
- Runtime behavior: no user-visible behavior and no production playback
  behavior changes. The unit is policy/test only.
- Import ledger: no change unless implementation copies or adapts original
  Lineup source, which this plan forbids for the first unit.
- Local-only artifacts: none expected. Do not create run bundles, screenshots,
  network logs, or live Plex evidence.

The first unit stays single-owner at the main/player policy seam. It does not
cross into Plex runtime, storage, renderer, preload, native helper, package, or
runtime IPC ownership.

## Files In Scope

Planning write scope for this pass:

- `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md`

Implementation write scope after clean read-only plan review:

- `src/main/player/streamPolicy/desktopStreamPolicy.ts`
- `src/main/player/streamPolicy/types.ts`
- `src/main/player/streamPolicy/fixtures.ts` only if fixtures are intentionally
  product-owned safe examples; otherwise use the test fixture path below
- `src/__tests__/desktopStreamPolicy.test.ts`
- `src/__tests__/fixtures/desktopStreamPolicyFixtures.ts` only if fixtures
  remain test-owned
- `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md` for factual
  closeout evidence only

Optional factual closeout docs after implementation review only:

- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/playback-architecture.md`
- `docs/roadmap/desktop-port-roadmap.md`

## Files Out Of Scope

- `src/contracts/player.ts` unless a reviewed replan expands scope for a
  contract-safe capability field.
- `src/contracts/ipc.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostPort.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/playerIpc.ts`
- `src/main/index.ts`
- `src/preload/**`
- `src/renderer/**`
- Future `src/main/plex/**`, Plex auth/discovery/library/runtime code, selected
  server state, network transport, source payload normalization, and PMS cleanup
- Secure storage, app-data persistence, scheduler/channel/content, renderer UI,
  navigation, settings, packaging, signing, installer, native helper binaries,
  native addons, dependency manifests, lockfiles, generated artifacts, and
  original Lineup source
- `docs/architecture/import-ledger.md` for the first unit, because copied or
  adapted upstream source is not authorized
- Existing unrelated dirty docs and untracked prior plans

## Planner Self-Check

1. Product, architecture, ownership, dependency, import, and verification
   decisions are resolved for the first RD-08 unit: pure main/player policy
   plus fixtures and tests only.
2. Adjacent runtime files do not need to change. Adapter, native-host, IPC,
   preload, renderer, storage, Plex runtime, and package owners are out of
   scope.
3. Files out of scope are not hidden dependencies; the policy consumes
   fixture-normalized candidate facts and does not need live Plex or native
   playback.
4. Evidence path and Codanna fallback are recorded, including the stale
   `src/modules/plex` results and direct-read authority.
5. The repo-preferred owner is used: main/player owns playback policy, contracts
   own renderer-safe vocabulary, and future Plex owners will own real input
   normalization.
6. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, native-helper, Plex transport, or
   verification policy.
7. Exact verification commands, expected outcomes, acceptance criteria,
   rollback notes, and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

Chosen seam: deterministic main/player stream policy under
`src/main/player/streamPolicy/*`.

Frozen decisions for the first implementation unit:

| Decision | RD-08 choice |
| --- | --- |
| Execution unit | `desktop-stream-policy-fixture-core` |
| Runtime owner | none; policy/test only |
| Policy owner | `src/main/player/streamPolicy/*` |
| Input source | deterministic safe fixtures, not Plex runtime |
| Output surface | safe decision objects and reason codes for future main/player use |
| Renderer/preload | out of scope |
| Native helper | out of scope |
| Plex contact | forbidden |
| Upstream source copy/adapt | forbidden for first unit |
| Dependency changes | forbidden |

The implementation must define and test these behavior classes at policy level:

- Capability profile inputs: container, video codec, audio codec, subtitle
  delivery, header-auth setup, track switching, HDR handling, Dolby Vision
  handling, transcode availability, and explicit unknown or unproven support.
- Candidate fixtures: media summary, part summary, video stream summary, audio
  stream summaries, subtitle stream summaries, duration/container/codec facts,
  safe labels/languages/default/forced flags, and policy-only candidate ids
  that are not renderer-visible engine or Plex internals.
- Direct play decisions: selected when a candidate's container, video, audio,
  subtitle, and HDR/Dolby Vision facts are supported without rewriting or
  fallback.
- Direct stream decisions: selected only when the video can remain unchanged
  while a container/audio/subtitle adjustment is explicitly supported by the
  capability profile.
- Transcode decisions: selected only when direct modes fail for a supported and
  explainable reason and transcode is allowed by the profile; otherwise return
  unsupported with reasons and unknowns.
- Audio fallback: prefer requested or default compatible audio; fall back to a
  compatible alternative when allowed; request transcode only when policy says
  fallback cannot satisfy capability; record no-audio-compatible as a reason.
- Subtitle fallback: prefer requested/forced/default compatible subtitles; fall
  back to sidecar/external/burn-in only when the profile supports the delivery
  mode; record unknown subtitle delivery instead of guessing.
- HDR and Dolby Vision handling: preserve only when explicitly supported;
  choose transcode or unsupported when explicitly unsupported; record unknown
  when fixture facts or profile facts are incomplete.
- Decision reasons: every outcome must include stable reason codes and a short
  renderer-safe summary. Reasons must be deterministic and testable.
- Explicit unknowns: unresolved profile facts, incomplete candidate facts,
  untested sample-matrix areas, and unsupported parity claims must be returned
  as unknowns rather than hidden defaults.

Forbidden shortcuts:

- No renderer privilege concession, public contract drift, broad preload RPC,
  runtime Plex transport, secure storage, renderer UI, native-helper launch,
  production playback setup, or package/dependency change.
- No privileged playback setup material, Plex transport fields, source payloads,
  stream identity internals, native internals, Electron/Node objects, or
  secret-bearing diagnostics in renderer-facing contracts, tests, fixtures,
  docs, logs, or Codex output.
- No webOS constants, browser direct-play assumptions, Plex HTPC parity claims,
  or original Lineup path mirrors as Desktop truth.
- No copied/adapted upstream Lineup source without import-ledger update before
  or with the import and reviewed replan.
- No tests that depend on live Plex, network availability, local credentials,
  local media libraries, native player installation, or current machine media
  capabilities.

Stop at this gate if implementation pressure requires any out-of-scope runtime
file, public contract change, privileged field, dependency change, copied
upstream source, live Plex contact, secure storage, renderer UI, native helper,
or unresolved Plex/native playback policy.

## Verification Commands

Plan authoring verification from `/Users/tristan/Software/LineupDesktop`:

```sh
npm run verify:docs
```

Expected outcome: exits `0`; this active Tier 3 plan satisfies the required
plan structure and docs checks without modifying unrelated dirty docs.

Implementation verification after clean plan review:

```sh
git status --short --branch
```

Expected outcome: branch and dirty state are observed before edits; unrelated
dirty docs and prior untracked plans are left untouched.

```sh
npm run typecheck
```

Expected outcome: policy types compile without runtime-only imports in shared
contracts and without weakening existing player or IPC contract strictness.

```sh
npm run test:contracts
```

Expected outcome: existing contract tests pass, and the new stream-policy tests
cover direct play, direct stream, transcode, unsupported decisions, audio
fallback, subtitle fallback, HDR/Dolby Vision handling, deterministic reasons,
explicit unknowns, and forbidden-field exclusion. The new tests must include a
recursive invariant over all RD-08 policy fixtures, policy inputs, and policy
decision outputs using the existing player forbidden-field vocabulary plus a
small RD-08 local denylist for transport/internal identity field names. The
invariant must fail if a fixture or result object contains privileged playback
setup material, Plex transport fields, source payload fields, stream identity
internals, native internals, Electron/Node object fields, or secret diagnostic
fields.

```sh
npm run verify:redaction
```

Expected outcome: the repo-wide baseline credential-pattern scanner exits `0`.
This command does not prove every RD-08 fixture/result constraint; it must be
paired with the scoped test invariant above and the source audit below.

```sh
npm run verify:docs
```

Expected outcome: docs verification passes with this plan still active or
factually closed after implementation review.

```sh
npm run verify
```

Expected outcome: full typecheck, architecture lint, tests, docs verification,
and redaction verification pass before implementation closeout.

Manual/source-audit proof after implementation:

- Inspect `git diff -- src/main/player/streamPolicy src/__tests__ docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md docs/architecture/CURRENT_STATE.md docs/architecture/playback-architecture.md docs/roadmap/desktop-port-roadmap.md`.
- Confirm no preload, renderer, runtime IPC, adapter, native-host,
  Plex-runtime, secure-storage, package, lockfile, generated, import-ledger, or
  upstream source files changed.
- Confirm policy fixtures are deterministic, safe, local, and not copied from
  live Plex responses.
- Run a scoped source audit over `src/main/player/streamPolicy`,
  `src/__tests__/desktopStreamPolicy.test.ts`, and
  `src/__tests__/fixtures/desktopStreamPolicyFixtures.ts` when present. The
  audit must confirm these RD-08 files contain no raw URL examples,
  credential/header examples, live server origins, real media-library payloads,
  native handles, engine ids, part keys, stream keys, raw Plex payload dumps, or
  secret diagnostics. It must also confirm any forbidden-field vocabulary used
  by tests comes from imported contract constants or a local denylist for
  negative key checks, not from realistic secret-bearing fixture values.
- Confirm every tested decision includes stable reason codes and explicit
  unknowns where capability or candidate facts are incomplete.

## Acceptance Criteria

- `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md` is complete,
  feature/design, Tier 3, and passes `npm run verify:docs` before review.
- Plan review is clean before implementation begins.
- The first implementation unit creates a pure deterministic stream-policy
  owner under `src/main/player/streamPolicy/*` with fixture-driven tests.
- Decisions are capability-driven and do not use webOS/browser constants as
  Desktop truth.
- Tests cover direct play, direct stream, transcode, unsupported decisions,
  audio fallback, subtitle fallback, HDR/Dolby Vision handling, stable decision
  reasons, explicit unknowns, and a recursive forbidden-field invariant over all
  RD-08 fixtures, inputs, and outputs.
- No live Plex contact, secure storage, auth/discovery/library runtime,
  renderer UI, production native helper, package/dependency change, or native
  playback launch is introduced.
- Renderer-facing contracts, docs, tests, fixtures, logs, and Codex output do
  not contain privileged playback setup material, Plex transport fields, source
  payloads, stream identity internals, native internals, Electron/Node objects,
  or secret-bearing diagnostics. `npm run verify:redaction` is only the baseline
  credential-pattern proof; scoped RD-08 tests and source audit must prove the
  broader first-unit fixture/result boundary.
- Original Lineup stream resolver/policy remains reference evidence only; no
  import-ledger update is needed for the first unit because no upstream source
  is copied or adapted.
- Required verification passes with observed output before implementation
  closeout.
- Read-only implementation review is clean before RD-08 is marked complete or
  roadmap/current-state docs advance.
- Windows closeout adds a conservative Windows RD-06/RD-07 capability/sample
  matrix test and keeps unsupported fallback reasons, explicit unknowns,
  forbidden-field invariants, no-Plex-contact behavior, and no Plex HTPC parity
  claim intact.

## Replan Triggers

- Plan review finds the policy seam, fixture model, verification surface, or
  forbidden-field policy under-specified.
- Current architecture, playback docs, roadmap status, RD-03 contracts, RD-07
  player files, package scripts, or verifier behavior changed materially since
  this plan.
- Implementation needs public contract changes, preload/main IPC changes,
  renderer UI, native host changes, secure storage, Plex runtime contact,
  selected-server state, production helper launch, dependencies, package
  scripts, lockfile changes, or packaging work.
- Fixture modeling cannot represent required Plex-like candidates without
  copying or adapting original Lineup source.
- Any decision output appears to require privileged playback setup material,
  Plex transport fields, source payloads, stream identity internals, native
  internals, Electron/Node objects, or secret-bearing diagnostics.
- Direct play, direct stream, transcode, audio fallback, subtitle fallback, HDR,
  or Dolby Vision behavior cannot be expressed with deterministic reason codes
  and explicit unknowns.
- Tests require live Plex, real credentials, local media libraries, native
  player installation, current machine media capabilities, or network
  availability.
- Verification fails for an in-scope reason that cannot be fixed inside the
  reviewed file list.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-08 evidence.

## Rollback Notes

Rollback for this planner pass:

- Revert only
  `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md`.
- Do not touch unrelated dirty docs, prior untracked plans, product source,
  package files, roadmap, architecture docs, or import ledger.
- Rerun `git status --short --branch` and `npm run verify:docs` after rollback
  or replacement.

Rollback for the first implementation unit:

- Revert only reviewed RD-08 additions under `src/main/player/streamPolicy/*`,
  `src/__tests__/desktopStreamPolicy.test.ts`,
  `src/__tests__/fixtures/desktopStreamPolicyFixtures.ts`, this plan's factual
  closeout notes, and optional closeout updates to current-state/playback/
  roadmap docs.
- Do not revert RD-03 contracts, RD-07 adapter/native-host files, preload,
  renderer, package metadata, lockfiles, import ledger, original Lineup source,
  or unrelated dirty files.
- Because no runtime storage, credentials, native helper, network transport, or
  generated artifacts are authorized, rollback should not require data
  migration, credential cleanup, helper teardown, package restoration, or local
  Plex cleanup.

## Commit Checkpoints

Checkpoint 1: RD-08 plan authoring only.

- Commit only after `npm run verify:docs` passes and read-only plan review is
  clean.
- Suggested commit: `docs: plan rd-08 desktop stream policy`
- Include only
  `docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md`.
- Do not stage unrelated dirty docs or prior untracked plans.

Checkpoint 2: reviewed fixture-policy implementation only.

- Commit only after clean plan review, scoped implementation, required
  verification, and read-only implementation review are clean.
- Suggested commit: `feat(player): add desktop stream policy fixtures`
- Include only reviewed RD-08 policy/test files and factual closeout docs.
- Do not include import-ledger changes, package changes, Plex runtime, secure
  storage, renderer UI, native helper, generated output, local evidence, or
  unrelated dirty files.

MODEL_SUGGESTION
PLANNER: planner with high reasoning
IMPLEMENTER: worker with high reasoning
REVIEWER: reviewer with high reasoning
WHY: RD-09 will define credential and app-data persistence boundaries before Plex auth/import work, so it touches storage/secrets, renderer custody, redaction, and future Plex integration.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Plan RD-09 Secure Storage And Persistence Boundary
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: none
ARTIFACT: completed RD-08 Desktop stream policy fixture core and Windows capability/sample-matrix closeout
FILES:
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/agentic/session-prompts/feature-quality-loop.md
- docs/agentic/plan-authoring-standard.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/playback-architecture.md
- docs/architecture/import-ledger.md
- docs/roadmap/desktop-port-roadmap.md
- docs/plans/2026-05-10-rd-08-desktop-stream-policy-plan.md
- src/contracts/player.ts
- src/main/player/streamPolicy/desktopStreamPolicy.ts
- src/main/player/streamPolicy/types.ts
- src/__tests__/desktopStreamPolicy.test.ts
- src/__tests__/fixtures/desktopStreamPolicyFixtures.ts
- package.json
BLOCKERS: none for RD-09 planning; RD-08 intentionally did not contact Plex, wire runtime playback, add secure storage, expose transport fields, or claim Plex HTPC parity.
MESSAGE:
Create the RD-09 Secure Storage And Persistence Boundary plan. Start from the
completed RD-08 stream policy closeout: Desktop stream decisions are
deterministic and fixture-only, Windows capability/sample-matrix proof
conservatively preserves unknowns instead of claiming codec/container/audio or
Plex HTPC parity, production playback remains unsupported, and there is still
no Plex auth/discovery/library runtime, secure storage, selected-server state,
renderer UI, native helper production path, package/dependency change, or
copied/adapted upstream source. RD-09 should define main-owned credential and
app-data persistence boundaries before Plex auth/import work begins, keep the
renderer unprivileged, preserve redaction rules, and name exact files,
verification, rollback, and stop conditions before implementation.
