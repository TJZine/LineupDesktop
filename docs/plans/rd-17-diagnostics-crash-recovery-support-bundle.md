**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

# RD-17 Diagnostics, Crash Recovery, And Support Bundle

## Goal

Complete RD-17 through the feature-quality loop by adding local, redacted
diagnostics across renderer, preload/main IPC, Electron main, player/runtime,
and the native-host process seam; making helper crash/restart behavior
observable without taking down the Electron UI; and adding a user-triggered,
main-owned support-bundle export.

The result must cover the whole roadmap item, not only a first diagnostics
slice. Implementation must proceed one bounded unit at a time after read-only
plan review.

## Non-Goals

- No telemetry, cloud upload, remote support endpoint, auto-submission, or
  background export.
- No unredacted logs, crash dumps, IPC traces, support bundles, helper stderr,
  native logs, Plex payloads, auth headers, tokenized URLs, native handles,
  local media paths, app-data paths, environment dumps, or Codex output.
- No production native-helper playback enablement, helper binary packaging, live
  Plex transport, live renderer Plex API, scheduler/channel runtime expansion,
  packaging/signing/installer/release-pipeline work, dependency addition,
  lockfile change, or persisted credential/settings schema change.
- No copied or adapted upstream Lineup source in RD-17 unless a reviewed replan
  names the exact upstream files and updates `docs/architecture/import-ledger.md`
  before or with the import.
- No automatic playback resume/replay after helper crash. RD-17 may prove that
  the helper process seam can recover and spawn a replacement for a later
  explicit command, while the current failed playback remains renderer-safe
  error state.

## Parent Architecture Alignment

RD-17 follows the Desktop roadmap item after RD-16. It depends on:

- RD-07 player/helper diagnostics and native-host process seam.
- RD-09 secret and app-data path boundaries.
- RD-12 stream/playback failure seams and helper-crash cleanup ownership.

Current architecture says renderer remains unprivileged, preload exposes only a
narrow validated bridge, Electron main owns app paths and privileged IPC, Plex
secrets stay in main/helper-only custody, and production player commands remain
unsupported until a later reviewed native-helper plan. RD-17 advances the local
diagnostics/support boundary only; it does not change the production playback
availability boundary.

Platform proof decision: Windows proof is required before RD-17 closeout. RD-17
touches native-helper crash/restart behavior, OS app-path/log/export behavior,
support-bundle filesystem output, and helper-observed diagnostic behavior. Unit
tests may use injected seams on any platform, but closeout cannot mark RD-17
complete until a Windows run records the named support-bundle and helper
crash/restart evidence under ignored `docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/`.

## Required Reading

Read in this order before editing:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-implement.md`
4. this plan
5. `docs/agentic/plan-authoring-standard.md`
6. `docs/architecture/CURRENT_STATE.md`
7. `docs/architecture/security-and-secret-flow.md`
8. `docs/architecture/playback-architecture.md`
9. `docs/architecture/file-shape-guardrails.md`
10. `docs/roadmap/desktop-port-roadmap.md`
11. Source files listed in the selected execution unit

Freshness gate: if any in-scope file, owner boundary, roadmap status, active
plan, app-path behavior, preload guard vocabulary, redaction verifier, or
native-host process behavior changed after this plan was written, stop and
refresh or re-review the plan before implementation.

## Required Skills

- `execution-plan-authoring`: keep the Tier 3 plan decision-complete without
  pseudo-code.
- `architecture-boundaries`: RD-17 changes IPC contracts, preload vocabulary,
  main ownership, helper reporting, and renderer-safe contracts.
- `persistence-boundaries`: support-bundle and diagnostic files are local
  filesystem/app-path output owned by main, not renderer or credential schema.
- `plex-integration-boundaries`: diagnostics must not leak Plex tokens, headers,
  URL setup, raw payloads, stream keys, selected-server internals, or private
  playback descriptors.
- `ui-composition-patterns`: the user-triggered export entry point lives in the
  renderer settings workflow and must preserve focus/keyboard cleanup.
- `verification-strategy`: RD-17 needs new public-seam tests plus Windows
  closeout proof.
- `review-request`: plan review and each implementation-unit review are
  required before advancing.
- `closeout-verification`: required before staging, committing, or calling RD-17
  complete.

## Evidence And Discovery

- `semantic_search_with_context`: Codanna index is current
  (`4470` symbols, semantic enabled, updated minutes before planning). Broad
  RD-17 diagnostics queries primarily returned `DesktopStreamPolicyUnknownCode`
  and forbidden-field constants, so Codanna was useful for index health but too
  broad for RD-17 scope.
- `semantic_search_docs`: broad RD-17 diagnostics/support-bundle search did not
  surface a focused roadmap chunk, so direct roadmap reads were required.
- Targeted Codanna symbols confirmed the existing owners:
  `redactMainProcessError` in `src/main/redactedDiagnostics.ts`,
  `DesktopPlayerAdapter` in `src/main/player/desktopPlayerAdapter.ts`,
  `NativePlayerHostProcess` in
  `src/main/player/nativePlayerHostProcess.ts`,
  `PlexPlaybackRuntime` in `src/main/player/plexPlaybackRuntime.ts`, and
  `resolveDesktopAppDataPaths` in `src/main/persistence/appDataPaths.ts`.
- Direct reads / `rg`: read the RD-17 roadmap section, global roadmap gates,
  current architecture, security/secret flow, playback architecture,
  file-shape guardrails, packaging release gates, redaction verifier, main
  redaction utility, player/preload/main IPC code, native-host process code,
  renderer settings surfaces, and current tests. Fallback to direct reads was
  necessary because the semantic search did not identify support-bundle owners.
- Impact analysis: not required before plan freeze because RD-17 is a new
  bounded feature surface with exact file owners and public seams named below;
  each implementation unit must use Codanna or direct reads for the selected
  symbols before editing.
- Official docs: no new external API, dependency, packaging, signing, or
  Electron behavior is being chosen in this planning pass. If an implementation
  unit changes Electron dialog, crash reporter, shell, or OS path assumptions
  beyond injected seams, it must check official Electron docs in that unit and
  record the checked date in review evidence.

## Impact Snapshot

- Owners that may change: renderer settings workflow, preload bridge, shared
  contracts, Electron main composition, main diagnostics/support-bundle files,
  app-data path resolution, player IPC, adapter/helper lifecycle reporting, and
  redaction verifier/tests.
- Public contracts that may change: new renderer-safe diagnostics contract,
  new diagnostics IPC channels, and a narrow `window.lineupDesktop.diagnostics`
  preload surface.
- Dependency, build-tool, configuration, and lockfile impact: no dependency,
  build-tool, or lockfile change is allowed. A package script is not required;
  any new smoke harness must be runnable by direct `node` command unless a
  reviewed unit explains why a script is needed.
- User-visible behavior that may change: settings gains a support-bundle export
  action and export status. Player/helper failures may surface clearer
  renderer-safe recovery diagnostics. No playback availability, Plex transport,
  credential persistence, scheduler/channel behavior, packaging behavior, or
  release policy may change.
- Local-only artifacts: Windows proof and exported test bundles belong under
  ignored `docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/`.
- First execution unit remains single-owner at the contract/redaction seam. IPC,
  renderer UI, and Windows proof are later units and must not be bundled into
  Unit 1.

## Architecture Health

File-shape evidence from `docs/architecture/file-shape-guardrails.md` and
`wc -l` during planning:

- `src/main/player/desktopPlayerAdapter.ts`: 1279 lines, hard-overage.
- `src/main/player/plexPlaybackRuntime.ts`: 798 lines.
- `src/contracts/player.ts`: 703 lines.
- `src/main/plex/streamResolver.ts`: 659 lines.
- `src/preload/index.cts`: 581 lines.
- `src/main/player/nativePlayerHostProcess.ts`: 505 lines.
- `src/main/index.ts`: 288 lines.
- `src/main/redactedDiagnostics.ts`: 115 lines.
- `src/contracts/redaction.ts`: 26 lines.
- `tools/verify-redaction.mjs`: 210 lines.

Plan: avoid growing the large player/runtime/resolver files with support-bundle
policy. New diagnostics behavior belongs in focused main diagnostics modules,
with only narrow hooks in player/native-host/preload/main composition. Preload
is already allowlisted and must stay single-file-compatible, so any new bridge
vocabulary must be exact, parity-tested, and accompanied by a reviewed
`docs/architecture/file-shape-guardrails.md` row update if the file grows above
its current baseline. `desktopPlayerAdapter.ts` and
`nativePlayerHostProcess.ts` must not absorb bundle export, filesystem,
renderer UI, or broad logging policy; if helper diagnostics require more than a
small injected sink/hook, extract a same-owner helper diagnostics module in the
same unit before adding behavior. Do not raise file-shape baselines to
pre-authorize future growth.

Maintainability verification route: every implementation unit that changes
production source shape runs `npm run verify:maintainability` directly or via
`npm run verify:architecture`; closeout runs full `npm run verify`.

## Files In Scope

Planning artifact for this pass:

- `docs/plans/rd-17-diagnostics-crash-recovery-support-bundle.md`

Future implementation files, only within the bounded units below:

- `src/contracts/diagnostics.ts` (new)
- `src/contracts/redaction.ts`
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `src/main/redactedDiagnostics.ts`
- `src/main/diagnostics/diagnosticEventStore.ts` (new)
- `src/main/diagnostics/supportBundleExporter.ts` (new)
- `src/main/diagnostics/supportBundleIpc.ts` (new)
- `src/main/diagnostics/supportBundlePaths.ts` (new, exact owner for support
  bundle parent/target path policy)
- `src/main/index.ts`
- `src/main/player/playerIpc.ts`
- `src/main/player/nativePlayerHostPort.ts`
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/player/desktopPlayerAdapter.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/preload/index.cts`
- `src/renderer/global.d.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/workflow.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/index.ts`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/styles/responsive-accessibility.css`
- `src/__tests__/contracts/contracts.test.ts`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- `src/__tests__/main/playerIpc.test.ts`
- `src/__tests__/main/player/desktopPlayerAdapter.test.ts`
- `src/__tests__/main/player/nativePlayerHostProcess.test.ts`
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/diagnostics/*.test.ts` (new)
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`
- `tools/verify-redaction.mjs`
- `tools/rd17-diagnostics-smoke.mjs` (new, required direct command harness for
  Windows proof)
- `docs/architecture/file-shape-guardrails.md` when a guarded file grows
- `docs/architecture/CURRENT_STATE.md` at closeout
- `docs/roadmap/desktop-port-roadmap.md` at closeout

## Files Out Of Scope

- `package-lock.json`, dependency manifests beyond any reviewed script need,
  Electron packaging config, installer/signing/update files, and release
  pipeline files.
- `src/main/plex/**` live transport, auth/discovery runtime composition,
  selected-server persistence schema, and Plex library network owners.
- `src/domain/**` scheduler/channel runtime behavior.
- Production native-helper binary source, bundled media binaries, libmpv product
  binding, and packaging layout.
- `docs/architecture/import-ledger.md` unless a reviewed replan explicitly
  imports or adapts upstream source.
- Any local support-bundle output outside ignored `docs/runs/**` during tests.

## Invariants And Scope Rules

- Renderer may request diagnostics actions and display renderer-safe status
  only; it must never receive raw Electron objects, filesystem path custody,
  app-data paths, native handles, helper stderr, raw process data, raw Plex
  payloads, tokens, auth headers, tokenized URLs, private playback descriptors,
  local media paths, or unredacted diagnostics.
- Preload may expose only the reviewed diagnostics methods below. It must guard
  inputs/results/events and must not expose arbitrary IPC, channel strings,
  Node APIs, Electron APIs, filesystem access, or broad RPC.
- Main owns diagnostics storage, app-path/export path resolution, redaction,
  support-bundle assembly, support-bundle filesystem writes, Electron dialog
  interaction if used, and crash/restart reporting.
- Native-helper output cannot bypass redaction. Stdout/stderr/crash output may
  enter diagnostics only through a bounded, truncating, redacting main-owned
  sink.
- No diagnostic record, support bundle, fixture, IPC trace, test output, doc, or
  Codex output may contain forbidden credential, Plex, native-handle, raw-path,
  raw-process, or privileged-field material.
- Dependency/security/licensing/provenance policy: no new dependency or
  generated third-party code is in scope. Any future dependency request is a
  replan trigger and must name runtime owner, security posture, licensing,
  provenance, lockfile impact, and rollback path.

## Diagnostics Contract Decisions

Unit 1 must freeze these exact renderer-safe contract values in
`src/contracts/diagnostics.ts`; later units may consume them but must not invent
alternate names or shapes.

Schema/version values:

- `DIAGNOSTIC_SCHEMA_VERSION = 1`
- `DIAGNOSTIC_REDACTION_VERSION = 'rd17-redaction-v1'`
- `SUPPORT_BUNDLE_SCHEMA_VERSION = 1`

Diagnostic surfaces:

- `renderer`
- `preload`
- `main`
- `player-ipc`
- `desktop-player-adapter`
- `native-host-process`
- `plex-playback-runtime`
- `support-bundle`
- `redaction`

Diagnostic categories:

- `lifecycle`
- `ipc`
- `validation`
- `playback`
- `helper-crash`
- `helper-restart`
- `cleanup`
- `support-bundle-export`
- `redaction-scan`
- `security-boundary`
- `unknown`

Diagnostic severities:

- `debug`
- `info`
- `warning`
- `error`

Diagnostic statuses:

- `observed`
- `started`
- `succeeded`
- `failed`
- `rejected`
- `ignored`
- `redacted`
- `truncated`
- `cancelled`

Diagnostic result shapes:

- success: `{ ok: true, requestId: string, value: T }`
- failure: `{ ok: false, requestId: string, error: DiagnosticsError }`
- cancellation: `{ ok: false, requestId: string, cancelled: true, error:
  DiagnosticsError }`

`DiagnosticsError` is renderer-safe only:

- `code`: one of `DIAGNOSTICS_UNAUTHORIZED`,
  `DIAGNOSTICS_VALIDATION_FAILED`, `DIAGNOSTICS_EXPORT_CANCELLED`,
  `DIAGNOSTICS_EXPORT_FAILED`, `DIAGNOSTICS_REDACTION_FAILED`,
  `DIAGNOSTICS_UNAVAILABLE`, or `DIAGNOSTICS_UNKNOWN`
- `message`: safe user-facing text with no raw paths or secret-shaped content
- `recoverable`: boolean
- `retryable`: boolean
- `diagnostic`: optional safe `DiagnosticRecord`

`DiagnosticRecord` shape:

- `schemaVersion`: `1`
- `id`: generated safe id
- `timestampMs`: finite non-negative number
- `surface`: one diagnostic surface
- `category`: one diagnostic category
- `severity`: one diagnostic severity
- `status`: one diagnostic status
- `operation`: non-empty safe string, max 80 characters
- `message`: safe string, max 512 characters after redaction
- `requestId`: optional non-empty safe string, max 120 characters
- `result`: optional `success`, `failure`, `cancelled`, or `ignored`
- `context`: optional flat safe key/value object after recursive redaction and
  truncation
- `truncation`: optional counts for message/context/native-output truncation

`context` rules:

- max 16 entries;
- keys max 64 characters and must not match forbidden diagnostic fields;
- string values max 256 characters after redaction;
- number/boolean/null values allowed;
- arrays, nested objects, functions, Electron objects, Node objects, Errors,
  Buffers, process objects, and native handles are rejected or summarized before
  storage.

Renderer-originated payload vocabulary for Unit 4:

- `DiagnosticsRendererEventEnvelope`: `{ requestId, event }`
- `event.surface` must be `renderer`
- allowed renderer categories are `lifecycle`, `validation`, `ipc`, and
  `support-bundle-export`
- allowed renderer severities are `info`, `warning`, and `error`
- renderer may provide `operation`, `message`, and safe flat `context` only
- renderer may not provide ids, timestamps, filesystem values, redaction report
  fields, native output, helper crash details, player snapshots, or environment
  summaries

Summary/result vocabulary:

- `DiagnosticsSummary`: schema version, redaction version, bounded record count,
  last event timestamp, surface counts, severity counts, last export status, and
  redaction failure count.
- `SupportBundleExportResult`: bundle id, safe bundle directory name, created
  timestamp, file count, byte count, included file names, redaction report, and
  status `succeeded`; no absolute path.
- `SupportBundleExportFailure`: safe diagnostics error plus status `failed` or
  `cancelled`; no absolute path.

Forbidden diagnostic field policy:

- The recursive forbidden key set is the union of current player/IPC/persistence
  forbidden keys plus `path`, `filePath`, `directory`, `userData`, `home`,
  `username`, `env`, `argv`, `pid`, `process`, `stderr`, `stdout`,
  `crashDump`, `minidump`, `stack`, `rawLog`, `rawIpc`, `mediaPath`,
  `localPath`, `serverUri`, `connectionUri`, `privatePlaybackDescriptor`,
  `headers`, `authorization`, `token`, `credential`, and `secret`.
- If a forbidden key appears in renderer payloads, helper output, IPC traces, or
  diagnostic context, reject the renderer command or store only a generic
  redaction diagnostic that does not echo the key value.
- Redaction may preserve safe category/status/code vocabulary, but must not
  preserve raw secret-shaped values, raw URLs, raw paths, or raw native/process
  identifiers.

Truncation limits:

- single raw diagnostic input accepted by main before redaction: 64 KiB;
- stored `message`: 512 characters;
- stored `operation`: 80 characters;
- stored `requestId`: 120 characters;
- stored context key: 64 characters;
- stored context string value: 256 characters;
- stored context entries: 16;
- native stdout/stderr/crash-output sample after redaction: 1024 characters per
  event, with only count/bytes/truncated status exported;
- in-memory diagnostic store: newest 500 records;
- exported `diagnostics.ndjson`: newest 500 records and maximum 1 MiB before the
  completed-bundle scan.

Scanner/report contract:

- `RedactionScanReport`: redaction version, scanned file count, scanned byte
  count, finding count, findings by label, truncated record count, omitted file
  count, status `passed` or `failed`, and timestamp.
- A passed report may be written into the bundle. A failed report may only be
  returned as a renderer-safe failure and stored as a sanitized local diagnostic;
  the incomplete bundle must be deleted when possible.
- Scanner labels stay generic, such as `token-query-parameter`,
  `raw-auth-header`, `credential-scheme`, `header-map-credential`,
  `secret-field-value`, `privileged-diagnostic-field-value`,
  `oauth-token-path-segment`, `raw-filesystem-path`, `raw-process-data`,
  `native-handle`, and `raw-ipc-frame`.

## Diagnostics Surfaces

Tested by RD-17 before closeout:

- Main redaction utility and repository redaction scanner.
- Main diagnostics event store with bounded retention and safe serialization.
- Renderer-originated diagnostic events accepted only through the reviewed
  diagnostics IPC command.
- Player IPC cleanup/failure diagnostics.
- Desktop player adapter helper crash and stale-event diagnostics.
- Native-host process spawn, close, timeout, malformed-output, stderr,
  cleanup/reap, and restart-after-failure reporting.
- Plex playback runtime helper-crash cleanup reason and safe event projection.
- Support-bundle manifest, diagnostics log, crash/recovery summary, safe player
  snapshot, environment summary, and redaction report.
- Preload diagnostics method guards and contract vocabulary parity.
- Windows support-bundle filesystem output and helper-observed diagnostics.

Explicitly untested or out of scope for RD-17:

- Production native-helper playback with real Plex media.
- Live Plex network failures, live credential refresh, and live PMS cleanup
  against a real server.
- Binary crash dumps, minidumps, OS crash reporter integration, telemetry, cloud
  upload, signing/packaging, auto-update, and installer diagnostics.
- macOS/Linux platform export proof beyond local automated injected-path tests.

## Support-Bundle Filesystem Ownership

Exact owner: `src/main/diagnostics/supportBundlePaths.ts` owns support-bundle
path policy. Do not extend `src/main/persistence/appDataPaths.ts` for RD-17;
credential/selected-server persistence paths stay separate from diagnostics
export paths.

Target shape: support bundles are directories, not archives. Archive creation
is out of scope because it would add packaging/compression policy without
improving the RD-17 redaction proof.

User selection policy:

- User action opens a main-owned directory picker for a parent folder.
- In tests and the Windows smoke harness, the parent folder is injected by main
  test seams or command-line harness options.
- Renderer never supplies the parent folder, destination folder, file name, or
  archive path.
- Main creates a new child directory named
  `lineup-desktop-support-<safeBundleId>` inside the selected parent.
- `safeBundleId` is generated by main from timestamp plus safe random suffix and
  contains only ASCII letters, digits, and hyphens.
- If the child directory already exists, main must fail safely or generate a new
  bundle id; it must not merge into an existing directory.
- Main writes only inside that newly created child directory, scans the completed
  directory, and returns success only after the scan passes.

Renderer-visible export result:

- `status`: `succeeded`
- `bundleId`
- `bundleDirectoryName`
- `createdAtMs`
- `fileCount`
- `byteCount`
- `includedFiles`
- `redactionReport`

Renderer-visible failure/cancel result:

- `status`: `failed` or `cancelled`
- safe `DiagnosticsError`
- optional `redactionReport` only when it is safe and contains no paths

Renderer never receives absolute parent path, child path, app-data path,
temporary path, OS username, drive letter, UNC path, or shell item object.

## Support-Bundle Contents

The exported bundle is the main-created directory described above. The renderer
receives success/failure/cancel status, bundle id, safe bundle directory name,
file count, byte count, included file names, and timestamp only; it does not
receive an absolute path.

Required contents:

- `manifest.json`: schema version, bundle id, created timestamp, app version,
  platform family, shell mode, redaction version, included surfaces, and
  explicit omissions.
- `diagnostics.ndjson`: bounded redacted records from renderer, main,
  player/runtime, and native-host surfaces.
- `crash-recovery.json`: helper crash/restart attempts, cleanup outcomes,
  request ids, safe error categories/codes, and timestamps.
- `player-snapshot.json`: renderer-safe `PlayerSnapshot` or an inert snapshot.
- `environment.json`: safe app/runtime summary without env vars, usernames,
  absolute paths, local media paths, process args, or machine identifiers.
- `redaction-report.json`: scanner version, scanned file count, finding count,
  truncation counts, and pass/fail result.

Forbidden contents:

- Raw logs, raw crash dumps, raw IPC frames, raw stdout/stderr, native handles,
  process args, env vars, app-data paths, user profile paths, local media paths,
  tokenized URLs, auth headers, Plex tokens, raw Plex payloads, private playback
  descriptors, stream keys, part keys, or unredacted helper messages.

## IPC And Preload Vocabulary

If implementation adds the support-bundle API, use this exact renderer-safe
vocabulary unless plan review changes it before implementation:

- `LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL =
  'lineup:diagnostics:recordRendererEvent'`
- `LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL =
  'lineup:diagnostics:getSummary'`
- `LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL =
  'lineup:diagnostics:exportSupportBundle'`

Preload surface:

- `window.lineupDesktop.diagnostics.recordRendererEvent(envelope)`
- `window.lineupDesktop.diagnostics.getSummary()`
- `window.lineupDesktop.diagnostics.exportSupportBundle()`

Authorization and user gesture/export policy:

- All diagnostics IPC handlers use the existing shell sender/origin/main-frame
  authorization gate.
- Renderer cannot pass an output path. Main owns the save dialog or an injected
  export path in tests/smoke.
- Export is initiated only by the settings UI action or by an injected smoke
  harness path. Background export and automatic upload are forbidden.
- Main writes to a newly created bundle target and scans the completed output
  before returning success.
- If redaction scan fails, main deletes the incomplete bundle when possible,
  returns a renderer-safe failure, records only a sanitized failure diagnostic,
  and stops the unit for investigation.

Rollback path:

- Remove the diagnostics preload methods and channel constants.
- Remove diagnostics IPC registration from `src/main/index.ts`.
- Leave existing player/shell IPC behavior unchanged.
- Delete generated local proof under ignored `docs/runs/**`.

## Crash And Recovery Scenarios

RD-17 must test and document:

- helper spawn failure normalizes to renderer-safe helper failure and records no
  raw process/path data;
- helper closes while a command is pending, settling the command with safe
  failure and keeping the Electron UI alive;
- helper closes while idle, emitting safe lifecycle diagnostics;
- helper times out, is quarantined/reaped, and a later explicit command can
  spawn a replacement helper;
- helper emits malformed or oversized output, is quarantined, and does not leak
  the raw output;
- helper stderr/crash output containing forbidden-shaped material is redacted or
  dropped before diagnostics storage;
- cleanup failure records safe diagnostic status without preserving raw error
  text;
- Plex playback runtime `helper-crash` cleanup emits only safe events and
  releases injected PMS/player resources;
- support bundle includes crash/restart summary without raw crash output.

## Implementation Units

Unit 1: Redaction and diagnostics contract foundation.

- Owner/files: `src/contracts/diagnostics.ts`,
  `src/contracts/redaction.ts`, `src/main/redactedDiagnostics.ts`,
  `tools/verify-redaction.mjs`, `src/__tests__/contracts/contracts.test.ts`,
  `tools/__tests__/verify-redaction.test.mjs`, and new
  `src/__tests__/main/diagnostics/redaction.test.ts`.
- Scope: define renderer-safe diagnostic record/result vocabulary, redaction
  versioning, forbidden diagnostic fields, truncation policy, and bundle scanner
  expectations. Keep main redaction primitive focused; do not add IPC, renderer
  UI, app paths, or bundle export yet.
- Accepted Unit 1 fix scope after implementation review: diagnostic sanitizer
  redaction, scanner label alignment, verifier pattern coverage for raw
  filesystem path, raw process data, native handle, and raw IPC frame patterns,
  and the staging note below. Do not broaden Unit 1 into IPC, renderer UI,
  support-bundle export, player/native-host lifecycle hooks, or `.gitignore`
  changes.
- Staging note: if `src/__tests__/main/diagnostics/redaction.test.ts` is hidden
  by the existing global `diagnostics/` ignore pattern, it may be force-added at
  staging as an approved Unit 1 closeout/staging action. No `.gitignore` edit is
  required or approved for Unit 1.
- Verification:
  - `npm run typecheck`
    - Expected: new diagnostics/redaction contract types compile without
      widening existing player, IPC, persistence, or shell contracts beyond the
      Unit 1 scope.
  - `npm run test:contracts -- --test-name-pattern "diagnostics|redaction|contracts"`
    - Expected: tests prove exact diagnostic surfaces/categories/severities/
      statuses/result shapes, `rd17-redaction-v1`, truncation limits, forbidden
      diagnostic field rejection/redaction, and scanner report shape.
  - `npm run test:harness-docs -- --test-name-pattern "verify-redaction"`
    - Expected: verifier tests prove the new scanner patterns and labels cover
      raw filesystem paths, raw process data, native handles, and raw IPC frames
      without flagging the approved redacted placeholders.
  - `npm run verify:redaction`
    - Expected: repo scan passes with no forbidden diagnostic material in new
      fixtures, tests, contracts, docs, or verifier patterns.
  - `npm run verify:maintainability`
    - Expected: no unreviewed large-file or topology regression.
- Review gate: read-only implementation review before Unit 2.

Unit 2: Main diagnostics store and support-bundle exporter.

- Owner/files: new `src/main/diagnostics/diagnosticEventStore.ts`,
  `src/main/diagnostics/supportBundleExporter.ts`,
  `src/main/diagnostics/supportBundlePaths.ts`,
  `src/main/redactedDiagnostics.ts`, `tools/verify-redaction.mjs`, and new
  `src/__tests__/main/diagnostics/supportBundleExporter.test.ts`.
- Scope: main-owned bounded event store, safe serialization, app/export path
  ownership in `supportBundlePaths.ts`, main-created support-bundle directory
  target, bundle content assembly, completed-bundle redaction scan, failure
  cleanup, and no absolute path in renderer-safe results. Use injected
  filesystem/dialog/parent-folder seams in tests.
- Verification:
  - `npm run typecheck`
    - Expected: diagnostics store/exporter/path seams compile without requiring
      Electron runtime imports in tests or persistence schema changes.
  - `npm run test:contracts -- --test-name-pattern "support bundle|diagnostics"`
    - Expected: tests prove bounded retention, safe serialization, directory
      target creation under an injected parent, required bundle contents,
      no absolute path in renderer-safe result, scan-before-success, failed-scan
      cleanup, and safe failure/cancel envelopes.
  - `npm run verify:redaction`
    - Expected: repository and generated fixture scan passes; bundle fixtures
      contain no raw path, secret, native, process, IPC, or Plex material.
  - `npm run verify:architecture`
    - Expected: lint and maintainability pass with diagnostics ownership kept
      under `src/main/diagnostics/**`.
- Review gate: read-only implementation review before Unit 3.

Unit 3: Player/native-host crash recovery and diagnostic reporting.

- Owner/files: `src/main/player/nativePlayerHostPort.ts`,
  `src/main/player/nativePlayerHostProcess.ts`,
  `src/main/player/playerIpc.ts`,
  `src/main/player/desktopPlayerAdapter.ts`,
  `src/main/player/plexPlaybackRuntime.ts`,
  `src/main/diagnostics/diagnosticEventStore.ts`,
  `src/__tests__/main/player/nativePlayerHostProcess.test.ts`,
  `src/__tests__/main/player/desktopPlayerAdapter.test.ts`,
  `src/__tests__/main/playerIpc.test.ts`, and
  `src/__tests__/main/player/plexPlaybackRuntime.test.ts`.
- Scope: hook player/helper lifecycle diagnostics into the store, prove restart
  for a later explicit command after quarantine/reap, preserve safe error state
  for the failed request, and add crash/restart summary data for Unit 2 export.
  Keep production native-helper playback unsupported.
- Verification:
  - `npm run typecheck`
    - Expected: player/native-host diagnostics hooks compile without changing
      public player command semantics or enabling production native playback.
  - `npm run test:contracts -- --test-name-pattern "native host process|desktop player adapter|player IPC|plex playback runtime"`
    - Expected: tests prove spawn failure, pending-command close, idle close,
      timeout quarantine/reap, malformed/oversized output quarantine,
      redacted-or-dropped stderr/crash output, cleanup failure diagnostics,
      replacement helper on later explicit command, and Plex runtime
      `helper-crash` cleanup summary.
  - `npm run verify:redaction`
    - Expected: crash/restart fixtures, helper-output fixtures, IPC traces, and
      diagnostics output scan clean.
  - `npm run verify:architecture`
    - Expected: no unreviewed growth in hard-overage player/runtime files and no
      support-bundle filesystem policy in player owners.
- Review gate: read-only implementation review before Unit 4.

Unit 4: Diagnostics IPC, preload bridge, and settings export action.

- Owner/files: `src/contracts/ipc.ts`, `src/contracts/shell.ts`,
  `src/contracts/diagnostics.ts`, `src/preload/index.cts`,
  `src/main/diagnostics/supportBundleIpc.ts`, `src/main/index.ts`,
  `src/renderer/global.d.ts`, `src/renderer/staticDom.ts`,
  `src/renderer/domBindings.ts`, `src/renderer/settingsSetup.ts`,
  `src/renderer/workflow.ts`, `src/renderer/routeDom.ts`,
  `src/renderer/index.ts`, renderer CSS files listed in scope, contract tests,
  preload parity test, and focused renderer tests.
- Scope: add the exact diagnostics IPC/preload vocabulary from this plan, main
  authorization, renderer settings action, export status, and focus-safe user
  gesture path. Renderer must not pass or receive export filesystem paths.
- Verification:
  - `npm run typecheck`
    - Expected: diagnostics IPC/preload/renderer contracts compile and the
      `LineupDesktopPreloadApi` shape includes only the reviewed diagnostics
      methods.
  - `npm run test:contracts -- --test-name-pattern "diagnostics|preload|workflow|route DOM"`
    - Expected: tests prove exact diagnostics channel constants, preload guard
      vocabulary parity, main authorization, renderer settings user gesture,
      safe export status rendering, and no renderer-supplied or renderer-visible
      filesystem path.
  - `npm run smoke:electron`
    - Expected: existing shell/player smoke still boots and renderer privilege
      denial remains intact with the new preload surface.
  - `npm run verify:redaction`
    - Expected: IPC/preload/renderer fixtures and smoke evidence scan clean.
  - `npm run verify:architecture`
    - Expected: preload shape/parity and maintainability checks pass; any
      reviewed preload guardrail update is present if line count grows.
- Review gate: read-only implementation review before Unit 5.

Unit 5: Windows proof harness and RD-17 closeout docs.

- Owner/files: `tools/rd17-diagnostics-smoke.mjs`,
  `docs/architecture/file-shape-guardrails.md` if guarded files grew,
  `docs/architecture/CURRENT_STATE.md`,
  `docs/roadmap/desktop-port-roadmap.md`, and ignored local evidence under
  `docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/`.
- Scope: implement and run the required Windows proof harness for helper
  crash/restart reporting,
  support-bundle filesystem output, app-path/export ownership, helper-observed
  diagnostics, and completed-bundle redaction scan. Update durable docs only
  after observed proof and clean implementation review.
- Verification:
  - Windows `node tools/rd17-diagnostics-smoke.mjs --out docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke`
    - Expected: exits `0` and writes ignored evidence containing
      `manifest.json`, `summary.json`, `redaction-report.json`,
      `support-bundle/manifest.json`, `support-bundle/diagnostics.ndjson`,
      `support-bundle/crash-recovery.json`,
      `support-bundle/player-snapshot.json`,
      `support-bundle/environment.json`, and
      `support-bundle/redaction-report.json`.
    - Expected summary facts: platform is `win32`; helper crash detected;
      Electron/main process remains alive; failed request is safe error state;
      helper cleanup/reap observed; later explicit command uses replacement
      helper; support bundle target is a main-created directory under the
      injected parent; renderer-visible result contains bundle id/directory name
      only; completed-bundle scan status is `passed`; no forbidden raw path,
      secret, native, process, IPC, or Plex material is present.
  - Windows `npm run verify:redaction`
    - Expected: repository scan and Windows smoke evidence scan pass.
  - Windows `npm run verify`
    - Expected: full verification passes in the Windows proof environment.
  - `npm run verify:docs` after roadmap/current-state updates
    - Expected: docs verifier passes with RD-17 durable closeout updates.
- Review gate: final read-only implementation review before RD-17 closeout.

Parallelism: only read-only discovery/review sidecars may run in parallel.
Implementation units are sequential because contract, redaction, IPC, and
platform-proof decisions are shared.

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions are
   resolved for implementation start; Windows proof remains an explicit closeout
   gate, not an ambiguity.
2. Adjacent contract/preload/main/renderer files that may need changes are in
   scope for the unit that owns them.
3. No file is frozen out of scope while this plan relies on hidden wiring inside
   it.
4. Evidence path and direct-read fallback from broad Codanna results are
   recorded.
5. Work is assigned to repo-preferred owners; large player/preload/main files
   receive only narrow hooks, with extraction or guardrail updates required
   before growth.
6. Tier 3 Architecture Health is included before implementation unit selection,
   with file-shape evidence and avoidance/decomposition decisions.
7. A fresh implementer does not need to invent security, IPC, playback,
   persistence, packaging, import, support-bundle, or verification policy.
8. Verification commands, expected outcomes, review gates, acceptance criteria,
   rollback, and replan triggers are explicit.

## Architecture Seam Decision Gate

Chosen seam: main-owned local diagnostics/support-bundle boundary with a narrow
renderer/preload command surface and injected player/native-host diagnostic
hooks.

Renderer owns only the settings action, focus-safe status display, and
renderer-originated safe diagnostic events. Preload owns exact method guards and
typed invocation. Main owns authorization, event storage, redaction, app paths,
export path selection, filesystem writes, bundle scans, and failure cleanup.
Player/runtime/native-host owners emit safe lifecycle facts into main
diagnostics but do not own support-bundle policy.

Forbidden shortcuts:

- broad IPC/RPC channel, arbitrary channel strings, renderer-supplied output
  paths, renderer filesystem access, direct Electron/Node exposure, raw helper
  logs, raw crash dumps, unscanned bundle output, compatibility shims, old
  upstream path mirrors, production native-helper playback enablement, live Plex
  transport, or dependency/lockfile changes.

Stop and replan if implementing the chosen seam requires renderer path custody,
raw helper output, production helper playback, live Plex network access,
packaging behavior, credential/settings schema changes, copied upstream source,
new dependencies, or significant growth in hard-overage owners.

## Verification Commands

Verification classification: new regression/contract test required

Planning-only pass:

- `npm run verify:docs`
  - Expected: passes with the new active plan shape and exactly one
    classification marker.

Per-unit implementation commands are named in `## Implementation Units`.
RD-17 closeout commands:

- `npm run typecheck`
  - Expected: no TypeScript errors.
- `npm run verify:architecture`
  - Expected: lint and maintainability checks pass; any guarded file growth has
    a reviewed guardrail update.
- `npm run test`
  - Expected: contracts, diagnostics, support-bundle, player/native-host,
    preload, and renderer tests pass.
- `npm run verify:docs`
  - Expected: active plan, roadmap/current-state updates, and docs harness pass.
- `npm run verify:redaction`
  - Expected: repo scan passes with no forbidden diagnostic material.
- `npm run smoke:electron`
  - Expected: existing shell/player bridge smoke still passes.
- `npm run verify`
  - Expected: full repo verification passes before implementation closeout.
- Windows proof command:
  `node tools/rd17-diagnostics-smoke.mjs --out docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke`
  - Expected: records passed helper crash/restart reporting, support-bundle
    filesystem output, app-path/export ownership, helper-observed diagnostics,
    and bundle redaction scan under ignored local evidence.

## Acceptance Criteria

- Redaction tests cover logs, fixtures, crash output, IPC traces, and exported
  bundles.
- Native logs/helper output cannot bypass redaction and cannot be included
  unscanned.
- Support bundle contains the required files and explicit omissions, with no
  forbidden credential, Plex, native, path, process, or raw diagnostic material.
- Renderer-facing diagnostics contracts and preload methods expose only safe
  status/results and never expose absolute export paths.
- Helper crash/restart reporting proves the Electron UI stays alive, the failed
  request enters safe error state, cleanup/reap occurs, and a later explicit
  command can use a replacement helper.
- Production player commands remain unsupported in production shell mode.
- No telemetry/cloud upload, production native-helper playback, live Plex
  transport, packaging/signing, dependencies, lockfile changes, credential
  schema changes, or upstream source imports are introduced.
- Windows proof is recorded before RD-17 closeout.
- Plan review, per-unit implementation reviews, final implementation review,
  and closeout verification have no material blockers.

## Replan Triggers

- Any raw credential, auth header, tokenized URL, local media path, native
  handle, raw helper output, raw crash data, app-data path, process args, env
  var, or raw Plex payload appears in a renderer-facing surface, bundle, fixture,
  docs, tests, verifier output, or Codex output.
- Renderer must pass an export path or receive an absolute path to complete the
  feature.
- Native-helper crash/restart proof requires production playback enablement,
  helper binary packaging, live Plex transport, or a real Plex server.
- Windows support-bundle or helper crash/restart proof cannot be run or fails in
  a way that invalidates the injected-seam design.
- Preload, `desktopPlayerAdapter.ts`, `nativePlayerHostProcess.ts`, or
  `plexPlaybackRuntime.ts` grows beyond reviewed guardrails without extraction
  or guardrail update.
- Electron dialog, app path, or crash-reporter behavior requires official docs
  decisions not recorded in the active unit.
- A new dependency, lockfile change, copied/adapted upstream source, persisted
  schema change, or packaging/release change appears necessary.
- Any required verifier, smoke, redaction scan, plan review, or implementation
  review reports a material blocker.

## Rollback Notes

- Each implementation unit should be independently reversible.
- Unit 1 rollback removes new diagnostics contract/redaction changes and tests,
  restoring existing `redactMainProcessError` behavior.
- Unit 2 rollback removes main diagnostics store/exporter files and tests, with
  no persisted credential/settings migration to undo.
- Unit 3 rollback removes diagnostic hooks from player/native-host/runtime
  owners while preserving existing RD-07/RD-12 safe failure behavior.
- Unit 4 rollback removes diagnostics IPC constants, handlers, preload methods,
  renderer settings action/status, and related tests; existing shell/window/player
  APIs remain unchanged.
- Unit 5 rollback removes only closeout doc updates and ignored local evidence
  if proof is invalidated. Do not remove previous completed roadmap evidence.
- Any partially written support bundle from failed tests must be deleted or left
  only under ignored `docs/runs/**` after redaction scan passes.

## Commit Checkpoints

- Planning pass: one docs commit after plan review, e.g.
  `docs(plan): add rd-17 diagnostics plan`.
- Implementation: prefer one focused commit per reviewed unit.
- Keep workflow/control-plane or guardrail doc updates separate from product
  implementation when practical.
- Do not stage unrelated local changes or ignored support-bundle output.
- Before any commit or closeout claim, run the verification named for the unit
  and record observed output in the handoff or closeout summary.

MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: GPT-5 Codex high reasoning
REVIEWER: GPT-5 Codex high reasoning
WHY: Tier 3 work crosses Electron IPC/security, preload guards, renderer UI,
main-owned filesystem output, redaction, and native-helper lifecycle behavior.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Complete RD-17 Diagnostics, Crash Recovery, And Support Bundle Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-17-diagnostics-crash-recovery-support-bundle.md
ARTIFACT: active tracked plan
FILES:
- docs/plans/rd-17-diagnostics-crash-recovery-support-bundle.md
BLOCKERS: none
MESSAGE:
Review the active RD-17 plan read-only before implementation. Prioritize IPC/preload vocabulary, redaction and support-bundle invariants, file-shape decisions, Windows proof requirements, bounded unit sequencing, and whether Unit 1 is implementation-ready. RD-17 closeout requires Windows proof for native-helper crash/restart reporting, support-bundle filesystem output, app-path/export ownership, helper-observed diagnostics, and exported-bundle redaction.
