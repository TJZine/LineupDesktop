# RD-07 Desktop VideoPlayer Adapter Plan

**Plan Status:** complete

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** done

**Verification classification:** broader integration/manual proof required

## Goal

Finish RD-07 after the reviewed adapter core, runtime IPC/preload bridge, and
Mac-reviewed native-host process seam by authorizing one Windows closeout unit:
`desktop-player-windows-native-host-proof`.

Preserved baseline:

- Commit `75062e0` wires the reviewed runtime player IPC/preload bridge through
  `src/main/player/playerIpc.ts` and `window.lineupDesktop.player`.
- Commit `e2df530` closes out the RD-07 runtime bridge docs and roadmap state.
- The existing `DesktopPlayerAdapter`, `NativePlayerHostPort`, and player IPC
  bridge remain the reviewed public seam.

The plan review completed with no blockers. The Mac-bounded process-seam unit
was implemented, verified, reviewed, fixed, and re-reviewed with no remaining
blockers. The next RD-07 gate is Windows native-host proof and RD-07 closeout.
This unit must prove the reviewed process seam on Windows with a real spawned
helper test double, rerun the RD-06 app-owned native-presentation smoke as the
native surface proof inherited by RD-07, update closeout docs, and leave
production player commands renderer-safe unsupported until a later product
native-helper plan enables real Plex-backed playback.

## Non-Goals

- Do not claim Windows proof from macOS or from source audit alone.
- Do not reopen WID or helper-owned render API directions.
- Do not change renderer, preload, shared renderer-facing player contracts, or
  `src/main/index.ts` in this Windows closeout unit.
- Do not expose raw URLs, tokens, auth headers, native handles, libmpv objects,
  engine ids, raw Plex payloads, stream keys, part keys, Electron APIs, Node
  APIs, or secret diagnostics to renderer-facing state, tests, logs, docs, or
  Codex output.
- Do not move native process policy into `src/main/index.ts`, `App.ts`, future
  orchestration owners, renderer UI, Plex owners, scheduler owners, or storage
  owners.
- Do not add production native helper binaries, native addons, libmpv bindings,
  package scripts, dependencies, lockfile changes, packaging, signing, or
  installer work.
- Do not contact Plex, implement stream setup, resolve media URLs, move tokens,
  import scheduler/channel code, import renderer UI, or update secure storage.
- Do not edit RD-05/RD-06 spike tools as part of this RD-07 closeout unit.
- Do not update unrelated dirty files, stage unrelated work, or treat local
  generated artifacts as RD-07 proof.

## Parent Architecture Alignment

`docs/architecture/CURRENT_STATE.md` and
`docs/architecture/playback-architecture.md` record that RD-07 currently has a
main-owned adapter core and narrow runtime IPC/preload delivery backed by a
development/smoke fake host. Production commands still return renderer-safe
unsupported failures. Plex stream setup, renderer UI wiring, and a real native
helper remain unimplemented.

RD-06 routes future real native playback toward app-owned native presentation.
The Windows closeout unit may use the existing RD-06 native-presentation smoke
to prove the native surface direction on this Windows host, and may harden
`NativePlayerHostProcess` tests so the RD-07 adapter/process seam starts and
cleans up a real child process on Windows. It must not assert that a production
Plex-backed native helper or renderer UI has landed in product code.

Ownership alignment:

- `src/main/player/playerIpc.ts` remains the player host policy and factory
  owner. It may select the existing development/smoke fake host, production
  unsupported behavior, or the reviewed process seam only through reviewed plain
  options.
- `src/main/player/nativePlayerHostPort.ts` remains the private adapter-facing
  host contract. Additions must stay renderer-safe and must not expose native
  handles or engine objects.
- `src/main/player/nativePlayerHostProcess.ts` owns process lifecycle plumbing,
  adapter-to-process command translation, line/message parsing, cleanup/reap
  behavior, and redacted diagnostics for test doubles.
- `src/main/player/desktopPlayerAdapter.ts` may change only if the host port
  needs a narrow lifecycle or event callback seam.
- `src/main/index.ts` remains out of scope for this unit. It already passes
  `shellMode` and callbacks into `playerIpc.ts`; native process policy must not
  move there.
- Renderer, preload, contract, Plex, scheduler, secure storage, and packaging
  owners remain unchanged.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/session-prompts/feature-plan.md`
5. `docs/agentic/session-prompts/feature-review.md`
6. `docs/agentic/session-prompts/feature-implement.md`
7. `docs/agentic/plan-authoring-standard.md`
8. `docs/architecture/CURRENT_STATE.md`
9. `docs/architecture/playback-architecture.md`
10. `docs/architecture/security-and-secret-flow.md`
11. `docs/architecture/upstream-behavior-guardrails.md`
12. `docs/roadmap/desktop-port-roadmap.md`
13. This plan
14. `src/contracts/player.ts`
15. `src/contracts/ipc.ts`
16. `src/contracts/shell.ts`
17. `src/main/player/desktopPlayerAdapter.ts`
18. `src/main/player/nativePlayerHostPort.ts`
19. `src/main/player/playerIpc.ts`
20. `src/preload/index.cts`
21. `src/main/index.ts`
22. `src/__tests__/desktopPlayerAdapter.test.ts`
23. `src/__tests__/playerIpc.test.ts`
24. `src/__tests__/nativePlayerHostProcess.test.ts`
25. `src/__tests__/contracts.test.ts`
26. `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
27. `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
28. `package.json`

Freshness gate: rerun `git status --short --branch` before implementation.
Stop for plan update and re-review if architecture docs, roadmap status,
contract files, player source, package scripts, verifier behavior, or this plan
changed materially after this refresh.

## Required Skills

- `lineup-desktop-feature-quality-loop`: required Tier 3 controller for native
  playback and IPC/security boundary work.
- `lineup-desktop-feature-plan`: used for this plan refresh.
- `execution-plan-authoring`: required for durable seam, scope, verification,
  rollback, and stop conditions.
- `architecture-boundaries`: required because the work touches main/player host
  process ownership and adapter boundaries.
- `verification-strategy`: required because the Windows closeout combines
  focused adapter/process tests, Electron smoke, RD-06 native-presentation
  proof, redaction, and manual/source audit evidence without overclaiming a
  production native helper.
- `plex-integration-boundaries`: required as a constraint because future stream
  setup will be Plex-derived, while this unit must keep Plex URLs, tokens,
  headers, and payloads out of scope.
- `review-request`: required for the fresh read-only plan and implementation
  reviews.
- `review-adjudication`: required before acting on review findings.
- `closeout-verification`: required before committing, staging, or handing off.

## Evidence And Discovery

- `semantic_search_with_context`: attempted by the controller. Codanna returned
  stale or wrong-repo results from `/Users/tristan/Software/Lineup` rather than
  useful Lineup Desktop ownership evidence, so it is not authoritative for this
  refresh.
- `semantic_search_docs` and repo-document search: attempted by the controller
  and likewise returned stale or wrong-repo context. Direct reads are the
  authoritative evidence path for this plan.
- Impact analysis: not used because the available semantic index was noisy for
  this checkout. Ownership was determined by direct source and doc reads.
- Direct reads / `rg`: read `AGENTS.md`, workflow runbook, feature quality
  loop, feature plan/review/implement launchers, plan standard, current
  architecture, playback architecture, security and secret flow, upstream
  guardrails, roadmap, active RD-07 plan, contracts, preload, main composition,
  player adapter, host port, player IPC owner, contract tests, adapter tests,
  native host process tests, RD-06 native-presentation spike tooling, player IPC
  tests, `package.json`, architecture lint rules, commit stats for `75062e0`,
  `e2df530`, `f1c73af`, and `7850b47`, and `git status --short --branch`.
- Official docs: no new external Electron, Node, libmpv, packaging, signing, or
  dependency behavior is frozen by this plan refresh. The real child-process
  proof may use Node's existing `node:child_process` API in a test only; if it
  needs new runtime policy, product helper launch behavior, package scripts, or
  native dependency behavior, stop for official-doc research and reviewed
  replan.

Observed source state:

- `src/contracts/player.ts`, `src/contracts/ipc.ts`, and
  `src/contracts/shell.ts` already contain the renderer-safe player, IPC, and
  preload API shapes needed by RD-07 closeout. They are out of scope.
- `src/preload/index.cts` already exposes the narrow player API and runtime
  guards player events. It is out of scope.
- `src/main/index.ts` already wires `registerPlayerIpcHandlers` with
  `shellMode`, authorization, event-send, and request-id callbacks. It is out of
  scope for native process policy.
- `src/main/player/playerIpc.ts` currently owns development/smoke fake-host
  activation and production unsupported behavior. It is the correct owner for
  native-host factory selection.
- `src/main/player/nativePlayerHostPort.ts` currently defines `execute()` and
  `cleanup()` as the fakeable adapter-facing host seam.
- `src/main/player/desktopPlayerAdapter.ts` already validates renderer intents,
  host events, helper failures, cleanup, stale events, and forbidden fields.
- `src/__tests__/playerIpc.test.ts` proves closed player IPC handlers,
  development/smoke fake-host dispatch, invalid payload rejection,
  authorization, production unsupported behavior, cleanup, teardown, and
  forbidden-field exclusion.
- `src/__tests__/nativePlayerHostProcess.test.ts` proves process message
  translation, lifecycle failure normalization, cleanup/reap behavior, stale
  output quarantine, and forbidden-field exclusion with in-memory doubles. It
  may add a Windows-friendly real spawned helper test double without product
  native helper changes.
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` already owns the
  dev-only RD-06 app-owned native-presentation proof command and writes redacted
  local evidence under ignored `docs/runs/rd-06-native-libmpv-host-spike/`.
- `package.json` already has `typecheck`, `test:contracts`, `smoke:electron`,
  `verify:docs`, `verify:redaction`, and `verify`. No package or dependency
  change is authorized.

## Impact Snapshot

Expected blast radius for `desktop-player-windows-native-host-proof`:

- Owners that may change: focused main/player process-seam tests, closeout docs,
  and roadmap/current playback status after observed proof. A source fix inside
  `src/main/player/nativePlayerHostProcess.ts`, `nativePlayerHostPort.ts`,
  `playerIpc.ts`, or `desktopPlayerAdapter.ts` is allowed only if the Windows
  proof exposes a defect inside the approved RD-07 native-host unit.
- Owners that must not change: contracts, preload API, main composition root,
  renderer UI, Plex, scheduler, stream policy, secure storage, RD-05/RD-06
  spike tools, packaging/release, package metadata, lockfiles, dependencies,
  and copied/adapted upstream product source.
- Public renderer-facing contracts: no changes authorized.
- Runtime behavior: development/smoke may still use the existing fake host for
  Electron smoke. The process seam may be exercised through unit tests and
  explicit test doubles only. Production must continue to avoid fake playback
  success; this unit does not enable Plex-backed native playback in production.
- Dependency/build impact: none authorized.
- Local-only artifacts: RD-06 proof output may be refreshed under ignored
  `docs/runs/rd-06-native-libmpv-host-spike/`. Any other accidental logs,
  process traces, screenshots, media, or run evidence must remain untracked.

## Files In Scope

Planning refresh write scope:

- `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`

After clean read-only plan review, implementation/proof write scope for
`desktop-player-windows-native-host-proof`:

- `src/__tests__/nativePlayerHostProcess.test.ts`
- `src/main/player/nativePlayerHostProcess.ts` only for a Windows proof defect
  inside process lifecycle, cleanup/reap, message parsing, or redaction.
- `src/main/player/nativePlayerHostPort.ts` only if a narrow private host seam
  fix is required by an observed Windows proof defect.
- `src/main/player/playerIpc.ts` only if factory policy incorrectly exposes
  fake/test-double success outside approved development/smoke behavior.
- `src/main/player/desktopPlayerAdapter.ts` only if host event/failure handling
  fails renderer-safe validation, cleanup, crash, or stale-event behavior.
- `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/playback-architecture.md`
- `docs/roadmap/desktop-port-roadmap.md`

Scope limits:

- Keep native process lifecycle policy in `src/main/player/nativePlayerHostProcess.ts`
  and host factory selection in `src/main/player/playerIpc.ts`.
- Process tests may use in-memory or spawned Node-script test doubles, but
  test-double protocol payloads must be renderer-safe and must not resemble
  secret-bearing production Plex or libmpv values.
- RD-06 native-presentation proof output must remain ignored local evidence
  under `docs/runs/rd-06-native-libmpv-host-spike/`; tracked docs may summarize
  only redacted conclusions after proof is observed.

## Files Out Of Scope

- `src/contracts/player.ts`
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `src/preload/index.cts`
- `src/main/index.ts`
- `src/renderer/**`
- `src/native-helper/**`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
- `tools/mpv-poc/rd-05-external-mpv-poc.mjs`
- `package.json`
- lockfiles and package manager metadata
- `docs/architecture/import-ledger.md`
- Plex auth/discovery/library/stream setup, scheduler/channel/content, secure
  storage, packaging, installer, signing, native binaries, native addons, NuGet
  packages, libmpv headers, generated bindings, or copied/adapted upstream
  Lineup source
- Unrelated dirty files already present before this RD-07 refresh

## Planner Self-Check

1. Product, architecture, ownership, dependency, and verification decisions for
   the Windows closeout unit are resolved: `playerIpc.ts` owns host factory policy,
   `nativePlayerHostProcess.ts` owns lifecycle plumbing, and renderer-facing
   contracts do not change.
2. The unit depends on Windows proof access and existing dev-only RD-06
   native-presentation tooling, but does not depend on Plex, scheduler, stream
   policy, renderer UI, secure storage, product native binaries, or package
   changes.
3. Files frozen out of scope are not relied on for hidden wiring. `src/main/index.ts`
   already passes plain callbacks and remains out of scope.
4. Evidence path records Codanna fallback and direct reads.
5. The plan avoids growing `src/main/index.ts` or future orchestration owners
   into native process policy hotspots.
6. A fresh implementer should not need to invent Electron, IPC, security,
   playback, persistence, packaging, import, native proof, or verification
   policy.
7. Exact verification commands, expected outcomes, acceptance criteria,
   rollback, and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

Chosen seam: preserve the main-owned native-host process adapter in
`src/main/player/nativePlayerHostProcess.ts` behind `NativePlayerHostPort`.
`src/main/player/playerIpc.ts` remains the only host factory policy owner and
may opt into that seam only through reviewed options that are testable without
production helper activation.
`DesktopPlayerAdapter` continues to receive only `NativePlayerHostPort` and
renderer-safe `NativePlayerHostEvent` / `NativePlayerHostFailure` values.

Frozen decisions:

| Decision | RD-07 Windows closeout choice |
| --- | --- |
| Execution unit | `desktop-player-windows-native-host-proof` |
| Process seam owner | `src/main/player/nativePlayerHostProcess.ts` |
| Host factory owner | `src/main/player/playerIpc.ts` |
| Adapter owner | Preserve `DesktopPlayerAdapter`; narrow seam change only if required |
| Main composition | `src/main/index.ts` out of scope |
| Renderer/preload/contracts | Out of scope; no public shape changes |
| Process proof | Windows real spawned test helper through `NativePlayerHostProcess` and adapter |
| Native surface proof | Existing RD-06 app-owned native-presentation smoke rerun on Windows |
| Native direction | Preserve RD-06 app-owned native presentation |
| Dependency boundary | No package, lockfile, dependency, native addon, or build-tool change |

Required Windows closeout behavior:

- A host process adapter must translate `PlayerCommand` into a private
  process-facing message shape without exposing that shape to renderer-facing
  contracts.
- It must accept only renderer-safe host events/failures back into the adapter
  seam and rely on `DesktopPlayerAdapter` for final event validation.
- It must normalize process spawn, exit, stderr, malformed message, timeout, and
  cleanup failures into existing renderer-safe `PlayerError` categories without
  echoing raw process output, local paths, native handles, URLs, headers, or
  secret-like fields.
- It must support cleanup/reap behavior and reject or quarantine late process
  events after cleanup through the existing request-id/stale-event model.
- It must prove the process seam with a real spawned helper test double on
  Windows without adding a production native helper, native addon, package
  script, Plex stream, or local media dependency.
- It must rerun the RD-06 app-owned native-presentation preflight and smoke on
  Windows to prove inherited native surface behavior: real local/dummy HTTP
  playback, fullscreen/composition, focus/input continuity, helper crash
  detection, helper cleanup/reap, redacted diagnostics, and forbidden-field
  exclusion.
- It must not create a production-visible fake success path. Production command
  attempts must remain renderer-safe unsupported until a later product native
  helper plan enables real native-host behavior.

Forbidden shortcuts:

- No renderer privilege concession.
- No raw `ipcRenderer`, Electron, Node, filesystem, native, libmpv, graphics,
  token, URL, header, Plex, stream key, part key, or secret diagnostic values in
  renderer-facing state.
- No general RPC bridge or arbitrary channel strings.
- No native process policy in `src/main/index.ts`, `App.ts`, renderer UI, Plex,
  scheduler, storage, or orchestration owners.
- No WID or helper-owned render API revival.
- No hidden real native helper launch behind development/smoke fake-host
  behavior.
- No package, dependency, lockfile, native addon, native binary, packaging, or
  installer changes.

Windows execution packet:

- Files: `src/__tests__/nativePlayerHostProcess.test.ts` for a real spawned
  helper process proof; existing `src/main/player/*` only for observed in-scope
  defects; existing RD-06 proof tooling read-only.
- Helper prerequisites: Windows host with Node/npm dependencies installed,
  Electron available from the existing dev dependency, `dotnet` available for
  the RD-06 helper build, and local libmpv/mpv prerequisites already required by
  RD-06 native-presentation smoke. No Plex server, credentials, package script,
  native addon, checked-in binary, NuGet package, or generated binding is
  authorized.
- Commands: rerun baseline `npm run verify`, add/fix only scoped tests if the
  real spawned helper proof fails, run `npm run test:contracts`,
  `npm run smoke:electron`, RD-06 native-presentation preflight and smoke,
  `npm run verify:redaction`, and final `npm run verify`.
- Redacted evidence path: ignored local files under
  `docs/runs/rd-06-native-libmpv-host-spike/`. Tracked docs may record only the
  manifest-level redacted conclusion and command results.
- Manual/source audit: inspect diff scope; confirm contracts/preload/main
  composition/renderer/Plex/package files did not change; confirm production
  player IPC remains unsupported/noop; confirm no forbidden privileged fields
  appear in renderer-facing test results, tracked docs, or Codex output.
- Rollback: revert only this Windows closeout packet changes in
  `src/__tests__/nativePlayerHostProcess.test.ts`, any approved in-scope
  `src/main/player/*` fix, and closeout docs. Delete accidental ignored run
  output only if it was created by a failed proof and is not needed for local
  evidence.
- Stop conditions: stop for replan if real product helper launch, renderer or
  preload contract changes, `src/main/index.ts` native policy, package/dependency
  changes, RD-06 spike edits, Plex stream setup, unredacted diagnostics, WID or
  helper-owned render API revival, or unavailable Windows native proof is
  required.

## Verification Commands

Planner refresh commands:

```sh
git status --short --branch
```

Expected outcome: branch state is observed before edits; unrelated dirty files
are not modified, staged, reverted, or treated as RD-07 evidence.

```sh
npm run verify:docs
```

Expected outcome: passes after this active plan is refreshed. If it fails, fix
only the RD-07 plan unless the output proves a pre-existing unrelated issue.

Windows closeout commands after clean plan review:

```sh
git status --short --branch
```

Expected outcome: dirty state is understood; unrelated files are left alone.

```sh
npm run typecheck
```

Expected outcome: TypeScript compiles with the reviewed main/player process seam
and no renderer-facing contract drift.

```sh
npm run test:contracts
```

Expected outcome: existing contract, adapter, player IPC, and native host
process tests pass; the Windows closeout proof includes a real spawned helper
test double plus lifecycle success/failure paths, cleanup/reap, malformed
process output handling, stale/late event quarantine, production unsupported
behavior, and forbidden-field exclusion.

```sh
npm run smoke:electron
```

Expected outcome: existing Electron smoke still proves shell containment and
fake-host-backed player preload delivery. Smoke proof remains IPC/preload
contract evidence only, not native playback proof.

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-06-native-libmpv-host-spike
```

Expected outcome: Windows native-presentation prerequisites are present and the
redacted preflight manifest records no raw paths, URLs, native handles, auth
headers, or secret-shaped diagnostics.

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --out docs/runs/rd-06-native-libmpv-host-spike --duration-ms 5000 --dummy-input local-and-http --fullscreen-mode native-presentation-host
```

Expected outcome: RD-06 app-owned native-presentation smoke passes on Windows
with redacted evidence for local and dummy HTTP native playback,
fullscreen/composition through the native-presentation host, focus/input
continuity, helper crash detection, helper cleanup/reap, and forbidden-field
exclusion. This is RD-07 native surface proof, not production Plex playback.

```sh
npm run verify:redaction
```

Expected outcome: tracked docs, tests, and source contain no forbidden raw
secret, token, URL, header, native handle, libmpv, engine id, raw Plex, stream
key, part key, or secret diagnostic content.

```sh
npm run verify
```

Expected outcome: passes before RD-07 is called complete.

Manual/source-audit proof after implementation:

- Inspect `git diff -- src/main/player src/__tests__ docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md docs/architecture/CURRENT_STATE.md docs/architecture/playback-architecture.md docs/roadmap/desktop-port-roadmap.md`
  and confirm only reviewed RD-07 files changed.
- Confirm `src/main/index.ts`, preload, renderer, and contracts did not change.
- Confirm `playerIpc.ts` remains the host factory policy owner.
- Confirm `nativePlayerHostProcess.ts` owns lifecycle plumbing and returns only
  renderer-safe adapter-facing values.
- Confirm production mode cannot activate fake or test-double playback success.
- Confirm no package, lockfile, Plex, scheduler, stream policy, renderer UI,
  native helper binary/addon, RD-06 tool, or copied upstream source changed.
- Confirm ignored RD-06 run evidence remains under
  `docs/runs/rd-06-native-libmpv-host-spike/` and is not staged.

## Acceptance Criteria

Plan acceptance:

- This plan is refreshed for `desktop-player-windows-native-host-proof` and
  names exact files, commands, redacted evidence paths, stop conditions, and
  rollback for Windows native-host proof.
- The plan remains active, feature/design, Tier 3, and routes next to read-only
  plan review before source edits.
- Commits `75062e0` and `e2df530` remain the preserved baseline.
- Files in scope and out of scope are exact.
- The plan keeps contracts, preload, main composition, renderer, Plex,
  scheduler, secure storage, packaging, and product native binaries out of
  scope.
- The plan records Codanna fallback and direct-read evidence.
- `npm run verify:docs` passes after this refresh, or the exact failure is
  reported without a false success claim.

Implementation acceptance after clean plan review:

- Implementation/proof is limited to `desktop-player-windows-native-host-proof`.
- Source/test/doc changes stay within the approved file list unless a reviewed
  replan expands scope.
- `nativePlayerHostProcess.ts` provides a fakeable main-owned process seam
  behind `NativePlayerHostPort`.
- Lifecycle cleanup/reap, process/test-double failure normalization, malformed
  output handling, redaction, stale/late event quarantine, real spawned helper
  startup/lifecycle, and production unsupported behavior are covered by focused
  tests.
- Renderer-facing results, snapshots, events, errors, and diagnostics remain
  existing contract-bound shapes and forbidden-field-free.
- `playerIpc.ts` remains the host policy owner and `src/main/index.ts` remains
  unchanged.
- RD-06 app-owned native-presentation preflight and smoke pass on Windows, and
  tracked docs describe that as native surface proof only, not production
  Plex-backed playback.
- `npm run typecheck`, `npm run test:contracts`, `npm run smoke:electron`,
  RD-06 native-presentation preflight/smoke, `npm run verify:redaction`, and
  `npm run verify` pass before closeout.
- Read-only implementation review is clean, and accepted findings are fixed or
  routed back to planning before commit.

Closeout acceptance:

- Roadmap, current architecture, and playback architecture mark RD-07 complete
  only after observed Windows proof, final verification, and clean
  implementation review.
- Closeout preserves app-owned native presentation and does not reopen WID or
  helper-owned render API without reviewed replan.
- The next handoff routes to RD-08/RD-12 planning as appropriate and states that
  RD-07 still has no Plex stream setup, renderer UI, or production native
  helper.

## Replan Triggers

Stop and replan if any of the following occurs:

- Plan review finds the Windows closeout proof under-specified, too broad, or
  inconsistent with current architecture.
- Current architecture, roadmap, contract files, preload/main source, package
  scripts, verifier behavior, or baseline tests changed materially after this
  refresh.
- Implementation needs contract, preload, renderer API, `src/main/index.ts`, or
  shared IPC shape changes.
- Implementation needs production native helper binaries, native addons, libmpv
  bindings, package/dependency/lockfile changes, packaging, signing, installer
  work, or new Windows proof tooling outside the reviewed RD-06 smoke.
- `src/main/index.ts`, `App.ts`, renderer UI, Plex, scheduler, storage, or
  orchestration owners would need native process policy.
- WID or helper-owned render API would need to be reopened.
- Any renderer-facing shape requires raw URLs, tokens, auth headers, native
  handles, libmpv objects, engine ids, raw Plex payloads, stream keys, part
  keys, Electron APIs, Node APIs, or secret diagnostics.
- Smoke or contract proof cannot exercise the RD-07 process seam without
  overclaiming native playback.
- RD-06 native-presentation preflight or smoke fails for an in-scope reason that
  invalidates app-owned native presentation as the RD-07 native surface proof.
- Production behavior would appear to succeed through fake/test-double playback.
- `npm run verify:docs`, `npm run typecheck`, `npm run test:contracts`,
  `npm run smoke:electron`, `npm run verify:redaction`, or `npm run verify`
  fails for an in-scope reason that cannot be fixed inside reviewed scope.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-07 evidence.

## Rollback Notes

Rollback for this planner refresh:

- Revert only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md` to its
  previous reviewed state or replace it with a newly reviewed plan.
- Do not touch unrelated dirty files, roadmap, architecture docs, package files,
  or product source.
- Rerun `git status --short --branch` and `npm run verify:docs` after any plan
  rollback or replacement.

Rollback for the Mac process-seam unit:

- Revert only reviewed RD-07 changes in the files listed for
  `desktop-player-mac-native-host-process-seam`.
- Remove `src/main/player/nativePlayerHostProcess.ts` and
  `src/__tests__/nativePlayerHostProcess.test.ts` only if they were created by
  that unit and no reviewed follow-up depends on them.
- Restore prior `NativePlayerHostPort`, `playerIpc.ts`, and adapter behavior
  only for changes made by the Mac unit.
- Do not revert the reviewed adapter core or runtime IPC/preload bridge unless
  the reviewed rollback explicitly identifies a regression introduced by the
  Mac unit.
- Delete accidental local-only scratch output or ignored run artifacts created
  during implementation. Do not stage generated artifacts.
- Rerun `git status --short --branch` and the verification commands named
  above before closeout.

Rollback for the Windows native-host proof unit:

- Revert only `src/__tests__/nativePlayerHostProcess.test.ts` additions for the
  spawned-helper proof and any reviewed in-scope `src/main/player/*` fix made
  during this unit.
- Revert only RD-07 closeout updates in this plan,
  `docs/architecture/CURRENT_STATE.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/roadmap/desktop-port-roadmap.md`.
- Do not revert the reviewed adapter core, runtime IPC/preload bridge, Mac
  process seam, RD-06 native-presentation tooling, package metadata, lockfiles,
  contracts, preload, `src/main/index.ts`, renderer, Plex, scheduler, storage,
  packaging, or upstream import docs.
- Delete accidental ignored run output only when it was produced by a failed
  proof and is not needed for local diagnosis. Do not stage `docs/runs/`
  evidence.
- Rerun `git status --short --branch`, `npm run verify:docs`, and the relevant
  failed verification command after rollback.

## Commit Checkpoints

Checkpoint 1: RD-07 Mac process-seam plan refresh only.

- Commit only after this plan is refreshed, `npm run verify:docs` passes, and
  read-only plan review is clean.
- Suggested commit: `docs: refresh rd-07 native host plan`
- Include only
  `docs/plans/2026-05-10-rd-07-desktop-videoplayer-adapter-plan.md`.
- Do not include unrelated dirty plans or user work.

Checkpoint 2: reviewed Mac process-seam implementation only.

- Commit only after clean plan review, scoped implementation, required
  verification passes, and read-only implementation review is clean.
- Suggested commit: `feat(player): add native host process seam`
- Include only reviewed RD-07 Mac process-seam files. Do not include package,
  lockfile, Plex, scheduler, renderer UI import, native binary/addon, upstream
  import, generated, local-only, or unrelated dirty files.

Checkpoint 3: Windows native-host proof and RD-07 closeout.

- Commit only after clean plan review, scoped proof/fixes, required Windows
  native-presentation proof, full verification, closeout docs, and clean
  read-only implementation review.
- Suggested commit: `test(player): prove rd-07 native host on windows`
- Include only reviewed RD-07 Windows proof/test fixes and closeout docs. Do not
  include ignored run evidence, package/lockfile changes, Plex, scheduler,
  renderer UI import, production native binary/addon, upstream import, generated
  output, or unrelated dirty files.

MODEL_SUGGESTION
PLANNER: planner with high reasoning
IMPLEMENTER: worker with high reasoning
REVIEWER: reviewer with high reasoning
WHY: RD-07 touches native playback boundaries, Electron main/player ownership, process lifecycle seams, renderer-safe player contracts, redaction, and cross-machine proof.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Plan RD-08 Desktop Stream Policy
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: none
ARTIFACT: completed RD-07 Windows native-host proof and closeout
FILES:
- AGENTS.md
- docs/AGENTIC_DEV_WORKFLOW.md
- docs/agentic/session-prompts/feature-quality-loop.md
- docs/agentic/session-prompts/feature-plan.md
- docs/agentic/plan-authoring-standard.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/roadmap/desktop-port-roadmap.md
- src/contracts/player.ts
- src/contracts/ipc.ts
- src/contracts/shell.ts
- src/main/player/desktopPlayerAdapter.ts
- src/main/player/nativePlayerHostPort.ts
- src/main/player/nativePlayerHostProcess.ts
- src/main/player/playerIpc.ts
- src/__tests__/desktopPlayerAdapter.test.ts
- src/__tests__/nativePlayerHostProcess.test.ts
- src/__tests__/playerIpc.test.ts
- src/__tests__/contracts.test.ts
- package.json
BLOCKERS: none for RD-08 planning; RD-07 intentionally did not implement Plex stream setup, renderer UI, or a production native helper.
MESSAGE:
Create the RD-08 Desktop Stream Policy plan. Start from the completed RD-07 adapter/process boundary and Windows native surface proof: renderer-facing player contracts are in `src/contracts/player.ts`, runtime player IPC/preload delivery exists but remains development/smoke fake-host-backed, production player commands still return renderer-safe unsupported failures, and no Plex stream setup, renderer UI, secure storage, or production native helper exists yet. RD-08 should define Desktop capability-driven stream decisions without webOS constants as Desktop truth, preserve raw URL/header/token custody outside renderer-facing contracts, and name exact Plex/stream-policy evidence, files in scope, verification, redaction, rollback, and stop conditions before implementation.
