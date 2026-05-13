**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Complete RD-18 Windows Packaging And Release Pipeline through the first
internal Windows x64 packaging unit, then stop at closeout until the required
Windows x64 platform proof is observed on a Windows machine.

RD-18's first bounded implementation unit is exactly one internal Windows x64
unpacked/portable artifact layout plus provenance manifest generated under
`out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/`. Unit 1 must use
the existing Electron prebuilt runtime already locked in this repo, stage the
application payload only as unpacked `resources/app`, and must not add
packaging dependencies, package scripts, installer tooling, auto-update tooling,
or lockfile changes.

The plan freezes the first public release boundary as blocked: public signed
NSIS packaging, redistribution of native media binaries, and auto-update are
later units gated by reviewed licensing, provenance, signing, update-channel,
rollback, and Windows install-layout proof.

Platform proof label: Windows proof required before closeout. Expected Windows
proof surface is an observed Windows x64 internal package artifact with
renderer/main/preload Electron layout, provenance and checksum manifest,
license/notice audit, support-bundle redaction proof, install-layout inspection,
and native binary load proof when production helper/media binaries exist.

## Non-Goals

- Do not implement code during this planning pass.
- Do not change `package.json`, `package-lock.json`, package scripts, package
  metadata, dependencies, or devDependencies during planning or Unit 1.
- Do not add `electron-builder`, `@electron/packager`,
  `@electron/windows-sign`, `electron-updater`, NSIS tooling, signing
  configuration, update feed configuration, or release automation in Unit 1.
- Do not create a public installer, public release artifact, signed artifact,
  update metadata, release channel, or auto-update behavior in RD-18 Unit 1.
- Do not redistribute mpv/libmpv or other media binaries until exact binary
  versions, checksums, GPL/LGPL and third-party notices, source-offer/notice
  obligations, provenance, and legal/security review are complete.
- Do not treat RD-17 diagnostics smoke evidence as packaging proof.
- Do not grow renderer, preload, player, diagnostics, Plex, persistence, or
  native-helper runtime behavior as part of the packaging unit.
- Do not import or adapt upstream Lineup source in Unit 1.

## Parent Architecture Alignment

Current architecture says Lineup Desktop remains Windows-first and has no
packaging/signing/update pipeline. Production native-helper playback, production
playback host, live Plex transport, and live renderer Plex APIs also remain not
implemented. RD-17 added diagnostics/support-bundle behavior only; it did not
add packaging, signing, release, installer, auto-update, dependency, or lockfile
behavior.

RD-18 aligns with `docs/architecture/packaging-release-gates.md`: Windows x64
comes first; unsigned internal unpacked or portable artifacts are acceptable
before MVP; signed NSIS public distribution is the intended later shape; and
auto-update is deferred until signing, release channels, rollback behavior, and
native binary layout are stable.

The first unit advances the packaging architecture boundary by defining a
reviewable artifact layout and manifest surface around the already-built
Electron app. It does not widen renderer privilege, preload IPC, main/native
process ownership, Plex custody, credential persistence, support-bundle
redaction, or playback capability claims.

## Required Reading

Read in this order before review or implementation:

- `AGENTS.md`
- `docs/AGENTIC_DEV_WORKFLOW.md`
- `docs/agentic/session-prompts/feature-plan.md`
- `docs/agentic/session-prompts/feature-review.md`
- `docs/agentic/plan-authoring-standard.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/packaging-release-gates.md`
- `docs/architecture/file-shape-guardrails.md`
- `docs/architecture/import-ledger.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `package.json`
- `package-lock.json`
- `tsconfig.electron.json`
- `tools/clean-electron-build.mjs`
- `tools/copy-renderer-assets.mjs`
- `tools/smoke-electron.mjs`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`

Freshness gate: if package metadata, Electron version, lockfile package set,
dist layout, architecture docs, packaging docs, native-helper status, or
official Electron/electron-builder packaging guidance changed after
2026-05-13, stop and refresh this plan before implementation.

## Required Skills

- `lineup-desktop-feature-plan`: owns this Tier 3 active tracked planning pass.
- `execution-plan-authoring`: freezes scope, ownership seams, verification,
  acceptance criteria, rollback, and replan triggers without pseudo-code.
- `verification-strategy`: selects integration/manual proof because packaging
  cannot be closed by unit tests alone.
- `architecture-boundaries`: preserves Electron main/preload/renderer/helper
  ownership and prevents packaging work from becoming runtime IPC or privilege
  expansion.
- `persistence-boundaries`: protects app paths, generated artifacts, local-only
  evidence, support-bundle outputs, and any future signing credentials.
- `review-request`: routes this active plan to read-only adversarial review
  before implementation.
- `model-selection`: records Tier 3 model guidance for packaging/release risk.
- `closeout-verification`: applies only after review/implementation units,
  observed verification, and durable memory updates are complete.

## Evidence And Discovery

- Workspace and git state: `/Users/tristan/Software/LineupDesktop`; branch
  initially observed as `initial-build...origin/initial-build` with no dirty
  files before this plan. Controller status after plan creation showed
  `initial-build...origin/initial-build [ahead 1]` plus the untracked RD-18
  plan file.
- Codanna: index was fresh with 5565 symbols / 198 files / updated 32 minutes
  ago. Semantic searches were low-signal for packaging docs, so direct reads,
  `rg`, and package metadata were used as fallback. Record this fallback in
  review because packaging evidence mostly lives in docs, scripts, package
  metadata, dist shape, and official external docs rather than code symbols.
- Current architecture: `docs/architecture/CURRENT_STATE.md` records no
  packaging/signing/update pipeline; no production native-helper playback; no
  production playback host; no live Plex transport; no live renderer Plex APIs;
  and RD-17 diagnostics/support-bundle only.
- Packaging gate doc: `docs/architecture/packaging-release-gates.md` records
  Windows x64 first, signed NSIS as the eventual public distribution target,
  internal unpacked/portable artifacts as acceptable before MVP, auto-update
  deferred, and public distribution blockers for versions, native binaries,
  provenance/checksums, notices, signing, installer layout/native load proof,
  and redacted diagnostics export proof.
- `package.json`: private package, Apache-2.0, version `0.0.0`; scripts include
  `build:electron`, `smoke:electron`, and `verify:*`; no package, make, dist, or
  installer scripts.
- `package-lock.json`: lockfileVersion 3; 143 packages; Electron locked at
  `42.0.0`; no missing license fields observed.
- `npm ls --depth=0` evidence: `@eslint/js@10.0.1`, `@types/node@22.19.17`,
  `@typescript-eslint/eslint-plugin@8.59.2`,
  `@typescript-eslint/parser@8.59.2`, `electron@42.0.0`,
  `eslint@10.3.0`, `tsx@4.21.0`, and `typescript@5.9.3`.
- Runtime version proof: `ELECTRON_RUN_AS_NODE=1 ./node_modules/.bin/electron
  -p ...` observed Electron `42.0.0`, Node `24.15.0`, Chrome
  `148.0.7778.96`, V8 `14.8.178.14-electron.0`, modules `146`, and napi `10`.
  Host `node` was `24.14.0`; package engine is `>=22.12.0`.
- Dist shape: `dist/**` currently contains compiled contracts, domain, main,
  preload, and renderer JS/maps plus copied renderer `index.html`, `styles.css`,
  and `styles/**`. There is no package artifact and no `build/**` output.
- Build shape: `npm run build:electron` runs
  `tools/clean-electron-build.mjs`, `tsc -p tsconfig.electron.json`, and
  `tools/copy-renderer-assets.mjs`. `smoke:electron` runs Electron against
  `dist/main/index.js` with `LINEUP_DESKTOP_SMOKE=1` and
  `NODE_ENV=production`.
- Native/media evidence: RD-06 spike remains dev-only under
  `tools/libmpv-spike`; known local prerequisite root is
  `C:\Software\LineupDesktop-prereqs\mpv\shinchiro-20260421-x86_64-dev`.
  Prior mpv evidence recorded `mpv v0.41.0-524-g5921fe50b`, libmpv client API
  `2.5`, provenance `official-installation-page-linked-shinchiro-windows-build`,
  and redistribution `not-redistributed-local-proof-only`. This is not a
  production packaged binary decision.
- RD-17 evidence: Windows-only smoke, ignored local evidence, and support-bundle
  redaction proof exist, but they are diagnostics proof, not packaging proof.
- File-shape evidence: `npm run verify:maintainability` passed. Relevant counts
  observed were `package.json` 42, `tsconfig.electron.json` 15,
  `tools/clean-electron-build.mjs` 7, `tools/copy-renderer-assets.mjs` 19,
  `tools/smoke-electron.mjs` 25, `tools/rd17-diagnostics-smoke.mjs` 489,
  `src/main/player/nativePlayerHostProcess.ts` 500,
  `src/contracts/diagnostics.ts` 553, `src/preload/index.cts` 1031, and
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` 1842.
- Existing guardrail allowlist includes `src/contracts/diagnostics.ts` and
  `src/preload/index.cts`; RD-18 must avoid growing them.
- Official docs checked 2026-05-13: Electron packaging tutorial, application
  distribution, code signing, and updating docs; electron-builder NSIS/Windows
  docs. Electron docs say core Electron has no bundled
  packaging/distribution tooling; manual packaging uses prebuilt binaries with
  app under `resources/app` or `app.asar`; Windows installer signing is needed
  for distribution; and auto-update has separate metadata/update requirements.
  electron-builder docs show Windows target options including
  files/extraResources/signing and NSIS target options.
- `npm view` on 2026-05-13 observed candidate packages:
  `electron-builder@26.8.1` MIT, `@electron/packager@20.0.0` BSD-2-Clause,
  `@electron/windows-sign@2.0.3` BSD-2-Clause, and `electron-updater@6.8.3`
  MIT. These are candidates for later reviewed units only, not Unit 1.
- Accepted review blocker from plan review: Unit 1 was not
  decision-complete because the plan left `resources/app` versus equivalent
  layout optional, kept `app.asar` optional, and did not name the tool, docs,
  package/provenance/checksum, or install-layout command surfaces. Verdict:
  accept. Fix scope for this pass is this plan only, freezing Unit 1 layout,
  files, commands, verification, acceptance criteria, replan triggers, and
  handoff routing for clean read-only re-review before implementation.

## Impact Snapshot

- Owners that may change in Unit 1: exact new packaging/provenance tool and
  test files named below, the exact internal artifact staging layout named
  below, and generated local artifacts that must stay untracked.
- Owners that must not change in Unit 1: `package.json`, `package-lock.json`,
  runtime Electron main/preload/renderer source, contracts, Plex owners,
  persistence owners, diagnostics runtime, native-helper runtime, and
  file-shape guardrail baselines.
- Public contracts: no renderer, preload, IPC, diagnostics, player, Plex,
  persistence, native-helper, or update contract changes in Unit 1.
- Dependency/build-tool/configuration impact: no dependency, lockfile, package
  script, signing config, installer config, or update config changes in Unit 1.
- Commands/tests/docs that may change later: Unit 1 may add only
  `tools/package-windows-internal.mjs`,
  `tools/verify-windows-internal-package.mjs`, and
  `tools/__tests__/package-windows-internal.test.mjs`; it may update
  `docs/architecture/packaging-release-gates.md` only if implementation
  produces durable conclusions that must be promoted beyond this active plan.
  Existing docs verification remains required for this plan. Source-wide
  verification is reserved for implementation units that touch source or build
  behavior.
- User-visible runtime behavior: no app behavior changes in Unit 1. Artifact
  layout may change only outside runtime execution until a reviewed packaging
  command creates the internal portable/unpacked output.
- Local-only artifacts: package outputs, checksums, local evidence, raw
  diagnostics bundles, native binary proof, and Windows run bundles must remain
  ignored/local unless a later reviewed doc promotes only redacted durable
  conclusions.
- First execution unit remains single-owner: packaging/provenance artifact
  layout. Public installer, signing, update, native media redistribution, and
  production helper playback are split into later gates.

## Architecture Health

RD-18 should avoid growing existing production hotspots. Unit 1 must not touch
`src/preload/index.cts`, `src/contracts/diagnostics.ts`,
`src/main/player/nativePlayerHostProcess.ts`, player runtime files, Plex files,
renderer composition files, or CSS surfaces. The plan explicitly blocks using
packaging work to add bridge vocabulary, diagnostics schemas, playback helper
commands, or renderer APIs.

Known file-shape evidence for this planning pass:

- `src/preload/index.cts` is 1031 lines and already allowlisted; do not add
  another bridge namespace, diagnostics result family, arbitrary RPC, context
  exposure, or channel vocabulary for packaging.
- `src/contracts/diagnostics.ts` is 553 lines and already allowlisted; do not
  add packaging/support-bundle schemas there in Unit 1.
- `src/main/player/nativePlayerHostProcess.ts` is 500 lines; do not grow native
  host runtime code for packaging until production helper behavior is reviewed
  in a later plan.
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` is 1842 lines and
  dev-only; do not promote it into production packaging.
- `tools/rd17-diagnostics-smoke.mjs` is 489 lines; do not turn diagnostics
  smoke into packaging smoke.

Decision: Unit 1 avoids existing owner hotspots by creating or changing only a
focused packaging/provenance surface if implementation needs one, and keeping
generated artifact assembly separate from existing runtime owners. No file-shape
baseline may be raised or used to pre-authorize future growth for RD-18 Unit 1.
If a future implementation needs to touch an allowlisted or near-threshold
production file, stop and replan with a new Architecture Health decision before
editing.

Maintainability route: `npm run verify:maintainability` remains the expected
source-shape proof for any later production source or guardrail change. It is
not required for this planning-only edit unless a reviewer requests it.

## Implementation Unit Selection

Selected first unit: internal Windows x64 unpacked/portable artifact layout and
provenance manifest.

Why this unit comes first: it proves the smallest packaging boundary using the
repo's existing Electron prebuilt runtime, current `dist/**` output, current
license metadata, and explicit native/media blockers. It creates the evidence
surface later public release work needs without taking on installer signing,
auto-update, native media redistribution, CI release publishing, or dependency
selection.

Parallelism: no implementation parallelism for Unit 1. Review may use
read-only side evidence, but the implementation owner must keep one artifact
layout and one manifest contract to avoid contradictory package shapes.

Exit to later units only after Unit 1 has reviewed Windows proof and redacted
durable conclusions:

- signed public NSIS installer
- signing credential and certificate handling
- release channel and auto-update metadata
- production native-helper/media binary packaging
- CI release automation

## Files In Scope

Planning pass:

- `docs/plans/rd-18-windows-packaging-release-pipeline.md`

RD-18 Unit 1, after clean read-only plan review only:

- `tools/package-windows-internal.mjs`
- `tools/verify-windows-internal-package.mjs`
- `tools/__tests__/package-windows-internal.test.mjs`
- Optional: `docs/architecture/packaging-release-gates.md` only if durable
  packaging/release-gate conclusions need reference-doc updates during
  implementation.
- Ignored/local Windows package artifact output paths, checksums, and evidence
  bundles.
- Existing read-only build inputs: `dist/**`, `node_modules/electron/**`,
  `package.json`, `package-lock.json`, `tsconfig.electron.json`,
  `tools/clean-electron-build.mjs`, `tools/copy-renderer-assets.mjs`, and
  `tools/smoke-electron.mjs`.

Artifact layout decision for Unit 1:

- Electron runtime: use the installed Electron prebuilt runtime corresponding
  to the locked `electron@42.0.0`; record Electron, Node, Chrome, V8, modules,
  and napi versions in the provenance manifest.
- Output root: generate only
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/` for Unit 1.
- Application payload: place the built app only under Electron's expected
  unpacked `resources/app` layout using the current `dist/**` output. Unit 1
  must not use `app.asar` and must not use any equivalent or alternate reviewed
  layout.
- Entrypoint executable: the generated local package must contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/LineupDesktop.exe`.
- Staging manifest: the generated local package must contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/app/package.json`
  with `main: dist/main/index.js`; `name`, `version`, `license`, and `type`
  copied from tracked package metadata; and no dependency install.
- Application dist payload: the generated local package must contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/app/dist/**`.
- Renderer assets: include copied `dist/renderer/index.html`,
  `dist/renderer/styles.css`, and `dist/renderer/styles/**` exactly as produced
  by the current build shape.
- Native helper: production native helper does not exist yet. The generated
  local package must contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/native-helper/PRODUCTION_HELPER_BLOCKED.txt`.
- Media binaries: production mpv/libmpv redistribution is blocked. The
  generated local package must contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/media-binaries/REDISTRIBUTION_BLOCKED.txt`
  and must not copy local RD-06 prerequisite binaries into a redistributable
  package.
- Provenance manifest: record runtime versions, package metadata, lockfile
  package count, build input hashes or checksums, artifact file checksums,
  license/notice audit status, native/media blocked status, support-bundle
  redaction proof reference, and Windows proof status.
- Generated manifest/checksum/notices files: the generated local package must
  contain
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`,
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/checksums.sha256`,
  and
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/third-party-notices-internal.json`.

## Files Out Of Scope

- `package.json`
- `package-lock.json`
- `node_modules/**`
- `src/preload/index.cts`
- `src/contracts/diagnostics.ts`
- `src/contracts/player.ts`
- `src/contracts/ipc.ts`
- `src/main/index.ts`
- `src/main/player/**`
- `src/main/plex/**`
- `src/main/persistence/**`
- `src/main/diagnostics/**`
- `src/renderer/**`
- `tools/libmpv-spike/**`
- `docs/architecture/import-ledger.md` unless a later reviewed unit copies or
  adapts upstream Lineup source, which Unit 1 must not do.
- `docs/architecture/file-shape-guardrails.md` unless a later reviewed source
  shape change requires it, which Unit 1 should avoid.
- Public release notes, installer config, signing config, update metadata,
  certificates, secrets, upload credentials, CI release jobs, and native media
  redistribution materials.

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions for
   Unit 1 are resolved: exactly one internal Windows x64 unpacked/portable
   artifact layout under
   `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/`, unpacked
   `resources/app` payload only, no `app.asar`, no alternate layout, exact
   future tool/test surfaces, no new dependency, no package or lockfile change,
   no public release, no auto-update, and Windows proof before closeout.
2. The plan does not depend on adjacent contract or type changes. If an
   implementer finds a contract change is needed, stop and replan.
3. Files out of scope are not hidden dependencies for Unit 1 behavior. They are
   read-only inputs or explicitly blocked runtime owners.
4. Evidence and fallback reads are recorded, including Codanna low-signal
   fallback to direct reads, `rg`, package metadata, dist shape, and official
   docs.
5. The work is assigned to a packaging/provenance owner rather than growing
   preload, diagnostics, native-player, Plex, persistence, or renderer hotspots.
6. Tier 3 Architecture Health is included and avoids allowlist growth.
7. A fresh implementer should not need to invent packaging, signing,
   auto-update, media redistribution, native-helper, security, IPC, persistence,
   or verification policy for Unit 1.
8. Verification commands, expected outcomes, stop/replan triggers, rollback
   notes, and read-only plan review gate are explicit.

Current execution state: Unit 1 plan review is clean, Unit 1 implementation is
locally implemented, and the scoped implementation re-review is clean after
accepted verifier fixes. RD-18 is not complete because the required Windows x64
platform proof has not been observed in this workspace.

## Architecture Seam Decision Gate

Chosen owner seam: RD-18 Unit 1 belongs to a packaging/provenance artifact owner
that consumes the existing Electron build output and locked Electron prebuilt
runtime as inputs. It must not move packaging responsibilities into renderer,
preload, IPC contracts, diagnostics schemas, player runtime, Plex runtime,
persistence, or native-helper runtime.

Forbidden shortcuts:

- No broad IPC, arbitrary renderer RPC, raw filesystem path exposure, native
  handle exposure, token/auth-header exposure, or renderer access to packaging
  internals.
- No dependency or lockfile change in Unit 1.
- No public package/installer/update artifact before signing, release-channel,
  rollback, native binary, checksum, and license/notice gates pass.
- No redistribution of the RD-06 local mpv/libmpv prerequisite binaries without
  reviewed binary identity, checksums, GPL/LGPL and third-party notices,
  source-offer/notice obligations, provenance, and security review.
- No treating RD-17 Windows diagnostics smoke as package/install proof.
- No local-only artifact paths, raw support bundles, crash dumps, native media
  logs, secrets, certificates, or signing credentials in tracked files.

Stop and replan if implementation needs package scripts, lockfile changes,
third-party packaging tools, signing tools, auto-update libraries, native helper
runtime changes, mpv/libmpv redistribution, public installer behavior, CI
release jobs, or changes to out-of-scope runtime owners.

## Invariants And Scope Rules

- Unit 1 must keep renderer unprivileged and preload narrow.
- Main/helper ownership remains unchanged; packaging may stage files but must
  not define new helper runtime behavior.
- Redaction remains mandatory for diagnostics/support-bundle proof and package
  evidence. No raw Plex tokens, tokenized URLs, auth headers, media logs,
  crash dumps with secrets, native paths containing secrets, certificates, or
  signing credentials may be committed.
- Import provenance remains unchanged because Unit 1 has no copied/adapted
  upstream Lineup source. If a later unit copies/adapts source, update
  `docs/architecture/import-ledger.md` before or with that import.
- Auto-update policy: disabled for RD-18 until signing, release channels,
  rollback behavior, and native binary layout are stable. Unit 1 must not add
  `electron-updater` or update metadata.
- Public/internal packaging policy: Unit 1 may create only an internal artifact
  for local Windows proof. Public signed NSIS packaging is later gated and
  likely uses reviewed `electron-builder@26.8.1` only after
  licensing/provenance/signing gates pass.
- Dependency policy: if any packaging tool becomes necessary in a future unit,
  that unit must name the runtime owner, security/licensing/provenance risk,
  package and lockfile impact, verification, rollback, and why existing
  Electron/npm tooling is insufficient. Candidate evidence from 2026-05-13 is
  `electron-builder@26.8.1` MIT, `@electron/packager@20.0.0` BSD-2-Clause,
  `@electron/windows-sign@2.0.3` BSD-2-Clause, and `electron-updater@6.8.3`
  MIT.
- Signing policy: no signing credentials, certificate paths, password material,
  or secret-backed CI variables may be introduced without a separate reviewed
  signing plan.
- Local artifact policy: package output, checksums, and proof bundles stay
  ignored/local unless a later reviewed doc promotes redacted conclusions.

## Verification Commands

Verification classification: broader integration/manual proof required

Planning pass expected verification:

- `npm run verify:docs`
  Observed outcome on 2026-05-13: passed. Active plan structure, required
  headings, exactly one verification classification marker, markdown links, and
  docs verifier checks were accepted.

This planning session intentionally does not run implementation or packaging
commands. The next review session must treat the plan as review target first;
implementation commands are future gates only.

Future RD-18 Unit 1 proof surface, to be added by implementation when reviewed:

- Build proof command: `npm run build:electron`.
  Expected outcome: `dist/**` is freshly produced with main/preload/renderer
  compiled outputs and copied renderer assets.
- Internal package command:
  `node tools/package-windows-internal.mjs --out out/rd-18-windows-internal`.
  Expected outcome: only
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/` is produced from
  the existing Electron prebuilt runtime and `dist/**` without new
  dependencies, package scripts, dependency installs, or lockfile changes.
- Package verification, provenance, checksum, redaction, and install-layout
  inspection command:
  `node tools/verify-windows-internal-package.mjs --package out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`.
  Expected outcome: the verifier confirms `LineupDesktop.exe`, unpacked
  `resources/app/package.json`, `resources/app/dist/**`, blocked native-helper
  and media-binary marker files, provenance manifest, checksums, and internal
  notices are present; the staging manifest has `main: dist/main/index.js` and
  only copied `name`, `version`, `license`, and `type` metadata; checksums match
  staged files; license/notice status is recorded for the current internal
  package; package evidence under `out/rd-18-windows-internal` contains no raw
  Plex tokens, tokenized URLs, auth headers, secret paths, crash dumps with
  secrets, native media logs with forbidden material, certificates, or signing
  credentials.
- Tooling test command: `npm run test:harness-docs`.
  Expected outcome: the implementation adds focused coverage for the packaging
  tool and verifier while using the existing full harness-docs runner because
  this plan does not rely on `node --test` name-pattern passthrough.
- Docs verification command: `npm run verify:docs`.
  Expected outcome: active-plan structure, command surfaces, docs links,
  verification marker count, and any updated packaging-gates reference doc pass.
- Existing repo-wide redaction proof command: `npm run verify:redaction`.
  Expected outcome: existing tracked redaction surfaces still pass. Redaction
  proof for generated `out/rd-18-windows-internal` package evidence is owned by
  `tools/verify-windows-internal-package.mjs` unless a reviewed implementation
  explicitly extends the repo-wide verifier to scan that output path.
- Native binary load proof command is future-blocked until production
  helper/media binaries exist.
  Expected outcome when unblocked: packaged app loads the reviewed production
  helper/media binary from the approved path on Windows x64 and records version,
  checksum, license/notice, cleanup, and redaction evidence.

Future public installer/signing/update gates:

- Public NSIS proof is blocked until a reviewed future unit decides installer
  tooling, likely `electron-builder@26.8.1`, and passes signing,
  license/provenance, install-layout, native-load, checksum, redaction, and
  rollback proof.
- Auto-update proof is blocked until signing, release channels, update metadata,
  rollback behavior, and native binary layout are stable. No `electron-updater`
  dependency is allowed in Unit 1.

## Acceptance Criteria

- The active plan exists at exactly
  `docs/plans/rd-18-windows-packaging-release-pipeline.md`.
- The plan includes `**Plan Status:** active`, `**Task family:** feature/design`,
  and `**Tier:** Tier 3` before the first heading.
- Required plan-standard headings appear in order, with `## Architecture Health`
  before implementation-unit selection and `## Invariants And Scope Rules`
  included.
- The plan records workspace, branch/status evidence, Codanna freshness and
  fallback, current architecture blockers, package metadata, lockfile/runtime
  evidence, dist/build shape, native/media limitations, RD-17 limitation, file
  shape evidence, and official docs/candidate package evidence from
  2026-05-13.
- The plan selects Unit 1 as internal Windows x64 unpacked/portable artifact
  layout plus provenance manifest, using the existing Electron prebuilt runtime
  and no new packaging dependency.
- The plan freezes Unit 1 to exactly
  `out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/` with unpacked
  `resources/app` only, no `app.asar`, and no alternate reviewed layout.
- The plan freezes the required generated local package files:
  `LineupDesktop.exe`, `resources/app/package.json`,
  `resources/app/dist/**`,
  `resources/native-helper/PRODUCTION_HELPER_BLOCKED.txt`,
  `resources/media-binaries/REDISTRIBUTION_BLOCKED.txt`,
  `resources/lineup-desktop-provenance.json`, `resources/checksums.sha256`,
  and `resources/third-party-notices-internal.json`.
- The plan freezes Unit 1 tracked implementation surfaces to
  `tools/package-windows-internal.mjs`,
  `tools/verify-windows-internal-package.mjs`,
  `tools/__tests__/package-windows-internal.test.mjs`, and optional
  `docs/architecture/packaging-release-gates.md` only for durable reference-doc
  conclusions.
- The plan freezes Unit 1 command surfaces exactly without package scripts:
  `npm run build:electron`,
  `node tools/package-windows-internal.mjs --out out/rd-18-windows-internal`,
  `node tools/verify-windows-internal-package.mjs --package out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`,
  `npm run test:harness-docs`, `npm run verify:docs`, and
  `npm run verify:redaction`.
- The plan explicitly blocks dependency/package-lock changes in Unit 1 and
  defines the required decision record for any future packaging tool.
- The plan resolves Electron, renderer, native-helper, and media-binary artifact
  layout, including blocked placeholders/manifest entries for missing
  production helper/media binaries.
- The plan disables auto-update for RD-18 and blocks `electron-updater` in
  Unit 1.
- The plan labels platform proof as Windows proof required before closeout and
  names the expected proof surface.
- The plan routes next to clean read-only re-review and does not call
  implementation ready before review passes.

## Replan Triggers

- `npm run verify:docs` fails for active-plan shape, links, markers, or
  structure.
- Read-only plan review finds unresolved ownership, dependency, packaging,
  signing, native-media, update, verification, or public-release decisions.
- Re-review finds Unit 1 still allows `app.asar`, an alternate package layout,
  more than one generated output root, unnamed tool/test/doc surfaces, package
  scripts, dependency installs, or ambiguous package/provenance/checksum/install
  layout command surfaces.
- Electron, Node, Chrome, V8, lockfile contents, package metadata, package
  scripts, dist shape, or official packaging docs changed materially after
  2026-05-13.
- Unit 1 needs a package script, dependency, lockfile change, installer tool,
  signing tool, update library, CI release job, or `electron-builder` config.
- Unit 1 needs to change `package.json`, `package-lock.json`, package scripts,
  dependency metadata, dependency installation behavior, signing secret
  handling, auto-update behavior, public NSIS installer behavior, native-helper
  runtime behavior, mpv/libmpv redistribution, live Plex behavior, or
  renderer/preload/IPC behavior.
- Unit 1 needs to touch `src/preload/index.cts`,
  `src/contracts/diagnostics.ts`, `src/main/player/**`, `src/main/plex/**`,
  `src/main/persistence/**`, `src/renderer/**`, or other runtime owners.
- Implementation needs to redistribute mpv/libmpv or any media binary.
- Native helper/media binaries become available and change packaging proof
  surface.
- Windows proof is unavailable before closeout.
- Any artifact evidence would require committing local package outputs, raw
  support bundles, checksums tied to secret paths, certificates, credentials, or
  unredacted diagnostics.

## Rollback Notes

- Planning rollback: remove or revert only
  `docs/plans/rd-18-windows-packaging-release-pipeline.md`; no product files,
  package files, lockfiles, dependencies, or generated artifacts should have
  changed during this planning pass.
- Unit 1 rollback: delete generated internal package output, checksums,
  manifests, and local evidence bundles; revert only reviewed packaging docs or
  tools added for the unit; leave existing build/runtime source and lockfiles
  untouched.
- Future dependency rollback: if a later reviewed unit adds a packaging tool,
  rollback must remove package metadata and lockfile changes, generated config,
  package scripts, installer outputs, and docs references in the same focused
  revert unless a reviewed replan preserves part of the change.
- Public release rollback: public installer, signing, update metadata, and
  native/media redistribution are blocked in Unit 1, so rollback should not
  need to revoke certificates, pull public artifacts, or disable update feeds.
  If a future unit crosses that boundary, it must define its own rollback before
  implementation.

## Commit Checkpoints

- Checkpoint 1: `docs(plans): add rd-18 windows packaging release plan`
  containing only this active plan, after read-only plan review and
  `npm run verify:docs` pass or after accepted review fixes are applied.
- Checkpoint 2: `build(packaging): add internal windows artifact layout`
  reserved for reviewed Unit 1 implementation only. It must exclude
  `package.json`, `package-lock.json`, dependency changes, public installer
  config, signing config, update config, and native media redistribution unless
  a reviewed replan supersedes Unit 1.
- Later checkpoints: public signed NSIS, signing, update, and native media
  redistribution each require a separate reviewed unit or replan. Do not batch
  them with Unit 1.

MODEL_SUGGESTION
PLANNER: planner, high reasoning
IMPLEMENTER: worker, high reasoning
REVIEWER: reviewer, high reasoning
WHY: Tier 3 packaging/release work touches Electron distribution, native media
redistribution blockers, signing/update gates, dependency policy, and Windows
manual proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-18 Windows Packaging And Release Pipeline Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/rd-18-windows-packaging-release-pipeline.md
ARTIFACT: RD-18 Unit 1 internal Windows package tooling and verifier
FILES:
- docs/plans/rd-18-windows-packaging-release-pipeline.md
- tools/package-windows-internal.mjs
- tools/verify-windows-internal-package.mjs
- tools/__tests__/package-windows-internal.test.mjs
BLOCKERS: RD-18 closeout is blocked on observed Windows x64 platform proof.
MESSAGE:
Continue the Tier 3 feature-quality-loop at closeout-pending for RD-18 Unit 1.
The active plan review is clean and the implementation review is clean. Local
macOS controller verification passed with `node --test
tools/__tests__/package-windows-internal.test.mjs` 18/18, `npm run
test:harness-docs` 144/144, `npm run verify:docs`, `npm run
verify:redaction`, `npm run build:electron`, and `npm run verify`. On macOS,
`node tools/package-windows-internal.mjs --out out/rd-18-windows-internal`
correctly exits 1 with the Windows x64 refusal message.

Windows closeout proof to run on a Windows x64 checkout of this commit:

1. Confirm the checkout includes packaging implementation commit
   `eb36ed37ee743d88ea144db75909cde8882f1d88` in `git log --oneline`, then
   record `git rev-parse HEAD` and `git status --short --branch` before the
   proof run.
2. Confirm `node -p "process.platform + ' ' + process.arch"` prints
   `win32 x64`.
3. Run `npm ci` only if dependencies are not already installed from the
   committed `package-lock.json`; do not change `package.json` or
   `package-lock.json`.
4. Run `npm run build:electron`.
5. Run `node tools/package-windows-internal.mjs --out
   out/rd-18-windows-internal`.
6. Run `node tools/verify-windows-internal-package.mjs --package
   out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest
   out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`.
7. Inspect and summarize, without committing generated artifacts, that the
   package contains `LineupDesktop.exe`, `resources/app/package.json`,
   `resources/app/dist/**`,
   `resources/native-helper/PRODUCTION_HELPER_BLOCKED.txt`,
   `resources/media-binaries/REDISTRIBUTION_BLOCKED.txt`,
   `resources/lineup-desktop-provenance.json`,
   `resources/checksums.sha256`, and
   `resources/third-party-notices-internal.json`.
8. Confirm the verifier output is clean, the provenance records Electron/Node
   runtime versions from the Windows Electron runtime, artifact checksum
   manifest rows use deterministic relative path ordering, native helper and
   media binaries remain blocked placeholders only, generated package evidence
   is redaction-safe, and public release/signing/update remain blocked.
9. Record `git status --short --branch` after the proof run. Expected tracked
   changes: none. Expected local-only generated output: ignored
   `out/rd-18-windows-internal/**` and any ignored redacted proof notes.

Do not call RD-18 done until the Windows x64 run observes that real generated
artifact and records redacted layout/provenance/checksum evidence. Do not add
or change package scripts, dependencies, lockfiles, signing config, update
metadata, native media binaries, Plex behavior, renderer/preload/IPC contracts,
or runtime behavior while collecting this proof. Keep `out/rd-18-windows-internal`
and any raw proof bundle local/ignored.
