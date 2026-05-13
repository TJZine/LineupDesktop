# File Shape Guardrails

Lineup Desktop treats file shape as an architecture surface. Large files are not
forbidden, but unreviewed growth in composition roots, runtime owners, contracts,
and CSS makes later feature work harder to review and easier to couple.

## Policy

- Production files under `src/**` over 500 lines require a temporary row in the
  allowlist below. The row records a reviewed baseline line count. Current line
  count may shrink below that baseline, but it must not grow above it without a
  reviewed update to this file.
- Files over 800 lines are hard-overage files. They need an explicit
  decomposition trigger before further feature behavior grows that owner.
- Rows are not permanent exceptions. Remove a row when the file drops to 500
  lines or below.
- Row updates are review decisions, not bulk bookkeeping. Do not raise a
  baseline to pre-authorize future growth; raise it only with the source change
  that needs the additional size and record why decomposition is not the better
  move yet.
- New Tier 3 plans must include an `## Architecture Health` section with current
  large-file evidence, affected owner hotspots, and decomposition, avoidance, or
  allowlist decisions before implementation unit selection.
- Run `npm run verify:maintainability` after changing production source shape or
  this guardrail.

## Current Allowlist

| Path | Baseline lines | Rationale | Growth/decomposition trigger |
| --- | ---: | --- | --- |
| src/main/player/desktopPlayerAdapter.ts | 1279 | RD-07 adapter centralizes player command validation, fakeable native-host state, request custody, and safe diagnostics in one owner while the native-helper boundary is still settling; comment-only seam documentation records the reviewed adapter invariants. | Decompose before production native-helper playback adds new command families, helper capabilities, or renderer-facing diagnostics. |
| src/domain/channel/channelManager.ts | 1022 | RD-11 channel manager currently owns transactional channel mutation, persistence coordination, current-channel custody, and event emission invariants in one pure domain owner; comment-only seam documentation clarifies mutation serialization and current-channel persistence limits. | Split mutation queue, current-channel selection, and persistence coordination before adding live channel editing workflows or backup/restore behavior. |
| src/main/player/plexPlaybackRuntime.ts | 798 | RD-12 runtime keeps PMS lease custody, player dispatch, stale-event handling, and cleanup sequencing together while production playback remains fakeable. | Extract cleanup orchestration or stale-event custody before production native-helper playback or live Plex transport composition grows this file. |
| src/domain/channel/channelRepository.ts | 770 | RD-11 repository owns channel import normalization, source resolution, cache behavior, and stale fallback semantics in a pure domain owner; comment-only seam documentation records the normalization/repair mutation signal. | Split cache/source resolution from import normalization before live library browsing or persisted channel editing expands the repository. |
| src/contracts/player.ts | 703 | RD-07/RD-12 player contract vocabulary is intentionally centralized to keep renderer-safe command, event, snapshot, error, and guard vocabulary aligned; comment-only seam documentation clarifies forbidden-field guard limits. | Split stable sub-vocabularies only when a new public player contract family is added and parity tests can protect each module. |
| src/main/plex/streamResolver.ts | 662 | RD-12 stream resolver maps injected Plex media details into private playback descriptors and renderer-safe load payloads while keeping privileged setup private. | Split candidate mapping from descriptor projection before live Plex transport or additional stream modes are introduced. |
| src/main/player/streamPolicy/desktopStreamPolicy.ts | 627 | RD-08 stream policy keeps capability-driven direct play, direct stream, transcode, fallback, and unsupported decision logic together for deterministic fixture proof; comment-only seam documentation states the explicit-reason/unknown contract. | Split decision phases before adding new codec families, platform capability matrices, or subtitle/audio policy branches. |
| src/preload/index.cts | 1031 | RD-17 diagnostics suggestion remediation keeps the diagnostics summary and redaction report map validators in the sandbox-compatible preload entrypoint so key and numeric value validation stay beside the exact `lineupDesktop` exposure, channel constants, invoke methods, renderer-safe request ids/context values, and parity-tested result guards. | Extract stable guard families or introduce reviewed preload bundling before adding another bridge namespace, new diagnostics result family, arbitrary RPC, extra contextBridge exposure, or any bridge vocabulary growth not covered by the parity/shape harness. |
| src/contracts/diagnostics.ts | 553 | RD-17 centralizes diagnostics schema, renderer event envelopes, support-bundle result vocabulary, renderer-safe request-id and context-value shape, redaction labels, and sanitizer helpers while the diagnostics/support boundary is still being frozen across main, preload, player, and renderer seams. | Split sanitizer helpers from renderer-safe public vocabulary before adding another diagnostics schema version, export artifact family, scanner taxonomy, or non-RD-17 diagnostics surface. |
| src/domain/channel/channelAuthoringService.ts | 521 | Channel authoring keeps validation, draft normalization, and safe update shaping together while channel workflows remain pure and runtime-free. | Extract validation helpers before adding richer channel setup persistence or live library-driven authoring. |

### Preload Bridge Allowlist Note

ARCH-01 keeps guard vocabulary in the sandbox-compatible preload entrypoint while
the parity/shape harness checks channel constants, the single `lineupDesktop`
exposure, and approved `ipcRenderer` method/channel pairs against renderer-safe
IPC contracts without importing or executing preload.
