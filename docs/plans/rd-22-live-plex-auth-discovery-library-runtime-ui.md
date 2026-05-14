# RD-22 Live Plex Auth, Discovery, And Library Runtime UI

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Treat RD-22 as source-implemented but not proofable or complete. The live Plex
contracts, preload bridge, main runtime/composition, and initial renderer panel
exist, but the Windows live proof was blocked on 2026-05-14 because the setup
surface behaves like a transport debug panel inside placeholder channel setup,
not a usable Lineup-style setup flow.

This plan authorizes one bounded remediation execution unit: replace the
placeholder live Plex setup panel with a real setup flow that can be driven on
Windows with keyboard/remote-like input, correct Plex claim guidance, reliable
scrolling, explicit cancel/back/clear behavior, and redaction-safe proof
criteria. RD-22 remains open until this remediation is implemented, reviewed,
verified, and live Windows proof passes.

## Non-Goals

- Do not mark RD-22 complete, archive this plan, or promote closeout claims to
  roadmap, current-state, parity, or proof-plan docs during this planning pass.
- Do not add RD-23 scope: no channel creation, channel persistence, settings
  persistence, scheduler-backed guide, EPG runtime, or channel authoring from
  real library data.
- Do not change main-owned Plex transport, credentials, selected connection
  custody, selected-server storage, contracts, preload API, IPC channels, package
  files, dependencies, lockfiles, native helper, playback, signing, update, or
  public release behavior unless a stop/replan trigger fires.
- Do not store raw Windows proof, screenshots, account names, server names,
  library names, media titles, URLs, tokens, headers, connection details, local
  paths, raw Plex payloads, raw IPC frames, logs, or support bundles in tracked
  docs.

## Parent Architecture Alignment

RD-22 has already added the intended ownership split: renderer sends typed
`lineupDesktop.plex` setup/library intents through preload; preload validates a
narrow Plex namespace and exact IPC channels; main owns live Plex transport,
credentials, selected connection memory, selected-server persistence, operation
abort/stale handling, and sanitized diagnostics.

The blocker is not an ownership gap in main/preload. The remediation seam is
renderer-owned setup composition over the existing Plex bridge. Renderer may
reshape local view state, DOM, focus order, selection state, setup copy, and CSS
for usability, but it must continue to receive only renderer-safe summaries and
must not gain transport, storage, token, app-path, Electron, Node, retry-policy,
or raw Plex response ownership.

## Required Reading

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/architecture/security-and-secret-flow.md`
7. `docs/architecture/file-shape-guardrails.md`
8. `docs/development/windows-ui-proof-plan.md`
9. `docs/product/lineup-product-parity-matrix.md`
10. `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
11. `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/windows-live-proof-blocked.redacted.md`
12. Source files named in `## Files In Scope` and `## Files Out Of Scope`

Freshness gate: if Plex contracts, preload bridge methods, main Plex runtime,
renderer route/focus owners, file-shape guardrails, or the blocker note changed
after this plan revision, stop and update or re-review the plan before editing.

## Required Skills

- `execution-plan-authoring`: this plan freezes the remediation scope, owner
  seam, verification, rollback, and stop conditions.
- `architecture-boundaries`: the remediation must preserve the established
  renderer/preload/main split and avoid broadening the bridge.
- `persistence-boundaries`: selected-server and credential custody stay in main;
  renderer state remains ephemeral.
- `plex-integration-boundaries`: token, connection, raw payload, and live
  transport policy remain privileged.
- `ui-composition-patterns`: the execution unit is a renderer setup-flow,
  focus, keyboard/back, scroll, and accessibility change.
- `verification-strategy`: RD-22 cannot close without broader integration/manual
  Windows proof in addition to automated tests.
- `review-request`: the revised active plan and the later implementation need
  read-only adversarial review.
- `closeout-verification`: required before closeout, staging, commit, or
  handoff.

## Evidence And Discovery

- `semantic_search_with_context`: attempted for RD-22 setup-flow and Plex
  runtime queries; Codanna returned `No embeddings available for search`, so it
  was not useful for this pass.
- `semantic_search_docs`: attempted for the RD-22 proof blocker; Codanna returned
  `No embeddings available for search`, so repo docs were read directly.
- Impact analysis: not run because Codanna semantic anchoring was unavailable and
  this planner pass edits only the tracked plan.
- Direct reads / `rg`: read the required workflow/architecture/product/proof
  docs, the active RD-22 plan, the blocked Windows proof note, `docs/roadmap`
  RD-22/RD-23 sequencing, `src/contracts/plex.ts`, `src/contracts/ipc.ts`,
  `src/contracts/shell.ts`, `src/preload/index.cts`, `src/main/index.ts`,
  `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/desktopPlexRuntimeSupport.ts`,
  `src/main/plex/plexIpc.ts`, `src/main/plex/plexComposition.ts`,
  `src/main/plex/livePlexTransport.ts`, `src/renderer/index.ts`,
  `src/renderer/domBindings.ts`, `src/renderer/staticDom.ts`,
  `src/renderer/plexRuntimeState.ts`, `src/renderer/plexRuntimeActions.ts`,
  `src/renderer/plexRuntimeDom.ts`, `src/renderer/workflow.ts`,
  `src/renderer/routeDom.ts`, `src/renderer/navigation.ts`,
  `src/renderer/desktopInput.ts`, `src/renderer/styles/workflow-screens.css`,
  `src/__tests__/renderer/plexRuntime.test.ts`,
  `src/__tests__/renderer/routeDom.test.ts`,
  `src/__tests__/renderer/workflow.test.ts`, and
  `src/__tests__/main/plexRuntimeIpc.test.ts`.
- Blocker evidence: the redacted note records `npm ci`, `npm run verify`, and
  `npm run build:electron` passing before manual proof, then Windows manual
  proof blocking because PIN claim guidance did not match expected Plex
  link/Auth App behavior, scrolling and nested selection escape/back behavior
  were insufficient, and the UI looked like a live transport debug panel rather
  than a normal Lineup setup flow.
- Current implementation evidence from source reads: main Plex runtime and IPC
  handlers exist; preload exposes the exact `lineupDesktop.plex` namespace;
  renderer mounts a single `.plex-runtime` panel in `staticDom.ts` with direct
  buttons for `Load`, `Sign in`, `Check PIN`, `Cancel PIN`, `Profiles`,
  `Restore server`, `Refresh servers`, `Libraries`, `Browse`, and `Search`.
  Current controller cleanup cancels pending PIN on route exit, but there is no
  real setup-step view model, nested setup navigation model, explicit back/clear
  behavior for selected server/library/item states, or Windows proofable scroll
  contract.
- Import ledger: no copied/adapted upstream source is authorized. If
  implementation proposes copying or adapting original Lineup UI source, stop,
  justify the import, and update `docs/architecture/import-ledger.md` before or
  with that import.

## Impact Snapshot

- Owners that may change: renderer Plex setup state/actions/DOM modules, static
  channel setup markup, renderer route wiring, focus/back handling, workflow
  copy for channel setup, CSS for the setup flow, and renderer tests.
- Public contracts that may change: none expected. `src/contracts/plex.ts`,
  `src/contracts/ipc.ts`, `src/contracts/shell.ts`, and `src/preload/index.cts`
  are out of scope for the bounded remediation unless review proves a contract
  ambiguity blocks usability.
- Dependency, build-tool, configuration, and lockfile changes: none authorized.
- Commands/tests/docs that must change: renderer Plex/setup tests must cover the
  real setup flow, focus order, back/clear/cancel behavior, scroll containment,
  sanitized failures, and no regression of existing fake player/guide surfaces.
- User-visible behavior that must not regress: shell/window/player/diagnostics
  APIs, existing fake-backed player/guide/settings route reachability,
  fullscreen bridge, support-bundle export, route navigation, and main/preload
  Plex runtime behavior.
- Cross-boundary status: the execution unit is renderer-owned over an existing
  bridge. Main/preload are read-only evidence surfaces unless a stop/replan
  trigger fires.

## Files In Scope

One bounded remediation execution unit: `RD-22R1 renderer Plex setup flow`.

- `src/renderer/plexRuntimeState.ts`: may replace debug-panel state with
  renderer-local setup-flow state for current step, selected server, selected
  library section, selected item/metadata, query, protected-home PIN input,
  pending operations, sanitized error copy, clear/back targets, and proofable
  status labels.
- `src/renderer/plexRuntimeActions.ts`: may add renderer-local actions that map
  setup steps to existing bridge calls, preserve cleanup/cancellation, clear
  selected server/library/item/search states explicitly, and avoid committing
  stale async results after navigation or newer requests.
- `src/renderer/plexRuntimeDom.ts`: may replace debug lists/buttons with
  Lineup-style setup sections using existing safe summaries, stable focus ids,
  clear/cancel/back affordances, selected-state rendering, empty/error/loading
  states, and redaction-safe display copy.
- `src/renderer/staticDom.ts`: may replace the `.plex-runtime` debug-panel
  markup inside the channel-setup route with the real setup-flow host and
  controls. Keep it renderer-only and avoid nesting unrelated settings/fake
  channel controls inside the live Plex setup flow.
- `src/renderer/domBindings.ts`: may update bindings and `readPlexRuntimeActionId`
  only for concrete setup-flow controls. Do not add generic action strings or
  bridge/channel passthroughs.
- `src/renderer/index.ts`: may update click/input handlers, desktop back
  behavior, route cleanup, and focus synchronization for the setup flow. Back
  should first unwind nested setup selection/detail/search states, then leave
  the route only when the setup flow is already at its top level.
- `src/renderer/workflow.ts` and `src/renderer/routeDom.ts`: may update channel
  setup copy/status and hosting so the live Plex setup reads as the setup
  workflow rather than a placeholder/fake draft plus debug panel. Do not add
  channel creation or persistence behavior.
- `src/renderer/styles.css` and `src/renderer/styles/*`, especially
  `src/renderer/styles/workflow-screens.css`: may add responsive layout, scroll
  containment, focus-visible, reduced-motion/forced-colors-compatible styling,
  and non-overlapping setup-flow controls.
- `src/__tests__/renderer/plexRuntime.test.ts`: must be updated or expanded for
  setup-flow state/actions/DOM, dynamic focus ids, clear/back/cancel behavior,
  safe copy, and stale/cleanup behavior.
- `src/__tests__/renderer/workflow.test.ts`,
  `src/__tests__/renderer/routeDom.test.ts`, and focused renderer tests may
  change only to protect route/workflow/focus regressions introduced by the
  setup flow.

Ignored local proof may be written under
`docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/` during the
implementation/proof session only, and must remain redaction-safe.

## Files Out Of Scope

- `docs/architecture/CURRENT_STATE.md`, `docs/roadmap/desktop-port-roadmap.md`,
  `docs/product/lineup-product-parity-matrix.md`, and
  `docs/development/windows-ui-proof-plan.md` for this planner pass and for the
  remediation implementation until Windows proof passes and reviewed closeout
  explicitly authorizes durable claims.
- `src/contracts/plex.ts`, `src/contracts/ipc.ts`, `src/contracts/shell.ts`,
  and `src/preload/index.cts` unless a reviewed replan finds the existing bridge
  contract cannot support the setup-flow remediation.
- `src/main/index.ts`, `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/desktopPlexRuntimeSupport.ts`, `src/main/plex/plexIpc.ts`,
  `src/main/plex/plexComposition.ts`, `src/main/plex/livePlexTransport.ts`, and
  all `src/main/plex/auth/**`, `src/main/plex/discovery/**`,
  `src/main/plex/library/**`, `src/main/persistence/**`, and
  `src/main/diagnostics/**` source files unless a blocker proves the current UI
  failure is caused by a main/runtime defect.
- `src/main/player/**`, `src/main/plex/streamResolver.ts`,
  `src/contracts/player.ts`, `src/domain/scheduler/**`,
  `src/domain/channel/**`, channel persistence/authoring owners, native helper,
  playback, package tooling, dependency manifests, lockfiles, signing/update,
  installer, and public release docs.
- Tracked raw run logs, screenshots, account/server/library/media names, local
  paths, URLs, connection details, raw Plex payloads, raw IPC frames, tokens,
  headers, credentials, or support-bundle contents.

## Architecture Health

File-shape evidence from direct reads and
`docs/architecture/file-shape-guardrails.md`:

- `src/preload/index.cts`: 2045 lines and already allowlisted for the RD-22
  same-file sandboxed preload exception. This remediation must avoid growing it.
- `src/main/player/desktopPlayerAdapter.ts`: 1279-line allowlisted hotspot,
  out of scope.
- `src/main/player/plexPlaybackRuntime.ts`: 798-line allowlisted hotspot, out
  of scope.
- `src/contracts/player.ts`: 703-line allowlisted hotspot, out of scope.
- `src/main/plex/streamResolver.ts`: 662-line allowlisted hotspot, out of scope.
- RD-22-adjacent renderer files currently measured in this pass:
  `src/renderer/staticDom.ts` 204, `src/renderer/plexRuntimeDom.ts` 329,
  `src/renderer/plexRuntimeActions.ts` 314,
  `src/renderer/plexRuntimeState.ts` 217,
  `src/renderer/styles/workflow-screens.css` 418,
  `src/renderer/index.ts` 336, and `src/renderer/domBindings.ts` 259.

Decision: decompose and avoid hotspots. Keep the remediation in the existing
focused renderer Plex/setup owners instead of adding behavior to preload,
main composition, player/runtime, scheduler/channel, stream resolver, or
contracts. If any production file crosses 500 lines or an allowlisted file
would grow, stop for an Architecture Health review decision rather than raising
baselines casually. Do not raise file-shape guardrails to pre-authorize future
growth.

Maintainability route: implementation closeout must include
`npm run verify:maintainability` directly or through `npm run verify`.

## Planner Self-Check

1. Product/architecture/ownership decisions are resolved for this remediation:
   renderer owns setup composition; main/preload/contracts remain stable unless
   a replan trigger fires.
2. Adjacent contract changes are not required for the planned unit; the existing
   `lineupDesktop.plex` methods already support sign-in, profiles, server
   restore/refresh/select, library sections/items/search, metadata, and cancel.
3. Files frozen out of scope are not hidden implementation dependencies for UI
   replacement; they are evidence surfaces and existing runtime owners.
4. Codanna fallback and direct-read evidence are recorded.
5. Work stays with repo-preferred owners and avoids current hotspots.
6. Tier 3 Architecture Health evidence and avoidance decisions are recorded.
7. A fresh implementer should not need to invent security, IPC, persistence,
   Plex transport, renderer privilege, packaging, import, or verification
   policy.
8. Verification commands, expected outcomes, Windows proof requirements,
   acceptance criteria, rollback notes, and stop/replan triggers are explicit.

## Architecture Seam Decision Gate

Chosen seam: renderer-only setup-flow remediation over the existing
`LineupDesktopPreloadApi.plex` bridge.

Required UI behavior:

- The channel-setup route must present a real setup flow with clear phases for
  Plex sign-in, Plex Home/profile selection when available, server
  restore/refresh/select, library section browse/search, and metadata preview.
- PIN claim guidance must match the live Plex behavior observed by the current
  implementation: show the PIN code and provide user-facing guidance to claim it
  with Plex's link/Auth App flow without embedding raw URLs or tokens in
  tracked proof. The UI may contain a generic product-safe instruction such as
  using Plex's sign-in/link flow; it must not expose token-bearing material or
  assume a renderer network permission.
- Back/Escape/remote-back behavior on the channel-setup route must first close
  or clear the deepest active setup state in this order when present: metadata
  detail, search results/query, selected library item/list, selected library
  section, selected server, pending PIN/profile subflow. Only after the setup
  flow is at the top level may back leave channel setup for the previous route
  or player fallback.
- Explicit controls must exist for cancelling a pending PIN and clearing server,
  library section, item/metadata, and search/query UI state. Clearing renderer
  selection state must not clear persisted selected-server state unless the
  existing bridge method explicitly does so; there is no such bridge method in
  RD-22, so selected-server persistence clearing is out of scope.
- Scrolling must be reliable on Windows with keyboard/remote-like focus. Focused
  controls in the setup flow must remain visible, long server/library/item text
  must not overlap adjacent controls, and the route must not trap focus inside a
  non-scrollable nested panel.
- Text entry bypass must remain intact for protected-home PIN and search inputs:
  arrow/backspace typing behavior inside inputs must not be hijacked by desktop
  navigation, while Escape/back outside text entry follows the setup unwind rule.
- Route cleanup must cancel pending PIN polling and stale async work as it does
  today, without leaving visible stale PIN/profile/search/detail state after
  route exit and return.
- Renderer-visible failures must be generic and sanitized, with retry/cancel
  affordances where recoverable.

Security and redaction invariants:

- Renderer code must not fetch Plex, construct Plex endpoints, store
  credentials, persist selected state, expose connection URIs, log raw payloads,
  or receive tokens/auth headers/tokenized URLs/native handles/filesystem paths.
- Protected-home PIN input may transit renderer to main only through the
  existing `switchHomeUser` bridge call and must be cleared after use, cleanup,
  route exit, and failed/cancelled flows.
- Account, server, library, and media display names may appear in the local UI,
  but tracked docs and proof summaries must replace them with counts/categories.
- Keep `connect-src 'none'`; renderer network remains forbidden.

Forbidden shortcuts: broad RPC bridges, arbitrary action/channel strings,
renderer-held secrets, renderer persistence/storage, Electron/Node access from
renderer, raw diagnostic output, compatibility shims, package/dependency edits,
contract/preload/main changes without replan, channel creation, playback hooks,
and upstream imports without an import-ledger update.

Stop at this gate if the UI cannot satisfy the Windows proof blocker without
crossing one of these boundaries.

## Verification Commands

Verification classification: broader integration/manual proof required.

Planner-pass verification after this plan revision:

- `npm run verify:docs`: expected to pass active-plan structure and Tier 3 plan
  checks.
- `npm run verify:redaction`: expected to pass with no token, header, raw Plex,
  path, credential, connection-detail, or private proof findings in the tracked
  plan.
- `git diff --check`: expected to report no whitespace errors.

Implementation closeout verification:

- `npm run test -- src/__tests__/renderer/plexRuntime.test.ts`: expected to pass
  focused renderer setup-flow state/DOM/focus/cancel/back/clear/sanitized-copy
  coverage.
- `npm run test -- src/__tests__/renderer/workflow.test.ts
  src/__tests__/renderer/routeDom.test.ts`: expected to pass route/workflow
  regression coverage. If the repo test runner does not accept these exact file
  arguments, use the closest existing focused renderer test command and record
  the substitution.
- `npm run verify`: expected to pass typecheck, architecture lint,
  maintainability, contract/main/preload/renderer tests, docs, and redaction.
- `npm run verify:docs`, `npm run verify:redaction`, and `git diff --check`:
  expected to pass after source, tests, and any redacted proof summary changes.

Windows proof required before RD-22 closeout:

- Run the built Electron app on Windows through the live RD-22 product path.
- Store only ignored local evidence under
  `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/`.
- Redacted proof summary must include platform, app mode/build identity,
  credential availability status, PIN requested and either claimed/cancelled or
  safely expired, profile/Plex Home selection status when applicable, server
  count/selection/restore status, library section count, browse count, search
  count, metadata category/count, explicit back/clear/cancel behavior observed,
  scroll/focus behavior observed, sanitized failure categories, and redaction
  scan status.
- The proof must not include account, server, library, or media names; raw
  screenshots; logs; paths; URLs; connection details; tokens; headers; raw Plex
  payloads; raw IPC frames; or support-bundle contents.

## Acceptance Criteria

- RD-22 remains active/open until proof passes; no roadmap/current-state/parity
  closeout claims are added by the remediation plan itself.
- The placeholder/debug Plex panel is replaced by a real setup flow on the
  existing channel-setup surface.
- The flow supports sign-in/PIN guidance, profile/Plex Home selection, server
  restore/refresh/select, library sections/items/search, metadata preview,
  sanitized failure display, retry where appropriate, explicit PIN cancel, and
  explicit clear/back behavior for nested selections.
- Windows keyboard/remote-like focus can reach every setup control and dynamic
  list item; focused items remain visible inside scrollable regions; Back/Escape
  unwinds nested setup state before route navigation; text inputs keep desktop
  input bypass.
- Existing main/preload Plex runtime, contracts, shell/window/player/diagnostics
  APIs, fake-backed player/guide/settings behavior, fullscreen bridge, and
  support-bundle export remain compatible.
- Renderer and tracked proof surfaces contain no credentials, tokens, auth
  headers, tokenized URLs, connection details, raw Plex payloads, filesystem
  paths, raw IPC frames, native handles, or private proof names.
- `npm run verify` and the focused renderer tests pass, and live redaction-safe
  Windows proof observes the remediated flow.
- Plan review and implementation review are clean before closeout.

## Replan Triggers

- The remediation requires changing `src/contracts/plex.ts`,
  `src/contracts/ipc.ts`, `src/contracts/shell.ts`, `src/preload/index.cts`,
  main Plex runtime/transport/composition, package files, dependencies, or
  lockfiles.
- Correct Plex claim guidance requires renderer network access, token-bearing
  links, raw URLs, or renderer-held credentials.
- The existing bridge cannot support required cancel/back/clear behavior without
  a new persisted selected-server clearing operation or a contract change.
- Back/scroll/focus behavior cannot be proven through renderer-local state and
  existing navigation owners.
- Any touched production file crosses 500 lines or any allowlisted hotspot grows
  without a reviewed Architecture Health decision.
- Live proof cannot be captured without raw/private tracked evidence.
- `npm run verify:redaction`, docs verification, architecture/maintainability,
  focused renderer tests, or implementation review finds a boundary/security
  issue.
- Channel creation, runtime persistence, scheduler-backed guide, playback,
  package/release, native-helper, signing/update, public-release, or RD-23 scope
  becomes necessary to prove RD-22.

## Rollback Notes

- Roll back the remediation by restoring the prior renderer Plex panel state,
  DOM, route wiring, CSS, and focused renderer tests. This should not require
  changes to main Plex runtime, contracts, preload, persistence, diagnostics, or
  package files.
- Ignored Windows proof under
  `docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/` can be deleted
  without affecting source.
- If the remediation is rolled back or proof remains blocked, keep this plan
  active and do not promote RD-22 closeout claims.

## Commit Checkpoints

- Use one focused implementation commit for the reviewed remediation unit, for
  example `feat: replace plex setup debug panel`.
- Keep this plan revision separate from product implementation when practical.
- Do not stage unrelated local changes.

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: Tier 3 remediation touches renderer setup composition over live Plex IPC/security, storage/secret boundaries, Windows usability proof, and redaction policy.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Run RD-22 Remediated Windows Live Plex Proof
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
ARTIFACT: current RD-22R1 implementation diff
FILES:
- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md
- docs/runs/rd-22-live-plex-auth-discovery-library-runtime-ui/windows-live-proof-blocked.redacted.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/file-shape-guardrails.md
- docs/development/windows-ui-proof-plan.md
- docs/product/lineup-product-parity-matrix.md
- src/renderer/plexRuntimeState.ts
- src/renderer/plexRuntimeActions.ts
- src/renderer/plexRuntimeDom.ts
- src/renderer/staticDom.ts
- src/renderer/domBindings.ts
- src/renderer/index.ts
- src/renderer/workflow.ts
- src/renderer/routeDom.ts
- src/renderer/styles/workflow-screens.css
- src/__tests__/renderer/plexRuntime.test.ts
BLOCKERS: RD-22 remediated live Windows proof still requires an interactive Plex account/server run with redaction-safe summaries; do not mark RD-22 complete before that proof and review pass.
MESSAGE:
Continue RD-22 through the feature-quality loop from the post-implementation proof gate. The RD-22R1 renderer setup-flow remediation has clean plan review and clean implementation re-review; automated verification passed in the implementing session, including focused renderer tests, `npm run verify`, `npm run build:electron`, `npm run smoke:electron`, `npm run verify:docs`, `npm run verify:redaction`, and `git diff --check` with line-ending warnings only. Do not change main/preload/contracts/Plex transport/persistence/package surfaces unless a replan trigger fires. Run the credentialed Windows live Plex proof through the remediated UI and record only ignored redaction-safe summaries for PIN claim/cancel or claim/expiry, profile/Plex Home when applicable, server restore/refresh/select, library sections/items/search/metadata counts, back/clear/cancel, scroll/focus, sanitized failures, and redaction status. Then rerun required docs/redaction/diff gates, send the proof/diff for read-only review, and keep RD-22 open until proof and review are clean.
