# RD-19 Internal Alpha/Beta Validation Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Define the private RD-19 validation program for Lineup Desktop internal alpha
and beta readiness without adding product runtime behavior. RD-19 owns the
validation matrix, blocker taxonomy, evidence policy, platform proof
requirements, and release-readiness decision gates for the current Desktop
state after RD-18.

RD-19 does not claim the app is live-Plex or production-playback ready. It
separates what can be privately validated now from what must be recorded as a
release blocker, beta blocker, or deferred item until a smaller reviewed
enabling unit implements the missing runtime surface.

The output of this plan is a reviewed validation protocol and handoff for
read-only plan review. Implementation sessions may later add narrowly scoped
validation harnesses or docs only if review approves them; broad manual
validation is out of scope for this planner pass.

## Non-Goals

- Do not execute broad internal alpha or beta manual validation in this pass.
- Do not import upstream Lineup code or add copied/adapted source.
- Do not add live Plex auth, discovery, library transport, scheduler runtime
  composition, or renderer Plex APIs.
- Do not add production native-helper playback, production playback host
  behavior, Plex-to-native-helper setup, native media binary redistribution, or
  public signing/update behavior.
- Do not change package scripts, dependencies, package-lock, installer tooling,
  release metadata, or generated package artifacts.
- Do not add preload/renderer persistence IPC, credential backup/restore, or
  product IPC beyond the current local diagnostics surface.
- Do not lower redaction, architecture, packaging, or file-shape gates to make a
  private MVP appear more complete than the current implementation supports.

## Parent Architecture Alignment

RD-19 aligns with `docs/architecture/CURRENT_STATE.md`: the repo currently has
secure Electron shell behavior, fake-backed renderer navigation/workflows, main
Plex domain seams behind injected transports, deterministic stream policy,
Plex-to-player runtime seams behind injected ports, local diagnostics/support
bundle export, and internal Windows x64 unpacked package proof.

The following current-state constraints are binding for RD-19:

- Live Plex auth/discovery/library transport and runtime composition are not
  implemented.
- Production native playback helper, production playback host, and
  Plex-to-native-helper setup are not implemented.
- Live renderer Plex APIs and production renderer-to-Plex/player API wiring are
  not implemented.
- Product IPC beyond the local RD-17 diagnostics surface is not implemented.
- Preload/renderer persistence IPC, credential backup/restore, public
  signing/update, and native helper/media binary redistribution are not
  implemented.

Therefore RD-19 private MVP validation must classify live-auth, live-server,
live-library, live-channel-from-library, and live-Plex playback scenarios as
blocked until a reviewed enabling plan adds the smallest missing owner. RD-19
may still validate fake-backed UI flows, injected/domain behavior, diagnostics,
redaction, package layout, Windows native-presentation evidence, and manually
observed local package install/uninstall handling where the current package
shape permits it.

## Required Reading

Read these in order before reviewing or implementing any RD-19 follow-up:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/README.md`
4. `docs/agentic/session-prompts/feature-quality-loop.md`
5. `docs/agentic/session-prompts/feature-plan.md`
6. `docs/agentic/plan-authoring-standard.md`
7. `docs/architecture/CURRENT_STATE.md`
8. `docs/roadmap/desktop-port-roadmap.md`
9. `docs/architecture/packaging-release-gates.md`
10. `docs/architecture/playback-architecture.md`
11. `docs/architecture/security-and-secret-flow.md`
12. `docs/architecture/renderer-architecture.md`
13. `docs/architecture/file-shape-guardrails.md`
14. `tools/rd17-diagnostics-smoke.mjs`
15. `tools/package-windows-internal.mjs`
16. `tools/verify-windows-internal-package.mjs`
17. `tools/verify-redaction.mjs`
18. `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`

Freshness gate: if any of the current-state constraints, RD-17 diagnostics
contracts, RD-18 package tooling, package metadata, Electron version, or
roadmap status changes before RD-19 review, update this plan and reroute it to
read-only review before implementation.

## Required Skills

- `lineup-desktop-feature-quality-loop`: RD-19 is Tier 3 because it crosses
  packaging, diagnostics, playback, renderer, Plex, platform proof, and release
  readiness.
- `lineup-desktop-feature-plan`: this pass authors the durable tracked plan.
- `execution-plan-authoring`: keeps scope, invariants, verification, rollback,
  and stop conditions explicit without writing product pseudo-code.
- `verification-strategy`: RD-19 relies on a mixed proof surface of automated
  verifiers, Windows package proof, redacted diagnostics proof, and bounded
  private manual matrix results.
- `architecture-boundaries`: prevents validation planning from inventing
  renderer/preload/main/helper runtime ownership.
- `persistence-boundaries`: applies to credential availability, backup/restore
  blockers, app data, diagnostics paths, and uninstall cleanup.
- `plex-integration-boundaries`: applies to auth, server selection, library,
  channel creation from Plex media, stream setup, and token custody.
- `ui-composition-patterns`: applies to fake-backed renderer validation,
  fullscreen, multi-monitor, focus, EPG, settings, overlays, and long playback
  presentation observations.
- `closeout-verification`: required before calling any RD-19 validation unit
  done.
- `review-request`: the next gate is a clean read-only plan review through
  `lineup-desktop-feature-review`.

## Evidence And Discovery

- `semantic_search_docs`: attempted for RD-19 validation/release wording; the
  index returned mostly unrelated stream-policy symbols, so it was too noisy for
  plan authority.
- `semantic_search_with_context`: not exposed by the current Codanna tool
  surface in this session, so direct reads and `rg` were used for the decisive
  diagnostics and support-bundle evidence.
- Impact analysis: not required for this planning-only pass because no product
  symbols are changed. A future implementation unit that edits source must run
  symbol-specific discovery for its owner.
- Direct reads / `rg`: read the required workflow docs, plan standard, current
  architecture, roadmap, packaging gates, playback architecture, security
  policy, renderer architecture, file-shape guardrails, `package.json`, plan/run
  directory docs, RD-17 diagnostics smoke, RD-18 package and verifier tools, and
  searched for diagnostics, package, native-presentation, fullscreen,
  multi-monitor, sleep/wake, and long-playback surfaces.
- Official docs: no external behavior is changed by this plan. Future units
  that change Electron, signing, installer, native helper, media binary,
  update, or dependency behavior must check official vendor documentation in
  that unit.
- Import ledger: no copied or adapted upstream source is in scope for RD-19
  planning, so no import-ledger row is required.

Relevant observed surfaces:

- RD-17 local diagnostics and support-bundle export are owned by
  `src/main/diagnostics/*`, `src/contracts/diagnostics.ts`, preload diagnostics
  methods, renderer settings export action, `tools/rd17-diagnostics-smoke.mjs`,
  and `tools/verify-redaction.mjs`.
- RD-18 internal package proof is owned by
  `tools/package-windows-internal.mjs`,
  `tools/verify-windows-internal-package.mjs`, and
  `tools/__tests__/package-windows-internal.test.mjs`.
- Native-presentation evidence remains dev-only under
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` and ignored local
  `docs/runs/**` evidence. It is not product playback.

## Impact Snapshot

Expected blast radius for this planner pass:

- Owners that may change: only `docs/plans/rd-19-internal-alpha-beta-validation.md`.
- Public contracts that may change: none.
- Dependency, build-tool, configuration, and lockfile changes: none.
- Package scripts and generated artifacts: no changes.
- Runtime behavior: no user-visible behavior changes.
- Local-only artifacts: future manual evidence, support bundles, package
  outputs, logs, screenshots, crash dumps, media samples, and tester notes must
  stay under ignored local paths such as `docs/runs/**` or `out/**` unless a
  later reviewed doc explicitly promotes a redacted summary.

RD-19 validation is cross-boundary, but this plan keeps implementation units
single-owner where possible:

- Unit A, if approved: docs-only validation checklist and blocker-log template.
- Unit B, if approved: optional narrow verifier or harness documentation for
  validation summaries.
- Unit C, if approved and only on Windows x64: bounded private package proof
  rerun using RD-18 commands and ignored output.

No unit may enable live Plex or production native playback by validation
shortcut. If validation needs behavior that does not exist, the result is a
blocker classification and a stop/replan for the smallest reviewed enabling
unit.

### Release-Blocker Taxonomy

- release blocker: prevents any public release and must be fixed or explicitly
  removed by reviewed scope change before public distribution.
- beta blocker: prevents broader private beta but may allow maintainer-only
  alpha evidence when the limitation is documented, redacted, and not security
  critical.
- deferred: acceptable for private beta if documented with owner, rationale,
  user impact, and revisit trigger; cannot hide a security, data-loss,
  credential, or installer integrity issue.

Security, credential leakage, unredacted diagnostics, public signing/update
misrepresentation, native/media binary provenance gaps, and package integrity
failures are release blockers by default. Missing live Plex/runtime features
are beta blockers when they prevent private MVP validation; they become release
blockers if the app is represented as live-Plex capable.

### Private Validation Matrix

| Area | Current proof surface | Required private validation | Expected RD-19 classification rule |
| --- | --- | --- | --- |
| Auth | RD-10 injected auth domain, RD-09 storage seam, no live transport/preload API | Verify fake/injected auth tests remain green; attempt no real Plex sign-in unless a later reviewed unit adds live transport and renderer API | Live sign-in is a beta blocker; token leakage is a release blocker |
| Server selection | RD-10 discovery/selected-server domain, selected connection only in main memory, no live runtime | Validate injected selected-server restore/probe tests and document that real server picker is absent | Real server selection is a beta blocker until live discovery UI/API exists |
| Channel creation | RD-11 pure domain and RD-13 fake channel setup UI | Validate fake channel setup flow and domain tests; no live Plex library-backed creation | Live library-backed channel creation is a beta blocker |
| Playback | RD-07 fake/smoke player IPC, RD-12 injected Plex runtime, RD-15/16 dev-only native-presentation proof | Validate fake-backed player route, injected runtime tests, and dev-only Windows evidence only; do not claim production playback | Production native playback is a release blocker for public release and beta blocker for real media beta |
| Switching | RD-12 runtime cleanup/stale-event tests, RD-13/15 fake UI | Validate injected switch cleanup tests and fake UI switching; no real channel switch with Plex media | Real switching is a beta blocker until live playback is enabled |
| Subtitles/audio | RD-16 policy/resolver tests and redacted media-matrix summary; dummy harness cannot prove real track switching | Validate deterministic policy/resolver tests; record real runtime track selection as unproven | Broken/unsafe track leakage is a release blocker; missing real switching is a beta blocker |
| EPG | RD-13 fake-backed EPG surface and renderer tests | Validate fake EPG route, focus, formatting, and RD-15 UI-over-video evidence | Real Plex/scheduler-backed EPG is a beta blocker if required for private MVP |
| Settings | RD-13 fake settings, RD-17 support-bundle action, no persistence IPC | Validate fake settings route and diagnostics export action; do not claim persisted settings | Persistence IPC absence is deferred for fake alpha, beta blocker for real settings beta |
| Sleep/wake | No dedicated product owner or proof | Manual Windows observation may be recorded only against current fake/package shell; any playback/network recovery claim is blocked | Sleep/wake affecting runtime playback or credentials is a beta blocker until owned |
| Fullscreen | RD-14 window controller and RD-15/16 dev-only native-presentation evidence | Validate fullscreen shell/fake UI smoke and Windows native-presentation evidence; no production playback claim | Fullscreen failure in shell is beta blocker; native fullscreen production gap remains release blocker for public playback |
| Multi-monitor | RD-14 display/restore policy and limited proof notes | Manual Windows observation may record display count/DPI and shell behavior; native playback multi-monitor remains unproven | Shell placement failure is beta blocker; production video multi-monitor gap is deferred until playback unit unless severe |
| Crash recovery | RD-17 diagnostics smoke and native-host process tests | Rerun RD-17 smoke on Windows when validating package/readiness; evidence must show main alive, safe failed state, cleanup/reap, replacement helper | Unredacted or unrecovered helper crash is release blocker |
| Diagnostics export | RD-17 support bundle, redaction scanner, renderer-safe result | Validate export through RD-17 smoke or approved package flow; inspect only redacted summary fields | Redaction failure or absolute path exposure is release blocker |
| Install/uninstall | RD-18 unpacked internal package only; no installer | Validate package creation/verification and manual launch/delete of unpacked artifact only; no signed installer claim | Installer absence is deferred for maintainer alpha, release blocker for public release |
| Long playback | No production playback; dev-only harness can run bounded dummy durations | Do not claim long real playback. Optional bounded fake/native-presentation soak may record local dummy stability only | Real long playback is beta blocker until production playback exists |

### Blocker Matrix

| Blocker | Classification | Owner for next enabling plan | Stop condition |
| --- | --- | --- | --- |
| Live Plex auth/discovery/library transport absent | beta blocker | Main Plex runtime plus preload/renderer Plex API plan | Any validation asks tester to sign into real Plex |
| Production native helper/playback host absent | release blocker for public release, beta blocker for real media beta | Native helper/playback plan | Any validation claims real Plex media playback support |
| Plex-to-native-helper setup absent | beta blocker | Main/helper playback setup plan | Any private descriptor is logged, persisted, or exposed |
| Renderer Plex APIs absent | beta blocker | Preload/renderer API plan | Any renderer is asked to browse real Plex libraries |
| Persistence IPC and credential backup/restore absent | deferred for maintainer alpha, release blocker for public release | Persistence/recovery plan | Any validation claims recoverable credentials or persistent settings UX |
| Public signing/update absent | release blocker | Packaging/release plan | Any artifact is described as public distributable |
| Native helper/media binary redistribution absent | release blocker | Packaging/provenance/licensing plan | Any package includes native/media binaries outside reviewed provenance |
| RD-17 redaction scan fails | release blocker | Diagnostics/redaction plan | Any support bundle, log, or evidence contains forbidden material |
| RD-18 package verifier fails | beta blocker for internal validation, release blocker for public release | Packaging tooling plan | Any package artifact is used after verifier failure |
| Sleep/wake or multi-monitor shell failure corrupts state | beta blocker | Window/platform UX plan | Reproducible Windows shell state loss or unusable display placement |
| Long fake/native soak leaks resources or crashes shell | beta blocker | Runtime/window/diagnostics plan | Reproducible crash without safe diagnostics and cleanup |

### Evidence Redaction Policy

RD-19 evidence must never include raw Plex tokens, tokenized URLs, auth
headers, raw Plex payloads, credential values, native handles, process ids,
crash dumps with secrets, absolute local paths, media samples, raw helper logs,
raw IPC frames, signing credentials, certificate material, or local filesystem
details.

Allowed tracked material is limited to redacted summaries, blocker
classification, command names, expected outcomes, platform family, package
directory name, verifier status, and sanitized counts. Raw evidence stays local
and ignored under `docs/runs/**` or `out/**`; support bundles must pass
`tools/verify-redaction.mjs` or the RD-17 support-bundle scanner before any
summary is used for readiness decisions.

### Platform Proof Requirements

RD-19 is Windows-first. Platform proof requirements are:

- Windows x64 proof is required for internal package validation, install/delete
  handling of the unpacked RD-18 artifact, fullscreen shell behavior, display
  placement, sleep/wake observations, diagnostics export, helper crash
  recovery, and any native-presentation evidence.
- Mac/local automated proof is sufficient only for this docs-only planning pass
  and for source tests that exercise injected seams without OS behavior.
- Public release proof is blocked until signing, installer layout, production
  native helper/media binary provenance, update behavior, credential recovery,
  and live runtime behavior have reviewed owners.

## Files In Scope

- `docs/plans/rd-19-internal-alpha-beta-validation.md`

Future implementation units may only add files after reviewed plan approval.
Likely reviewed targets, if needed, are a redacted validation checklist under
`docs/architecture/` or `docs/development/`, a local-only run-bundle template
under ignored `docs/runs/**`, or narrow verifier tests for plan/checklist shape.

## Files Out Of Scope

- `src/**`
- `tools/**`
- `package.json`
- `package-lock.json`
- `out/**`
- `dist/**`
- `docs/runs/**` except ignored local evidence produced by a later approved
  validation run
- `docs/architecture/import-ledger.md` unless a later plan authorizes copied or
  adapted upstream source
- Any signing certificates, native helper binaries, media binaries, crash
  dumps, local media samples, token-bearing logs, or generated package
  artifacts

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions are
   resolved for the planning pass. Missing live runtime surfaces are explicitly
   blockers, not assumptions.
2. The plan does not depend on adjacent contract or type changes.
3. Files are out of scope only where the plan does not rely on hidden edits
   inside them.
4. Evidence path and Codanna/direct-read fallback are recorded.
5. The work is assigned to the docs/plan owner and avoids production hotspots.
6. Architecture Health evidence is included for Tier 3, with an avoidance
   decision for guarded production files.
7. A fresh session does not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
8. Verification commands, expected outcomes, and stop/replan triggers are
   explicit.

## Architecture Health

File-shape evidence from `docs/architecture/file-shape-guardrails.md` shows
current production owner hotspots in `src/main/player/desktopPlayerAdapter.ts`,
`src/domain/channel/channelManager.ts`,
`src/main/player/plexPlaybackRuntime.ts`,
`src/domain/channel/channelRepository.ts`, `src/contracts/player.ts`,
`src/main/plex/streamResolver.ts`,
`src/main/player/streamPolicy/desktopStreamPolicy.ts`,
`src/preload/index.cts`, `src/contracts/diagnostics.ts`, and
`src/domain/channel/channelAuthoringService.ts`.

Affected owner hotspots for this planner pass: none. The plan is docs-only and
does not grow production source, preload, contracts, player, Plex, channel,
renderer, diagnostics, or packaging tools.

Decision: avoid production owner growth. RD-19 must classify missing behavior
as blockers or stop/replan for a smaller enabling unit instead of expanding
oversized owners opportunistically. No allowlist baseline is raised, no
temporary allowlist row is added, and this plan does not pre-authorize future
growth in any guarded file.

Maintainability verification route: run `npm run verify:docs` for this
planning artifact. Any later source or guardrail change must run
`npm run verify:maintainability` directly or through `npm run
verify:architecture`/`npm run verify`, as required by that reviewed unit.

## Architecture Seam Decision Gate

Chosen seam: RD-19 is a validation-control-plane and release-readiness plan.
It records validation scope, proof requirements, and blocker taxonomy while
leaving runtime ownership unchanged.

Allowed validation seams:

- Renderer validation may use existing fake-backed UI surfaces and current
  preload APIs only.
- Main diagnostics validation may use current RD-17 diagnostics APIs and
  Windows smoke tooling.
- Package validation may use current RD-18 internal package tooling and
  verifier output only.
- Native-presentation validation may use dev-only RD-06/RD-15/RD-16 harness
  evidence only as presentation proof, not as production playback proof.

Forbidden shortcuts:

- Broad preload RPC, arbitrary IPC channels, or renderer access to Electron,
  Node, filesystem, Plex tokens, auth headers, tokenized URLs, native handles,
  helper diagnostics, or raw package paths.
- Runtime feature claims based on fake-backed UI, injected tests, or dev-only
  native-presentation smoke.
- Package claims that imply signing, update support, installer behavior,
  bundled native helper, media binary redistribution, or public distribution.
- Compatibility shims, upstream path mirrors, dependency additions, or package
  script changes to make validation easier.
- Any evidence workflow that stores raw secrets, local paths, media samples, or
  crash dumps in tracked docs.

Stop and replan if validation needs live Plex transport, production playback,
new preload/renderer APIs, persistence IPC, package script changes, native
binary layout, signing/update behavior, or any source edit outside a reviewed
bounded unit.

## Verification Commands

Verification classification: broader integration/manual proof required

Planning-pass verification:

- `npm run verify:docs`
  - Expected outcome: passes and confirms the active plan shape, Tier 3 handoff,
    Architecture Health section, required headings, and single verification
    classification marker.

Required commands before any later RD-19 validation unit is called done:

- `git status --short --branch`
  - Expected outcome: no unrelated tracked changes are included in the
    validation unit; generated output remains ignored.
- `npm run verify:docs`
  - Expected outcome: passes after docs/checklist changes.
- `npm run verify:redaction`
  - Expected outcome: passes before using any diagnostics, package, or manual
    evidence summary for readiness decisions.
- `npm run verify`
  - Expected outcome: passes for any source, contract, IPC, runtime, packaging,
    verifier, or harness change unless a reviewed unit names a narrower proof.

Windows x64 package and diagnostics proof commands for a later approved
validation run:

- `npm run build:electron`
  - Expected outcome: passes before packaging or RD-17 smoke.
- `node tools/package-windows-internal.mjs --out out/rd-18-windows-internal`
  - Expected outcome: on Windows x64 only, produces the reviewed unpacked
    internal package under
    `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/`.
- `node tools/verify-windows-internal-package.mjs --package out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`
  - Expected outcome: passes, confirms blocked native-helper/media markers,
    checksums, provenance, redaction-safe package evidence, and no signing or
    forbidden native/media material.
- `node tools/rd17-diagnostics-smoke.mjs --out docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke-rd19`
  - Expected outcome: on Windows only, passes with ignored local evidence,
    helper crash detected, main process alive, safe failed request state,
    helper cleanup/reap, replacement helper use, renderer-visible support
    bundle result limited to bundle identity, completed bundle scan passed, and
    forbidden material absent.

Manual/private validation proof, when later approved, must record only redacted
summary rows for the validation matrix: platform, app/package build identity,
scenario id, pass/fail/blocked status, blocker classification, command or
screen route used, and redaction scan status. Raw logs, media, screenshots with
local paths, support bundles, and package output stay ignored.

## Acceptance Criteria

- The active plan satisfies every required active-plan heading, declares
  `**Plan Status:** active`, `**Task family:** feature/design`, Tier 3 routing,
  and `## Architecture Health`.
- The private validation matrix covers auth, server selection, channel
  creation, playback, switching, subtitles/audio, EPG, settings, sleep/wake,
  fullscreen, multi-monitor, crash recovery, diagnostics export,
  install/uninstall, and long playback.
- The blocker matrix classifies missing or failed behavior as release blocker,
  beta blocker, or deferred without inventing runtime behavior.
- Evidence redaction policy forbids raw Plex, token, auth, filesystem, helper,
  native, crash, signing, media, and IPC material in tracked output.
- Platform proof requirements distinguish Windows x64 proof, local automated
  proof, and blocked public-release proof.
- Current-state constraints are preserved and meaningful private MVP gaps are
  routed to stop/replan for smallest reviewed enabling units.
- Verification commands include exact commands and expected outcomes for the
  planning pass and later approved validation units.
- The next handoff routes to `lineup-desktop-feature-review` for clean
  read-only plan review.

## Replan Triggers

Stop and replan before implementation or validation if:

- Any current-state constraint in `docs/architecture/CURRENT_STATE.md` changes.
- A reviewer finds that RD-19 implies live Plex, production playback, public
  release, persistence IPC, or signing/update behavior that does not exist.
- Validation requires a new preload method, IPC channel, renderer Plex API,
  persistence API, native helper contract, package script, dependency, or
  lockfile change.
- A support bundle, package artifact, log, screenshot, tester note, or summary
  contains forbidden material or fails redaction scanning.
- RD-18 package verification fails or the artifact is produced off Windows x64.
- RD-17 diagnostics smoke fails on Windows when crash recovery or support
  export readiness is being claimed.
- Sleep/wake, fullscreen, multi-monitor, or long-playback observations reveal a
  reproducible state corruption, resource leak, crash, focus trap, display
  placement failure, or unredacted diagnostics path.
- Broad manual validation would require testers to use real Plex credentials,
  real Plex media, or tokenized playback URLs before a reviewed live-runtime
  plan exists.

## Rollback Notes

This planning pass changes only the tracked plan file. Rollback is removal or
replacement of `docs/plans/rd-19-internal-alpha-beta-validation.md` with the
last reviewed plan state.

Later RD-19 validation units must keep generated package output, support
bundles, logs, and manual evidence ignored/local. If evidence is accidentally
tracked, stop, remove it from the index/worktree using non-destructive review of
the affected files, rerun redaction verification, and document only a sanitized
summary after review.

If a later unit adds a docs/checklist artifact and review rejects it, revert
that artifact only. Do not revert unrelated user or agent changes.

## Commit Checkpoints

Recommended checkpoint for this planner pass, if the user asks to commit:

- `docs: add RD-19 validation plan`

Do not stage unrelated changes. Do not commit generated `dist/**`, `out/**`, or
`docs/runs/**` artifacts. Future RD-19 execution units should use one focused
commit per reviewed unit when they change tracked docs, verifiers, or approved
source.

MODEL_SUGGESTION
PLANNER: gpt-5
IMPLEMENTER: n/a
REVIEWER: gpt-5
WHY: RD-19 is Tier 3 and crosses validation, diagnostics, packaging, security,
playback, Plex, and platform-proof boundaries while preserving missing-runtime
constraints.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review RD-19 Internal Alpha/Beta Validation Plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-19-internal-alpha-beta-validation.md
ARTIFACT: docs/plans/rd-19-internal-alpha-beta-validation.md
FILES:
- docs/plans/rd-19-internal-alpha-beta-validation.md
BLOCKERS: none known before read-only plan review
MESSAGE:
Perform a read-only adversarial review of the active RD-19 plan. Verify that it satisfies `docs/agentic/plan-authoring-standard.md`, preserves current-state constraints, does not invent live Plex or production native playback behavior, covers the required private validation and blocker matrices, includes release-blocker taxonomy, evidence redaction policy, platform proof requirements, Architecture Health, stop/replan triggers, exact verification commands with expected outcomes, and correctly routes the next gate after review.
