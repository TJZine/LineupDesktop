# RD-16 Subtitle, Audio, And HDR Hardening

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Controller phase:** scope-load/plan
**Verification classification:** new regression/contract test required
**Platform proof:** Windows proof required before closeout

## Goal

Harden the existing native playback policy seams for subtitle, audio, and HDR
behavior without turning on production native-helper playback. RD-16 must make
track identity unambiguous between Plex metadata, renderer-safe player state,
and future playback-engine/native ids; expand deterministic stream-policy and
Plex resolver coverage for forced/default subtitle decisions, language metadata
projection, audio
fallback, burn-in/conversion decisions, and conservative HDR/Dolby Vision
outcomes; and record a tested/untested media matrix before closeout.

The implementation must preserve the current production boundary: RD-16 may use
injected seams and dev-only native-presentation proof tooling, but it must not
claim production native playback support or live Plex transport support from
RD-15. RD-15 proved fake-backed renderer UI composition over the dev-only native
presentation boundary only.

## Non-Goals

- No production native-helper playback enablement.
- No live Plex network transport composition or renderer Plex API.
- No preload, product IPC, or renderer-facing contract expansion unless a
  reviewed replan proves the existing `PlayerTrackId` and player load policy
  shapes cannot safely carry RD-16 behavior.
- No packaging, dependency, lockfile, installer, signing, or release-gate work.
- No persisted credentials/settings changes.
- No copied/adapted upstream Lineup source unless a reviewed replan adds a
  bounded import scope and updates `docs/architecture/import-ledger.md` before
  or with the import.
- No Plex HTPC parity claim, codec/container parity claim, passthrough claim, or
  HDR/Dolby Vision support claim beyond the tested matrix.

## Parent Architecture Alignment

RD-16 aligns with the current main/player and main/Plex ownership model:

- `src/contracts/player.ts` owns renderer-safe player vocabulary. Public track
  ids stay opaque strings and must not encode Plex stream ids, engine ids,
  native handles, URLs, headers, or part keys.
- `src/main/player/streamPolicy/*` owns deterministic capability-driven policy
  for direct play, direct stream, transcode, unsupported decisions, and explicit
  unknowns.
- `src/main/plex/streamResolver.ts` owns Plex metadata to policy-candidate
  mapping and keeps privileged playback descriptors separate from renderer-safe
  player load payloads.
- `src/main/player/plexPlaybackRuntime.ts`,
  `src/main/player/plexPlaybackBridge.ts`, and
  `src/main/player/plexPlaybackComposition.ts` own injected Plex-to-player
  runtime handoff and cleanup custody only.
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` may be extended only
  as dev-only evidence tooling. It must remain outside product runtime
  architecture.

Renderer-safe track identity policy for all RD-16 units:

- Public `PlayerTrackId` values are UI/request-scope ids only. They are stable
  within one resolved playback candidate and current player request, but are not
  persisted as Plex or engine identifiers.
- Plex stream ids, Plex part keys, stream keys, native engine ids, libmpv track
  ids, URLs, auth headers, and native handles stay private to main/helper setup
  and private descriptor mapping.
- The resolver may keep private selected-track mapping in
  `privatePlayback.setup.selectedPrivateTrackIds`; renderer-safe load payloads,
  diagnostics, player snapshots, and player events may contain only public ids.
- Existing adapter validation for renderer-originating track selection is
  shape-only: non-empty public string ids for audio, non-empty public string ids
  or `null` for subtitles. RD-16 must prove public/private id separation in
  stream policy, resolver, and runtime load handoff, but it must not claim
  adapter current-request membership validation. Semantic membership remains
  future host/adapter track-state work for a production native-helper plan
  unless Unit 3 is selected by a reviewed replan.
- Diagnostics may report public track ids and reason codes, not raw Plex/native
  ids or secret-bearing media setup.

RD-16 target media matrix policy before implementation:

| Category | Automated injected proof target | Windows native proof target | Explicitly untested/unsupported unless later proven |
| --- | --- | --- | --- |
| Containers | MP4 and MKV safe candidates; unsupported container reasons | Local dummy MP4/MKV samples sufficient to observe track/HDR fields | AVI/WMV parity, multi-part edge cases, remote live Plex streams |
| Video/HDR | SDR, HDR10, Dolby Vision, unknown dynamic range decisions | HDR metadata observation when the local Windows sample exposes it; otherwise record blocked/unavailable | Dolby Vision preservation, tone mapping quality, passthrough parity |
| Audio | AAC/Opus supported fixtures, incompatible FLAC/TrueHD/DTS-style fallback/unsupported reasons, channel count and language metadata preservation; language mismatch does not drive selection by itself | At least one multi-audio local sample with observed default/selected audio track and switch attempt result | Bitstream/passthrough, Atmos, DTS-HD, TrueHD parity; preferred-language selection |
| Subtitles | Embedded, sidecar, external, burn-in, unknown, forced, default, preferred-off, requested-missing, requested-incompatible fixtures; language metadata preservation; language mismatch does not drive selection by itself | At least one subtitle-bearing local sample with observed track list and selection/off result | Styling fidelity for ASS/SSA, image subtitle burn-in quality, external subtitle download behavior; preferred-language selection |
| Track identity | Public/private id separation, uniqueness per candidate/request, no forbidden fields | Redacted evidence shows no raw Plex/native ids in public proof outputs | Persisting track ids across sessions or exposing engine/Plex ids |

Language behavior is intentionally limited to metadata preservation and
deterministic forced/default/requested-id decisions. RD-16 does not add
preferred-language selection or fallback because the current policy input uses
preferred track ids, not preferred language. If preferred-language behavior is
needed, stop and replan for an explicit contract/input change.

## Required Reading

- `AGENTS.md`
- `docs/AGENTIC_DEV_WORKFLOW.md`
- `docs/agentic/session-prompts/README.md`
- `docs/agentic/session-prompts/feature-plan.md`
- `docs/agentic/session-prompts/feature-quality-loop.md`
- `docs/agentic/plan-authoring-standard.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/playback-architecture.md`
- `docs/architecture/renderer-architecture.md`
- `docs/architecture/file-shape-guardrails.md`
- `docs/architecture/security-and-secret-flow.md`
- `docs/architecture/import-ledger.md`
- `docs/runs/rd-16-subtitle-audio-hdr-hardening/controller-state.md` when present locally

## Required Skills

- `lineup-desktop-feature-quality-loop`: controller owns RD-16 from planning
  through review, bounded implementation, implementation review, verification,
  Windows proof, and closeout.
- `lineup-desktop-feature-plan`: this tracked plan is the active durable
  planning artifact.
- `execution-plan-authoring`: scope, owners, invariants, acceptance criteria,
  rollback, and stop conditions are frozen here for fresh sessions.
- `verification-strategy`: RD-16 requires new public-seam tests plus Windows
  native proof before closeout.
- `architecture-boundaries`: player contract, main/player, main/Plex, helper
  proof tooling, and renderer-safe surfaces are boundary-sensitive.
- `plex-integration-boundaries`: Plex stream metadata, selected tracks,
  private playback descriptors, and token-bearing setup remain main-owned and
  redacted.
- `review-request` / `lineup-desktop-feature-review`: the next gate is
  read-only plan review, then read-only implementation review per unit.
- `review-adjudication`: required before changing the plan or implementation in
  response to review findings.
- `closeout-verification`: required before calling any plan revision,
  implementation unit, or RD-16 closeout done.

## Evidence And Discovery

- Plan-revise freshness observation: the controller reported unrelated
  worktree source modifications outside the RD-16 plan and a pre-existing
  `npm run verify:maintainability` failure before RD-16 implementation. That
  drift is not RD-16 implementation scope and must not be reverted or included
  by an RD-16 worker. At the time of this plan-revise pass, a read-only local
  rerun of `npm run verify:maintainability` passed, but the source worktree was
  still dirty. The freshness gate below therefore remains mandatory at
  execution-unit-select.
- `semantic_search_with_context`: attempted through Codanna for subtitle/audio
  track/HDR stream policy context; failed with `No embeddings available for
  search`.
- `semantic_search_docs`: attempted through Codanna for RD-16/platform proof
  context; failed with `No embeddings available for search`.
- Codanna index status: 3775 symbols across 137 files, semantic search enabled
  but zero embeddings.
- Codanna symbol search: found `PlayerTrackId`,
  `PlayerSubtitleDeliveryMode`, `selectTracks`, `selectSubtitle`,
  `DesktopStreamPolicyReasonCode`, `DesktopStreamPolicyUnknownCode`, and
  `decideDesktopStreamPolicy`; additional resolver symbols were confirmed by
  direct reads because symbol search did not surface the private resolver
  helpers.
- Direct reads / `rg`: inspected the required roadmap, workflow, architecture,
  import-ledger, stream-policy, Plex resolver, Plex playback runtime/bridge/
  composition, player contract, adapter track handling, RD-06 native harness,
  RD-06 harness tests, and existing policy/resolver test fixtures.
- Source evidence confirms current public track state already uses opaque
  renderer-safe ids in `src/contracts/player.ts`, stream policy already carries
  subtitle/audio/HDR reason and unknown codes, and `src/main/plex/streamResolver.ts`
  already separates renderer-safe selected track ids from private Plex stream
  ids.
- RD-06/RD-15 evidence tooling still records track behavior as not proven by
  dummy visual media; RD-15 cannot be used as subtitle/audio/HDR proof.
- Import ledger: no RD-16 import is currently authorized. If implementation
  copies or adapts upstream source, stop and replan before editing.
- Official external docs: not required for this plan because RD-16 is scoped to
  existing repo seams and dev-only proof tooling, with no new dependency,
  Electron API, packaging, signing, or external native-player behavior claim.

## Impact Snapshot

Expected owners that may change after clean plan review:

- Main/player stream-policy types, implementation, and fixtures/tests.
- Main/Plex stream resolver mapping and tests.
- Main/player injected runtime/bridge/composition tests only if policy output
  shape or selected-track custody needs proof at that seam.
- Dev-only RD-06 native-presentation proof tooling and harness tests for RD-16
  media matrix evidence.
- Architecture/roadmap/current-state docs at closeout only if ownership,
  proof status, or durable RD-16 conclusions change.

Expected owners that must not change without replan:

- Preload bridge and product IPC.
- Renderer UI and live Plex renderer APIs.
- Production native-helper playback wiring.
- Persistence, credentials, app paths, packaging, dependencies, and lockfiles.

The first execution unit remains single-owner in main/player stream policy.
Cross-boundary work is split so a worker cannot use resolver, adapter, or
harness edits to compensate for unresolved policy decisions.

## Freshness Gate

Before Unit 1 implementation begins, the controller must run:

- `git status --short --branch`
- `npm run verify:maintainability`

Unit 1 cannot start while unrelated source-shape drift, unrelated source
modifications that affect RD-16 owners, or `verify:maintainability` failures
remain unresolved. The controller must either get the worktree back to a
verified baseline through a separate reviewed pass or user resolution, or
replan RD-16 if RD-16 deliberately owns any guardrail/source-shape update.

The freshness gate is also required before selecting each later execution unit.
If a referenced file, owner boundary, verification command, or architecture doc
changed materially since this plan was reviewed, stop for plan revision and
read-only review before editing.

## Architecture Health

Current file-shape evidence from `docs/architecture/file-shape-guardrails.md`
and the accepted plan-revise gate observation:

| File | Guardrail baseline | Plan-revise observed drift | RD-16 decision |
| --- | ---: | ---: | --- |
| `src/main/player/desktopPlayerAdapter.ts` | 1275 | 1276 | Avoid by default. Do not grow for policy/resolver hardening. Current unrelated drift is a pre-implementation blocker, not RD-16 scope. Touch only after reviewed replan if adapter validation must change for an explicitly selected Unit 3. |
| `src/main/player/plexPlaybackRuntime.ts` | 798 | no over-baseline drift reported | Avoid for Units 1-2. Touch only for public runtime load-handoff tests or minimal guard updates if selected-track custody crosses this seam. Extract cleanup/stale-event code before production playback growth. |
| `src/contracts/player.ts` | 695 | 697 | Avoid public contract expansion. Existing opaque ids and track summary fields should be sufficient. Current unrelated drift is a pre-implementation blocker, not RD-16 scope. If a new public track family is unavoidable, replan before editing and split stable sub-vocabularies rather than growing this file casually. |
| `src/main/plex/streamResolver.ts` | 662 | no over-baseline drift reported | Unit 2 may touch after the freshness gate passes. Keep mapping changes focused; if track identity/HDR mapping grows substantially, split candidate mapping or private descriptor projection before adding broad behavior. |
| `src/main/player/streamPolicy/desktopStreamPolicy.ts` | 625 | 626 | Unit 1 may touch only after unrelated file-shape drift is resolved or RD-16 is replanned to own it. Add focused policy behavior only; if subtitle/audio/HDR branches become broad, split selection/evaluation phases before closeout. |
| `src/main/player/nativePlayerHostProcess.ts` | 501 | 502 | Out of scope. Current unrelated drift is a pre-implementation blocker, not RD-16 scope. RD-16 must not expand production helper protocol or process ownership. |
| `src/preload/index.cts` | 575 | 576 | Out of scope. Current unrelated drift is a pre-implementation blocker, not RD-16 scope. RD-16 must not add preload methods or channel vocabulary. |

The accepted blocker also noted unrelated source modifications from outside the
RD-16 plan. These source changes are not part of RD-16 and must not be staged,
reverted, rationalized, or verified as RD-16 implementation by an RD-16 worker.

Maintainability verification route:

- Run `npm run verify:maintainability` after any production source-shape change.
- Run `npm run verify:architecture` for implementation units that touch
  production source.
- Decision: avoidance by default for
  `desktopPlayerAdapter.ts`, `plexPlaybackRuntime.ts`, `contracts/player.ts`,
  and `nativePlayerHostProcess.ts`; bounded touched-file decisions for
  `streamResolver.ts` and `desktopStreamPolicy.ts`; decomposition required
  before broad policy/resolver growth; allowlist updates only with reviewed
  source changes that prove decomposition is worse for the current unit.
- Do not raise file-shape baselines to pre-authorize RD-16 growth. Any allowlist
  update must be paired with the source change that needs it, state why
  decomposition is not better, and pass review.

## Files In Scope

Planning artifact:

- `docs/plans/rd-16-subtitle-audio-hdr-hardening.md`

Implementation scope after clean plan review:

- `src/main/player/streamPolicy/types.ts`
- `src/main/player/streamPolicy/desktopStreamPolicy.ts`
- `src/__tests__/main/player/desktopStreamPolicy.test.ts`
- `src/__tests__/main/player/fixtures/desktopStreamPolicyFixtures.ts`
- `src/main/plex/streamResolver.ts`
- `src/__tests__/main/plexStreamResolver.test.ts`
- `src/main/player/plexPlaybackRuntime.ts` only if selected-track custody needs
  runtime seam proof
- `src/main/player/plexPlaybackBridge.ts` only if preferred track handoff must
  be proven through scheduler-to-resolver injection
- `src/main/player/plexPlaybackComposition.ts` only if player intent projection
  needs track-command proof
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/player/plexPlaybackBridge.test.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`
- `src/__tests__/main/player/desktopPlayerAdapter.test.ts` only if adapter
  command/event validation proof is needed
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
- `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
- `docs/architecture/CURRENT_STATE.md`, `docs/architecture/playback-architecture.md`,
  `docs/roadmap/desktop-port-roadmap.md`, and
  `docs/architecture/import-ledger.md` only for closeout memory updates if
  RD-16 changes durable architecture/provenance state

## Files Out Of Scope

- `src/preload/**`
- `src/renderer/**`
- `src/main/index.ts`
- `src/main/player/playerIpc.ts` unless a reviewed replan adds product IPC
  scope
- `src/main/player/nativePlayerHostProcess.ts`
- `src/main/persistence/**`
- `src/main/plex/auth/**`
- `src/main/plex/discovery/**`
- `src/main/plex/library/**` except test fixtures may construct existing safe
  `PlexMediaItem` shapes
- `package.json`, package manager lockfiles, build config, packaging, signing,
  installer, and release files
- Any live Plex server credentials, token-bearing URLs, raw auth headers, or
  non-redacted native evidence

## Execution Units

Unit 1: stream policy and media matrix core.

- Status: complete locally; plan review, Freshness Gate, implementation review,
  `npm run test:contracts`, `npm run verify:architecture`, and
  `npm run verify:redaction` passed. Committed in
  `d413e0e feat(player): harden subtitle audio hdr stream policy`.
- Write scope: `src/main/player/streamPolicy/types.ts`,
  `src/main/player/streamPolicy/desktopStreamPolicy.ts`,
  `src/__tests__/main/player/desktopStreamPolicy.test.ts`, and
  `src/__tests__/main/player/fixtures/desktopStreamPolicyFixtures.ts`.
- Required outcome: deterministic fixtures cover the RD-16 matrix for
  forced/default subtitle decisions, language metadata preservation, preferred
  subtitle off, requested
  unavailable/incompatible audio and subtitles, burn-in/conversion decisions,
  HDR10, Dolby Vision, unknown dynamic range, and explicit unsupported/unknown
  reasons. Tests must show language mismatch alone does not drive audio or
  subtitle selection.
- Stop/replan if this unit requires public contract expansion, live Plex
  transport, renderer changes, preferred-language selection, or broad
  stream-policy decomposition.

Unit 2: Plex resolver mapping and private/public track identity custody.

- Status: complete locally; implementation review, `npm run test:contracts`,
  `npm run verify:architecture`, and `npm run verify:redaction` passed.
  Committed in
  `c6b723a feat(plex): harden playback track identity projection`.
- Write scope: `src/main/plex/streamResolver.ts` and
  `src/__tests__/main/plexStreamResolver.test.ts`.
- Required outcome: Plex stream metadata maps to public track ids without raw
  Plex ids; private selected ids remain only in the privileged descriptor;
  language/default/forced/delivery/HDR facts project into policy candidates,
  language metadata is preserved, and redacted diagnostics plus safe unsupported
  failures contain no private ids.
- Stop/replan if resolver changes require live Plex transport, raw URL/header
  exposure, public contract expansion, preferred-language selection, or
  significant growth without splitting candidate mapping from descriptor
  projection.

Unit 3: runtime load-handoff proof for selected public ids, only by reviewed
replan.

- Status: not selected; no reviewed replan made runtime/adapter membership or
  handoff changes required for RD-16.
- Write scope: the existing main/player runtime, bridge, composition, and
  adapter tests named in Files In Scope; production source only if a reviewed
  replan makes Unit 3 required and tests expose a real seam defect.
- Required outcome: selected public track ids survive scheduler-to-resolver to
  player-load handoff and subtitle-off remains `null`. Existing adapter
  renderer-intent validation remains shape-only unless a reviewed replan
  explicitly adds host/adapter current-request membership validation scope.
- Stop/replan if this requires preload/product IPC expansion or production
  native-helper protocol changes.

Unit 4: Windows native-presentation media proof tooling.

- Status: harness tooling complete locally; implementation review,
  `npm run test:harness-docs`, `npm run verify:docs`, and
  `npm run verify:redaction` passed. Committed in
  `21c22f6 test(playback): add rd-16 native media proof harness`. Windows
  native-presentation proof remains required before RD-16 closeout.
- Write scope: `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`,
  `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`, and ignored local
  evidence under `docs/runs/rd-16-subtitle-audio-hdr-hardening/`.
- Required outcome: extend the dev-only harness/test scope to accept an RD-16
  ignored media-matrix manifest or equivalent local-only sample descriptor
  while preserving the existing `--dummy-input local-and-http` path. The
  descriptor must use redacted sample labels, not committed raw paths, for
  `multi-audio`, `subtitle-bearing`, `hdr`, and `hdr-unavailable` cases.
  Windows preflight/smoke records redacted `observed`, `unavailable`, or
  `blocker` statuses for each case. It must keep the tool dev-only and preserve
  no-forbidden-header and redaction checks.
- Stop/replan if proof requires production helper wiring, live Plex streams,
  external secret-bearing media, dependency/package changes, or non-redacted
  local evidence. If safe local samples are unavailable, RD-16 remains blocked
  and cannot close as complete.

Parallelism:

- Units 1 and 2 are sequential because resolver mapping depends on the frozen
  policy matrix.
- Unit 4 can be prepared in parallel with Unit 3 only after Units 1 and 2 are
  reviewed clean and the worker scopes are disjoint.

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions are
   frozen at the planning level. The only implementation-time choice left is
   local code shape inside approved owners.
2. Adjacent contract/type changes are not assumed. If existing player contracts
   cannot carry RD-16 safely, implementation must stop and replan.
3. Files out of scope are not hidden dependencies for Units 1-2. Unit 3 is
   explicitly conditional for runtime/adapter seam proof.
4. Evidence path and Codanna fallback are recorded above.
5. Work starts in the repo-preferred owner, stream policy, before touching
   resolver or runtime owners, but only after the Freshness Gate passes.
6. Tier 3 Architecture Health evidence is recorded, with avoid/decompose
   decisions for every touched hotspot over the guardrail threshold.
7. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Exact verification commands, expected outcomes, Windows proof requirement,
   and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

Chosen seam: main-owned stream-policy and Plex resolver hardening, with
renderer-safe public ids and private main/helper setup kept separate.

Forbidden shortcuts:

- No broad preload RPC, arbitrary channel strings, or renderer privilege
  concessions.
- No raw Plex tokens, tokenized URLs, auth headers, raw Plex payloads, Plex
  stream ids, part keys, stream keys, engine ids, native handles, local paths,
  or libmpv objects in renderer-safe contracts, diagnostics, fixtures, docs, or
  Codex output.
- No compatibility barrels, old upstream path shims, temporary adapter families,
  or fallback API variants.
- No use of RD-15 proof as subtitle/audio/HDR support proof.
- No production native-helper playback or live Plex transport.

Stop and replan if implementation discovers that safe track identity requires a
new public contract family, native helper protocol expansion, live Plex
transport, dependency/package changes, copied upstream source, persisted
settings, or a broader file-shape baseline increase.

## Verification Commands

Planning pass:

- `npm run verify:docs`
  - Expected: exits 0 and validates this active plan structure, headings,
    classification marker, docs links, and docs/control-plane rules.

Unit 1:

- Freshness Gate:
  - Expected: `git status --short --branch` shows no unrelated source
    modifications that affect RD-16 owners, and `npm run verify:maintainability`
    exits 0 before implementation starts.
- `npm run typecheck`
  - Expected: exits 0 with stream-policy types and fixtures compiling.
- `npm run test:contracts`
  - Expected: exits 0; desktop stream policy tests include the RD-16 media
    matrix, language metadata preservation, language mismatch non-selection,
    and forbidden-field assertions.
- `npm run verify:architecture`
  - Expected: exits 0; lint and maintainability guardrails pass without
    unreviewed file-shape growth.
- `npm run verify:redaction`
  - Expected: exits 0; fixtures and diagnostics do not contain secret-shaped or
    forbidden playback fields.

Unit 2:

- `npm run typecheck`
  - Expected: exits 0 with resolver projections compiling.
- `npm run test:contracts`
  - Expected: exits 0; Plex resolver tests prove public/private track-id
    separation, language metadata preservation, default/forced/delivery/HDR
    mapping, safe unsupported errors, and no raw Plex id leakage.
- `npm run verify:architecture`
  - Expected: exits 0; resolver growth is either under the reviewed baseline or
    paired with reviewed decomposition/allowlist handling.
- `npm run verify:redaction`
  - Expected: exits 0.

Unit 3, only if selected by reviewed replan:

- `npm run test:contracts`
  - Expected: exits 0; runtime/bridge/composition/adapter tests prove
    selected public-id load handoff and subtitle-off behavior through existing
    seams. Adapter current-request membership validation is not expected unless
    the reviewed replan explicitly adds that scope.
- `npm run verify:architecture`
  - Expected: exits 0.
- `npm run verify:redaction`
  - Expected: exits 0.

Unit 4 and RD-16 Windows proof:

- `npm run test:harness-docs`
  - Expected: exits 0; dev-only native-presentation harness source/shape tests
    cover RD-16 media proof fields and preserve RD-06/RD-15 guardrails.
- `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof`
  - Expected on Windows: exits 0 and writes redacted preflight evidence under
    the ignored RD-16 run bundle.
- `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --fullscreen-mode native-presentation-host --dummy-input local-and-http --rd16-media-matrix docs/runs/rd-16-subtitle-audio-hdr-hardening/media-matrix.local.json --duration-ms 7500 --out docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof`
  - Expected on Windows after RD-16 harness changes: exits 0 when safe local
    samples are available, keeps native presentation proof passing, reads an
    ignored local media-matrix descriptor with redacted sample labels, records
    subtitle/audio/HDR `observed`, `unavailable`, or `blocker` statuses,
    observes no forbidden header, and writes redacted local evidence only. If
    safe local samples are unavailable, the command or evidence status must
    block RD-16 closeout instead of marking the item complete.

Implementation closeout:

- `npm run verify`
  - Expected: exits 0 after all accepted units and closeout docs are updated.
- `git status --short --branch`
  - Expected: only intended tracked files are modified; ignored RD-16 run-bundle
    evidence remains untracked.

## Windows Proof Handoff

Status entering Windows proof:

- Units 1, 2, and 4 are implemented, locally verified, and reviewed clean.
- Unit 3 was intentionally not selected because no reviewed replan made
  runtime/adapter membership or handoff changes required for RD-16.
- `npm run verify` passed locally after Unit 4. The remaining closeout gate is
  Windows native-presentation media-matrix proof.

Windows tester setup:

- Use a Windows checkout that includes commits `754532d`, `d413e0e`,
  `c6b723a`, `21c22f6`, `dd9b2e4`, and this reviewed handoff revision, or a
  newer commit containing the same RD-16 plan and harness changes.
- Start from a clean tracked worktree or explicitly report unrelated tracked
  changes before running proof commands.
- Install npm dependencies with the existing lockfile, for example `npm ci` if
  `node_modules` is absent or stale. Do not commit dependency or lockfile
  changes.
- Ensure Node, Electron dependencies, a `.NET` SDK capable of `dotnet build`
  for the harness `net7.0` helper target, `mpv.exe`, and `libmpv-2.dll`
  satisfy the existing RD-06 native-presentation preflight. The harness uses
  `RD06_MPV_ROOT` / `RD06_MPV_EXE` / `RD06_LIBMPV_DLL` when those environment
  variables are set, otherwise it uses the existing RD-06 default path.
- Do not add package dependencies, lockfile changes, production native-helper
  wiring, product IPC, preload APIs, live Plex transport, persisted settings, or
  copied/adapted upstream source during the Windows proof pass.

Create the ignored local descriptor at
`docs/runs/rd-16-subtitle-audio-hdr-hardening/media-matrix.local.json`.
The descriptor is tester-observed metadata; the harness records it as redacted
evidence beside dummy native-presentation proof. The harness does not load raw
sample paths and does not automatically inspect real media tracks from this
descriptor.

Descriptor shape policy:

```json
{
  "cases": {
    "multi-audio": {
      "label": "multi-audio-safe-sample",
      "status": "observed"
    },
    "subtitle-bearing": {
      "label": "subtitle-bearing-safe-sample",
      "status": "observed"
    },
    "hdr": {
      "label": "hdr-safe-sample",
      "status": "observed"
    },
    "hdr-unavailable": {
      "label": "hdr-unavailable-safe-sample",
      "status": "observed",
      "reason": "safe-negative-hdr-sample-observed"
    }
  }
}
```

Descriptor rules:

- The descriptor must provide exactly the known RD-16 case keys
  `multi-audio`, `subtitle-bearing`, `hdr`, and `hdr-unavailable`. This handoff
  policy is intentionally stricter than harness parsing: the parser can ignore
  extra cases and convert missing known cases to `blocker`, but a closeout-ready
  Windows proof descriptor should not rely on that leniency.
- Status values must be `observed`, `unavailable`, or `blocker`. Unknown
  statuses normalize to `blocker`.
- Labels and reasons must be short, redacted, and path-free. Do not include raw
  local paths, drive letters, URLs, native handles, Plex field names, token-like
  text, auth headers, process args/env, or sample filenames that expose private
  media.
- Mark `observed` only after the Windows tester has actually observed the named
  safe local sample behavior outside the descriptor itself. Mark `unavailable`
  when the safe local sample is missing but the absence is explainable. Mark
  `blocker` for failed or ambiguous behavior.
- RD-16 closeout requires all four cases to be `observed`. Any `blocker`,
  `unavailable`, missing, or unknown-normalized case blocks closeout unless a
  later reviewed replan changes the Windows proof requirement. If a case is
  unavailable, record the unavailable matrix explicitly and do not claim support
  for that behavior.

Run the Windows proof commands from the repo root:

```sh
npm run test:harness-docs
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof/preflight
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --fullscreen-mode native-presentation-host --dummy-input local-and-http --rd16-media-matrix docs/runs/rd-16-subtitle-audio-hdr-hardening/media-matrix.local.json --duration-ms 7500 --out docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof/smoke
npm run verify:redaction
```

Expected Windows proof outputs:

- `npm run test:harness-docs` exits 0.
- Preflight exits 0 and
  `docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof/preflight/manifest.redacted.json`
  records `mode: native-presentation-preflight` and `status: passed`.
- Smoke exits 0 and
  `docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof/smoke/manifest.redacted.json`
  records
  `mode: native-presentation-smoke`, `status: passed`,
  `fullscreenMode: native-presentation-host`, `productIpcUsed: false`,
  `dummyInputsOnly: true`, `dummyHeaderOnly: true`,
  `rawLocalPathsPersisted: false`, `rawUrlsPersisted: false`, and
  `rawNativeValuesPersisted: false`.
- `docs/runs/rd-16-subtitle-audio-hdr-hardening/native-proof/smoke/summary.redacted.md`
  includes
  `RD-15 native presentation UI: 16/16 observed` and an
  `RD-16 media matrix: observed (...)` line with all four case statuses marked
  `observed`.
- The manifest keeps `tracks: not-proven-by-dummy-visual-media`; do not remove
  or reinterpret this marker. RD-16 media proof comes from the redacted
  descriptor plus tester observation, not from dummy GIF playback.
- `npm run verify:redaction` exits 0 after the evidence exists.

Windows tester report-back packet:

```text
RD-16_WINDOWS_PROOF_RESULT
branch/commit:
tracked git status:
test:harness-docs:
native-presentation-preflight exit/status:
native-presentation-smoke exit/status:
summary RD-15 native presentation UI line:
summary RD-16 media matrix line:
matrix case notes:
- multi-audio:
- subtitle-bearing:
- hdr:
- hdr-unavailable:
redaction verification:
blockers/unavailable cases:
```

Do not paste raw `events.redacted.ndjson` unless a reviewer asks for a redacted
excerpt, and never paste raw local paths, URLs, headers, token-shaped values,
native handles, or private sample filenames.

Closeout routing after Windows proof:

- If preflight/smoke pass, redaction passes, and every matrix case is
  `observed`, route back to `lineup-desktop-feature-quality-loop` for RD-16
  closeout docs, implementation review if the proof changed tracked files,
  `npm run verify`, and roadmap/current-state updates.
- If preflight/smoke fails, redaction fails, descriptor loading rejects the
  matrix, any case is `blocker` or `unavailable`, any known case is missing, or
  the tester cannot provide safe local media, keep RD-16 active and blocked. Do
  not update roadmap/current-state as complete unless a later reviewed replan
  deliberately relaxes the Windows proof requirement.
- If satisfying proof requires real media paths in committed files, production
  helper behavior, live Plex streams, product IPC, dependencies, or broader
  contract changes, stop and replan before editing.

## Acceptance Criteria

- Plan review is clean before any implementation unit begins.
- Freshness Gate passes before Unit 1 starts; unrelated source-shape drift is
  resolved through a separate reviewed pass/user resolution, or RD-16 is
  replanned to own the relevant guardrail/source-shape update.
- RD-16 media matrix is represented in deterministic tests and closeout docs,
  with tested and untested cases clearly distinguished.
- Public track ids cannot become ambiguous between Plex stream ids, native
  playback engine ids, and renderer-safe player ids.
- Forced/default subtitle behavior, language metadata preservation, language
  mismatch non-selection, subtitle-off behavior, audio fallback,
  burn-in/conversion decisions, HDR10, Dolby Vision, and unknown dynamic range
  produce stable policy outcomes and diagnostics.
- Plex resolver keeps private playback setup private and exposes only safe
  public ids, reason codes, and media summaries.
- Unsupported cases have explicit renderer-safe diagnostics and fallback or
  unsupported behavior.
- Windows proof is satisfied before RD-16 closeout through redacted RD-16 media
  matrix evidence, or the item is left blocked with reviewed evidence explaining
  why safe local samples or proof are unavailable.
- `npm run verify` passes before implementation closeout.
- Import ledger is unchanged unless a reviewed replan authorizes copied/adapted
  upstream source, in which case the ledger is updated before or with the import.

## Replan Triggers

- Existing `PlayerTrackId` / `PlayerTrackSummary` shapes cannot safely express
  RD-16 behavior without a new public contract family.
- Preferred-language selection or fallback becomes required.
- Adapter or host current-request track membership validation becomes required.
- Any implementation path requires preload/product IPC expansion, renderer live
  Plex APIs, live Plex transport, production native-helper playback, native
  helper protocol expansion, persistence/settings changes, package/dependency
  changes, or packaging work.
- Windows native proof cannot observe required subtitle/audio/HDR behavior with
  safe local samples, or the ignored RD-16 media-matrix descriptor cannot be
  supplied without raw paths or secret-bearing evidence. This blocks RD-16
  closeout unless reviewed replan changes the platform-proof requirement.
- File-shape growth crosses guardrail baselines without a reviewed
  decomposition or allowlist decision.
- Tests require raw Plex ids, engine ids, token-bearing URLs, auth headers,
  local paths, native handles, or non-redacted evidence.
- Upstream source copy/adaptation appears necessary.
- Reviewer finds a material architecture, security, verification, or scope
  blocker.

## Rollback Notes

- Unit 1 rollback: revert stream-policy type/decision/test/fixture changes.
  Existing RD-08 policy behavior should remain intact.
- Unit 2 rollback: revert resolver mapping/test changes. Private descriptor and
  safe load projection should return to RD-12 behavior.
- Unit 3 rollback: revert runtime/bridge/composition/adapter seam changes or
  tests. Do not leave half-wired selected-track behavior.
- Unit 4 rollback: revert dev-only harness source/test changes and remove
  ignored RD-16 evidence if it is stale or misleading. Never commit raw local
  evidence.
- If closeout docs are updated and implementation rolls back, update docs in the
  same pass so roadmap/current-state do not overclaim RD-16 support.

## Commit Checkpoints

- Plan commit: `docs(plans): add rd-16 subtitle audio hdr hardening plan`
- Unit 1 commit: `feat(player): harden subtitle audio hdr stream policy`
- Unit 2 commit: `feat(plex): harden playback track identity projection`
- Unit 3 commit, if needed: `feat(player): prove selected track handoff seams`
- Unit 4 commit: `test(playback): add rd-16 native media proof harness`
- Closeout docs commit, if separated: `docs(roadmap): record rd-16 playback proof`

Keep one focused commit per reviewed execution unit unless the controller
records a narrower no-commit handoff. Do not stage unrelated local changes or
ignored run-bundle evidence.

MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: GPT-5 high reasoning
REVIEWER: GPT-5 high reasoning
WHY: Tier 3 native playback/Plex boundary work touches renderer-safe contracts,
track identity, redaction, dev-only native proof, and Windows closeout evidence.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-16 Subtitle, Audio, And HDR Hardening Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-16-subtitle-audio-hdr-hardening.md
ARTIFACT: docs/plans/rd-16-subtitle-audio-hdr-hardening.md
FILES:
- docs/plans/rd-16-subtitle-audio-hdr-hardening.md
- tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs
- tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs
- docs/roadmap/desktop-port-roadmap.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
BLOCKERS: Windows native-presentation media-matrix proof is required before RD-16 closeout.
MESSAGE:
Resume RD-16 at the Windows proof gate, not implementation. Units 1, 2, and 4
are implemented, locally verified, reviewed clean, and committed; Unit 3 was not
selected. Follow the `Windows Proof Handoff` section exactly. On Windows, create
the ignored redacted descriptor at
`docs/runs/rd-16-subtitle-audio-hdr-hardening/media-matrix.local.json`, run
`npm run test:harness-docs`, the native-presentation preflight, the
native-presentation smoke with `--rd16-media-matrix`, and
`npm run verify:redaction`. Report back with the
`RD-16_WINDOWS_PROOF_RESULT` packet. If proof passes and all four matrix cases
are `observed`, route to RD-16 closeout docs, read-only implementation/closeout
review, and `npm run verify`; if proof is unavailable, blocked, incomplete, or
contains any `unavailable` case, leave RD-16 active and do not update
roadmap/current-state as complete.
