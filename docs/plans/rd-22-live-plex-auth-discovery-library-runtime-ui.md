# RD-22B Live Plex Onboarding Runtime Wiring Into Parity Body

**Plan Status:** complete and reviewed; durable RD-22B closeout is reflected in
`docs/architecture/CURRENT_STATE.md` and
`docs/roadmap/desktop-port-roadmap.md`
**Task family:** feature/design
**Tier:** Tier 3

Path note: this plan keeps the historical RD-22 filename for handoff
continuity. RD-22A is complete and reviewed as fixture/injected
renderer-safe upstream-shaped app body parity. RD-22B was the live runtime
wiring and closeout plan for RD-22 and is now closed.

## Goal

Wire live Plex onboarding and library runtime into the committed RD-22A body
without reshaping that body except for reviewed data-binding adjustments.

RD-22B must make the reachable Desktop setup path operate through the existing
main-owned Plex runtime and narrow preload bridge for:

- live Plex auth and link PIN request, polling, cancellation, and retry
- credential availability and encrypted credential restore status
- profile and Plex Home selection, including protected-user PIN handling
- server discovery, selection, and selected-server restore after relaunch
- library section loading, browse, search, and metadata summary preview
- sanitized failure, loading, empty, cancelled, stale, back, clear, and retry
  states inside the RD-22A body
- focus, text-entry, scroll/list, and keyboard/remote-like behavior for the
  live setup path

Close RD-22 only after implementation, redaction-safe Windows live proof, full
verification, implementation review, and durable memory updates are complete.

## Closeout Summary

RD-22B closed the live Plex onboarding and library runtime wiring slice without
needing source changes after the approved freshness gate. Existing
main/preload/renderer seams already satisfied the plan, and the no-diff
implementation review was clean.

Observed closeout proof and verification:

- focused Plex contract/main/preload/renderer tests passed
- targeted renderer Plex runtime/navigation/focus/input tests passed
- `npm run typecheck` passed
- `npm run smoke:electron` passed
- `npm run verify` passed
- `npm run verify:docs` passed for plan activation and closeout docs
- `npm run verify:redaction` passed
- `git diff --check` passed
- redaction-safe Windows live proof passed for auth/PIN, credential
  availability and restore, Plex Home/profile selection, protected-user PIN
  failure handling, server discovery/selection/restore, library sections,
  browse, search, metadata, failure/empty/loading/stale categories, and
  clear/back/cancel/text-entry/scroll behavior
- plan, implementation, and proof reviews were clean; final closeout review
  findings were adjudicated in this closeout update

No raw account, profile, server, library, media, endpoint, token, path, payload,
log, screenshot, process, native-handle, or support-bundle evidence is tracked.
No copied or adapted upstream source landed in RD-22B, so no import-ledger
update was required.

## Non-Goals

- Do not implement RD-23 channel creation, live channel setup commit,
  channel settings persistence, or persisted channel recovery.
- Do not implement RD-24 scheduler-backed guide/player runtime, current-channel
  state, guide schedule refresh, channel switching, or runtime player chrome.
- Do not implement RD-25 production playback, native-helper behavior, media
  load, stop/switch playback, or production playback controls.
- Do not implement RD-26 media-option runtime, subtitle/audio/HDR mutation, or
  playback-quality controls.
- Do not change package scripts, dependencies, lockfiles, signing, update,
  installer, release, public readiness claims, or native/media redistribution.
- Do not add renderer custody of credentials, tokens, selected connections,
  raw Plex payloads, auth headers, endpoint details, app paths, diagnostics
  internals, raw private proof, Node APIs, Electron APIs, native handles, or
  broad IPC/RPC access.
- Do not copy raw screenshots, logs, account names, server names, library
  titles, media titles, local paths, endpoint URLs, tokens, auth headers,
  payloads, native handles, process ids, support-bundle contents, or private
  proof into tracked docs, tests, diagnostics, fixtures, or Codex output.

## Parent Architecture Alignment

Chosen route: Tier 3 feature/design through the Desktop feature-quality loop:
plan, read-only plan review, bounded implementation, verification, read-only
implementation review, closeout, and RD-22 durable memory update.

Current architecture already has the required process owners:

- Electron main owns app paths, Electron `safeStorage`, encrypted Plex
  credential records, selected-server persistence, live Plex transport,
  profile-scoped active tokens, selected connections, raw Plex payloads,
  sanitized diagnostics, and shutdown cleanup.
- Preload owns the typed, validated `window.lineupDesktop.plex` bridge only.
  It must stay a single narrow exposure and must reject malformed or
  privileged Plex results locally.
- Renderer owns the RD-22A body, setup composition, safe UI state, focus,
  keyboard/remote-like input, text-entry, lists, loading/empty/error display,
  and live setup actions against the preload bridge.
- Contracts own renderer-safe public shapes only. They may contain profile,
  home-user, server, library, media, selection, operation, request, and error
  summaries, but never raw transport or secret material.
- Persistence remains main-owned. Renderer may show only safe credential
  availability states such as missing, present, unavailable, or corrupt.

RD-22B may change main/preload/contracts/runtime/persistence/renderer seams
only where the reviewed implementation unit proves the existing seam is
insufficient for the live setup path. The default posture is to bind, verify,
and narrowly fix the existing RD-22 live runtime rather than invent a second
runtime.

## Required Reading

Fresh-session implementers and reviewers must read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/session-prompts/feature-plan.md`
5. `docs/agentic/session-prompts/feature-review.md`
6. `docs/agentic/plan-authoring-standard.md`
7. `docs/architecture/CURRENT_STATE.md`
8. `docs/architecture/file-shape-guardrails.md`
9. `docs/architecture/security-and-secret-flow.md`
10. `docs/architecture/import-ledger.md`
11. `docs/roadmap/desktop-port-roadmap.md`
12. `docs/development/windows-ui-proof-plan.md`
13. `docs/plans/rd-22a-upstream-ui-body-parity-matrix.md`
14. This plan
15. Current source in:
    `src/contracts/plex.ts`, `src/contracts/ipc.ts`, `src/contracts/shell.ts`,
    `src/preload/index.cts`, `src/main/index.ts`, `src/main/plex/**`,
    `src/main/persistence/**`, `src/renderer/plexRuntime*.ts`,
    `src/renderer/staticDom.ts`, route/workflow/navigation/input owners, and
    `src/__tests__/**`.

Freshness gate: before source edits, run `git status --short --branch`,
`git rev-parse HEAD`, `git -C C:\Software\Lineup status --short --branch`,
and `git -C C:\Software\Lineup rev-parse HEAD`. If Desktop moved from
`d743fc1d4f42c6f514987216106d8ffdd3f8f343`, upstream moved from
`613b1c516c7c9e37f9c18ea3e92c474013472b11`, relevant ownership changed, or
this plan conflicts with the roadmap/current-state docs, update and re-review
the plan before editing source.

## Required Skills

- `lineup-desktop-feature-quality-loop`: required because RD-22B crosses
  main/preload/contracts/persistence/Plex/renderer and needs repeated gates.
- `execution-plan-authoring`: freezes scope, ownership seams, verification,
  rollback, and replan triggers for a fresh implementer.
- `architecture-boundaries`: keeps Electron process ownership, contracts, IPC,
  preload, and renderer responsibilities narrow.
- `persistence-boundaries`: applies to credential availability,
  selected-server persistence, app paths, and encrypted storage status.
- `plex-integration-boundaries`: applies to auth/PIN, Plex Home,
  selected-server state, discovery, library, search, metadata, token custody,
  and transport redaction.
- `ui-composition-patterns`: applies to binding live state into the RD-22A
  body, focus, text entry, scroll/list behavior, cancellation, and back/clear
  behavior.
- `verification-strategy`: required because automated public-seam tests must
  be paired with redaction-safe Windows live proof.
- `review-request`: required for read-only plan and implementation review.
- `closeout-verification`: required before staging, committing, closing
  RD-22, or handing off to RD-23.

## Evidence And Discovery

- `semantic_search_with_context`: controller-confirmed Codanna index has
  `0 symbols`, `0 files`, and `0 embeddings`; semantic discovery is not useful
  for this plan. Direct `rg` and file reads are the recorded fallback path.
- `semantic_search_docs` or repo-doc search: same Codanna fallback. Required
  docs were read directly.
- impact analysis: not run because Codanna has no indexed graph. Direct source
  reads and `rg` anchored the current public seams and tests.
- direct reads / `rg`: read the workflow runbook, feature-plan launcher,
  plan-authoring standard, current architecture state, file-shape guardrails,
  roadmap RD-22B/RD-23+ boundaries, import ledger, secret-flow doc,
  Windows proof plan, active RD-22/RD-22A plan artifacts, `src/contracts/plex.ts`,
  `src/contracts/ipc.ts`, `src/contracts/shell.ts`, `src/preload/index.cts`,
  `src/main/index.ts`, `src/main/plex/plexIpc.ts`,
  `src/main/plex/plexComposition.ts`, `src/main/plex/desktopPlexRuntime.ts`,
  `src/main/plex/desktopPlexRuntimeSupport.ts`,
  `src/main/plex/livePlexTransport.ts`,
  `src/main/persistence/desktopPersistenceStore.ts`,
  renderer Plex runtime/static/focus/action owners, and relevant contract,
  main, preload, renderer, persistence, and discovery tests.
- official docs: not required for this plan because RD-22B does not change
  Electron, package, dependency, signing, release, or external API policy. If
  implementation proposes external framework/API behavior changes, stop and
  add official-doc evidence before review.
- upstream source: upstream `C:\Software\Lineup` is on
  `code-health` at `613b1c516c7c9e37f9c18ea3e92c474013472b11`. RD-22A already
  imported/adapted the UI body at that commit. RD-22B should not copy more
  upstream UI/source unless a reviewed implementation unit records a new
  import-ledger row before or with the copy/adaptation.
- current implementation evidence:
  `src/contracts/plex.ts` already declares renderer-safe auth/profile/Home
  user/server/library/search/metadata snapshots, operations, and recursive
  forbidden-field checks. `src/preload/index.cts` already exposes the Plex
  bridge with validated request/result guards. `src/main/index.ts` registers
  Plex composition before shell window creation. `src/main/plex/desktopPlexRuntime.ts`
  already owns PIN, Home users, selected-server restore/refresh/select, library
  sections/items/search/metadata, abort/stale handling, and sanitized snapshot
  commits. `src/renderer/plexRuntimeActions.ts`,
  `src/renderer/plexRuntimeDom.ts`, and `src/renderer/plexRuntimeRows.ts`
  already bind safe runtime snapshots into RD-22A onboarding/setup controls.

## Impact Snapshot

Expected blast radius is cross-boundary but bounded to the live Plex setup
path:

- Main Plex/runtime may receive narrow fixes for live auth/PIN, credential
  availability, profile/Plex Home switching, selected-server restore after
  relaunch, discovery, library browse/search/metadata, stale/cancel handling,
  and sanitized diagnostics.
- Main persistence may receive narrow fixes only for profile-scoped
  selected-server restore or credential availability if live proof contradicts
  existing behavior.
- Contracts/preload may change only if the live path needs a renderer-safe
  summary or validation correction that cannot be represented by current
  shapes. No privileged field may cross the seam.
- Renderer Plex setup owners may receive data-binding, focus, text-entry,
  scroll/list, clear/back/cancel, loading/empty/error, and redaction-safe copy
  adjustments inside the RD-22A body.
- Tests must change wherever a public seam changes or a live-path regression
  needs stable automated protection.
- Import ledger must change before or with any additional copied/adapted
  upstream Plex/UI/CSS/copy/test source.
- No dependency, build-tool, package, lockfile, packaging, signing, update, CI,
  native-helper, or release change is expected or approved.

The first implementation unit may cross main/preload/renderer only to verify
and patch the single onboarding journey end to end. That cross-boundary unit is
allowed because splitting auth/profile/server/library binding into isolated
source commits would make Windows live proof and RD-22 closure less reliable.
Each patch inside that unit must still name its owner and stay inside this
plan's files.

User-visible behavior that must not regress: the RD-22A body structure,
product copy posture, route isolation, player/guide/settings shells, fake-free
reachable setup body, keyboard/remote-like navigation, text-entry bypass, and
sanitized diagnostics/support behavior.

Local-only artifacts, raw proof notes, screenshots, logs, support bundles, and
manual evidence stay ignored under `docs/runs/**` or outside tracked docs.

## Architecture Health

Tier 3 file-shape evidence from current direct line counts:

- `src/preload/index.cts`: 2116 lines, allowlisted hard-overage. It may not
  grow for RD-22B unless a reviewed implementation unit proves a missing
  Plex bridge guard is required and also records why the existing approved
  bridge vocabulary cannot represent the live path. Preferred decision:
  avoid growth.
- `src/main/plex/desktopPlexRuntime.ts`: 664 lines, allowlisted. It may receive
  narrow live-path fixes, but selection/profile orchestration must be split
  before adding another broad runtime behavior family. Preferred decision:
  avoid or shrink; do not add a new operation family.
- `src/main/persistence/desktopPersistenceStore.ts`: 625 lines, allowlisted.
  Only selected-server/profile-scope or credential availability defects are in
  scope. No new persisted state family is approved. Preferred decision: avoid
  growth or make a focused same-owner extraction if needed.
- `src/contracts/plex.ts`: 380 lines, below the production guardrail. Contract
  additions are allowed only for renderer-safe summaries, not privileged
  transport fields.
- `src/main/index.ts`: 319 lines, below the guardrail. It should remain
  composition wiring only.
- `src/renderer/staticDom.ts`: 269 lines,
  `src/renderer/plexRuntimeActions.ts`: 472 lines,
  `src/renderer/plexRuntimeDom.ts`: 225 lines, and
  `src/renderer/plexRuntimeRows.ts`: 329 lines. Renderer Plex binding changes
  should stay in these focused owners unless a new focused renderer owner
  clearly reduces complexity.

Affected owner hotspots: preload bridge, main Plex runtime, main persistence
store, and renderer setup binding. RD-22B must not raise file-shape baselines
to pre-authorize growth. If implementation must grow an allowlisted file above
its current reviewed baseline, stop for a reviewed decomposition or temporary
allowlist decision with a removal trigger.

Maintainability route:

- Run `npm run verify:maintainability` directly after any production source
  shape or file-shape guardrail change.
- `npm run verify` remains the closeout command for source implementation and
  should include maintainability unless the reviewed implementation packet
  names a narrower command for a docs-only checkpoint.

## Files In Scope

Plan/review/control surfaces:

- `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
- `docs/plans/rd-22a-upstream-ui-body-parity-matrix.md` read-only context
- `docs/architecture/import-ledger.md` only for copied/adapted upstream source
- `docs/architecture/CURRENT_STATE.md` and
  `docs/roadmap/desktop-port-roadmap.md` only during RD-22 closeout memory
  update after observed implementation/proof/review completion

Source implementation scope after read-only plan review:

- `src/contracts/plex.ts`
- `src/contracts/ipc.ts` only for approved Plex channel vocabulary correction
- `src/contracts/shell.ts` only for typed Plex bridge shape correction
- `src/preload/index.cts`
- `src/main/index.ts`
- `src/main/plex/plexComposition.ts`
- `src/main/plex/plexIpc.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/desktopPlexRuntimeSupport.ts`
- `src/main/plex/livePlexTransport.ts`
- `src/main/plex/auth/**`
- `src/main/plex/discovery/**`
- `src/main/plex/library/**`
- `src/main/persistence/desktopPersistenceStore.ts`
- `src/main/persistence/appDataPaths.ts`
- `src/main/persistence/secureStorageCodec.ts`
- `src/renderer/plexRuntimeActions.ts`
- `src/renderer/plexRuntimeState.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/index.ts`
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/plex-onboarding-cards.css`
- focused tests in `src/__tests__/contracts/**`,
  `src/__tests__/integration/preloadContractVocabulary.test.ts`,
  `src/__tests__/main/plex*.test.ts`,
  `src/__tests__/main/persistenceBoundary.test.ts`,
  and `src/__tests__/renderer/plexRuntime.test.ts`

Read-only upstream source may be inspected under `C:\Software\Lineup` for
behavior parity. Copy/adaptation requires the import-ledger obligation above.

## Files Out Of Scope

- `src/domain/**`
- `src/main/player/**` except read-only context
- `src/main/persistence/desktopChannelPersistenceStore.ts`
- `src/native/**`
- production native-helper files or tools
- scheduler/channel runtime owners
- package manifests, lockfiles, package tooling, signing/update/installer
  configuration, release docs, and CI configuration
- guide/player runtime, media-option runtime, and playback-specific contracts
- tracked raw proof artifacts, screenshots, logs, support-bundle contents,
  account/server/library/media names, local paths, endpoint URLs, connection
  details, auth headers, tokens, raw Plex payloads, process ids, native
  handles, and private diagnostic output

## Planner Self-Check

1. No product, ownership, dependency, or verification decision is left
   unresolved for RD-22B planning. Existing owners are main Plex/persistence,
   preload bridge, contracts, and renderer setup binding.
2. The plan includes adjacent contract/preload/main/persistence/renderer files
   that may need changes; it does not rely on hidden wiring in frozen files.
3. Files out of scope are not needed to prove RD-22B because channel creation,
   scheduler guide/player runtime, playback, media options, native helper, and
   package behavior are later roadmap items.
4. Evidence path records Codanna fallback plus direct doc/source/test reads.
5. Work stays with repo-preferred owners and explicitly avoids hotspot growth
   unless a reviewed decomposition/allowlist decision is made.
6. Tier 3 Architecture Health evidence and maintainability route are included.
7. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Exact verification commands, expected outcomes, live proof expectations,
   stop/replan triggers, rollback notes, commit checkpoints, and review
   handoff are recorded.

## Architecture Seam Decision Gate

Chosen seam: main-owned live Plex runtime and persistence feed renderer-safe
snapshots through the narrow preload bridge into the RD-22A renderer body.
Renderer owns display, focus, and local transient input only.

Forbidden shortcuts:

- no renderer Plex fetches, token handling, auth headers, raw endpoint details,
  selected connections, raw payloads, raw diagnostics, Electron/Node APIs,
  filesystem paths, app paths, browser storage, native handles, or privileged
  playback descriptors
- no broad preload RPC, arbitrary channel strings, second contextBridge world,
  compatibility barrels, old upstream path shims, or fallback API variants
- no persistence schema expansion beyond credential/selected-server behavior
  already owned by RD-09/RD-22 unless a reviewed migration/no-migration note is
  added before implementation
- no tracked raw live proof or private Plex/account/server/library/media data
- no package/dependency/release/native-helper changes

Storage decision: existing RD-09 main persistence remains the owner. RD-22B may
use only encrypted credential records and active-profile scoped
selected-server summaries. No migration is expected. If live proof shows legacy
singleton selected-server data needs migration into profile-scoped records,
stop and replan with explicit schema/migration verification.

Redaction decision: renderer-facing state, contracts, diagnostics, tests, docs,
and proof summaries may contain only safe status, counts, operation names,
request ids, and generic product copy. Main may hold private material only in
runtime memory or encrypted storage as already approved.

UI decision: preserve RD-22A body structure. Data-binding adjustments may alter
button enabled states, list contents, focus registration, scrollable regions,
input clearing, status/error copy, and empty/loading states. Rebuilding the
body, reintroducing scaffold/debug controls, or changing later RD-23/RD-24/RD-25
surfaces is out of scope.

Stop and replan if implementation contradicts any owner seam above.

## Verification Commands

Verification classification: `broader integration/manual proof required`.

Plan-only checkpoint:

- `npm run verify:docs` should pass for this active tracked plan.
- `git diff --check -- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
  should pass or report only known pre-existing line-ending warnings that do
  not affect content.

Implementation units must run the smallest focused proof first, then close with
the full source proof:

- `npm run typecheck` should pass after contract, preload, main, or renderer
  type changes.
- `npm run test:contracts -- --test-name-pattern "plex runtime|plex auth|plex discovery|plex library|preload Plex|contract|persistence"`
  should pass when Plex runtime, persistence, contract, or preload behavior is
  touched.
- `node --import tsx --test src/__tests__/renderer/plexRuntime.test.ts src/__tests__/renderer/navigation.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/desktopInput.test.ts`
  should pass when renderer Plex binding, focus, text-entry, or back/clear
  behavior is touched.
- `npm run verify:redaction` should pass after any live Plex, diagnostics,
  contract, test, or proof-surface change.
- `npm run verify:maintainability` should pass after any production source
  shape change or file-shape guardrail change.
- `npm run smoke:electron` should pass before closeout because the live bridge
  is composed during shell startup.
- `npm run verify` should pass before source implementation closeout.
- `git diff --check` should pass before commit, with only explicitly observed
  and acceptable line-ending warnings if present.

Expected outcomes:

- Contract/preload tests reject forbidden Plex fields, malformed request/result
  envelopes, mismatched request ids, invalid PINs, invalid limits/filters, and
  unsafe bridge exposure.
- Main tests prove token/connection/raw payload custody remains in main,
  selected-server restore is profile-scoped, protected Home PIN switching is
  safe, stale/cancelled operations do not commit old state, library
  browse/search/metadata summaries remain renderer-safe, and sanitized errors
  omit private material.
- Renderer tests prove live state binding, loading/empty/error text, protected
  Home PIN input clearing, search text-entry, scroll/list focus targets,
  nested back/clear/cancel ordering, stale result ignores, and no forbidden
  renderer state.
- Smoke proves the shell starts with the preload/main Plex bridge composed and
  without weakening sandbox/containment.

Windows live proof is mandatory before RD-22B closeout. Tracked summary may
include only categories, scenario counts, pass/fail/blocked status, command or
route names, and sanitized blocker classification. Required categories:

- auth/PIN: request, poll/claim, cancel, retry, expired or failed state if
  observed
- credential availability: missing/present/unavailable or corrupt state as
  safely observable
- profile/Plex Home: Home user load, protected-user PIN success/failure or
  blocked-unavailable, profile switch reset behavior
- server discovery and selection: refresh, select, unavailable/error state,
  profile-scoped selected-server restore after app relaunch
- library: sections, browse, search, metadata summary, empty/error state
- renderer behavior: back, clear, cancel, focus movement, text-entry bypass,
  scroll/list reachability, route cleanup
- redaction: no tracked private names, paths, URLs, tokens, headers, payloads,
  screenshots, logs, native handles, support-bundle contents, or raw proof

Live proof counts should use a shape like:
`RD-22B live Plex onboarding: <passed>/<total> observed; blocked=<count>`.
Do not include account, server, library, or media names in the tracked summary.

## Acceptance Criteria

- Live Plex sign-in through link PIN works from the RD-22A body, including
  cancel/retry and sanitized failed/expired/rate-limited states.
- Credential availability is visible only as safe status and main can restore
  an encrypted credential without exposing the secret to renderer/preload
  contracts, docs, tests, diagnostics, or output.
- Plex Home profiles load through main, protected users accept a PIN through
  renderer-local transient input, and profile switching clears server/library
  state without leaking the account token or managed-user token.
- Server discovery, selection, and selected-server restore after relaunch work
  for the active profile, while selected connections and endpoint details stay
  in main memory only.
- Library sections, browse, search, and metadata summaries populate the RD-22A
  body with renderer-safe summaries only. No artwork URLs, media files, raw
  payloads, tokenized URLs, headers, or private endpoint details cross the
  seam.
- Sanitized loading, empty, failed, cancelled, stale, auth-required,
  storage-unavailable/corrupt, server-unreachable, access-denied,
  rate-limited, and parse/library failure states appear in the setup body
  without raw private material.
- Back/clear/cancel behavior unwinds metadata, search, items, selected
  section, selected server, and PIN/profile subflow before route back, while
  cancelling active PIN polling and ignoring stale results.
- Focus, text-entry, dynamic row focus ids, OK activation, scroll/list
  reachability, and route cleanup stay stable on Windows.
- RD-22A body parity remains intact except for reviewed live data-binding
  adjustments. Channel setup shell remains shell-only until RD-23.
- Any copied/adapted upstream Plex/UI/CSS/copy/test source has an
  import-ledger row before or in the same change.
- `npm run verify`, `npm run smoke:electron`, `npm run verify:redaction`,
  required focused tests, redaction-safe Windows live proof, and read-only
  implementation review pass before RD-22 closes.

## Replan Triggers

- Live behavior requires renderer custody of credentials, tokens, auth
  headers, selected connections, raw Plex payloads, endpoint details,
  diagnostics internals, app paths, filesystem paths, Electron/Node APIs,
  native handles, or privileged playback descriptors.
- The preload bridge would need broad RPC, arbitrary channel strings, another
  contextBridge exposure, compatibility shims, or old upstream path mirrors.
- Credential restore or selected-server restore requires a persistence schema
  migration, plaintext fallback, browser storage, or renderer-owned storage.
- Plex proof requires channel creation, persisted channel settings, scheduler
  guide/player runtime, production playback, media-option runtime,
  native-helper behavior, package/release changes, or public release claims.
- Live proof is blocked by missing redaction-safe Plex account/server access or
  active Plex rate limiting after a quiet retry window. Record blocked status
  without storing private evidence.
- Windows proof would require tracked screenshots, raw logs, account/server/
  library/media names, local paths, endpoint URLs, tokens, auth headers, raw
  payloads, support bundles, process ids, native handles, or private proof.
- Any allowlisted production file must grow above its reviewed baseline without
  an approved decomposition or temporary allowlist update.
- Required verification fails in a way that invalidates the chosen seam.
- Read-only plan or implementation review reports a material security,
  boundary, verification, import-ledger, body-preservation, or scope blocker.

## Rollback Notes

- Plan-only changes can be reverted by reverting this file.
- Implementation should use focused commits so rollback can drop a failed live
  wiring unit without disturbing RD-22A body parity.
- If a runtime source change fails verification or live proof, revert only that
  focused change and preserve committed RD-22A body parity.
- If a profile-scoped selected-server or credential availability fix is wrong,
  remove the narrow runtime/persistence change and keep encrypted credential
  storage fail-closed.
- Ignored local proof under `docs/runs/**` can be deleted without affecting
  tracked source. Do not commit raw proof.
- Do not revert unrelated user changes or prior committed RD-22A/runtime fixes
  unless explicitly requested.
- If RD-22B is blocked by live account/server availability or rate limiting,
  leave RD-22B active or mark the reviewed handoff blocked; do not close RD-22
  with fake/injected proof.

## Commit Checkpoints

- Checkpoint 1: `docs(plan): activate RD-22B live Plex wiring packet` after
  this plan passes `npm run verify:docs` and read-only plan review.
- Checkpoint 2: `feat(plex): wire live onboarding into parity body` after the
  approved implementation unit passes focused tests, `npm run verify`,
  `npm run smoke:electron`, redaction-safe Windows live proof, and
  implementation review.
- Optional checkpoint 3: `docs(roadmap): close RD-22 live Plex onboarding`
  only after RD-22B source implementation, proof, review, and memory updates
  are complete. Keep workflow/control-plane docs separate from source when
  practical.
- Do not stage unrelated files. Do not combine RD-23/RD-24/RD-25/RD-26 work
  into RD-22B commits.

## Execution Units

### Unit 1: Plan Activation And Review

Scope:

- Replace the completed RD-22A active plan body with this RD-22B packet.
- Do not edit product source.

Verification:

- `npm run verify:docs` should pass.
- `git diff --check -- docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
  should pass or report only observed acceptable line-ending warnings.
- Read-only plan review through `lineup-desktop-feature-review` should report
  no material blockers before source implementation begins.

### Unit 2: Runtime Seam Freshness And Focused Patch

Scope after clean plan review:

- Reconfirm current live runtime behavior through focused contract/main/
  preload/renderer tests and source reads.
- Patch only the smallest defects that prevent live auth/PIN, credential
  availability, profile/Home switch, protected-user PIN handling, server
  discovery/selection/restore, library browse/search/metadata, sanitized
  failures, and RD-22A body binding from working as planned.
- Preserve the existing operation vocabulary unless a reviewed public-seam
  correction is unavoidable.

Files in scope: the source/test files listed in `## Files In Scope`.

Files out of scope: all RD-23 through RD-26 owners and all package/native/
release surfaces listed in `## Files Out Of Scope`.

Verification:

- Focused commands from `## Verification Commands` for touched owners.
- `npm run verify:redaction`
- `npm run verify:maintainability` when production source shape changes
- `npm run smoke:electron`
- `npm run verify`

Stop/replan:

- Any architecture seam, persistence schema, preload breadth, raw private data,
  source import, file-shape, or roadmap-scope trigger above fires.

### Unit 3: Redaction-Safe Windows Live Proof

Scope:

- On Windows, run the live setup path through the RD-22A body against an
  available redaction-safe Plex account/server.
- Record only local ignored raw notes if needed.
- Track only sanitized category/count/pass-fail/blocked summary after a
  redaction scan.

Required proof categories:

- auth/PIN
- credential availability
- profile/Plex Home, including protected PIN if available
- server discovery, selection, and relaunch restore
- library sections, browse, search, and metadata
- failure/empty/loading/cancel/stale state
- back/clear/cancel/focus/text-entry/scroll behavior
- redaction gate

Verification:

- `npm run verify:redaction`
- `git diff --check`
- Any exact live-proof command or manual script named by the implementation
  packet, with observed exit/status and sanitized result counts.

Stop/replan:

- Live proof cannot be completed without raw tracked evidence, private data
  exposure, package/native/playback/channel work, or public release claims.

### Unit 4: Implementation Review And RD-22 Closeout

Scope:

- Send the implementation diff, observed commands, Windows proof summary, and
  known risks to read-only implementation review.
- Adjudicate findings. Rerun required verification after accepted fixes.
- Update durable memory only after implementation review is clean:
  `docs/architecture/CURRENT_STATE.md`,
  `docs/roadmap/desktop-port-roadmap.md`, and import ledger if needed.
- Archive completed full plan body locally only after durable conclusions are
  reflected in tracked docs.

Verification:

- `npm run verify:docs` for closeout docs.
- `npm run verify:redaction`
- `npm run verify`
- read-only implementation review clean.

Stop/replan:

- Any material review finding remains unresolved, required verification fails,
  Windows proof is blocked, or memory updates would overclaim RD-23+ scope.

## Closeout Handoff

MODEL_SUGGESTION
PLANNER: gpt-5 high reasoning
IMPLEMENTER: gpt-5 high reasoning
REVIEWER: gpt-5 high reasoning
WHY: RD-23 is Tier 3 channel setup and persistence work across live Plex library data, channel/domain seams, main-owned persistence, preload/renderer boundaries, UI binding, Windows proof, and redaction boundaries.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Plan RD-23 Live Channel Setup And Runtime Persistence
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: create or update an active tracked RD-23 plan under docs/plans/
ARTIFACT: RD-22B closed and reviewed; roadmap now routes to RD-23
FILES:
- docs/architecture/CURRENT_STATE.md
- docs/architecture/file-shape-guardrails.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/import-ledger.md
- docs/roadmap/desktop-port-roadmap.md
- docs/development/windows-ui-proof-plan.md
- src/contracts/plex.ts
- src/contracts/persistence.ts
- src/preload/index.cts
- src/main/index.ts
- src/main/plex/**
- src/main/persistence/**
- src/domain/channel/**
- src/domain/scheduler/**
- src/renderer/plexRuntime*.ts
- src/renderer/staticDom.ts
- src/renderer/domBindings.ts
- src/renderer/focusDom.ts
- src/renderer/navigation.ts
- src/renderer/desktopInput.ts
- src/renderer/index.ts
- src/__tests__/**
BLOCKERS: none known. RD-23 must still produce and review its own plan before implementation.
MESSAGE:
Start the RD-23 quality loop from the current architecture truth and roadmap.
Plan the live channel setup and runtime persistence slice without reopening
RD-22B live Plex onboarding/library scope, production playback, scheduler-backed
guide/player runtime, media options, package/release behavior, native-helper
production behavior, or public readiness claims. Prioritize main-owned channel
persistence, renderer-safe channel authoring from live library summaries,
settings/recovery behavior, redaction-safe Windows proof, import-ledger duties
for any copied/adapted upstream channel setup UI/code, and clear stop/replan
triggers before implementation.
