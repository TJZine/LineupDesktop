**Plan Status:** active

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** planning

**Verification classification:** new regression/contract test required

## Goal

Plan RD-07 Desktop VideoPlayer Adapter as the production player adapter
boundary between renderer-safe player contracts and the future privileged
native playback host.

RD-07 must define the Desktop adapter against `src/contracts/player.ts` and
`src/contracts/ipc.ts`, keep renderer/preload/main/native-helper ownership
narrow, and make the first implementation unit small enough for one reviewed
worker pass after clean read-only plan review.

The first execution unit is `desktop-player-adapter-boundary-core`: add the
main-owned adapter boundary and public-seam tests that prove command mapping,
state snapshots, event ordering, stale request handling, renderer-safe
diagnostics, helper crash handling, and request cleanup using a fake native host
port. The unit must not wire production Plex, scheduler, broad UI, secure
storage, packaging, or native smoke proof.

## Non-Goals

- Do not edit implementation source in this planning pass.
- Do not begin source or test implementation until read-only
  `lineup-desktop-feature-review` reports no plan blockers.
- Do not reopen WID or helper-owned render API as the RD-07 native surface
  direction. RD-07 may target the reviewed app-owned native presentation
  direction from RD-06.
- Do not require this macOS planning session to run Windows native proof.
  Windows-native proof remains Windows-only and belongs to a later bounded
  native proof or smoke plan.
- Do not import product Plex, scheduler, stream policy, secure storage, broad
  renderer UI, packaging, installer, signing, updater, or upstream product code.
- Do not contact real Plex servers or use real tokens, tokenized URLs, auth
  headers, raw Plex payloads, checked-in media, raw native logs, native handles,
  libmpv objects, engine ids, broad IPC, stream keys, part keys, or secret
  diagnostics.
- Do not expose raw media URLs, headers, tokens, native handles, libmpv objects,
  engine ids, Electron APIs, Node APIs, broad IPC, raw Plex payloads, stream
  keys, part keys, or secret diagnostics to renderer-facing state, preload
  APIs, tests, docs, logs, diagnostics, or Codex output.
- Do not implement real native helper process management in the first execution
  unit. The first unit may define a private fakeable host port for adapter
  tests only.
- Do not claim track selection, subtitle selection, DPI, multi-monitor, or
  full media matrix behavior as production-proven by RD-07. RD-06 left
  track/subtitle behavior conservative and unproven by the tiny dummy visual
  input.
- Do not update roadmap, architecture docs, package files, lockfiles, unrelated
  plans, or import ledger in this planning pass. Implementation closeout is
  different: if the reviewed first unit creates the durable main-owned adapter
  boundary, closeout must refresh the authorized architecture memory named
  below after source/tests pass.

## Parent Architecture Alignment

Current architecture says the repository has a secure Electron shell,
renderer-safe player and IPC contract vocabulary, and no production Plex
integration, scheduler, native playback helper, player runtime adapter, secure
storage, or packaging implementation yet.

RD-03 completed the player contract and capability model in
`src/contracts/player.ts` and `src/contracts/ipc.ts`. These contracts already
name renderer-safe commands, request ids, snapshots, events, capability
profiles, opaque track ids, error categories, diagnostics, renderer intents,
and forbidden privileged field vocabulary.

RD-06 is complete and reviewed for RD-07 routing. WID and helper-owned render
API failed required fullscreen video-surface proof and must stay closed unless
a new reviewed plan explicitly reopens them. The reviewed native surface target
for RD-07 is app-owned native presentation, but RD-07 must not turn the
dev-only spike into production helper code without a reviewed implementation
plan.

Ownership alignment:

- Renderer owns UI composition and renderer-safe player state only.
- Preload remains a narrow validated bridge and must not become a broad player
  RPC passthrough.
- Electron main owns privileged player command ingestion, request lifecycle,
  redaction, diagnostics, and future native host coordination.
- Native-helper/native-host code owns native playback and app-owned native
  presentation only after a reviewed implementation unit creates that owner.
- Contracts own public renderer-safe shapes and forbidden privileged field
  vocabulary, not secrets, native handles, raw Plex data, Electron objects,
  Node APIs, or libmpv objects.

The first RD-07 implementation unit should create the adapter core as a
main-owned boundary with a fakeable host port. It should not wire preload or
renderer runtime APIs until the adapter contract behavior is reviewed and
tested.

Renderer-originating player commands enter the first unit as
`RendererIntentEnvelope<unknown>` at the adapter boundary, not as already
trusted `PlayerCommand` values. The adapter owns schema validation and closed
intent-to-command mapping before any fake host call. Helper-originating events
from the typed fake native host port are also treated as boundary payloads:
they must be validated and normalized before state mutation. Invalid renderer
or fake-host payloads must produce renderer-safe validation errors, exclude
forbidden privileged fields, and must not reach or mutate through the fake
host.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/roadmap/desktop-port-roadmap.md`
7. `docs/architecture/playback-architecture.md`
8. `docs/architecture/security-and-secret-flow.md`
9. `docs/architecture/upstream-behavior-guardrails.md`
10. `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`
11. `src/contracts/player.ts`
12. `src/contracts/ipc.ts`
13. `src/__tests__/contracts.test.ts`
14. `package.json`
15. This plan.

Freshness gate: before review or implementation, rerun
`git status --short --branch` and reread the files above if architecture docs,
contracts, roadmap status, RD-06 status, verifier behavior, package scripts, or
this plan changed materially after 2026-05-10. Stop for plan update or
re-review if any assumption is contradicted.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3 RD-07
  planner pass.
- `execution-plan-authoring`: freezes scope, ownership, invariants,
  verification, acceptance criteria, rollback, and replan triggers without
  pseudo-code.
- `architecture-boundaries`: required because RD-07 defines player adapter,
  IPC/contract, Electron main, preload, renderer, and future native-helper
  boundaries.
- `plex-integration-boundaries`: required because future playback setup may
  carry Plex-derived stream material, while RD-07 must keep Plex tokens,
  tokenized URLs, auth headers, raw Plex payloads, stream keys, and part keys
  out of renderer-facing state.
- `verification-strategy`: required because the adapter boundary needs public
  seam tests, redaction checks, and explicit Windows-native proof limits.
- `review-request`: next gate is read-only adversarial plan review through
  `lineup-desktop-feature-review`.
- `closeout-verification`: required before calling this plan ready, staging,
  committing, handing off, or later calling implementation complete.

## Evidence And Discovery

- `semantic_search_with_context`: Codanna is enabled and reported 12134 symbols
  across 801 indexed files, with embeddings updated about one hour before this
  planner pass. The query for Desktop player adapter contracts returned mostly
  original/upstream Lineup symbols such as `src/modules/player/VideoPlayer.ts`
  and UI/navigation modules that are not present in the current Desktop
  `src` tree. This was useful as a warning that the index is stale or broader
  than the checked-out Desktop surface, not as authoritative RD-07 evidence.
- `semantic_search_docs` or repo-doc search: Codanna semantic docs for RD-07
  also returned upstream-style symbols and webOS stream constants instead of
  the tracked Desktop docs. Direct repo reads and `rg` were used for Desktop
  docs.
- Impact analysis: deeper Codanna impact analysis was not used because the
  relevant production adapter symbols do not exist yet in the Desktop source
  tree, and the returned symbol graph was noisy for this repo state.
- Direct reads / `rg`: required launcher docs, architecture docs, roadmap,
  RD-06 plan, contracts, contract tests, and `package.json` were read directly.
  `rg --files src` confirmed the current Desktop source tree only contains
  contracts, secure shell main/preload/renderer files, and contract tests.
  `rg -n "RD-07|Desktop VideoPlayer Adapter|app-owned native|VideoPlayer|player adapter|native presentation" docs src package.json`
  anchored the RD-07 roadmap objective, RD-06 native presentation conclusion,
  and guardrail references.
- Official docs: no new external Electron, native, packaging, or dependency
  behavior is frozen by this planner pass. RD-06 already records native proof
  evidence and official-doc checks for its spike. If RD-07 implementation needs
  new Electron, libmpv, native addon, packaging, signing, or platform claims,
  stop for a reviewed replan or bounded docs-research check.

Direct evidence summary:

- `docs/roadmap/desktop-port-roadmap.md` marks RD-07 not started, dependent on
  RD-03 and RD-06, and requires adapter tests for command mapping, state,
  events, errors, stale request handling, diagnostics, helper crash behavior,
  request cleanup, renderer-safe state, and non-bloated orchestration owners.
- `docs/architecture/playback-architecture.md` records that WID and
  helper-owned render API are blocked for RD-07, while the revised app-owned
  native presentation proof is the reviewed direction. Track selection and
  subtitle behavior remain unproven.
- `docs/architecture/security-and-secret-flow.md` keeps token-bearing playback
  material inside privileged main/helper setup and outside renderer ownership.
- `docs/architecture/upstream-behavior-guardrails.md` requires RD-07/RD-08
  player and stream behavior to protect original command/state/event,
  stale-load, track, error, diagnostic, teardown, and cleanup lessons without
  exposing raw URLs, headers, native handles, engine ids, libmpv objects, or
  webOS constants through renderer-facing state.
- `src/contracts/player.ts` defines renderer-safe command, state, event, error,
  diagnostic, capability, and forbidden privileged field vocabulary.
- `src/contracts/ipc.ts` defines player renderer intents and shared forbidden
  renderer payload keys, but no production player IPC channels yet.
- `src/__tests__/contracts.test.ts` already protects forbidden fields,
  renderer-safe player events, stale request identifiability, capability
  profiles, opaque track ids, error taxonomy, diagnostics, shell IPC literals,
  and the currently narrow preload API.
- `package.json` already has `typecheck`, `test:contracts`,
  `verify:architecture`, `verify:docs`, `verify:redaction`, and `verify`
  scripts. No dependency, script, lockfile, or package metadata change is
  needed for the first RD-07 unit.

## Impact Snapshot

Expected blast radius after clean plan review:

- Owners that may change: shared player/IPC contracts only if the adapter seam
  needs additive renderer-safe vocabulary; new main-owned player adapter
  boundary; adapter contract tests.
- Owners that must not change in the first unit: renderer UI, preload bridge,
  production Electron IPC handlers, native-helper implementation, Plex,
  scheduler, stream policy, secure storage, packaging, installer, signing, and
  update owners.
- Public contracts that may change: `src/contracts/player.ts` and
  `src/contracts/ipc.ts` may receive additive closed vocabulary only when
  required by the adapter boundary. They must not gain raw URLs, headers,
  tokens, native handles, libmpv objects, engine ids, Electron/Node APIs,
  broad channel strings, raw Plex payloads, stream keys, part keys, or secret
  diagnostics.
- Dependency, build-tool, configuration, and lockfile impact: none authorized.
- Commands/tests/docs that must change after clean review: add focused adapter
  contract tests; update existing contract tests only if public vocabulary
  changes. If the durable main-owned adapter boundary survives implementation
  review, closeout must update only `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md` to keep architecture memory current.
- User-visible behavior: none in the first unit. The adapter core is not wired
  to a real renderer/preload/main runtime path yet.
- Local-only artifacts: none expected. Any accidental local logs, scratch
  output, generated media, native traces, or `docs/runs/*` evidence must stay
  untracked and out of this RD-07 commit.

The first execution unit touches more than one ownership concept, but it stays
single runtime-owner in source: Electron main owns the adapter core and its
private fakeable host port. Contracts and tests define the public seam; they do
not create runtime wiring.

## Files In Scope

Planning pass write scope:

- `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`

After clean read-only plan review, first execution unit write scope:

Source/test scope:

- `src/contracts/player.ts`
- `src/contracts/ipc.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/nativePlayerHostPort.ts`
- `src/__tests__/desktopPlayerAdapter.test.ts`
- `src/__tests__/contracts.test.ts`

Implementation closeout memory scope, only after source/tests pass and
read-only implementation review/adjudication confirms the durable owner must
be recorded:

- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/playback-architecture.md`
- `docs/roadmap/desktop-port-roadmap.md`

Scope limits for those files:

- Contract files may only define renderer-safe public shapes or closed
  vocabulary needed by the adapter boundary.
- Main player files may only define the adapter core and a private fakeable
  native-host port. They must not launch a real helper, open media, contact
  Plex, perform stream policy, own secure storage, or wire production preload
  and renderer APIs.
- Tests must exercise public adapter and contract behavior with fakes, not
  private helper internals or real native media.
- Tests must prove adapter-boundary validation for
  `RendererIntentEnvelope<unknown>` mapping, invalid renderer payload
  rejection before fake-host calls, typed fake-host event validation and
  normalization before state mutation, and renderer-safe validation errors for
  rejected payloads.

## Files Out Of Scope

- Any file outside the planning-pass write scope during this planner pass.
- Roadmap and architecture docs during this planner pass, including
  `docs/roadmap/desktop-port-roadmap.md`,
  `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`,
  `docs/architecture/security-and-secret-flow.md`,
  `docs/architecture/upstream-behavior-guardrails.md`, and
  `docs/architecture/import-ledger.md`.
- During the first unit source/test implementation, architecture and roadmap
  docs remain out of scope until the closeout memory gate. After that gate,
  only `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md` may change, and only to record the
  implemented durable main-owned adapter boundary.
- Existing unrelated plans and handoffs.
- `package.json`, lockfiles, package manager metadata, dependency manifests,
  build tooling, installer, signing, update, release, and packaging config.
- `src/preload/**`.
- `src/renderer/**`.
- Existing shell-only runtime wiring in `src/main/index.ts`,
  `src/main/protocol.ts`, and `src/main/shellSecurity.ts`, except a later
  reviewed RD-07 replan may explicitly authorize narrow player IPC wiring.
- Production `src/native-helper/**` or equivalent native helper runtime paths.
- RD-05 and RD-06 dev-only tools under `tools/mpv-poc/**` and
  `tools/libmpv-spike/**`.
- Plex auth, discovery, library, stream resolution, selected-server,
  subtitles, token handling, URL/header setup, secure storage, scheduler,
  channel, settings, broad UI import, navigation, EPG, OSD, packaging, native
  addon, or copied/adapted upstream Lineup source.
- Checked-in media fixtures, raw run evidence, native logs, crash dumps,
  generated helper output, local native binaries, copied mpv headers/examples,
  generated bindings, NuGet packages, or npm dependencies.
- Unrelated dirty files already present before this RD-07 planner pass.

## Planner Self-Check

1. No product, architecture, ownership, dependency, or verification decision is
   left open for the first execution unit: a main-owned adapter boundary with
   fake native host tests and adapter-boundary payload validation is selected.
2. The first execution unit does not depend on Plex, scheduler, stream policy,
   preload, renderer, packaging, secure storage, or real native helper changes.
3. Files frozen out of scope are not relied on for hidden wiring. Runtime
   preload/main wiring is explicitly deferred.
4. Evidence path is recorded through required direct reads, `rg`, and Codanna
   fallback notes.
5. The owner path avoids growing renderer, preload, shell main composition
   roots, Plex, scheduler, or UI hot spots.
6. A fresh implementer should not need to invent IPC, security, playback,
   persistence, packaging, import, native proof, or verification policy for the
   first unit.
7. Verification commands, expected outcomes, acceptance criteria, rollback,
   and stop/replan triggers are explicit.

## Architecture Seam Decision Gate

Chosen seam: main-owned Desktop player adapter boundary, contract-anchored by
`src/contracts/player.ts` and `src/contracts/ipc.ts`, with a private fakeable
native host port that targets the RD-06 app-owned native presentation direction
without implementing native playback in the first unit.

Frozen decisions:

| Decision | RD-07 choice |
| --- | --- |
| First execution unit | `desktop-player-adapter-boundary-core` |
| Runtime owner | Electron main owns adapter request lifecycle, event ordering, error normalization, helper crash translation, cleanup, and redacted diagnostics |
| Renderer boundary | Renderer receives only `PlayerSnapshot`, `PlayerEvent`, `PlayerError`, and renderer-safe diagnostics from contracts |
| Preload boundary | No preload expansion in the first unit; future preload player API needs a reviewed replan or later reviewed RD-07 unit |
| IPC boundary | Accept renderer-originating `RendererIntentEnvelope<unknown>` at the adapter boundary and map only validated closed intents to `PlayerCommand`; no arbitrary channel strings or broad RPC |
| Native boundary | Use a private fakeable host port shaped for app-owned native presentation; no real helper process, libmpv object, native handle, graphics context, or engine id enters renderer-facing state |
| Payload validation boundary | Adapter validates renderer-originating intent envelopes and typed fake-host events before fake-host calls or state mutation; invalid payloads produce renderer-safe validation errors and forbidden fields are excluded |
| Plex boundary | No Plex or stream policy implementation; future Plex-derived playback setup remains privileged main/helper work |
| Track/subtitle boundary | Keep audio/subtitle selection conservative because RD-06 did not prove real track/subtitle behavior; tests may prove opaque id handling and failure mapping only |
| Diagnostics boundary | Diagnostics may contain component, operation, status, reason, counts, capability profile id, safe track ids, safe media summary, and timestamps only |
| Import boundary | No copied/adapted upstream product source in RD-07 first unit; import ledger is unchanged |
| Dependency boundary | No package, lockfile, native addon, NuGet, generated binding, checked-in binary, or new build-tool change |

Forbidden shortcuts:

- No renderer privilege concession.
- No raw Electron, Node, filesystem, native, libmpv, graphics, token, URL,
  header, Plex, stream key, part key, or secret diagnostic values in
  renderer-facing state.
- No broad preload RPC or arbitrary channel pass-through.
- No production helper launch hidden inside adapter tests.
- No WID or helper-owned render API revival without a new reviewed plan.
- No upstream path shims, compatibility barrels, broad helper owners, or copied
  product code.
- No blessing stale events as harmless without request-id gating and tests.
- No claiming track/subtitle production support beyond the conservative
  contract behavior proved by RD-07 tests.

Stop before implementation if plan review finds the seam too broad, if the
adapter cannot be tested without runtime preload/main wiring, if source needs
Plex/scheduler/stream/native implementation to compile, or if contracts need
privileged values to satisfy the adapter.

Stop before implementation or during the first unit if adapter-boundary
validation cannot be implemented without broad preload/main runtime IPC wiring,
without treating unvalidated renderer payloads as `PlayerCommand`, or without
letting fake-host events mutate state before validation.

## Verification Commands

Planner commands:

```sh
git status --short --branch
```

Expected outcome: branch state is observed before edits; unrelated dirty files
are not modified, staged, reverted, or treated as RD-07 evidence.

```sh
npm run verify:docs
```

Expected outcome: passes after this active plan is written. If it fails, fix
only the RD-07 plan shape/content unless the failure exposes a pre-existing
unrelated repo issue that should be reported instead of edited.

First execution unit commands after clean plan review:

```sh
git status --short --branch
```

Expected outcome: dirty state is understood before implementation; unrelated
files are left alone.

```sh
npm run typecheck
```

Expected outcome: TypeScript compiles with the new adapter boundary and no
public/concrete signature drift.

```sh
npm run test:contracts
```

Expected outcome: existing contract tests still pass and new adapter tests
prove command mapping, snapshot/event behavior, stale request rejection or
quarantine, helper crash error mapping, request cleanup, opaque track id
handling, conservative unproven track/subtitle behavior, adapter-boundary
validation for renderer-originating `RendererIntentEnvelope<unknown>` payloads,
invalid renderer payload rejection before fake-host calls, typed fake-host
event validation and normalization before state mutation, renderer-safe
validation errors, and forbidden field exclusion.

```sh
npm run verify:redaction
```

Expected outcome: tracked docs, tests, and source contain no forbidden raw
secret, token, URL, header, native handle, libmpv, engine id, raw Plex, stream
key, part key, or secret diagnostic content.

```sh
npm run verify
```

Expected outcome: passes before RD-07 implementation is called complete. If a
later implementation unit adds runtime IPC/security wiring, native playback,
or Windows-only proof, this command is necessary but not sufficient; that unit
must add the narrower proof named by its reviewed plan.

Manual/source-audit proof after implementation:

- Inspect `git diff -- src/contracts/player.ts src/contracts/ipc.ts src/main/player src/__tests__`
  and confirm only reviewed RD-07 source/test files changed before the closeout
  memory gate.
- Confirm adapter validators reject malformed renderer envelopes and fake-host
  events before fake-host calls or state mutation, and that all such failures
  use renderer-safe `validation-failure` errors.
- After source/tests pass and read-only implementation review/adjudication
  confirms the durable main-owned adapter boundary should be recorded, inspect
  `git diff -- docs/architecture/CURRENT_STATE.md docs/architecture/playback-architecture.md docs/roadmap/desktop-port-roadmap.md`
  and confirm those are the only closeout memory docs changed.
- Confirm no package metadata, lockfile, RD-06 tools, Plex, scheduler,
  renderer, preload, native helper runtime, unrelated architecture docs, or
  unrelated plan files changed.
- Confirm adapter diagnostics and test fixtures contain renderer-safe data
  only.
- Run `npm run verify:docs` after any authorized closeout memory update, then
  rerun `npm run verify` before implementation is called complete.

## Acceptance Criteria

Plan acceptance:

- This file is the only file created or edited by the RD-07 planner pass.
- The plan is marked active, feature/design, Tier 3, and contains the required
  active-plan headings.
- The plan freezes the RD-07 seam against `src/contracts/player.ts` and
  `src/contracts/ipc.ts`.
- The plan keeps renderer, preload, main, and native-helper ownership narrow.
- The plan records that app-owned native presentation is the RD-07 native
  surface target from RD-06, without reopening WID or helper-owned render API.
- The plan records that track/subtitle behavior remains conservative or
  unproven until later media matrix work.
- The plan does not authorize Plex, scheduler, broad UI, stream policy,
  packaging, secure storage, native smoke proof, source imports, dependencies,
  package changes, roadmap edits, or architecture doc edits in this planning
  pass.
- The plan authorizes first-unit closeout memory updates to only
  `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md`, and only after source/tests pass and
  implementation review/adjudication confirms the durable adapter owner must be
  recorded.
- `npm run verify:docs` passes, or any failure is reported with exact observed
  output and no false success claim.
- The next session is routed to read-only `lineup-desktop-feature-review`.

First execution unit acceptance after clean plan review:

- Implementation is limited to `desktop-player-adapter-boundary-core`.
- Source changes are limited to the first execution unit write scope unless a
  reviewed replan expands it.
- Adapter tests cover renderer intent to player command mapping, player state
  snapshots, player events, errors, stale request handling, renderer-safe
  diagnostics, helper crash behavior, request cleanup, adapter-boundary
  validation for renderer-originating `RendererIntentEnvelope<unknown>`,
  typed fake-host event validation and normalization, invalid payload rejection
  before fake-host calls or state mutation, and forbidden field exclusion.
- Invalid renderer and fake-host payloads map to renderer-safe
  `validation-failure` errors and do not expose forbidden privileged fields or
  raw diagnostics.
- Adapter behavior uses request ids to prevent stale native events from
  corrupting current playback state.
- Helper crash and cleanup failures map to renderer-safe `PlayerError`
  categories without raw native diagnostics.
- Renderer-facing state and diagnostics do not include raw media URLs, headers,
  tokens, native handles, libmpv objects, engine ids, Electron/Node APIs, broad
  IPC, raw Plex payloads, stream keys, part keys, or secret diagnostics.
- Track and subtitle behavior is limited to opaque id handling, unsupported or
  unproven capability reporting, and safe error mapping until a later reviewed
  media matrix proves more.
- No product Plex, scheduler, stream policy, secure storage, broad UI,
  packaging, native helper runtime, package, lockfile, or upstream import files
  change.
- After the adapter source/tests pass and implementation review/adjudication is
  clean, closeout updates `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md` to remove stale "no adapter" memory
  and record the new main-owned adapter boundary. No other architecture,
  roadmap, or plan files change.
- `npm run verify:docs` passes after closeout memory docs are updated.
- `npm run verify` passes before implementation closeout.
- Read-only implementation review is clean before RD-07 is called complete.

## Replan Triggers

Stop and replan if any of the following occurs:

- Read-only plan review finds the adapter boundary too broad, under-specified,
  or inconsistent with current contracts.
- Current architecture, roadmap, RD-06 status, contract files, package scripts,
  or verifier behavior changed materially after this plan.
- Implementation needs preload expansion, production main IPC wiring, renderer
  UI wiring, native helper runtime, real native smoke proof, Plex, stream
  policy, scheduler, secure storage, package, lockfile, dependency, packaging,
  installer, signing, or upstream import changes.
- Adapter-boundary validation for renderer-originating
  `RendererIntentEnvelope<unknown>` or fake-host events requires broad
  preload/main runtime IPC wiring, or cannot prevent invalid payloads from
  reaching the fake host or mutating state.
- Contracts appear to require raw media URLs, headers, tokens, native handles,
  libmpv objects, engine ids, Electron/Node APIs, broad channel strings, raw
  Plex payloads, stream keys, part keys, or secret diagnostics.
- The fake native host port becomes a no-value abstraction, a hidden native
  implementation, a broad helper owner, or a compatibility shim.
- Stale events cannot be rejected or quarantined through request ids without
  hidden runtime policy.
- Required closeout memory cannot be kept to
  `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md`, or those docs would need to change
  before the adapter source/tests pass.
- Track/subtitle selection cannot be represented conservatively without
  overclaiming unproven RD-06 behavior.
- Codanna or direct reads reveal an existing Desktop owner for the adapter that
  contradicts the selected main-owned seam.
- `npm run verify:docs`, `npm run typecheck`, `npm run test:contracts`,
  `npm run verify:redaction`, or `npm run verify` fails for an in-scope reason
  that cannot be fixed inside the reviewed scope.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-07 evidence.

## Rollback Notes

Rollback for this planner pass:

- Remove only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`.
- Do not touch unrelated dirty files, existing plans, roadmap, architecture
  docs, package files, or implementation source.
- Rerun `git status --short --branch` and `npm run verify:docs` if the plan is
  removed or replaced.

Rollback for the first reviewed implementation unit:

- Revert only reviewed RD-07 changes in `src/contracts/player.ts`,
  `src/contracts/ipc.ts`, `src/main/player/desktopPlayerAdapter.ts`,
  `src/main/player/nativePlayerHostPort.ts`,
  `src/__tests__/desktopPlayerAdapter.test.ts`, and
  `src/__tests__/contracts.test.ts`.
- If the implementation reached the closeout memory gate, also revert only the
  RD-07 memory updates in `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md`.
- Delete any empty `src/main/player/` directory left by rollback if it was
  created only by the RD-07 unit.
- No package, lockfile, unrelated roadmap, unrelated architecture, Plex,
  scheduler, renderer, preload, native helper, or import-ledger rollback should
  be needed because those files are out of scope. If they changed, stop and
  adjudicate before reverting anything not created by the RD-07 unit.
- Delete accidental local-only scratch output or ignored run artifacts created
  during implementation. Do not stage generated artifacts.
- Rerun `git status --short --branch` and the verification commands named by
  the reviewed implementation plan before closeout.

## Commit Checkpoints

Checkpoint 1: RD-07 plan artifact only.

- Commit only after this plan is written, read-only plan review is clean, and
  `npm run verify:docs` passes.
- Suggested commit: `docs: plan rd-07 desktop player adapter`
- Include only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`.
- Do not include unrelated dirty plans or user work.

Checkpoint 2: reviewed adapter boundary core only.

- Commit only after clean plan review, scoped implementation, `npm run verify`
  passing, required closeout memory updates, `npm run verify:docs` passing
  after those docs updates, and clean read-only implementation review.
- Suggested commit: `feat: add desktop player adapter boundary`
- Include only reviewed RD-07 source/test files and required closeout memory
  updates in `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md`. Do not include package, lockfile,
  unrelated roadmap, unrelated architecture, Plex, scheduler, renderer,
  preload, native helper, upstream import, generated, or local-only artifact
  changes.

Checkpoint 3: blocked closeout, if the first unit cannot stay bounded.

- If the adapter boundary cannot be implemented without out-of-scope owners,
  stop without product implementation commits.
- Update this plan only if the controller explicitly asks for a blocked replan
  artifact, then run `npm run verify:docs`.
- Suggested commit if a blocked plan update is applied:
  `docs: mark rd-07 adapter boundary blocked`

MODEL_SUGGESTION
PLANNER: planner with high reasoning; exact `gpt-5-codex` may be approximated by available models.
IMPLEMENTER: worker with high reasoning; exact `gpt-5-codex` may be approximated by available models.
REVIEWER: reviewer with high reasoning; exact `gpt-5-codex` may be approximated by available models.
WHY: RD-07 touches player contracts, IPC/security boundaries, Electron main ownership, future native playback boundaries, redaction, stale-event handling, and Tier 3 review gates.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review RD-07 Desktop VideoPlayer Adapter plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md
ARTIFACT: active RD-07 tracked plan
FILES:
- docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/agentic/session-prompts/feature-plan.md
- docs/agentic/plan-authoring-standard.md
- docs/architecture/CURRENT_STATE.md
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
- src/contracts/player.ts
- src/contracts/ipc.ts
- src/__tests__/contracts.test.ts
- package.json
BLOCKERS: none for read-only plan review; implementation must not begin until review is clean.
MESSAGE:
Review the active RD-07 Desktop VideoPlayer Adapter plan read-only. Confirm it satisfies `docs/agentic/plan-authoring-standard.md`, keeps RD-07 scoped to the contract-anchored main-owned adapter boundary and tests, preserves renderer/preload/main/native-helper ownership, uses RD-06 app-owned native presentation as the reviewed native surface target without reopening WID or helper-owned render API, requires adapter-boundary validation for renderer-originating `RendererIntentEnvelope<unknown>` and typed fake-host events before fake-host calls or state mutation, maps invalid payloads to renderer-safe validation errors, excludes Plex/scheduler/broad UI/stream policy/secure storage/packaging/native smoke/source imports from the first unit, keeps track/subtitle support conservative or unproven, and authorizes closeout memory updates only to `docs/architecture/CURRENT_STATE.md`, `docs/architecture/playback-architecture.md`, and `docs/roadmap/desktop-port-roadmap.md` after source/tests pass and implementation review/adjudication confirms the durable adapter owner must be recorded. Lead with blockers or material findings, cite file/section references, and do not edit files.
