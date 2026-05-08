# Electron Shell Security Foundation Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Controller phase:** plan-review pending
**Verification classification:** new regression/contract test required

## Goal

Create the first runnable, production-quality Electron process skeleton for
Lineup Desktop while preserving the repo's security model: Electron main owns
window lifecycle and privileged IPC, preload owns a narrow typed bridge,
renderer code remains unprivileged, and shared contracts expose only
renderer-safe data.

The first implementation unit is the secure Electron shell frame. It must boot a
minimal renderer through Electron, prove the renderer can call only approved
preload APIs, and prove the renderer cannot access Node, Electron, filesystem,
process, credential, token, or native-handle surfaces.

## Non-Goals

- No Plex auth, discovery, library, server setup, stream resolution, or imported
  Plex UI state.
- No existing TV UI import, route/navigation import, webOS compatibility layer,
  scheduler, EPG, lineup generation, or playback queue behavior.
- No native playback helper, external media POC, libmpv binding, media surface,
  track mapping, or production playback decision.
- No secure storage implementation. The first unit may name the future main
  owner for credentials, but it must not store real secrets.
- No installer, signing, auto-update, release automation, or binary provenance
  implementation.
- No compatibility barrels, old upstream path shims, broad RPC bridge, or
  renderer fallback access to privileged APIs.
- No copied or adapted upstream Lineup product slice. If that changes, stop and
  add an import-ledger row before or with the import.

## Parent Architecture Alignment

Lineup Desktop is currently a Windows-first Electron repo with docs, workflow,
contract, and harness scaffolding only. This plan advances the scaffold into the
first Electron runtime slice without changing the accepted product boundaries.

Process ownership is frozen for the first implementation unit:

| Surface | Owns in this unit | Must not own in this unit |
| --- | --- | --- |
| Main | App lifecycle, single-window creation, secure `BrowserWindow` defaults, fixed preload path resolution, privileged shell/window IPC handlers, app-ready smoke exit behavior, redacted startup diagnostics. | Plex policy, scheduler policy, renderer UI state, native playback, secure credential storage, packaging or release policy. |
| Preload | `contextBridge` bridge, runtime validation for renderer-facing shell/window calls, event subscription cleanup, conversion between renderer API calls and approved IPC channels. | Raw `ipcRenderer` exposure, broad RPC passthrough, policy decisions, secret material, native helper commands, Plex/playback/scheduler APIs. |
| Renderer | Minimal DOM boot proof, shell status display, renderer-safe capability display, calls to the approved preload API only. | Node/Electron imports, filesystem/process access, persistent secrets, token-bearing values, raw auth headers, native handles, Plex transport policy, playback policy. |
| Native helper | No production files or runtime behavior. The boundary remains reserved by architecture lint only. | Helper lifecycle, libmpv integration, media IPC, token-bearing playback setup. |
| Contracts | Renderer-safe shell, IPC, and redaction shapes; forbidden privileged-field assertions. | Concrete secrets, Electron objects, OS handles, helper handles, token-bearing URLs, raw auth headers, engine ids. |

Dependency and build-tool choices are frozen for the first unit:

- Add `electron` as a development dependency because the unit must run a real
  Electron shell and verify Chromium renderer privileges.
- The Electron dependency change must record the exact installed version,
  `package-lock.json` impact, npm audit result, license/provenance notes for the
  npm package, and any security advisory or platform-runtime caveat found during
  implementation closeout.
- Keep TypeScript, ESLint, Node test runner, and npm scripts as the build and
  verification baseline.
- Add only the minimum Electron build wiring needed to emit main, preload, and
  renderer boot artifacts. Prefer a dedicated TypeScript build config plus a
  small asset-copy script over introducing Vite, React, Electron Forge,
  Electron Builder, or packaging tools in this unit.
- Serve the built renderer through the Electron-owned local app origin
  `lineup://shell` at the initial URL `lineup://shell/index.html`. The `lineup`
  scheme must be registered before app ready as a privileged standard, secure
  scheme, and the handler may serve only files from the built renderer output
  root. Path traversal, remote hosts, additional hosts, query strings used as
  file selectors, and fallback to `file://` are forbidden. If the worker cannot
  support this local protocol in the first unit, stop and replan before using any
  broader load policy.
- Do not introduce UI framework, router, state library, native media package,
  secure-storage package, installer package, or release tooling.

## Required Reading

- [AGENTS.md](../../AGENTS.md)
- [docs/AGENTIC_DEV_WORKFLOW.md](../AGENTIC_DEV_WORKFLOW.md)
- [docs/agentic/session-prompts/feature-quality-loop.md](../agentic/session-prompts/feature-quality-loop.md)
- [docs/agentic/session-prompts/feature-plan.md](../agentic/session-prompts/feature-plan.md)
- [docs/agentic/session-prompts/feature-review.md](../agentic/session-prompts/feature-review.md)
- [docs/agentic/plan-authoring-standard.md](../agentic/plan-authoring-standard.md)
- [docs/agentic/skill-strategy.md](../agentic/skill-strategy.md)
- [docs/agentic/codanna-playbook.md](../agentic/codanna-playbook.md)
- [docs/architecture/CURRENT_STATE.md](../architecture/CURRENT_STATE.md)
- [docs/architecture/desktop-repo-genesis-adr.md](../architecture/desktop-repo-genesis-adr.md)
- [docs/architecture/security-and-secret-flow.md](../architecture/security-and-secret-flow.md)
- [docs/architecture/playback-architecture.md](../architecture/playback-architecture.md)
- [docs/architecture/packaging-release-gates.md](../architecture/packaging-release-gates.md)
- [docs/architecture/import-ledger.md](../architecture/import-ledger.md)
- [docs/development/testing.md](../development/testing.md)
- [docs/plans/2026-05-07-electron-shell-security-foundation-handoff.md](./2026-05-07-electron-shell-security-foundation-handoff.md)
- [Electron Security](https://www.electronjs.org/docs/latest/tutorial/security)

Freshness gate: before implementation starts, rerun `git status --short
--branch` and re-read the files named in Required Reading plus
`src/contracts/ipc.ts`, `package.json`, `tsconfig.json`, `eslint.config.js`,
`tools/architecture-rules/*`, and `tools/verify-redaction.mjs`. If any
referenced file, owner boundary, dependency behavior, Electron security guidance,
or verifier expectation changed materially since this plan was last reviewed,
stop and update or re-review this plan before editing product code.

## Required Skills

- `lineup-desktop-feature-quality-loop`: Tier 3 controller state, plan/review
  gates, implementation gate, and closeout gate.
- `lineup-desktop-feature-plan`: feature/design planning route and handoff
  expectations.
- `execution-plan-authoring`: decision-complete plan shape without pseudo-code
  bloat.
- `verification-strategy`: risk-matched contract, architecture, redaction,
  smoke, and docs verification depth.
- `architecture-boundaries`: Electron main/preload/renderer/helper ownership
  and shared contract boundaries.
- `persistence-boundaries`: credential, app path, filesystem, and renderer-safe
  state limits, even though secure storage implementation is out of scope.
- `plex-integration-boundaries`: Plex token and transport boundaries, even
  though Plex implementation is out of scope.
- `review-request`: bounded read-only plan and implementation review packets.
- `review-adjudication`: controller-owned handling of reviewer findings.
- `closeout-verification`: evidence-backed diff audit, verification, staging,
  commit, and handoff truth.

## Evidence And Discovery

- Required docs were read in the user-requested order: `AGENTS.md`, workflow
  runbook, feature-quality-loop launcher, plan standard, skill strategy,
  Codanna playbook, current architecture state, and the Electron shell handoff.
- Desktop skills loaded or reapplied for this plan:
  `lineup-desktop-feature-quality-loop`, `lineup-desktop-feature-plan`,
  `execution-plan-authoring`, `verification-strategy`,
  `architecture-boundaries`, `persistence-boundaries`,
  `plex-integration-boundaries`, `review-request`, `review-adjudication`, and
  `closeout-verification`.
- `git status --short --branch` showed the repo on `main` with no pre-existing
  worktree changes before this plan file was added.
- Codanna index was present with 274 symbols across 24 files, but semantic
  search failed because no embeddings were available. Fallback was recorded and
  discovery used Codanna symbol search plus direct reads.
- Codanna symbol search found `RendererIntentEnvelope` in
  `src/contracts/ipc.ts`, `RedactionSurface` in
  `src/contracts/redaction.ts`, and `PlayerSnapshot` in
  `src/contracts/player.ts`.
- Direct reads inspected `package.json`, `tsconfig.json`, `eslint.config.js`,
  `src/contracts/*`, `src/__tests__/contracts.test.ts`,
  `tools/architecture-rules/*`, `tools/verify-redaction.mjs`,
  `tools/verify-docs.mjs`, `docs/architecture/security-and-secret-flow.md`,
  `docs/architecture/playback-architecture.md`,
  `docs/architecture/packaging-release-gates.md`,
  `docs/architecture/import-ledger.md`, and `docs/development/testing.md`.
- Current architecture rules already target `src/renderer`, `src/preload`,
  `src/main`, and `src/native-helper`, and already block renderer imports of
  Electron, Node builtins, main, preload, and native-helper implementation.
- Current redaction verification scans docs, source, tests, and tool files for
  token-bearing Plex URLs, raw auth-header examples, and credential-like secret
  patterns.
- Official Electron security guidance was checked on 2026-05-08. The plan folds
  in its relevant first-shell recommendations: local or secure content only,
  context isolation, process sandboxing, web security, restrictive CSP,
  navigation limits, new-window denial, IPC sender validation, custom local
  protocol preference, and no raw Electron APIs exposed to renderer code.

## Impact Snapshot

- Owners that may change: `src/main`, `src/preload`, `src/renderer`,
  `src/contracts`, architecture lint rules, redaction verification, testing
  docs, and current architecture docs.
- Public contracts that may change: renderer-safe shell/preload API types,
  shell/window IPC vocabulary, redaction forbidden-field assertions, and smoke
  command expectations.
- Commands/tests that must change: package scripts, Electron build/smoke
  commands, contract tests, architecture-rule tests, and redaction checks if new
  secret-bearing patterns are introduced.
- Behavior that must not enter this unit: Plex auth/discovery/stream behavior,
  scheduler behavior, imported TV UI, native playback, secure storage,
  packaging, release automation, or broad app feature behavior.
- Local-only artifacts that must remain untracked: `.codanna/`,
  `.fastembed_cache`, `.agent/`, `.codex/cache/`, build output, coverage output,
  and raw `docs/runs/*` bundles.
- Cross-boundary status: this is intentionally cross-process but single
  execution-unit work. Splitting main/preload/renderer/contracts would make the
  first security proof weaker because the smoke proof must exercise the complete
  boundary.

## Files In Scope

First implementation unit scope:

- `package.json` and `package-lock.json`: add Electron dependency and scripts
  for Electron build/dev/smoke only.
- `tsconfig.json` plus a narrowly named Electron build config if needed.
- `eslint.config.js` only if new Electron source extensions or generated output
  require lint routing changes.
- `src/main/**`: Electron main entrypoint, secure window factory, lifecycle
  owner, shell/window IPC handlers, smoke-mode orchestration.
- `src/preload/**`: typed preload bridge and runtime validation for the approved
  renderer API.
- `src/renderer/**`: minimal renderer boot page and TypeScript entrypoint.
- `src/contracts/ipc.ts`, `src/contracts/redaction.ts`, and a new
  `src/contracts/shell.ts` if needed for renderer-safe shell capability and
  bridge types.
- `src/__tests__/*.test.ts`: contract tests for renderer-safe payloads,
  approved preload API surface, forbidden privileged fields, and shell IPC
  vocabulary.
- `tools/architecture-rules/desktopArchitectureRules.mjs` and related harness
  tests only for boundary rules required by the new source directories.
- `tools/verify-redaction.mjs` and related tests only if the first unit creates
  a new secret-bearing pattern that must be blocked.
- A narrowly named Electron smoke script under `tools/` if needed to launch the
  built shell and assert renderer privilege limits.
- `docs/architecture/CURRENT_STATE.md`, `docs/architecture/security-and-secret-flow.md`,
  and `docs/development/testing.md` only for factual updates after the shell
  exists and verification is observed.
- `docs/architecture/import-ledger.md` only if a copied or adapted upstream
  Lineup slice enters scope after a reviewed replan.

## Files Out Of Scope

- `src/native-helper/**` production files.
- Plex/auth/discovery/library/server modules, fixtures, and tests.
- Scheduler, channel, lineup, EPG, playback queue, or imported TV UI modules.
- Existing upstream Lineup renderer routes, components, CSS, assets, or
  compatibility wrappers.
- Secure credential persistence implementation or keychain/keytar wrappers.
- Installer, signing, auto-update, release, CI packaging, or binary-provenance
  config.
- `.codanna/`, `.fastembed_cache`, `.agent/`, `.codex/cache/`, `docs/runs/*`
  local run artifacts.
- Repo-hosting conveniences such as PR templates, review bot config, or GitHub
  workflow changes unless a separate reviewed plan authorizes them.

## Planner Self-Check

- Product scope is resolved: shell frame only.
- Ownership is resolved: main lifecycle/privileged IPC, preload bridge, renderer
  minimal UI, contracts renderer-safe shapes, helper reserved only.
- Freshness is explicit: material changes to referenced docs, source contracts,
  dependencies, Electron security guidance, or verifiers require plan update or
  re-review before implementation.
- Adjacent files are named in or out of scope; no hidden Plex/playback/storage
  wiring is required.
- The first unit uses existing repo owners and avoids growing native-helper,
  renderer, or packaging hotspots.
- A fresh implementer should not need to invent Electron security defaults,
  preload shape, renderer privilege rules, dependency choices, verification, or
  stop conditions.
- Verification classification and commands are named.
- Stop/replan triggers are explicit.

## Architecture Seam Decision Gate

The approved first execution unit is `secure-electron-shell-frame`.

Parallel implementation units are not allowed for the first unit. Main, preload,
renderer, contracts, architecture lint, and smoke verification are tightly
coupled enough that one worker should own the slice end to end after plan review.

Preload API shape is frozen to shell/window proof only:

- `window.lineupDesktop.shell.getCapabilities()` returns
  `Promise<ShellIpcResult<ShellCapabilities>>`.
- `window.lineupDesktop.shell.onStatusChanged(listener)` subscribes only to a
  renderer-safe `ShellStatusEvent` and returns an unsubscribe function.
- `window.lineupDesktop.window.setFullscreen(enabled)` requests fullscreen
  changes through main-owned IPC and returns
  `Promise<ShellIpcResult<WindowFullscreenState>>` without exposing
  `BrowserWindow`.

The shell contract shapes are frozen for the first unit:

- `ShellCapabilities`: `{ appName: 'Lineup Desktop'; appVersion: string;
  platform: 'darwin' | 'linux' | 'win32' | 'unknown'; shellMode: 'development' |
  'smoke' | 'production'; protocolOrigin: 'lineup://shell' }`.
- `ShellStatusEvent`: `{ status: 'booting' | 'ready' | 'closing'; timestampMs:
  number }`.
- `WindowFullscreenState`: `{ enabled: boolean }`.
- `ShellIpcResult<T>`: `{ ok: true; value: T; requestId: string } | { ok:
  false; error: { code: 'unauthorized' | 'validation-failed' |
  'operation-failed'; message: string }; requestId: string }`.

The first unit must use these exact IPC channel and event literals:

- Request channel `lineup:shell:getCapabilities` with no payload.
- Request channel `lineup:window:intent` with a `RendererIntentEnvelope` whose
  intent is exactly `window.enterFullscreen` or `window.exitFullscreen` and whose
  payload is `{}`.
- Main-to-preload event channel `lineup:shell:statusChanged` carrying a
  `ShellStatusEvent`.

`window.lineupDesktop.window.setFullscreen(true)` maps to the existing
`window.enterFullscreen` intent. `setFullscreen(false)` maps to the existing
`window.exitFullscreen` intent. Do not add a third `window.setFullscreen`
intent. If these existing window intents cannot support the bridge without
semantic ambiguity, stop and replan `src/contracts/ipc.ts` before wiring main or
preload.

The existing `player.*` values in `src/contracts/ipc.ts` remain future contract
stubs only. They must not be wired to preload, main IPC handlers, renderer calls,
or smoke behavior in the first unit. If shell IPC cannot stay separate from
future player IPC, stop and replan the contract shape before implementation.

IPC security contract:

- Preload must use a fixed allowlist of channels and methods. It must not expose
  `ipcRenderer`, `send`, `invoke`, `on`, `removeListener`, or a method that takes
  an arbitrary channel string from renderer code.
- Renderer-originating payloads must be validated in preload before IPC and in
  main before action. Unknown methods, unknown event names, and unexpected
  payload keys fail closed.
- Main IPC handlers must authorize the caller before acting. Authorization is
  limited to the one expected shell `webContents`, expected main frame, and
  exact local app origin `lineup://shell`; calls from any other
  `event.sender`, frame, origin, or destroyed/replaced window fail closed with a
  redacted error.
- The smoke proof and contract tests must cover unauthorized IPC sender/origin
  rejection for the shell/window channels, not only successful renderer calls.
- Main handlers must return discriminated success/failure results or throw
  redacted errors that do not reveal paths, headers, tokens, native handles, or
  Electron internals to the renderer.
- Renderer-facing contracts must reject or omit the existing forbidden payload
  keys in `RENDERER_FORBIDDEN_PAYLOAD_KEYS`.
- No player, Plex, scheduler, storage, helper, diagnostics-export, or packaging
  channel may be exposed in the first unit.

Renderer privilege limits:

- `BrowserWindow` must use local content only, `nodeIntegration: false`,
  `contextIsolation: true`, `sandbox: true`, web security enabled,
  `allowRunningInsecureContent: false`, no experimental Blink or Chromium
  features, a fixed preload script path, and no remote module.
- Main must register containment handlers before renderer interaction:
  deny unexpected navigation, deny all new-window creation, deny unneeded
  permission requests, prevent insecure webview attachment, and avoid
  `shell.openExternal` entirely in the first unit.
- The renderer must include or receive a restrictive CSP for the minimal shell:
  default deny, scripts and styles from self only, no object/embed/base URI, and
  no remote connect sources unless a reviewed future plan names one.
- Main must verify the loaded renderer URL is `lineup://shell/index.html` and
  origin is `lineup://shell` before exposing shell IPC as usable, and must treat
  any navigation away from that approved local shell origin as a stop condition
  for IPC.
- The renderer must not import Electron, Node builtins, main implementation,
  preload implementation, native-helper implementation, filesystem, process, or
  OS modules.
- The smoke proof must assert renderer globals such as `process`, `require`,
  `Buffer`, and raw Electron bridge names are unavailable, while the single
  approved `window.lineupDesktop` API exists.
- Development-only conveniences must not weaken production window defaults. Any
  dev-only branch must be explicit, narrow, and covered by architecture or smoke
  verification.

Guardrails that apply:

- Hotspot growth: main owns shell lifecycle only; preload remains bridge-only;
  renderer remains minimal UI-only.
- Boundary leakage: renderer receives no secrets, raw Electron APIs, Node
  globals, token-bearing values, native handles, or privileged imports.
- Contract drift: one public renderer API shape, one IPC vocabulary owner, and
  aligned type/runtime validation.
- Test debt: contract tests, architecture lint, redaction scan, and Electron
  smoke proof cover public seams rather than private helper internals.
- Source signal: no broad helper names, compatibility shims, copied UI imports,
  or unrelated cleanup in the first unit.
- Release debt: packaging and public release gates stay out of scope.

## Verification Commands

The implementation unit must run these commands fresh and record observed
results:

```sh
npm run typecheck
npm run verify:architecture
npm run test:contracts
npm run verify:redaction
npm run smoke:electron
npm audit --audit-level=moderate
npm run verify:docs
npm run verify
```

Expected outcomes:

- `npm run typecheck` passes with strict TypeScript across contracts, main,
  preload, renderer, tests, and tools.
- `npm run verify:architecture` passes and blocks renderer imports of Electron,
  Node, main, preload, and native-helper implementation.
- `npm run test:contracts` passes new and existing contract tests for the
  renderer API shape, IPC vocabulary, forbidden privileged fields, and redaction
  boundary constants, including unauthorized IPC sender/origin rejection.
- `npm run verify:redaction` passes with no token, auth-header, tokenized URL,
  native-handle, or secret-bearing fixture leaks.
- `npm run smoke:electron` launches the built Electron shell, observes the
  minimal renderer boot, proves the approved preload API works, proves forbidden
  renderer globals/APIs are absent, proves navigation/new-window/permission/CSP
  containment is active, and exits cleanly.
- `npm audit --audit-level=moderate` reports no moderate-or-higher
  vulnerabilities after adding Electron and any supporting build dependency.
- `npm run verify:docs` passes after this active plan and any architecture or
  testing doc updates.
- `npm run verify` passes as the final scaffold/source closeout command. If
  `smoke:electron` cannot be folded into `verify` because the local environment
  lacks a graphical shell, the worker must still run `smoke:electron` separately
  or stop and document the environment blocker before closeout.

This depth fits the risk because the first unit creates the app's process and
IPC foundation. New contract tests and a real Electron smoke proof are required;
private unit tests for helper functions are optional unless a public seam cannot
otherwise be verified.

## Acceptance Criteria

- Plan review is clean before any product code implementation starts.
- The first implementation unit is limited to `secure-electron-shell-frame` and
  does not include Plex, scheduler, playback, native helper, secure storage,
  packaging, release, or imported TV UI behavior.
- Electron main creates one secure local window with the required
  `BrowserWindow` defaults and owns all shell/window IPC handlers.
- Preload exposes only the frozen `window.lineupDesktop` shell/window API, with
  no raw IPC or arbitrary channel access.
- Renderer boots a minimal shell surface, uses only the approved preload API,
  and has no Node/Electron/process/filesystem/native/secret access.
- Shared contracts are renderer-safe and tested for forbidden privileged fields.
- Architecture lint covers the new source directories and blocks privileged
  renderer imports and globals.
- Main IPC authorization rejects unexpected senders, frames, origins, and
  replaced/destroyed windows for shell/window channels.
- BrowserWindow containment denies unexpected navigation, new windows, unneeded
  permission requests, insecure webview attachment, remote renderer content, and
  missing/replaced CSP.
- Redaction verification covers the new files and passes.
- Electron smoke verification proves boot, bridge availability, and renderer
  privilege denial.
- Architecture/testing docs are updated only with observed facts after
  implementation; import ledger remains unchanged unless copied/adapted upstream
  code enters scope through a reviewed replan.
- A fresh read-only implementation review is clean before the Tier 3 controller
  advances past the implementation gate.

## Replan Triggers

Stop and return to planning if implementation requires any of the following:

- Renderer access to persistent Plex credentials, token-bearing values, raw auth
  headers, Node, Electron, filesystem, OS, process, native handles, or helper
  process state.
- `nodeIntegration: true`, disabled `contextIsolation`, disabled sandboxing,
  disabled web security, remote renderer content, dynamic preload path supplied
  by renderer state, or any other privileged renderer concession.
- Preload exposure of raw `ipcRenderer`, arbitrary IPC channel names, broad RPC,
  event wildcard subscriptions, or passthrough methods.
- Main importing renderer implementation or renderer importing main/preload
  implementation.
- Shell IPC that cannot reliably authenticate the expected `webContents`, frame,
  exact `lineup://shell` origin, and `lineup://shell/index.html` initial URL
  before acting.
- Any need to allow navigation, new windows, permission prompts, webviews,
  external URL opening, remote content, missing CSP, or broad file loading in the
  first shell unit.
- Any need to load renderer content outside the registered `lineup://shell`
  origin, serve resources outside the built renderer output root, use additional
  custom protocol hosts, or fall back to `file://` without a reviewed replan.
- Any need to invent new shell IPC channels, event names, result shapes, or
  fullscreen intents beyond the exact literals and shapes named in this plan.
- Shell boot depending on Plex, scheduler, playback, secure storage, native
  helper, installer, signing, release automation, or upstream UI imports.
- Renderer TypeScript that depends on ambient Node globals/types. Prefer a
  renderer-specific TypeScript config with DOM types only; if that is not
  practical, the worker must add equivalent lint and smoke proof before closeout.
- A need for Vite, React, Electron Forge, Electron Builder, or another large
  build/runtime tool before the worker proves the existing TypeScript/npm path
  cannot support the shell frame.
- A production playback or helper decision before the Windows playback spike
  proof is complete.
- Any copied/adapted upstream Lineup product code without a same-change import
  ledger entry.
- Verification commands cannot be made deterministic enough to prove renderer
  privilege denial.

## Rollback Notes

The first implementation unit should remain easy to revert because it is a new
shell frame with narrow package and config changes. Roll back by removing the
Electron dependency/scripts, Electron build config, `src/main`, `src/preload`,
`src/renderer`, new shell contract additions, new smoke tooling, and any
architecture/testing doc updates that described the reverted runtime.

Do not roll back pre-existing scaffold contracts, workflow docs, redaction
verifier, or architecture lint rules unless the reviewed implementation changed
them and the rollback specifically targets that change.

## Commit Checkpoints

The approved implementation unit should produce one focused conventional commit
after plan review, implementation review, full verification, and diff audit are
clean. Suggested commit shape:

```text
feat(shell): add secure Electron foundation frame
```

Do not include future Plex, playback, packaging, or broad workflow changes in
that implementation commit. If implementation discovers that workflow or
architecture docs need material policy changes beyond factual updates, stop and
split those into a separate reviewed control-plane pass.

MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: gpt-5.5 high
REVIEWER: gpt-5.5 high
WHY: Tier 3 Electron IPC/security foundation work touches main, preload,
renderer, contracts, architecture lint, redaction, and runtime smoke proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: `lineup-desktop-feature-review`
TASK: Review the revised active Tier 3 Electron shell security foundation plan.
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`
ARTIFACT: Active tracked plan for the first Electron shell and security
foundation implementation unit.
FILES:
- `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`
- `docs/AGENTIC_DEV_WORKFLOW.md`
- `docs/agentic/plan-authoring-standard.md`
- `docs/architecture/security-and-secret-flow.md`
- `docs/architecture/playback-architecture.md`
- `docs/development/testing.md`
- `src/contracts/*`
- `tools/architecture-rules/*`
- `tools/verify-redaction.mjs`
BLOCKERS: implementation remains blocked until read-only plan review confirms
the freshness gate, IPC/preload vocabulary, and local protocol/origin policy are
decision-complete.
MESSAGE: Use `lineup-desktop-feature-review` for read-only adversarial review.
Prioritize renderer privilege leaks, preload/raw IPC exposure, Electron
`BrowserWindow` security gaps, scope creep beyond the shell frame, missing
verification, import-ledger omissions, and whether a fresh implementer would
need to invent any IPC/security/build policy before implementation.
