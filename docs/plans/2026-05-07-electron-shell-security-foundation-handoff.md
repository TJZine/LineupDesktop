# Electron Shell Security Foundation Handoff

- **Status:** handoff-ready
- **Date:** 2026-05-07
- **Task family:** feature/design

This handoff is for a fresh Codex session rooted at
`/Users/tristan/Software/LineupDesktop`. The next session should create and
review an active Tier 3 plan before implementing product code.

## Next Session Objective

Create a tracked active plan for the Electron shell and security foundation
slice. Do not implement the shell in the planning session unless the user
explicitly changes scope after the plan is reviewed.

Suggested plan path:

```text
docs/plans/2026-05-07-electron-shell-security-foundation-plan.md
```

## What Foundation Slice Means

The foundation slice is the first production platform slice for Lineup Desktop.
It should create the safe Electron process skeleton that every later feature
plugs into. Its job is to prove that the app can boot locally with the right
privilege boundaries, typed renderer contracts, and baseline verification before
Plex, playback, packaging, or the full TV UI are imported.

The slice should produce a runnable but intentionally minimal Electron app:

- Electron main process ownership for app lifecycle, window creation, secure
  `BrowserWindow` defaults, and privileged IPC handling.
- A preload bridge that exposes a narrow typed API through `contextBridge`, not
  raw Electron or Node primitives.
- A minimal renderer boot surface that proves the shell and preload contract
  work, without importing the existing Lineup UI yet.
- Shared contract types for renderer-safe data only.
- Architecture, contract, and smoke verification proving the renderer remains
  unprivileged.

This is not a generic scaffold exercise. It is "foundation" because every later
slice depends on these boundaries: Plex/auth can only enter through privileged
owners, the renderer can only send typed intents, playback/native helper work
can attach later without exposing handles or secrets, and the existing Lineup UI
can be imported into a renderer that already has clear constraints.

## Foundation Slice Outputs

The implementation plan should make the following outputs explicit before code
starts:

- `src/main/`: Electron app entrypoint and window/lifecycle owner.
- `src/preload/`: typed bridge module exposing the renderer API and event
  subscriptions with cleanup.
- `src/renderer/`: minimal boot target for proving renderer load and bridge
  availability.
- `src/contracts/`: preload/IPC envelope types, renderer-safe payload shapes,
  and forbidden privileged-field assertions.
- `src/shared/` or equivalent only if the plan identifies pure code that must be
  shared without leaking ownership.
- package scripts needed for local development, build/typecheck, verification,
  and an Electron smoke proof if Electron is introduced in this slice.
- focused tests or static checks for contracts, renderer import boundaries,
  payload redaction, and privileged-field blocking.
- documentation updates for current architecture, security/secret flow, testing,
  and the import ledger if any upstream Lineup code is copied or adapted.

Do not require repository-hosting conveniences such as PR templates, CodeRabbit,
or GitHub Actions as blockers for this implementation slice. Those surfaces are
useful control-plane support, but local architecture and security checks are the
foundation acceptance gates.

## Process Boundary Contract

| Surface | Owns In Foundation | Must Not Own |
| --- | --- | --- |
| Renderer | Minimal DOM boot, visible shell placeholder, typed user/app intents, renderer-safe state display. | Node/Electron imports, persistent secrets, raw auth headers, tokenized URLs, native handles, player process handles, Plex policy, direct filesystem access. |
| Preload | `contextIsolation` bridge, narrow API methods, event subscription/unsubscription, payload validation before renderer delivery. | Raw `ipcRenderer`, broad RPC passthrough, secret material, native helper commands, policy decisions that belong in main/helper owners. |
| Main | App lifecycle, window creation, secure `BrowserWindow` defaults, IPC authorization, app paths, redacted diagnostics skeleton. | Plex parsing/import logic, scheduler policy, renderer UI state, native playback implementation, packaging/release commitments. |
| Native helper | No production implementation in this slice; only a reserved boundary if the plan needs a named future owner. | Fake production playback, helper process lifecycle, libmpv integration, IPC commands used by renderer-facing code. |
| Contracts | Renderer-safe public shapes and privileged-field denial rules. | Concrete secrets, token-bearing URLs, OS handles, Electron objects, or helper process handles. |

## Slice Boundaries

The first slice includes the secure Electron app shell only. It may add Electron
dependencies and local dev scripts if needed to run and verify that shell.

Later slices should remain separate unless the reviewed plan explicitly finds a
small dependency that must move earlier:

- Plex auth, discovery, secure storage, and server setup.
- Existing Lineup renderer UI import and navigation adaptation.
- Scheduler, EPG, lineup generation, and playback queue behavior.
- Native playback/helper spike and production player decision.
- Windows installer, signing, auto-update, binary provenance, and release gates.

This boundary is deliberately narrow to prevent the new repo from accumulating
tech debt while it is still proving its platform shape.

## Required Read Order

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/README.md`
4. `docs/agentic/session-prompts/feature-quality-loop.md`
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/agentic/skill-strategy.md`
7. `docs/agentic/codanna-playbook.md`
8. `docs/architecture/CURRENT_STATE.md`
9. `docs/architecture/desktop-repo-genesis-adr.md`
10. `docs/architecture/security-and-secret-flow.md`
11. `docs/architecture/playback-architecture.md`
12. `docs/architecture/packaging-release-gates.md`
13. `docs/architecture/import-ledger.md`
14. `docs/development/testing.md`
15. current `git status --short --branch`

Treat playback and packaging docs as boundary and non-goal context for this
first slice, not as authorization to implement player or release surfaces.
Treat `docs/agentic/skill-strategy.md` as the skill-transfer authority for the
fresh session: Desktop uses `.agents/skills/` launcher wrappers and tracked docs
rather than relying on the original Lineup repo's local skill context.

## Decisions Already Accepted

- Lineup Desktop is a separate Windows-first Electron repository.
- Renderer code must remain unprivileged.
- Preload must expose narrow typed APIs, not raw Electron primitives.
- Electron main and/or a privileged helper own persistent credentials,
  token-bearing setup, app paths, diagnostics, window lifecycle, and native
  process coordination.
- Helper-hosted libmpv is a production hypothesis, not yet proven.
- External mpv IPC may be a private disposable learning spike only.
- Public Windows distribution is blocked until signing, licensing, binary
  provenance, and diagnostics gates are recorded.
- Copied/adapted upstream Lineup slices require an import ledger entry before
  or with the import.

## Foundation Plan Must Freeze

- exact first implementation unit
- files in scope and out of scope
- Electron process ownership boundaries
- preload API shape and validation policy
- minimum renderer/main/preload directory structure
- secret-storage placeholder policy for private development
- diagnostics and redaction obligations
- architecture-lint expectations for new directories
- verification commands and expected outcomes
- replan triggers

The plan should freeze boundaries and contracts, not local helper names, full
function bodies, or broad future implementation recipes.

## Implementation-Ready Plan Requirements

Before implementation starts, the active plan should answer:

- Which Electron/build-tool dependencies are introduced in the first unit, with
  the reason they are needed now.
- Which `BrowserWindow` security defaults are required and how they are enforced.
- Which preload API methods/events exist in the first unit and what payload
  validation protects them. Keep these limited to shell, smoke, and capability
  APIs unless the plan proves a boot-level need for anything broader.
- Which renderer imports/globals are forbidden by static checks.
- Which dev, build/typecheck, docs, and smoke commands prove the slice.
- Which tests are new versus existing-verifier coverage.
- Which docs must change with the slice and which repo-hosting or release
  surfaces are intentionally out of scope.

Keep the verification proportional: contract/lint/redaction checks should block
security boundary regressions, but the plan should not demand broad UI,
installer, or end-to-end Plex tests for a shell-only slice.

## Recommended First Implementation Unit

The first implementation unit after plan review should be the secure Electron
shell frame:

- package scripts and dependencies required to run Electron locally
- `src/main/` entrypoint with BrowserWindow security defaults
- `src/preload/` typed bridge skeleton
- `src/renderer/` minimal renderer entrypoint
- IPC contract tests that prove renderer-facing payloads do not contain
  forbidden privileged fields
- redaction and architecture verification updated for any new surfaces
- a documented smoke proof that the Electron shell boots and the renderer can
  call only the approved preload API

Do not import Plex, scheduler, EPG UI, native playback, secure storage, or
packaging implementation in this first unit unless the reviewed plan explicitly
changes that scope.

## Verification Baseline

The plan should start from these commands:

```sh
npm run verify
```

It should add narrower commands only when useful. For Electron runtime behavior,
the plan must define a manual or automated smoke proof before implementation
claims are accepted.

## Stop And Replan Triggers

Stop and replan if the proposed implementation requires:

- renderer access to persistent Plex credentials
- renderer access to Node, Electron, filesystem, OS, or process primitives
- raw Electron APIs exposed through preload
- `nodeIntegration: true`, disabled `contextIsolation`, disabled sandboxing,
  disabled web security, remote renderer content, or other privileged renderer
  concessions
- token-bearing URLs, auth headers, native handles, or secret-bearing logs in
  renderer-facing contracts
- compatibility shims just to preserve old webOS paths
- preload methods shaped around playback, Plex, scheduler, or packaging behavior
  before the reviewed plan proves those are required for shell boot
- a production playback decision before the native playback spike proves the
  required behavior
- public release, auto-update, or installer commitments before the release gates
  are ready
- broad upstream Lineup imports without import-ledger entries

## Fresh Session Prompt

Use this prompt in the new Codex chat:

```text
We are in /Users/tristan/Software/LineupDesktop. Use the repo-scoped `lineup-desktop-feature-quality-loop` / `docs/agentic/session-prompts/feature-quality-loop.md` workflow to create a Tier 3 tracked plan for the Electron shell and security foundation slice. Use AGENTS.md, docs/AGENTIC_DEV_WORKFLOW.md, docs/agentic/session-prompts/feature-quality-loop.md, docs/agentic/plan-authoring-standard.md, docs/agentic/skill-strategy.md, docs/agentic/codanna-playbook.md, and the architecture docs.

Do not implement product code in this planning session. "Foundation slice" means the first runnable, production-quality Electron process skeleton: secure main-process window/lifecycle ownership, narrow typed preload bridge, minimal renderer boot surface, renderer-safe shared contracts, architecture lint boundaries, contract/redaction checks, and a smoke proof that the shell boots without giving the renderer Node/Electron/secret access.

Freeze the first implementation unit, files in/out of scope, Electron process boundaries, preload/IPC security contract, renderer privilege limits, verification commands, acceptance criteria, and stop/replan triggers. Keep the scope narrow: do not include Plex import, existing TV UI import, scheduler, native playback, secure storage implementation, installer/signing, or release automation unless the plan identifies a truly blocking dependency and explains why it must move earlier. Use Codanna where useful and record fallback reads. Request read-only adversarial review of the plan before implementation starts.
```
