# Original Lineup Reference Compatibility Matrix

## Purpose

This matrix is the RD-20 review surface for Desktop behavior that was copied,
adapted, or intentionally shaped by the original Lineup project. It records the
minimum evidence needed to compare a Desktop slice with upstream Lineup without
turning upstream into a live dependency, package mirror, or automatic source of
truth for Desktop architecture.

RD-20 is complete as docs, source-audit, and provenance work only. This matrix
is the tracked compatibility artifact for M01-M07 copied/adapted import and
ledger coverage, M08-M10 reference-only Desktop behavior, and M11 Desktop proof
context. Compatibility rows are closeout evidence only for the reviewed scope;
they do not authorize new copied/adapted source, runtime behavior, package
changes, platform claims, or upstream checkout writes.

## Redaction Policy

Tracked matrix rows may include:

- upstream commit hashes, dates, branch names when necessary, and relative
  upstream paths
- relative Desktop paths, symbol names, sanitized behavior summaries, import
  ledger references, and verifier command names
- sanitized review notes that do not identify private machines, private media,
  local workspaces, or raw support artifacts

Tracked matrix rows must not include:

- raw Plex tokens, auth headers, tokenized URLs, native handles, raw Plex
  payloads, raw diagnostics, raw support bundles, raw IPC frames, process dumps,
  or filesystem dumps
- absolute local paths, private upstream workspace details, media sample names,
  server names, account identifiers, or private network details
- copied proprietary-looking payload fragments from Plex, native helpers, or
  diagnostics evidence

When evidence contains forbidden material, summarize the behavior, record only
relative paths or command names, and run the redaction verifier before closeout.

## Source-Evidence Rules

- Treat upstream Lineup as read-only evidence. Do not edit upstream, copy code,
  or import new source during RD-20 without a separate reviewed implementation
  unit and import-ledger update.
- Use only relative upstream paths and relative Desktop paths in tracked docs.
- Record an upstream commit/date for every audited upstream source claim. If a
  row is seeded before audit, use `TBD` rather than guessing.
- Prefer import-ledger rows for copied/adapted slices. Use reference-only rows
  when Desktop used upstream behavior for product guidance without importing
  source.
- Record symbol names only when they materially improve traceability.
- Link intentional behavior differences to
  `docs/architecture/original-lineup-divergence-register.md`.
- Do not paste raw fixture payloads, diagnostics, command transcripts,
  token-bearing URLs, auth headers, native handles, or local machine evidence.
- If source discovery contradicts the row's review mode or owner boundary, stop
  and replan before expanding scope.

## Matrix Columns

| Column | Meaning |
| --- | --- |
| Row ID | Stable RD-20 matrix row id. |
| Coverage family | Roadmap or architecture family under review. |
| Review mode | `copied/adapted`, `reference-only`, `proof-context`, or `TBD`. |
| Upstream evidence | Relative upstream source paths or `TBD`; no local checkout paths. |
| Upstream commit/date | Commit hash, branch/date, or `TBD` for unaudited seeded rows. |
| Desktop evidence | Relative Desktop files, tests, docs, symbols, or `TBD`. |
| Import-ledger coverage | Import-ledger row reference, `not applicable`, or `TBD`. |
| Divergence row | Divergence-register id, `none known`, or `TBD`. |
| Review status | Status from the vocabulary below. |
| Verification/proof | Commands, test names, source-audit proof, or `TBD`. |
| Notes/follow-up | Sanitized reviewer notes, open questions, or replan triggers. |

## Review Status Vocabulary

| Status | Meaning |
| --- | --- |
| `seeded` | Row exists as required RD-20 coverage but has not been audited. |
| `audit in progress` | Evidence is being collected and is not final proof. |
| `compatible` | Reviewed evidence supports Desktop compatibility for the stated scope. |
| `compatible with divergence` | Compatibility is accepted with a linked intentional Desktop divergence. |
| `blocked` | Required evidence is missing or contradicted; row cannot support closeout. |
| `out of scope` | The family is intentionally excluded from the current RD-20 unit. |
| `superseded` | A later reviewed row or architecture decision replaces this row. |

## Compatibility Rows

| Row ID | Coverage family | Review mode | Upstream evidence | Upstream commit/date | Desktop evidence | Import-ledger coverage | Divergence row | Review status | Verification/proof | Notes/follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RD20-M01 | RD-10 Plex library parser/domain behavior | copied/adapted | `src/modules/plex/library/**`, `src/modules/plex/shared/types.ts` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/main/plex/library/**`, `src/contracts/plex.ts`, `src/__tests__/main/plexLibrary.test.ts` | `docs/architecture/import-ledger.md` RD-10 library row | RD20-D01 | compatible with divergence | Source audit plus existing `src/__tests__/main/plexLibrary.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Parser/domain behavior is represented for sections, media, files, streams, seasons, collections, playlists, tag directories, search hubs, request intent, pagination guards, and renderer-safe summaries. Desktop intentionally omits live fetch/cache/image URL/runtime behavior from this row. |
| RD20-M02 | RD-10 Plex auth and profile behavior | copied/adapted | `src/modules/plex/auth/**` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/main/plex/auth/**`, `src/contracts/plex.ts`, `src/__tests__/main/plexAuth.test.ts` | `docs/architecture/import-ledger.md` RD-10 auth row | RD20-D02 | compatible with divergence | Source audit plus existing `src/__tests__/main/plexAuth.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. PIN parsing/claim, token validation, Plex Home users, profile switching, identity headers, cancellation, fail-closed credential saves, and sanitized error/profile summaries have Desktop proof. Credential custody and transport composition are intentional Desktop adaptations. |
| RD20-M03 | RD-10 Plex discovery and selected-server behavior | copied/adapted | `src/modules/plex/discovery/**`, `src/core/server-selection/**` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/main/plex/discovery/**`, `src/contracts/plex.ts`, `src/__tests__/main/plexDiscovery.test.ts` | `docs/architecture/import-ledger.md` RD-10 discovery row | RD20-D03 | compatible with divergence | Source audit plus existing `src/__tests__/main/plexDiscovery.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Resource normalization, connection priority, probe health, selected-server restore, stale-context rejection, and renderer-safe server summaries are covered. Desktop persists only selected-server summary state and keeps connection details in main-owned memory. |
| RD20-M04 | RD-11 scheduler behavior | copied/adapted | `src/modules/scheduler/scheduler/**`, `src/modules/scheduler/shared/**` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/domain/scheduler/**`, `src/__tests__/domain/schedulerDomain.test.ts` | `docs/architecture/import-ledger.md` RD-11 scheduler row | RD20-D04 | compatible with divergence | Source audit plus existing `src/__tests__/domain/schedulerDomain.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Deterministic schedules, playback ordering, block validation, shuffle seeds, schedule windows, transition events, drift reporting, and timer cleanup are preserved through injected clock/timer seams. |
| RD20-M05 | RD-11 channel and content behavior | copied/adapted | `src/modules/scheduler/channel-manager/**` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/domain/channel/**`, `src/__tests__/domain/channelDomain.test.ts` | `docs/architecture/import-ledger.md` RD-11 channel/content row | RD20-D05 | compatible with divergence | Source audit plus existing `src/__tests__/domain/channelDomain.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Channel authoring, import/export normalization, duplicate-number handling, content resolution, stale fallback, cache/retry behavior, transactional mutations, and safety checks are covered through pure domain ports. |
| RD20-M06 | RD-11 channel persistence behavior | copied/adapted | `src/modules/scheduler/channel-manager/StoredChannelDataCodec.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceSaveQueue.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceCoordinator.ts`, `src/modules/scheduler/channel-manager/ChannelPersistenceStore.ts`, `src/modules/scheduler/channel-manager/ChannelRepository.ts` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/domain/channel/storedChannelDataCodec.ts`, `src/domain/channel/channelPersistenceStore.ts`, `src/domain/channel/channelRepository.ts`, `src/domain/channel/channelPersistenceSaveQueue.ts`, `src/domain/channel/channelPersistenceCoordinator.ts`, `src/main/persistence/desktopChannelPersistenceStore.ts`, `src/__tests__/domain/channelPersistence.test.ts`, `src/__tests__/main/channelPersistenceAdapter.test.ts` | `docs/architecture/import-ledger.md` RD-11 channel persistence row | RD20-D06 | compatible with divergence | Source audit plus existing `src/__tests__/domain/channelPersistence.test.ts` and `src/__tests__/main/channelPersistenceAdapter.test.ts`; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Malformed recovery, normalized load/save, current-channel repair, transactional snapshots, debounced queue semantics, and serialized file-adapter writes are covered. Browser storage is intentionally replaced by Desktop file-adapter ownership. |
| RD20-M07 | Workflow, control-plane, and architecture docs derived from upstream conventions | copied/adapted | Upstream Lineup workflow/control-plane conventions represented by import-ledger source rows for workflow, role config, Codanna convention, repo hosting/review config, architecture-lint pattern, roadmap/report, and genesis ADR | workflow/control-plane rows cite 2026-05-07 upstream base `08c4e0fe` or exact source date as applicable | `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, `docs/agentic/**`, `docs/architecture/**`, `.codex/**`, `.github/**` | `docs/architecture/import-ledger.md` workflow/control-plane rows | RD20-D07 | compatible with divergence | `npm run verify:docs`; closeout also runs `npm run verify:redaction` | Ledger coverage is accurate for Desktop workflow/control-plane provenance. Historical upstream cleanup mechanics remain intentionally omitted and are not imported as Desktop authority. |
| RD20-M08 | RD-07/RD-08 player boundary and stream policy | reference-only | `src/modules/player/**`, `src/modules/plex/stream/**`, `src/platform/**` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/contracts/player.ts`, `src/main/player/**`, `src/main/plex/streamResolver.ts`, `src/__tests__/main/player/**`, `src/__tests__/contracts/contracts.test.ts`, `docs/architecture/CURRENT_STATE.md` | not applicable | RD20-D08 | compatible with divergence | Source audit plus existing player contract, adapter, process-seam, stream-policy, runtime/bridge/composition, and contract safety tests; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Upstream browser/webOS player, stream URL, platform service, subtitle/audio/HDR policy, recovery, and debug behavior were used as reference only. Desktop keeps player commands and policy outputs renderer-safe, capability-driven, and main-owned; no copied/adapted upstream player or stream-policy source was found for this row. |
| RD20-M09 | RD-13 renderer UI, navigation, settings, guide, and player overlays | reference-only | `src/modules/ui/**`, `src/core/channel-setup/**`, `src/styles/**`, `src/types/channelSwitch.ts` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/renderer/**`, `src/__tests__/renderer/**`, `docs/architecture/renderer-architecture.md`, `docs/architecture/CURRENT_STATE.md` | not applicable | RD20-D09 | compatible with divergence | Source audit plus existing renderer navigation, workflow, settings/setup, EPG, overlay, focus, desktop input/cursor, route DOM, style, and support-bundle renderer tests; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Scoped upstream paths were clean before read. Current architecture states RD-13 used upstream UI/navigation/assets only as reference and no copied/adapted upstream source landed. Desktop renderer remains unprivileged, Desktop-owned, and fake-backed where live Plex, persistence, or runtime playback wiring is not in scope. |
| RD20-M10 | RD-17 diagnostics, crash recovery, support bundle, and redaction | reference-only | `src/modules/player/**`, `src/modules/plex/stream/diagnostics/**`, `src/utils/redact.ts` | `76bc7ba31fa695ecef88b4ae79d40e8d79b7605f`, 2026-05-11 | `src/contracts/diagnostics.ts`, `src/contracts/redaction.ts`, `src/main/diagnostics/**`, `src/__tests__/contracts/contracts.test.ts`, `tools/verify-redaction.mjs`, `tools/__tests__/verify-redaction.test.mjs`, `tools/rd17-diagnostics-smoke.mjs`, `tools/__tests__/rd17-diagnostics-smoke.test.mjs`, `docs/architecture/CURRENT_STATE.md` | not applicable | RD20-D10 | compatible with divergence | Source audit plus existing diagnostics contract tests, redaction verifier tests, RD-17 diagnostics smoke tests, and closeout command `npm run verify:redaction` | Upstream has token redaction helpers and stream/player debug probes, but Desktop RD-17 diagnostics/redaction is a Desktop-owned support-bundle and scanner surface. No copied/adapted upstream diagnostics source was found for this row, and no raw diagnostics or support-bundle evidence is recorded. |
| RD20-M11 | RD-19 validation as Desktop proof context | proof-context | not applicable | not applicable | `docs/development/rd-19-internal-validation-checklist.md`, `docs/roadmap/desktop-port-roadmap.md`, `docs/architecture/CURRENT_STATE.md` | not applicable | RD20-D11 | compatible | Source audit of RD-19 validation checklist and roadmap/current-state summaries; closeout commands `npm run verify:docs`, `npm run verify:redaction` | Audit found RD-19 records Desktop validation context only. It names fake/injected/package/diagnostics proof and blocker classifications, and it does not promote any specific upstream behavior claim into compatibility authority. |
