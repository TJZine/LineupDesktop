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
| src/main/player/desktopPlayerAdapter.ts | 1275 | RD-07 adapter centralizes player command validation, fakeable native-host state, request custody, and safe diagnostics in one owner while the native-helper boundary is still settling. | Decompose before production native-helper playback adds new command families, helper capabilities, or renderer-facing diagnostics. |
| src/domain/channel/channelManager.ts | 1017 | RD-11 channel manager currently owns transactional channel mutation, persistence coordination, current-channel custody, and event emission invariants in one pure domain owner. | Split mutation queue, current-channel selection, and persistence coordination before adding live channel editing workflows or backup/restore behavior. |
| src/renderer/styles.css | 857 | RD-13 intentionally kept renderer styling in one static CSS asset while the app avoided bundler, dependency, and protocol expansion. | Split CSS into copied static style modules before RD-14 or RD-15 adds more fullscreen, focus, cursor, or overlay styling. |
| src/renderer/index.ts | 850 | RD-13 renderer composition root wires route rendering, fake view models, DOM updates, and bridge smoke state while no frontend framework or bundler exists. | Split route DOM binding and renderer composition helpers before adding RD-14 input/window behavior. |
| src/main/player/plexPlaybackRuntime.ts | 798 | RD-12 runtime keeps PMS lease custody, player dispatch, stale-event handling, and cleanup sequencing together while production playback remains fakeable. | Extract cleanup orchestration or stale-event custody before production native-helper playback or live Plex transport composition grows this file. |
| src/domain/channel/channelRepository.ts | 766 | RD-11 repository owns channel import normalization, source resolution, cache behavior, and stale fallback semantics in a pure domain owner. | Split cache/source resolution from import normalization before live library browsing or persisted channel editing expands the repository. |
| src/contracts/player.ts | 695 | RD-07/RD-12 player contract vocabulary is intentionally centralized to keep renderer-safe command, event, snapshot, error, and guard vocabulary aligned. | Split stable sub-vocabularies only when a new public player contract family is added and parity tests can protect each module. |
| src/main/plex/streamResolver.ts | 662 | RD-12 stream resolver maps injected Plex media details into private playback descriptors and renderer-safe load payloads while keeping privileged setup private. | Split candidate mapping from descriptor projection before live Plex transport or additional stream modes are introduced. |
| src/main/player/streamPolicy/desktopStreamPolicy.ts | 625 | RD-08 stream policy keeps capability-driven direct play, direct stream, transcode, fallback, and unsupported decision logic together for deterministic fixture proof. | Split decision phases before adding new codec families, platform capability matrices, or subtitle/audio policy branches. |
| src/preload/index.cts | 575 | Sandboxed preload must stay single-file-compatible today, so guard vocabulary and bridge exposure live together without a bundler. | Revisit with an official preload bundling plan before adding any new preload surface or growing bridge vocabulary. |
| src/main/index.ts | 542 | Main composition currently combines secure shell creation, containment, development fake-player activation, and smoke-only assertions for the early desktop shell. | Split smoke assertions and runtime composition before adding RD-14 window/display/fullscreen behavior. |
| src/renderer/index.html | 541 | RD-13 kept the static DOM shell in one HTML asset while avoiding templating, bundlers, or protocol expansion. | Split renderer templates or introduce a reviewed static asset strategy before adding RD-14 or RD-15 UI surfaces. |
| src/domain/channel/channelAuthoringService.ts | 521 | Channel authoring keeps validation, draft normalization, and safe update shaping together while channel workflows remain pure and runtime-free. | Extract validation helpers before adding richer channel setup persistence or live library-driven authoring. |
| src/renderer/overlays.ts | 523 | RD-13 fake-backed overlay state keeps OSD, mini guide, channel number, badge, and playback options in one renderer-local module; the reviewed overlay hardening keeps action exhaustiveness and now-playing progress clamping in the same owner instead of prematurely splitting shared overlay state. | Split overlay state by overlay family before RD-15 integrates overlays over native video. |
| src/main/player/nativePlayerHostProcess.ts | 501 | RD-07 native host process owns child lifecycle, command framing, failure normalization, and cleanup/reap behavior in the main/player boundary. | Split framing or cleanup helpers before production native-helper protocol expands. |
