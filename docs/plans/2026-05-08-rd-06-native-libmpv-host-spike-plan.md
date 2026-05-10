**Plan Status:** active

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** blocked

**Plan review status:** clean read-only review reported no blockers for this
render API replan after `npm run verify:docs` passed. The previous reviewed WID
implementation was attempted on a Windows proof host, and the required
fullscreen video-surface proof failed. RD-06 is not complete.

**Windows WID smoke adjudication:** WID is blocked as the native surface
strategy for RD-07 unless a later reviewed plan reopens it with new evidence.
The Windows WID smoke proved windowed active video, overlay pixels, renderer
focus, dummy HTTP loading, helper crash detection, cleanup, libmpv API/version
evidence, and redaction, but did not capture active fullscreen video pixels.
That failure is material because RD-06 requires fullscreen video-surface proof
before RD-07 can harden native playback direction.

**Windows render API smoke adjudication:** The reviewed
`windows-libmpv-render-api-surface-probe` unit was implemented and attempted on
the Windows proof runner, then a narrow amended proof-path fix was attempted in
the same dev-only spike files. The render API smoke proved render API symbol
availability, render-context creation, app-owned input simulation, dummy local
and HTTP playback, windowed active video pixels, overlay pixels, renderer
focus, helper crash detection, cleanup, libmpv API/version evidence, and
redaction, but it did not capture active fullscreen video pixels while the
BrowserWindow was fullscreen. The amended helper-owned Win32 screen-pixel
fallback was requested only after Electron confirmed BrowserWindow fullscreen,
was scoped to the helper render child surface, and also reported
`not-captured`. The implementation records render-thread discipline and
composition proof as not proven by this helper loop, so RD-06 remains
blocked/replan and does not settle the RD-07 native surface direction.

**Implementation review status:** clean after amended re-review. The first
fallback diff had review blockers; the current session accepted the findings,
scoped the fallback to render API smoke only, removed stale clean-review
wording, kept RD-06 routed to replan, and re-review reported no scoped RD-06
blockers.

**Narrow proof-path amendment:** The current session made one bounded follow-up
attempt inside the same `windows-libmpv-render-api-surface-probe` unit:
Electron still owns BrowserWindow fullscreen state, but the privileged dev
helper can emit a redacted Win32 screen-pixel proof for its own rendered child
surface while Electron has confirmed `BrowserWindow` fullscreen. The fallback
adds no dependencies, product code, package changes, native addons, copied
headers/examples, or privileged renderer exposure, but the Windows proof still
failed because that scoped native capture did not observe fullscreen video
pixels.

**Chosen next execution unit:** none. RD-06 routes back to feature planning for
the next native surface decision.

**Verification classification:** broader integration/manual proof required

## Goal

Replan RD-06 after the reviewed Windows WID smoke failed fullscreen
video-surface proof, and freeze one next bounded proof unit before RD-07.

The next unit is `windows-libmpv-render-api-surface-probe`. It must test whether
mpv's render API can satisfy the missing Windows fullscreen video-surface proof
without moving production renderer, preload, main, contract, Plex, scheduler,
package, or import-ledger ownership. The unit remains dev-only and evidence
only.

The unit should extend the existing RD-06 spike surface only after clean
read-only review. It may add render-API-specific modes to
`tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` and the C# helper, plus
focused harness tests. It must not create product playback architecture.

RD-06 remains incomplete until Windows evidence proves the required native
surface behavior, or until the plan records a reviewed blocked conclusion that
routes native playback to another strategy before RD-07.

## Non-Goals

- Do not implement a new Windows proof unit in this planning pass.
- Do not run Windows proof commands in this planning pass.
- Do not complete RD-06 from WID, macOS, prerequisite, or docs-only evidence.
- Do not continue into RD-07 until RD-06 has a reviewed native surface
  conclusion.
- Do not add production player adapter behavior, production helper protocol,
  product renderer UI, preload bridge, main IPC, Plex integration, stream
  policy, scheduler, secure storage, packaging, signing, installer, or release
  work.
- Do not touch `src/main/**`, `src/preload/**`, `src/renderer/**`,
  `src/contracts/**`, Plex, scheduler, package metadata, lockfiles, packaging
  config, installer config, or `docs/architecture/import-ledger.md` in the next
  unit.
- Do not add a Node native addon in the next unit. Addon exploration is not the
  chosen execution unit because Node-API does not stabilize external libmpv ABI,
  and an addon would introduce package/build/signing/provenance decisions before
  the native surface strategy is proved.
- Do not install .NET, Visual Studio, Windows SDK, mpv/libmpv, NuGet packages,
  native headers, generated bindings, helper binaries, npm dependencies, or
  build tools as RD-06 implementation.
- Do not copy or adapt upstream Lineup source in RD-06 unless a reviewed replan
  authorizes the exact import and updates
  `docs/architecture/import-ledger.md` before or with the import.
- Do not contact real Plex servers or use real Plex tokens, tokenized URLs,
  auth headers, raw Plex payloads, checked-in media, raw native logs, native
  handles in renderer-facing state, libmpv objects in contracts, engine ids in
  renderer-facing state, broad IPC, or production renderer UI changes.
- Do not treat external `mpv` JSON IPC as production architecture. RD-05
  remains a disposable POC only.

## Parent Architecture Alignment

RD-06 is Tier 3 native playback architecture work and is Windows-first.

Current architecture alignment:

- `docs/architecture/CURRENT_STATE.md` says RD-06 remains blocked on
  fullscreen video-surface evidence and does not create a production playback
  host or settle the RD-07 native surface direction.
- `docs/architecture/playback-architecture.md` records that the dev-only WID
  spike proved several Windows behaviors but failed fullscreen video-surface
  proof; render API or addon exploration is back on the table.
- `docs/roadmap/desktop-port-roadmap.md` records RD-06 as blocked/replan and
  says the current WID smoke does not prove enough to route directly to RD-07.
- `docs/architecture/security-and-secret-flow.md` keeps token-bearing playback
  material inside privileged main/helper setup and outside renderer ownership.
- `docs/architecture/upstream-behavior-guardrails.md` forbids raw URLs, headers,
  native handles, engine ids, libmpv objects, and webOS constants through
  renderer-facing state.
- `src/contracts/player.ts` and `src/contracts/ipc.ts` already define
  renderer-safe player/IPC vocabulary and forbidden privileged keys; the next
  unit must not change those contracts.
- `package.json` currently uses Electron `^42.0.0`, Node `>=22.12.0`, and the
  existing verifier scripts. The next unit must not add package scripts,
  dependencies, or lockfile changes.

Native surface decision:

- WID is no longer the chosen route for the next unit because the reviewed
  Windows smoke failed the exact fullscreen video-surface proof RD-06 required.
- The next unit uses mpv render API as the only selected route because official
  mpv examples describe it as more flexible for app-owned composition and UI
  over video than raw window embedding.
- Addon exploration is deferred. It may become necessary only after render API
  evidence shows that the surface strategy is viable but the helper/process
  boundary cannot satisfy performance, lifecycle, packaging, or IPC needs.

Boundary decision for the next unit:

- Dev-only tool owner: `tools/libmpv-spike/`.
- Helper owner: a privileged dev helper owns libmpv, render context lifecycle,
  native graphics context/window state, dummy media loading, app-owned input
  simulation for mpv, crash behavior, and redacted proof event emission.
- Electron harness owner: a dev-only Electron harness creates the BrowserWindow
  proof surface, controls windowed/fullscreen transitions, focuses the
  renderer, captures proof pixels with Electron capture primitives, may request
  a private helper-owned Win32 screen-pixel fallback while fullscreen is true,
  starts and reaps the helper, and writes only redacted local evidence.
- Renderer owner: dev-only renderer content may expose a dummy overlay/focus
  target for proof, but it must not receive secrets, raw URLs, raw headers,
  native handles, libmpv objects, engine ids, arbitrary IPC, or production
  bridge access.
- Product owners: production renderer/preload/main/contracts/Plex/scheduler and
  package/import-ledger files remain out of scope.

Dependency/provenance/licensing/ABI/platform decision:

- Platform scope is Windows x64 only for the next proof.
- The Windows proof-runner facts already recorded for the failed WID smoke are:
  `win32 x64`, Node `v22.21.1`, npm `11.13.0`, .NET SDK `7.0.317`, Electron
  resolved from `node_modules`, mpv `v0.41.0-524-g5921fe50b`, and
  `libmpv-2.dll` client API `2.5` from a local shinchiro build outside the repo.
- The next unit may use only the already-present local Windows .NET SDK,
  Electron from repo `node_modules`, and local shinchiro mpv/libmpv files. It
  must record version, path-redacted provenance, no-redistribution status, and
  licensing notes in ignored local evidence.
- No Node-API addon is authorized. Node-API ABI stability is noted only as
  future evidence: it can stabilize an addon boundary across Node versions, but
  official Node docs warn that external libraries used by the addon do not
  automatically share that stability.
- No copied mpv example source, copied mpv headers, generated bindings, NuGet
  packages, npm packages, checked-in binaries, or package metadata changes are
  authorized. If implementation cannot call the required public libmpv render
  API from the existing dev helper without those additions, stop and replan.

## Required Reading

Read in this order before review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-plan.md`
4. `docs/agentic/plan-authoring-standard.md`
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/architecture/playback-architecture.md`
7. `docs/architecture/security-and-secret-flow.md`
8. `docs/architecture/upstream-behavior-guardrails.md`
9. `docs/roadmap/desktop-port-roadmap.md`
10. `docs/architecture/import-ledger.md`
11. `docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md`
12. `src/contracts/player.ts`
13. `src/contracts/ipc.ts`
14. `docs/runs/README.md`
15. `.gitignore`
16. `package.json`
17. `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
18. `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
19. `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
20. Official Electron BrowserWindow docs, checked 2026-05-10:
    https://www.electronjs.org/docs/latest/api/browser-window
21. Official Electron desktopCapturer docs, checked 2026-05-10:
    https://www.electronjs.org/docs/latest/api/desktop-capturer
22. Official mpv manual, checked 2026-05-10:
    https://mpv.io/manual/stable/
23. Official mpv libmpv examples, checked 2026-05-10:
    https://github.com/mpv-player/mpv-examples/blob/master/libmpv/README.md
24. Official mpv headers, checked 2026-05-10:
    - https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h
    - https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h
25. Official Node-API docs, checked 2026-05-10:
    https://nodejs.org/api/n-api.html

Freshness gate: before implementation, rerun `git status --short --branch` and
reread the files above if architecture docs, contracts, roadmap status, package
metadata, Electron version, mpv/libmpv documentation, Node native-addon
documentation, verifier behavior, or Windows proof prerequisites changed
materially. Stop for plan update or re-review when assumptions are
contradicted.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3
  feature/design replan.
- `execution-plan-authoring`: freezes scope, owner path, seam, verification,
  rollback, and stop conditions without pseudo-code.
- `architecture-boundaries`: applies because RD-06 decides native helper,
  Electron harness, renderer non-ownership, and future addon non-ownership
  boundaries.
- `plex-integration-boundaries`: applies because dummy Plex-like HTTP proof must
  preserve token/header/URL custody rules even though real Plex is out of
  scope.
- `persistence-boundaries`: applies because local evidence, generated dummy
  media, helper output, and path redaction are implicated while credentials and
  durable settings remain out of scope.
- `ui-composition-patterns`: applies because overlay, focus, fullscreen, and
  input continuity remain proof targets.
- `verification-strategy`: applies because native playback needs Windows
  smoke/manual evidence plus static and redaction proof.
- `review-request`: next gate is read-only adversarial plan review.
- `closeout-verification`: required before staging, committing, calling the
  plan ready, or calling implementation complete.

## Evidence And Discovery

Codanna is not used for this replan. Discovery uses direct repo reads and
official docs evidence only.

Direct reads:

- `AGENTS.md`: use `update_plan`, keep durable plans in `docs/plans/*` when
  needed, do not claim commands or tests without observed evidence, run
  `npm run verify:docs` for plan/control-plane changes, and run `npm run verify`
  before implementation closeout unless a plan narrows proof.
- `docs/AGENTIC_DEV_WORKFLOW.md`: native playback is Tier 3, active plans own
  current execution units, native playback changes require review, and source
  implementation must remain bounded to approved owners.
- `docs/agentic/plan-authoring-standard.md`: active tracked plans require this
  heading set, exact verification commands/outcomes, and explicit replan
  triggers.
- `docs/architecture/CURRENT_STATE.md`: RD-06 has a dev-only WID spike but is
  blocked on fullscreen video-surface proof and does not create production
  playback architecture.
- `docs/architecture/playback-architecture.md`: WID evidence proves windowed
  video, overlay, focus, dummy HTTP, helper crash, cleanup, libmpv API/version,
  and redaction, but not fullscreen video-surface.
- `docs/roadmap/desktop-port-roadmap.md`: RD-06 is blocked/replan and cannot
  route directly to RD-07 until helper-vs-addon/native-surface evidence is
  recorded.
- `docs/architecture/security-and-secret-flow.md`: token-bearing headers and
  URLs stay inside privileged main/helper setup.
- `docs/architecture/upstream-behavior-guardrails.md`: renderer-facing state
  must not expose raw URLs, headers, native handles, engine ids, libmpv objects,
  or webOS constants.
- `src/contracts/player.ts` and `src/contracts/ipc.ts`: renderer-safe player
  and IPC vocabularies already exist; no contract change is needed for this
  dev-only proof unit.
- `.gitignore` and `docs/runs/README.md`: raw run bundles are ignored; durable
  conclusions belong in tracked docs; raw logs, media samples, crash dumps, and
  diagnostics containing secrets must not be committed.
- `package.json`: no native dependency, package script, or lockfile change is
  authorized for RD-06.

Workspace evidence:

- `git status --short --branch` observed branch `main` ahead of `origin/main`
  with pre-existing unrelated dirty plan files. Those files must not be edited,
  staged, reverted, or treated as RD-06 evidence by this plan.
- Current controller host is not the Windows proof host. This planning pass did
  not run Windows proof commands.

Observed Windows WID proof-runner facts supplied to this planner:

- Environment: `win32 x64`, Node `v22.21.1`, npm `11.13.0`, .NET SDK
  `7.0.317`, Electron from `node_modules`, mpv
  `v0.41.0-524-g5921fe50b`, and `libmpv-2.dll` client API `2.5` from a local
  shinchiro build outside the repo.
- Commands/results: RD-06 static test passed with 12 tests, preflight passed,
  WID smoke failed because fullscreen video pixels were not captured, and
  `verify:redaction` passed.
- Later macOS ingest passed the RD-06 static test, `verify:redaction`,
  `verify:docs`, and `verify`; those macOS results do not complete RD-06.
- Tracked docs already record WID's positive evidence and its missing
  fullscreen video-surface proof.

Official docs evidence checked 2026-05-10:

- Electron BrowserWindow docs: `getNativeWindowHandle()` is the Windows HWND
  source, `setFullScreen()` / `isFullScreen()` are window APIs, and
  `capturePage()` is a BrowserWindow capture primitive.
- Electron desktopCapturer docs: `desktopCapturer` is a main-process capture
  primitive for screen/window sources.
- mpv manual: libmpv is the recommended backend integration path for a
  different application; JSON IPC is not secure and remains POC-only here.
- mpv examples: native window embedding through `wid` is OS-dependent; on
  win32 it fills the parent; `input-vo-keyboard` may be needed; render API uses
  OpenGL/ANGLE, requires app-owned input simulation, and offers flexibility to
  render UI over video. The examples generally recommend render API over window
  embedding, while noting both can be useful.
- mpv `render.h`: render API requires render-thread discipline; normal libmpv
  calls from the render thread can deadlock, and advanced control can make
  violations fatal.
- Node-API docs: Node-API gives ABI stability for addons using Node-API, but
  external libraries do not automatically share that stability; native addons
  require C/C++ build and packaging decisions.

Evidence conclusion:

- The failed WID fullscreen proof is not a capture-tool flake to waive. It
  blocks WID as the next native surface direction because RD-06 explicitly
  requires fullscreen video-surface proof.
- The next unit should probe mpv render API, not addon work, because render API
  directly addresses surface ownership and composition while addon work mainly
  changes the JavaScript/native binding and packaging/ABI burden.
- If render API cannot be probed with the current dev helper and local Windows
  prerequisites, stop and replan. Do not smuggle addon/package/build decisions
  into implementation.

## Impact Snapshot

Expected blast radius after clean plan review:

- May change:
  - `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`
  - `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`
  - `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`
  - `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
  - `docs/architecture/playback-architecture.md` only after observed Windows
    render API proof or blocked conclusion
  - `docs/roadmap/desktop-port-roadmap.md` only after observed Windows render
    API proof or blocked conclusion
  - `docs/architecture/CURRENT_STATE.md` only if tracked current architecture
    truth changes after observed Windows proof
  - ignored local evidence under `docs/runs/rd-06-native-libmpv-host-spike/`
- Must not change:
  - product renderer, preload, main, shared contracts, Plex owners, scheduler
    owners, package metadata, lockfiles, packaging config, installer config,
    import ledger, copied upstream Lineup source, or native addon paths.
- Public contracts: no changes.
- Dependency/build impact: no npm dependency, package script, lockfile, native
  addon, NuGet package, helper binary, native library install, copied header,
  generated binding, or system install is authorized.
- Native library impact: local Windows mpv/libmpv may be used only if already
  available in the proof environment; record path-redacted provenance, version,
  API, licensing note, and no-redistribution status.
- ABI impact: no Node addon ABI commitment is made. libmpv API/version evidence
  is recorded as local proof only.
- Runtime behavior: no user-visible product behavior changes.
- Local artifacts: redacted dummy-only evidence stays ignored; raw scratch,
  logs, screenshots, crash output, compiled helper output, generated dummy
  media, and native traces must be deleted or kept in a clearly local ignored
  quarantine and never staged.

The next unit is cross-boundary in what it proves, but implementation ownership
stays dev-tool-only under `tools/libmpv-spike/`.

## Files In Scope

- `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` after clean plan
  review only
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs` after clean
  plan review only
- `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs` after clean plan
  review only
- `docs/architecture/playback-architecture.md` after observed Windows render
  API proof or blocked conclusion only
- `docs/roadmap/desktop-port-roadmap.md` after observed Windows render API
  proof or blocked conclusion only
- `docs/architecture/CURRENT_STATE.md` after observed Windows proof only, if
  current architecture truth changes
- `docs/runs/rd-06-native-libmpv-host-spike/manifest.redacted.json` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/events.redacted.ndjson` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/summary.redacted.md` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/quarantine/` local-only only when
  raw dummy-only troubleshooting artifacts must be retained temporarily

## Files Out Of Scope

- `package.json`
- lockfiles and package manager metadata
- Electron Forge, installer, signing, or release config
- `src/main/**`
- `src/preload/**`
- `src/renderer/**`
- `src/contracts/**`
- `src/__tests__/contracts.test.ts`
- production `src/native-helper/**` or equivalent helper runtime paths
- Node native addon source or build configuration
- Plex auth, discovery, library, stream, selected-server, subtitle, token, URL,
  header, or secure-storage implementation
- scheduler, channel, settings, UI, and RD-07 player adapter implementation
- `docs/architecture/import-ledger.md`, unless a later reviewed replan
  authorizes copied/adapted upstream Lineup source
- checked-in media fixtures, helper binaries, native libraries, generated
  screenshots, generated logs, crash dumps, raw run evidence, copied mpv
  examples, copied mpv headers, generated bindings, or NuGet packages
- unrelated dirty files already present before this RD-06 replan

## Planner Self-Check

1. No ownership or verification decision is unresolved for the next unit:
   render API surface probe is chosen; addon exploration is deferred.
2. The next unit does not depend on product contract or type changes.
3. Product files are out of scope and the plan does not rely on hidden wiring
   inside them.
4. Evidence path is recorded: direct repo reads, supplied Windows proof-runner
   facts, and official Electron/mpv/Node docs checked on 2026-05-10.
5. The owner path is dev-tool-only and avoids product hot spots until Windows
   evidence proves the native surface direction.
6. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, dependency, ABI, or verification policy.
7. Verification commands, expected outcomes, stop/replan triggers, evidence
   format, redaction rules, and rollback are explicit.

## Architecture Seam Decision Gate

Chosen seam: dev-only Windows mpv render API surface probe under
`tools/libmpv-spike/`, driven by an Electron proof harness and a privileged
helper, with no production owner changes.

Frozen decisions:

| Decision | RD-06 next-unit choice |
| --- | --- |
| Execution unit | `windows-libmpv-render-api-surface-probe` |
| Owner path | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.*` |
| Strategy | mpv render API, not another WID proof and not addon exploration |
| Source-controlled status | Dev-only source and focused tests may be tracked after clean review; generated evidence stays local-only |
| Helper boundary | Separate privileged dev helper owns libmpv, render context lifecycle, native graphics context/window state, dummy media loading, input simulation, events, crash behavior, and redaction |
| Electron harness boundary | Dev Electron main owns BrowserWindow creation, windowed/fullscreen transitions, focus/capture orchestration, helper launch/reap, and redacted local evidence writing |
| Renderer boundary | Dev-only renderer may provide dummy overlay/focus target only; no product renderer/preload/main or privileged data |
| Libmpv mode | Render API via app-owned OpenGL/ANGLE-capable rendering path; software rendering is not accepted as RD-06 completion unless a later reviewed replan narrows it to diagnostics only |
| Addon decision | No Node-API addon, node-gyp, CMake.js, prebuild, package metadata, or lockfile work in this unit |
| Platform scope | Windows x64 desktop session with display/GPU |
| Toolchain scope | Pre-existing Windows .NET SDK and local shinchiro mpv/libmpv only; no installs or redistribution |
| API/provenance scope | Record mpv executable version, libmpv client API/version, path-redacted shinchiro provenance, .NET SDK version, Electron version, and no-redistribution/licensing notes |
| Dummy input policy | Generated local dummy visual media and local dummy HTTP only |
| Dummy header policy | Dummy non-secret header only, for example `X-Lineup-RD06: dummy`; no `Authorization`, `Cookie`, Plex, token, bearer, credential, or real server headers |
| Args/env policy | No media URLs, headers, tokens, native handles, libmpv object ids, graphics context values, or secret material in process args/env |
| Log policy | Persist only redacted summary/events/manifest; raw logs deleted or quarantined locally |
| Capture proof | Use Electron `capturePage()` and/or `desktopCapturer` first; for the amended proof fix, allow a private helper-owned Win32 screen-pixel fallback only when Electron has confirmed BrowserWindow fullscreen. Fullscreen proof must show active video pixels while the BrowserWindow is fullscreen |
| Overlay proof | Must prove overlay/composition appropriate to the chosen render path while video is active in windowed and fullscreen modes, or fail the unit |
| Input proof | Because render API requires app-owned input simulation, record only renderer-safe dummy input/focus outcomes and no raw native input payloads |
| Crash policy | Induce helper crash only with dummy media; prove Electron harness survives, helper is reaped, temp files are cleaned, and no raw crash output is committed |
| Evidence format | Redacted JSON manifest, redacted NDJSON events, redacted Markdown summary |
| Durable conclusion target | `docs/architecture/playback-architecture.md` and `docs/roadmap/desktop-port-roadmap.md` only after observed Windows proof or blocked conclusion |
| Verification closeout | `npm run verify` before implementation complete; `npm run verify:docs` for plan/status doc changes |

Forbidden shortcuts:

- No renderer privilege concession.
- No broad preload RPC.
- No arbitrary channel strings from renderer code.
- No raw media URL/header/native-handle/graphics-context/libmpv object/engine id
  in renderer-facing state.
- No real Plex access.
- No package metadata, lockfile, or dependency changes.
- No Node native addon in this unit.
- No checked-in native binaries, copied mpv headers/examples, generated
  bindings, or copied upstream Lineup source.
- No claiming RD-06 complete unless fullscreen active video-surface proof is
  captured on Windows.

Stop before implementation if plan review finds the render API seam too broad,
if Windows proof access is unavailable, or if the unit requires unplanned
dependency/install/package/lockfile/addon changes.

## Verification Commands

Plan/review commands:

```sh
git status --short --branch
```

Expected outcome: shows branch state and any unrelated dirty files; no RD-06
implementation files should be changed by the planning pass except this plan.

```sh
npm run verify:docs
```

Expected outcome: passes after the revised active plan is applied. If not run
by the planner, the reviewer or committer must run it before calling the plan
ready.

Windows proof-runner commands after clean plan review and implementation only:

```sh
node -p "process.platform + ' ' + process.arch"
```

Expected outcome: `win32 x64`.

```sh
node -v
npm -v
dotnet --info
```

Expected outcome: exits 0 and records only redacted version/provenance evidence.
The known WID proof-runner baseline was Node `v22.21.1`, npm `11.13.0`, and
.NET SDK `7.0.317`; materially different versions do not fail automatically
but must be recorded in local evidence.

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode render-api-preflight --out docs/runs/rd-06-native-libmpv-host-spike
```

Expected outcome on Windows with prerequisites: writes only redacted local
evidence showing OS/arch, Node/Electron versions, .NET SDK version, local mpv
version, local libmpv availability, libmpv client API/version, path-redacted
local shinchiro provenance, licensing/no-redistribution note, render API symbol
availability, and no forbidden persisted fields. On non-Windows, missing
display/GPU, missing .NET SDK, missing local mpv/libmpv, or missing render API
availability, exits blocked with a clear blocked reason and no success claim.

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode render-api-smoke --out docs/runs/rd-06-native-libmpv-host-spike --duration-ms 5000 --dummy-input local-and-http --fullscreen-mode browser-window
```

Expected outcome: on Windows only, with dummy data only, records redacted proof
of local dummy visual playback, dummy HTTP visual playback with only the
approved non-secret header, active windowed video pixels, active fullscreen
video pixels while `BrowserWindow` fullscreen is true, and the proof source
must distinguish Electron capture from the private helper-owned Win32
screen-pixel fallback. It also records overlay/composition proof in windowed and
fullscreen modes, renderer focus/input continuity, app-owned input simulation
notes, stop/channel-switch ordering, stale event handling, helper crash
detection, helper cleanup, DPI/multi-monitor notes when available, and redacted
logs. If fullscreen video pixels are not captured, if overlay or focus proof
fails, or if render-thread discipline cannot be maintained, the command exits
failed/blocked and RD-06 remains incomplete.

Static/local proof commands after implementation source exists:

```sh
npm run test:harness-docs -- --test-name-pattern=rd-06
npm run verify:redaction
```

Expected outcome: RD-06 focused tests pass, including render API argument
policy, mode parsing, evidence schema, forbidden field checks, and redaction
coverage; redaction verifier reports no forbidden content in tracked docs,
tests, or tools.

Closeout command before implementation is called complete:

```sh
npm run verify
```

Expected outcome: passes on the implementation host after RD-06 source/status
changes. If Windows-only render API smoke cannot run in that environment, or if
the smoke fails fullscreen active video-surface proof, RD-06 remains
blocked/replan and must not be marked complete.

Evidence closeout checks:

```sh
git status --short --branch
```

Expected outcome: no generated `docs/runs/rd-06-native-libmpv-host-spike/*`
files staged; no package metadata, lockfile, product runtime, native addon, or
unrelated dirty files touched.

On Windows PowerShell, inspect local evidence before closeout:

```powershell
Get-ChildItem -Recurse docs/runs/rd-06-native-libmpv-host-spike | Select-Object FullName
```

Expected outcome: only redacted evidence files remain outside any explicitly
local quarantine folder. Raw scratch logs, screenshots, crash output, helper
binaries, generated dummy media, temp output, and native traces are deleted or
quarantined and never staged.

## Acceptance Criteria

Plan acceptance:

- This plan exists as the active tracked RD-06 plan with the required headings.
- The plan adjudicates WID fullscreen failure as a native surface strategy
  blocker.
- The plan chooses exactly one next execution unit:
  `windows-libmpv-render-api-surface-probe`.
- The plan records why addon exploration is not selected for the next unit.
- Read-only plan review via `lineup-desktop-feature-review` reports no
  blockers before implementation.
- RD-06 remains not complete.

Next-unit implementation acceptance after clean review and Windows proof access:

- Implementation is limited to `windows-libmpv-render-api-surface-probe`.
- The unit runs only on Windows for native proof and blocks cleanly elsewhere.
- Local mpv/libmpv availability, version, client API, provenance, licensing
  concern, ABI/platform scope, pre-existing .NET SDK version/provenance, and
  no-redistribution/no-install status are recorded in redacted local evidence
  before smoke.
- No Node native addon, npm dependency, package script, lockfile, NuGet package,
  copied header, generated binding, checked-in binary, or package metadata is
  introduced.
- The dev-only Electron harness and helper prove or fail mpv render API
  playback with dummy local and dummy HTTP media.
- Fullscreen active video-surface pixels are captured on Windows while the
  BrowserWindow is fullscreen.
- Overlay/composition and renderer focus/input continuity are proved in
  windowed and fullscreen modes while video is active, or the unit fails.
- App-owned input simulation required by render API is recorded as redacted
  behavior only, with no raw native input payloads in renderer-facing state or
  evidence.
- Renderer-facing state and persisted evidence contain no real Plex data,
  tokens, tokenized URLs, auth headers, raw media URLs, raw Plex payloads,
  native handles, graphics context values, libmpv objects, engine ids,
  Electron/Node APIs, or secret diagnostics.
- Process args/env do not carry media URLs, headers, tokens, native handles,
  graphics context values, libmpv object ids, or secret material.
- RD-06-specific static/schema tests prove evidence manifests/events/summaries
  contain only allowed redacted fields and no raw URLs, headers, local paths,
  native parent values, native handles, graphics context values, libmpv objects,
  engine ids, process args/env, raw helper IPC payloads, raw logs, or crash
  bodies.
- Raw scratch/logs/screenshots/crash output/generated media/temp output is
  deleted or quarantined before closeout.
- If render API passes all required proof, `docs/architecture/playback-architecture.md`
  and `docs/roadmap/desktop-port-roadmap.md` record the durable native surface
  conclusion before RD-07 handoff.
- If render API fails fullscreen/overlay/focus/threading/dependency constraints,
  RD-06 records a blocked conclusion and replans before RD-07.
- `npm run verify` passes before implementation closeout.

## Replan Triggers

Stop and replan if any of the following occurs:

- No Windows proof runner is available after clean plan review.
- The proof host is not Windows x64 desktop with a usable display/GPU.
- Local mpv/libmpv is unavailable or provenance/version/API cannot be recorded.
- Pre-existing Windows .NET SDK is unavailable or its version/provenance cannot
  be recorded.
- Render API symbols or required graphics backend support are unavailable in
  the local libmpv build.
- Implementation requires installing a native library, helper binary, build
  tool, npm dependency, NuGet package, native addon, package script, package
  metadata, lockfile, copied header, generated binding, or checked-in binary.
- The C# helper cannot maintain mpv render-thread discipline without deadlock
  risk, blocking waits, or raw libmpv calls from the render thread.
- The render API proof cannot capture active fullscreen video pixels through
  either Electron capture primitives or the amended private helper-owned Win32
  screen-pixel fallback while BrowserWindow fullscreen is confirmed.
- Overlay/composition or renderer focus/input continuity fails in windowed or
  fullscreen modes.
- App-owned input simulation requires exposing raw native events, native
  handles, graphics context values, or broad IPC to renderer/preload/product
  code.
- Node native addon work becomes necessary. That requires a reviewed replan
  with package/build/signing/provenance/ABI decisions.
- Real Plex servers, tokens, tokenized URLs, auth headers, raw Plex payloads,
  checked-in media, raw native logs, crash dumps, native handles in
  renderer-facing state, libmpv objects, graphics context values, or engine ids
  appear in code, evidence, docs, tests, logs, screenshots, or Codex output.
- Product renderer/preload/main/contracts/Plex/scheduler/package/import-ledger
  files need changes.
- Any RD-05 stale post-stop behavior appears capable of corrupting the current
  playback request without a bounded mitigation plan.
- `npm run verify:docs`, redaction checks, render API smoke proof, or
  `npm run verify` fails and cannot be resolved inside the reviewed scope.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-06 evidence.

## Rollback Notes

Rollback for plan-only work:

- Remove or revert only
  `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md` changes made
  by the RD-06 planner.
- Do not touch unrelated dirty plans or user work.

Rollback for reviewed render API implementation work:

- Revert only the render API changes in
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs`.
- Revert only the render API changes in
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs`.
- Revert only the RD-06 render API test additions in
  `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`.
- Delete local ignored evidence under
  `docs/runs/rd-06-native-libmpv-host-spike/`.
- Delete any temporary helper binaries, compiled artifacts, generated media,
  screenshots, crash output, native logs, and quarantine contents that are not
  needed for local debugging.
- Re-run `git status --short --branch` and verify no generated or raw files are
  staged.
- No package or lockfile rollback should be needed because those files are out
  of scope. If they changed, stop and replan/adjudicate before reverting
  anything not created by this unit.
- Revert only RD-06 conclusion updates in
  `docs/architecture/playback-architecture.md`,
  `docs/roadmap/desktop-port-roadmap.md`, or
  `docs/architecture/CURRENT_STATE.md` if those tracked docs were updated by
  the reviewed RD-06 unit and the controller explicitly chooses rollback.

Rollback for prerequisite provisioning outside RD-06:

- Do not treat outside-task dependency installation as RD-06 implementation.
- If `npm install`, local mpv/libmpv provisioning, PATH changes, or Windows
  environment setup changes package metadata, lockfiles, global tools, native
  libraries, or machine state, verify those changes separately before resuming
  this plan.
- RD-06 resumes only after the Windows proof-runner starts with prerequisites
  already present.

## Commit Checkpoints

Checkpoint 1: replan artifact only.

- Commit only after the plan is applied, read-only plan review is clean, and
  `npm run verify:docs` passes.
- Suggested commit: `docs: replan rd-06 native surface proof`
- Do not include unrelated dirty plans unless the owning session explicitly
  asks.

Checkpoint 2: reviewed render API spike tooling only.

- Commit only after clean plan review, Windows render API proof execution,
  redaction cleanup, tracked conclusion updates, and `npm run verify` pass.
- Suggested commit: `test: add rd-06 windows render api surface probe`
- Include only reviewed dev-only tooling/tests and tracked status updates. Do
  not include `docs/runs/*`, helper binaries, native libraries, generated
  screenshots, crash dumps, package metadata, lockfiles, native addon work, or
  product runtime files.

Checkpoint 3: blocked closeout, if render API cannot be proved.

- If render API cannot be implemented or proved inside this scope, do not
  create product implementation commits.
- Record blocked/replan status in the plan and relevant architecture/roadmap
  docs only if the controller authorizes those tracked doc updates, then run
  `npm run verify:docs`.
- Suggested commit if a blocked status update is applied:
  `docs: mark rd-06 render api proof blocked`

MODEL_SUGGESTION
PLANNER: planner with high reasoning; exact `gpt-5-codex` may be approximated by available models.
IMPLEMENTER: worker with high reasoning on a Windows host; exact `gpt-5-codex` may be approximated by available models.
REVIEWER: reviewer with high reasoning; exact `gpt-5-codex` may be approximated by available models.
WHY: RD-06 touches native playback, Electron process ownership, helper boundaries, render-thread safety, security/redaction, dependency/ABI policy, and Windows proof gates.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Replan RD-06 native surface after WID and render API proof failures
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
ARTIFACT: blocked render API probe with amended scoped Win32 fallback evidence; WID and render API both failed fullscreen video-surface proof
FILES:
- docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/roadmap/desktop-port-roadmap.md
- tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs
- tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs
- tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs
- src/contracts/player.ts
- src/contracts/ipc.ts
BLOCKERS: RD-06 is still not complete; WID and render API smokes both failed required fullscreen video-surface proof. The amended helper-owned Win32 fallback was gated on BrowserWindow fullscreen and scoped to the render child surface, but also reported fullscreen pixels as not captured. Render API composition/render-thread discipline are not proven by this helper loop.
MESSAGE:
Replan RD-06 after the `windows-libmpv-render-api-surface-probe` remained blocked even with the amended scoped Win32 fallback. Do not use Codanna unless the new plan explicitly reopens discovery; current evidence is direct repo reads plus official docs. WID is blocked as the RD-07 native surface direction because fullscreen active video pixels were not captured. Render API evidence observed symbol availability, render-context creation, app-owned input simulation, dummy local/HTTP playback, windowed video pixels, overlay pixels, focus, helper crash detection, cleanup, libmpv API/version, and redaction, but fullscreen video pixels were not captured while BrowserWindow fullscreen was true. The helper-owned Win32 screen-pixel fallback was requested only after Electron confirmed BrowserWindow fullscreen and was scoped to the helper render child surface; it also reported not captured. Composition is not proven because capture sources were merged, and render-thread discipline is not proven by the blocking helper loop. Do not change product renderer/preload/main/contracts/Plex/scheduler/package/import-ledger files or add package/build dependencies, native addons, copied headers/examples, generated bindings, checked-in binaries, or unplanned native setup without a reviewed replan. The next plan should choose whether addon exploration, a different render API architecture, another native surface strategy, or a blocked native-playback conclusion is the next bounded unit before RD-07.
