# Original Lineup Divergence Register

## Purpose

This register records intentional Desktop differences from original Lineup
behavior discovered during RD-20. A divergence row is required when Desktop
keeps a different behavior, owner boundary, proof route, persistence model,
security posture, or user-visible workflow while still claiming reference
compatibility for a reviewed slice.

RD-20 is complete as docs, source-audit, and provenance work only. This register
is the tracked divergence artifact for the reviewed compatibility matrix rows:
D01-D07 copied/adapted import divergences, D08-D10 reference-only Desktop
divergences, and D11 proof-context classification. Accepted rows document
current Desktop intent only; they do not authorize production source changes,
new IPC, live Plex transport, persistence IPC, native playback, package changes,
or upstream checkout writes.

## Redaction Policy

Tracked register rows may include sanitized behavior summaries, relative source
paths, symbol names, upstream commit hashes or dates, Desktop verifier command
names, and architecture-owner references.

Tracked register rows must not include raw Plex tokens, auth headers,
tokenized URLs, native handles, raw Plex payloads, raw diagnostics, raw support
bundles, absolute local paths, private upstream workspace details, media sample
names, server names, account identifiers, private network details, or raw
filesystem/process evidence.

If a divergence was discovered from sensitive evidence, record the sanitized
decision and proof category only. Keep the raw evidence out of tracked docs and
run the redaction verifier before closeout.

## Source-Evidence Rules

- Treat upstream Lineup as read-only evidence and record only relative upstream
  paths plus commit/date evidence.
- Link every finalized divergence to the corresponding matrix row in
  `docs/architecture/original-lineup-reference-compatibility-matrix.md`.
- Distinguish product compatibility decisions from implementation gaps. Use
  `blocked` when Desktop cannot yet support the behavior and no reviewed
  divergence accepts that state.
- A divergence cannot authorize new runtime behavior, IPC, persistence,
  packaging, dependency, native playback, or source-import scope by itself.
  Those changes require a reviewed plan.
- Update the import ledger only when new copied/adapted source is imported.
  Reference-only divergence rows do not create import authority.
- Do not paste raw source payloads, diagnostics, local checkout details,
  command transcripts, secret-bearing strings, or native/runtime handles.

## Register Columns

| Column | Meaning |
| --- | --- |
| Divergence ID | Stable RD-20 divergence row id. |
| Matrix row | Related compatibility matrix row id. |
| Coverage family | Roadmap or architecture family where the divergence applies. |
| Desktop behavior | Sanitized summary of the Desktop behavior or owner boundary. |
| Original reference | Relative upstream path, symbol, or behavior summary; `TBD` until audited. |
| Intentional divergence | Exact accepted difference, or `TBD` for seeded rows. |
| Rationale | Why Desktop owns the difference. |
| Owner | Desktop owner doc, module, or workflow surface. |
| Evidence | Relative paths, tests, command names, or source-audit note. |
| User/security impact | Compatibility, UX, privacy, security, or operational impact. |
| Verification | Automated, source-audit, manual, or `TBD`. |
| Review status | Status from the vocabulary below. |
| Replan trigger | Condition that requires a new reviewed plan. |

## Review Status Vocabulary

| Status | Meaning |
| --- | --- |
| `seeded` | Row exists as required RD-20 coverage but has not been audited. |
| `candidate` | Evidence suggests a divergence, but it is not yet accepted. |
| `accepted` | Divergence is reviewed and intentionally owned by Desktop. |
| `accepted with follow-up` | Divergence is accepted with a named follow-up trigger. |
| `rejected` | Difference is not accepted; Desktop must restore compatibility or replan. |
| `blocked` | Missing or contradictory evidence prevents a decision. |
| `superseded` | A later reviewed row or architecture decision replaces this row. |
| `not a divergence` | Audit found no intentional Desktop behavior difference for the row. |

## Divergence Rows

| Divergence ID | Matrix row | Coverage family | Desktop behavior | Original reference | Intentional divergence | Rationale | Owner | Evidence | User/security impact | Verification | Review status | Replan trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD20-D01 | RD20-M01 | RD-10 Plex library parser/domain behavior | Main-owned metadata parsing and renderer-safe summaries; no live fetch/cache runtime or raw payload exposure. | `src/modules/plex/library/**`, `src/modules/plex/shared/types.ts` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop preserves copied/adapted parser behavior but intentionally excludes upstream live fetch/cache, image URL construction, auth-expired eventing, and raw payload/runtime custody from this row. | Desktop keeps Plex runtime and renderer exposure out of library parser/domain proof until later reviewed wiring; summaries enforce redaction boundaries. | `src/main/plex/library/**`, `src/contracts/plex.ts` | `src/__tests__/main/plexLibrary.test.ts`; source audit; import-ledger RD-10 library row | Preserves metadata compatibility while preventing renderer exposure of raw Plex payload, token-shaped fields, image keys, or local/runtime details. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires live Plex transport, renderer Plex APIs, raw payload retention, or contract changes. |
| RD20-D02 | RD20-M02 | RD-10 Plex auth and profile behavior | Main-owned auth behind injected transport and encrypted credential seam; renderer receives safe summaries only. | `src/modules/plex/auth/**` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop replaces upstream browser/localStorage/global-fetch auth ownership with injected transport, main-owned credential custody, cancellation guards, fail-closed saves, and renderer-safe profile summaries. | Auth tokens and credential persistence are Desktop main/security boundaries; exact sharing would expose browser assumptions and renderer-adjacent secret state. | `src/main/plex/auth/**`, `src/contracts/plex.ts` | `src/__tests__/main/plexAuth.test.ts`; source audit; import-ledger RD-10 auth row | Preserves auth/profile recovery behavior without exposing tokens, headers, account secrets, or raw auth failures. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires credential schema changes, live transport composition, preload/renderer auth expansion, or raw secret exposure. |
| RD20-D03 | RD20-M03 | RD-10 Plex discovery and selected-server behavior | Main-owned discovery restores by server id and keeps connection details in memory. | `src/modules/plex/discovery/**`, `src/core/server-selection/**` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop persists selected-server summary state and restores by server id with fresh probing instead of persisting selected connection URI or exposing connection-change URI events. | Connection URI custody belongs in main-owned runtime memory so renderer and persistence surfaces avoid server connection details. | `src/main/plex/discovery/**`, `src/contracts/plex.ts` | `src/__tests__/main/plexDiscovery.test.ts`; source audit; import-ledger RD-10 discovery row | Preserves selected-server recovery while avoiding persisted connection URLs and renderer-owned server secrets. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires persisted connection URI state, renderer connection custody, live discovery wiring, or selected-server schema changes. |
| RD20-D04 | RD20-M04 | RD-11 scheduler behavior | Pure scheduler domain with injected clock/timer ports and no runtime globals. | `src/modules/scheduler/scheduler/**`, `src/modules/scheduler/shared/**` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop preserves scheduling behavior while replacing upstream `Date.now`, global timers, event utility, and upstream channel/player imports with injected clock/timer ports and domain-local types. | `src/domain/**` must stay pure and runtime-free; exact sharing would pull browser/runtime assumptions into the scheduler owner. | `src/domain/scheduler/**` | `src/__tests__/domain/schedulerDomain.test.ts`; source audit; import-ledger RD-11 scheduler row | Preserves deterministic scheduling across Desktop runtime ownership and avoids Electron, Plex, playback URL, or browser-global coupling. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires Electron, Node, browser globals, live Plex, or playback URL ownership inside `src/domain/**`. |
| RD20-D05 | RD20-M05 | RD-11 channel and content behavior | Pure channel/content domain with injected library, persistence, clock, timer, logger, and id ports. | `src/modules/scheduler/channel-manager/**` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop preserves channel authoring/content behavior while replacing upstream runtime dependencies, browser storage keys, global timers, DOM abort construction, and main Plex types with pure domain ports and safe media shapes. | Channel/content domain must be reusable without main/preload/renderer/native-helper imports, live Plex transport, or raw Plex payload state. | `src/domain/channel/**` | `src/__tests__/domain/channelDomain.test.ts`; source audit; import-ledger RD-11 channel/content row | Preserves authoring and content-resolution continuity while keeping browser storage, raw Plex fields, and runtime globals out of domain state. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires domain imports from main/preload/renderer/native-helper, live transport, or raw Plex fields in domain state. |
| RD20-D06 | RD20-M06 | RD-11 channel persistence behavior | Domain persistence ports plus main-owned file adapter; no browser storage key or app-path runtime wiring in the domain. | `src/modules/scheduler/channel-manager/StoredChannelDataCodec.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceSaveQueue.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceCoordinator.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceStore.ts`, `src/modules/scheduler/channel-manager/ChannelRepository.ts` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop preserves persistence semantics through pure ports and a separate main-owned versioned file adapter instead of upstream browser `localStorage` keys. | Desktop channel persistence needs file ownership outside the domain and outside RD-09 credential/selected-server storage; browser storage compatibility is not a Desktop requirement. | `src/domain/channel/**`, `src/main/persistence/desktopChannelPersistenceStore.ts` | `src/__tests__/domain/channelPersistence.test.ts`, `src/__tests__/main/channelPersistenceAdapter.test.ts`; source audit; import-ledger RD-11 channel persistence row | Preserves malformed recovery and transactional snapshots without leaking local paths, secrets, or browser storage details. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires browser storage compatibility, app-path composition, backup/restore behavior, or renderer persistence APIs. |
| RD20-D07 | RD20-M07 | Workflow, control-plane, and architecture docs derived from upstream conventions | Desktop control plane adapts upstream workflow discipline while omitting historical upstream cleanup mechanics. | Import-ledger workflow/control-plane rows for upstream workflow conventions, role config, Codanna convention, repo hosting/review config, architecture-lint pattern, roadmap/report, and genesis ADR | Desktop keeps evidence-first workflow, review, verifier, role, and architecture-doc conventions, but historical upstream cleanup program mechanics are not Desktop authority. | Desktop is a separate Electron repo with its own roadmap, architecture boundaries, and verifier routing; stale upstream cleanup state would misroute current feature work. | `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, `docs/agentic/**`, `docs/architecture/**` | `docs/architecture/import-ledger.md`; `npm run verify:docs` | Keeps Desktop workflow authoritative without importing stale upstream program state, detector ids, package mechanics, or cleanup score artifacts. | `npm run verify:docs` | accepted | Replan if audit requires workflow routing, verifier behavior, or durable doc authority changes outside RD-20 Unit 2. |
| RD20-D08 | RD20-M08 | RD-07/RD-08 player boundary and stream policy | Desktop uses main-owned player adapter, native-host process seam, Plex playback runtime, and deterministic stream policy with renderer-safe payloads; production native playback remains scoped to later reviewed work. | Upstream browser/webOS player, stream resolver, stream URL/policy, and platform services under `src/modules/player/**`, `src/modules/plex/stream/**`, and `src/platform/**` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop does not preserve upstream browser video element ownership, webOS platform playback assumptions, raw stream URL/header construction in renderer-facing state, or live native playback capability claims. | Desktop playback is an Electron main/native-helper boundary; stream policy must express unsupported and unknown capability facts without leaking Plex URLs, auth headers, private track ids, or native handles. | `src/contracts/player.ts`, `src/main/player/**`, `src/main/player/streamPolicy/**`, `src/main/plex/streamResolver.ts`, `docs/architecture/CURRENT_STATE.md` | `src/__tests__/main/player/**`, `src/__tests__/contracts/contracts.test.ts`; source audit | Preserves Lineup player intent vocabulary and stream-decision rationale while avoiding overclaimed desktop codec/native support and privileged renderer exposure. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires production native-helper playback, player contract expansion, tokenized playback URLs or auth headers in renderer state, live Plex transport changes, or import-ledger coverage for copied/adapted player source. |
| RD20-D09 | RD20-M09 | RD-13 renderer UI, navigation, settings, guide, and player overlays | Renderer UI is Desktop-owned, unprivileged, and fake-backed where runtime wiring is not yet in scope. | Upstream UI, channel-setup, style, and channel-switch references under `src/modules/ui/**`, `src/core/channel-setup/**`, `src/styles/**`, and `src/types/channelSwitch.ts` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop did not copy upstream UI source and intentionally replaces upstream DOM/runtime, settings persistence, Plex-backed setup, guide refresh, and overlay runtime coupling with local renderer state and fake-backed view models. | Desktop renderer must stay unprivileged and cannot own Plex transport, persisted secrets/settings, native handles, raw diagnostics, or live playback setup. Reference-only UI preserves workflow shape without importing browser/webOS assumptions. | `src/renderer/**`, `docs/architecture/renderer-architecture.md`, `docs/architecture/CURRENT_STATE.md` | `src/__tests__/renderer/**`; source audit | Keeps expected player/guide/settings/channel-setup workflows reviewable while avoiding privileged renderer behavior and import-ledger obligations for source that was not copied/adapted. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires copied/adapted UI source, new preload APIs, live Plex renderer access, persisted settings IPC, browser storage reliance, or runtime playback wiring. |
| RD20-D10 | RD20-M10 | RD-17 diagnostics, crash recovery, support bundle, and redaction | Diagnostics use renderer-safe envelopes, main-owned support-bundle export, bounded diagnostic event storage, and repository/support-bundle redaction scanning. | Upstream player and stream diagnostics plus token redaction helpers under `src/modules/player/**`, `src/modules/plex/stream/diagnostics/**`, and `src/utils/redact.ts` at `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f` | Desktop treats upstream diagnostics/redaction as reference only and owns a stricter RD-17 diagnostic schema, support-bundle export surface, crash-recovery summary, scanner labels, and forbidden-field vocabulary. | Electron diagnostics cross renderer, preload, main, player, native-host, and support-bundle boundaries; exact upstream logging/probe behavior would not enforce Desktop redaction, path, process, native-handle, IPC, and support-bundle constraints. | `src/contracts/diagnostics.ts`, `src/contracts/redaction.ts`, `src/main/diagnostics/**`, `tools/verify-redaction.mjs`, `tools/rd17-diagnostics-smoke.mjs`, `docs/architecture/CURRENT_STATE.md` | `src/__tests__/contracts/contracts.test.ts`, `tools/__tests__/verify-redaction.test.mjs`, `tools/__tests__/rd17-diagnostics-smoke.test.mjs`; source audit | Maintains troubleshooting and crash-recovery value while preventing raw diagnostics, filesystem paths, process data, native handles, auth material, raw IPC, or support-bundle contents from entering tracked artifacts or renderer state. | Existing automated proof plus `npm run verify:redaction` | accepted | Replan if audit requires telemetry/cloud upload, raw support-bundle retention in tracked docs, diagnostics contract expansion, native/process detail exposure, or copied/adapted upstream diagnostics source. |
| RD20-D11 | RD20-M11 | RD-19 validation as Desktop proof context | RD-19 validates Desktop MVP behavior through redacted Desktop proof summaries and blocker classifications. | not applicable | RD-19 is not an upstream behavior divergence because it is not an upstream compatibility authority. | RD-19 is a Desktop validation/checklist artifact; treating it as upstream compatibility evidence would overstate fake/injected/package/diagnostics proof. | `docs/development/rd-19-internal-validation-checklist.md`, `docs/roadmap/desktop-port-roadmap.md`, `docs/architecture/CURRENT_STATE.md` | Source audit of RD-19 validation checklist and roadmap/current-state summaries | Prevents validation artifacts from overstating original Lineup compatibility or public/live-readiness while preserving their Desktop proof context. | `npm run verify:docs`; `npm run verify:redaction` | not a divergence | Replan if a specific RD-19 validation row is promoted into an upstream behavior claim. |
