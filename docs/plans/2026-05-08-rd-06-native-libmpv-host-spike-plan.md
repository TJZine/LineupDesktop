**Plan Status:** active

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** blocked

**Plan review status:** clean final read-only review reported no plan blockers
after revision. Implementation is blocked in this session because the observed
controller host is `darwin arm64` and no Windows proof environment is available.
No RD-06 source, spike tooling, native helper, product runtime, package
metadata, dependency, architecture status, roadmap status, or run evidence was
implemented in this session.

**Windows prerequisite gate status:** blocked on 2026-05-09. A Windows proof
host was available and reported `win32 x64`, Node `v22.21.1`, npm `11.13.0`,
and .NET SDK `7.0.317` / host `8.0.26` on Windows `10.0.19045` x64. The gate
stopped before implementation because repo Electron dependencies were missing
and no local `mpv` / `mpv-1.dll` availability was found. The Windows
proof-runner changed no files, produced no local RD-06 run evidence, ran no
preflight/WID smoke/verification commands beyond prerequisite checks, and left
only a pre-existing `.codex/config.toml` dirty state in that checkout. The next
step is prerequisite provisioning outside the RD-06 implementation task, then a
fresh Windows proof-runner resume.

**Verification classification:** broader integration/manual proof required

## Goal

Create the RD-06 Native libmpv Host Spike plan for the first Windows-first
native playback proof after RD-05.

First execution unit: `windows-libmpv-environment-and-wid-smoke`.

The unit must prove or block Windows native playback feasibility before RD-07.
It targets a helper-hosted libmpv path using Windows native window embedding
through `wid`, with a minimal dev-only Electron harness only because RD-06 must
prove BrowserWindow surface, overlay, fullscreen, focus, track, crash, and
redaction behavior in the shape closest to the production hypothesis.

The initial controller host observed `darwin arm64`. A later Windows
proof-runner reached only prerequisite checks and stopped because repo Electron
dependencies and local mpv/libmpv were unavailable. Implementation must remain
blocked/replan unless a Windows proof environment with all prerequisites already
present is provided. A macOS-only proof, or a Windows host that fails
prerequisite gates, is not RD-06 completion.

Owner path after clean plan review only:

- Source-controlled dev-only spike tooling:
  `tools/libmpv-spike/rd-06-native-libmpv-host-spike.*`
- Optional focused static/unit proof:
  `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
- Local-only redacted evidence:
  `docs/runs/rd-06-native-libmpv-host-spike/`

Source-control decision:

- The tracked plan lives at
  `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`.
- Dev-only spike source may be source-controlled only after clean plan review.
- No helper binaries, native libraries, generated media, screenshots, crash
  dumps, raw logs, raw native traces, or run evidence may be committed.
- Generated evidence stays local-only under the gitignored
  `docs/runs/rd-06-native-libmpv-host-spike/`.

## Non-Goals

- Do not complete RD-06 from macOS-only evidence.
- Do not implement RD-07 player adapter behavior, production player runtime,
  production helper protocol, product renderer UI, preload bridge, main IPC,
  Plex integration, stream policy, scheduler, secure storage, packaging,
  signing, or installer work.
- Do not add package metadata, package scripts, lockfile changes, npm
  dependencies, native addons, helper binaries, build-tool installs, native
  library installs, or system-library bindings unless a reviewed replan or
  clean review explicitly accepts the owner, provenance, licensing, ABI,
  platform, lockfile, rollback, and verification decision.
- Do not install .NET, Visual Studio, Windows SDK, mpv/libmpv, NuGet packages,
  native headers, generated bindings, helper binaries, or any other build/native
  dependency in RD-06. The first unit may use only tools and native libraries
  already present on the Windows proof host and must block if they are missing.
- Do not contact real Plex servers or use real Plex tokens, tokenized URLs,
  auth headers, raw Plex payloads, checked-in media, raw native logs, native
  handles in renderer-facing state, libmpv objects in contracts, engine ids in
  renderer-facing state, broad IPC, or production renderer UI changes.
- Do not copy or adapt upstream Lineup source in RD-06 unless a reviewed replan
  authorizes the exact import and updates `docs/architecture/import-ledger.md`
  before or with the import.
- Do not use external `mpv` JSON IPC as production architecture. RD-05 remains a
  disposable POC only.

## Parent Architecture Alignment

RD-06 is Tier 3 native playback architecture work and is Windows-first.

Current architecture alignment:

- `docs/architecture/CURRENT_STATE.md` says there is no native playback host
  yet. RD-05 added only a disposable external `mpv` POC and ignored redacted
  local evidence.
- `docs/architecture/playback-architecture.md` keeps the production hypothesis
  at Electron plus helper-hosted native libmpv. External `mpv` is disposable POC
  only.
- RD-05 observed local dummy HTTP/header/audio/start/stop/cleanup behavior and
  four sanitized events after stop. Those stale post-stop events are RD-06/RD-07
  risk evidence, not accepted production behavior.
- `docs/architecture/playback-architecture.md` requires Windows proof for local
  media, dummy Plex-like stream without renderer secrets, overlay, focus,
  tracks, helper crash, redacted logs, DPI, and multi-monitor behavior.
- `docs/architecture/security-and-secret-flow.md` keeps Plex credentials,
  token-bearing URLs, and token-bearing headers inside privileged main/helper
  setup and outside renderer ownership.
- `docs/architecture/upstream-behavior-guardrails.md` forbids raw URLs, headers,
  native handles, engine ids, libmpv objects, and webOS constants through
  renderer-facing state.
- `docs/roadmap/desktop-port-roadmap.md` requires RD-06 Windows production
  playback proof and helper-vs-addon decision evidence before RD-07.
- `src/contracts/player.ts` and `src/contracts/ipc.ts` already define
  renderer-safe player/IPC vocabulary and forbidden privileged keys.
- `package.json` currently uses Electron `^42.0.0`, Node `>=22.12.0`, and
  existing `verify:docs` / `verify` scripts.

Architecture direction:

- Helper boundary shape: a dev-only privileged helper child owns libmpv calls,
  libmpv handles, native playback state, dummy media loading, and crash
  isolation.
- Electron harness shape: a minimal dev-only Electron harness under
  `tools/libmpv-spike/` creates a BrowserWindow only to provide a Windows native
  parent window and overlay/focus/fullscreen test surface.
- Renderer shape: the dev harness renderer is not product renderer code and
  must not receive secrets, raw URLs, raw headers, native handles, libmpv
  objects, engine ids, or broad IPC.
- Helper launch shape: Electron-launched for the WID smoke because the smoke
  needs a BrowserWindow HWND and overlay/focus/fullscreen proof. Preflight mode
  may run standalone.
- Helper custody shape: the dev Electron harness main process obtains the
  BrowserWindow native parent identifier and sends it once over a private
  one-shot `child_process` stdio channel to the helper. The value is never sent
  through renderer, preload, product IPC, process args, environment variables,
  logs, tests, tracked docs beyond this conceptual policy, diagnostics, or
  evidence files. The helper accepts it only during initialization for the
  current request id, validates the platform is Windows, keeps it in memory, and
  drops it during stop/crash/cleanup.
- Libmpv option: first unit uses native window embedding via libmpv `wid` on
  Windows because it is the smallest proof of the helper-hosted production
  hypothesis. The render API is not first-unit scope; it is the replan path if
  WID cannot satisfy overlay, focus, fullscreen, DPI, or crash isolation needs.
- Electron/render harness decision: required for the smoke unit, but strictly
  dev-only and scoped to `tools/libmpv-spike/`.
- Native binding/toolchain decision: the first implementation unit uses a
  source-controlled C# P/Invoke helper compiled locally in a temporary output
  directory with a pre-existing Windows .NET SDK only. It must not use NuGet,
  vendored headers, copied bindings, generated source, checked-in binaries,
  package metadata, or lockfiles. `dotnet --info` and the local `mpv-1.dll` /
  libmpv provenance must be recorded in redacted local evidence before
  compilation. If .NET SDK or libmpv is unavailable, the unit blocks/replans.

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
17. Official Electron docs via Context7 `/electron/electron`, checked
    2026-05-08
18. Official mpv manual, checked 2026-05-08: https://mpv.io/manual/stable/
19. Official mpv libmpv examples, checked 2026-05-08:
    https://github.com/mpv-player/mpv-examples/blob/master/libmpv/README.md
20. Official mpv headers, checked 2026-05-08:
    - https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h
    - https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h

Freshness gate: before implementation, rerun `git status --short --branch` and
reread the files above if architecture, contracts, roadmap status, package
metadata, Electron version, mpv/libmpv documentation, verifier behavior, or
local Windows proof prerequisites changed materially. Stop for plan update or
re-review when assumptions are contradicted.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3
  feature/design plan.
- `execution-plan-authoring`: freezes scope, owner path, seam, verification,
  rollback, and stop conditions without pseudo-code.
- `architecture-boundaries`: applies because RD-06 changes native helper,
  Electron process ownership, and renderer/preload/main non-ownership
  decisions.
- `plex-integration-boundaries`: applies because dummy Plex-like stream setup
  must preserve token/header/URL custody rules.
- `persistence-boundaries`: applies because RD-06 may inspect app paths and
  local files for dummy-only evidence, while credentials and durable settings
  remain out of scope.
- `ui-composition-patterns`: applies because overlay, focus, fullscreen, and
  input continuity are explicit proof targets.
- `verification-strategy`: applies because native playback needs Windows
  smoke/manual evidence plus redaction/static proof.
- `model-selection`: applies because the user requested model guidance and the
  task is Tier 3 native playback architecture work.
- `review-request`: next gate is read-only adversarial plan review.
- `closeout-verification`: required before staging, committing, calling the plan
  ready, or calling implementation complete.

## Evidence And Discovery

Codanna is not used for RD-06 plan decisions. One controller probe ran before
the user corrected the route; that output was disregarded. Discovery for this
plan uses direct repo reads and official docs evidence only.

Direct reads:

- `AGENTS.md`: durable plans are local by default, `docs/plans/*` is for
  durable handoff memory, `npm run verify:docs` applies to plan/control-plane
  changes, and `npm run verify` applies before implementation closeout unless
  narrowed by plan.
- `docs/AGENTIC_DEV_WORKFLOW.md`: native playback is Tier 3, helper-hosted
  libmpv remains a hypothesis until Windows proof, external `mpv` IPC is
  disposable POC only, and native playback changes require read-only review.
- `docs/agentic/plan-authoring-standard.md`: active tracked plans require this
  heading set, decision-complete seams, exact verification commands/outcomes,
  and stop/replan triggers.
- `docs/architecture/CURRENT_STATE.md`: no native playback host exists; RD-05
  is only a disposable external `mpv` POC.
- `docs/architecture/playback-architecture.md`: production hypothesis is
  helper-hosted native libmpv; required spike proof includes Windows local
  media, dummy Plex-like stream, overlay, focus, track selection, crash, logs,
  DPI, and multi-monitor.
- `docs/architecture/security-and-secret-flow.md`: token-bearing headers and
  URLs stay inside privileged main/helper setup.
- `docs/architecture/upstream-behavior-guardrails.md`: renderer-facing state
  must not expose raw URLs, headers, native handles, engine ids, libmpv objects,
  or webOS constants.
- `docs/roadmap/desktop-port-roadmap.md`: RD-06 must record helper-vs-addon
  decision evidence before RD-07.
- `src/contracts/player.ts` and `src/contracts/ipc.ts`: renderer-safe vocabulary
  exists; forbidden privileged keys already include raw media URLs, tokenized
  URLs, auth headers, native handles, libmpv objects, engine ids, Electron/Node
  APIs, raw Plex payloads, stream keys, part keys, and secret diagnostics.
- `.gitignore` ignores `docs/runs/*` except `docs/runs/README.md`.
- `docs/runs/README.md` says raw run bundles are ignored and durable conclusions
  must be promoted into tracked docs when needed; raw logs, media samples, crash
  dumps, diagnostics containing secrets, and local-only scratch output must not
  be committed.
- `package.json` has no current native dependency or package script for RD-06.
  Electron is already present as a devDependency.

Workspace evidence:

- `git status --short --branch` observed branch `main` with pre-existing
  unrelated dirty state:
  - modified `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`
  - untracked RD-02/RD-03/RD-04 plans
- Current controller host observed with `node -p "process.platform + ' ' +
  process.arch"`: `darwin arm64`.
- Those unrelated dirty files must not be edited, staged, reverted, or used as
  RD-06 implementation evidence.

Official docs evidence checked 2026-05-08:

- Electron `/electron/electron` docs via Context7: `BrowserWindow` exposes
  `getNativeWindowHandle()`, Windows message hook APIs, fullscreen APIs, and
  secure BrowserWindow practices using preload and context isolation.
- mpv manual: libmpv is generally recommended for applications using mpv as a
  playback backend; JSON IPC is explicitly not secure and is suitable only for
  local control/POC-style use.
- mpv manual and client API docs: libmpv client API supports embedding mpv in
  applications, event loops via `mpv_wait_event`, asynchronous command replies,
  and API version considerations.
- mpv examples: native window embedding via `wid` is OS-dependent but on win32
  fills the parent window; `input-vo-keyboard` may be needed for keyboard input;
  render API gives overlay flexibility but requires simulated input and more
  rendering responsibility.
- mpv examples: the C# Windows example uses `mpv-1.dll` with native window
  embedding.
- mpv `render.h`: render API should use separate render-thread discipline;
  normal libmpv API calls from the render thread can deadlock.
- mpv `client.h`: event-loop, asynchronous request, API version, and termination
  semantics must be considered before production helper design or packaging.

Evidence conclusion:

- WID embedding is the correct first smoke because it directly tests the
  helper-hosted production hypothesis with the smallest Windows surface.
- The render API remains a replan candidate if WID cannot satisfy
  overlay/focus/fullscreen/DPI requirements.
- Any native binding, helper source, build tool use, or local libmpv use must be
  constrained to the planned C# P/Invoke helper and pre-existing Windows .NET
  SDK/libmpv environment. It must not add package metadata, NuGet packages,
  generated bindings, copied headers, or checked-in binaries.

## Impact Snapshot

Expected blast radius after clean plan review:

- May change:
  - `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`
  - `tools/libmpv-spike/rd-06-native-libmpv-host-spike.*`
  - `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs`
  - `docs/architecture/playback-architecture.md` after observed Windows proof
    or blocked RD-06 conclusion only
  - `docs/roadmap/desktop-port-roadmap.md` after observed Windows proof or
    blocked RD-06 conclusion only
  - `docs/architecture/CURRENT_STATE.md` after observed Windows proof only, if
    the dev-only spike changes current architecture truth
  - local ignored evidence under `docs/runs/rd-06-native-libmpv-host-spike/`
- Must not change:
  - product renderer, preload, main, shared contracts, Plex owners, scheduler
    owners, package metadata, lockfiles, packaging config, installer config,
    import ledger, or upstream Lineup source.
- Public contracts: no changes in the first unit.
- Dependency/build impact: no npm dependency, package script, lockfile, native
  addon, NuGet package, helper binary, native library install, or system install
  is authorized. A pre-existing Windows .NET SDK is allowed only as a local proof
  tool after its version/provenance are recorded in redacted local evidence.
- Native library impact: local Windows libmpv may be used only if already
  available in the proof environment and provenance/version/API evidence is
  recorded. No redistribution.
- Runtime behavior: no user-visible product behavior changes.
- Local artifacts: redacted dummy-only evidence stays ignored; raw scratch,
  logs, screenshots, and crash output must be deleted or quarantined by
  closeout.

The first unit is cross-boundary in what it proves, but implementation
ownership stays dev-tool-only under `tools/libmpv-spike/`. It must not wire
product IPC or production runtime owners.

## Files In Scope

- `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` after clean plan
  review only
- `tools/libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs` after clean
  plan review only; this is the only approved helper binding path for the first
  unit
- `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs` after clean plan
  review only
- `docs/architecture/playback-architecture.md` after observed Windows proof or
  blocked RD-06 conclusion only
- `docs/roadmap/desktop-port-roadmap.md` after observed Windows proof or blocked
  RD-06 conclusion only
- `docs/architecture/CURRENT_STATE.md` after observed Windows proof only, if the
  dev-only spike changes current architecture truth
- `docs/runs/rd-06-native-libmpv-host-spike/manifest.redacted.json` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/events.redacted.ndjson` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/summary.redacted.md` local-only
- `docs/runs/rd-06-native-libmpv-host-spike/quarantine/` local-only only when
  raw dummy-only troubleshooting artifacts must be retained temporarily; delete
  instead when artifacts are not needed

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
- Plex auth, discovery, library, stream, selected-server, subtitle, token, URL,
  header, or secure-storage implementation
- scheduler, channel, settings, UI, and RD-07 player adapter implementation
- `docs/architecture/import-ledger.md`, unless a reviewed replan authorizes
  copied/adapted upstream source
- checked-in media fixtures, helper binaries, native libraries, generated
  screenshots, generated logs, crash dumps, or raw run evidence
- unrelated dirty files already present before RD-06:
  - `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md`
  - untracked RD-02/RD-03/RD-04 plan files

## Planner Self-Check

1. No product, architecture, ownership, dependency, or verification decision is
   left unresolved for the first unit. Implementation is blocked on this macOS
   controller unless a Windows proof environment with pre-existing .NET SDK and
   local libmpv is provided.
2. The first unit does not depend on product contract or type changes.
3. Product files are out of scope and the plan does not rely on hidden wiring
   inside them.
4. Evidence path is recorded: direct reads only, no Codanna plan reliance, plus
   official Electron/mpv docs checked on 2026-05-08.
5. The owner path is dev-tool-only, avoiding product hot spots until Windows
   evidence proves the native seam.
6. A fresh implementer should not need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy.
7. Verification commands, expected outcomes, stop/replan triggers, evidence
   format, deletion/quarantine rules, and rollback are explicit.

## Architecture Seam Decision Gate

Chosen seam: dev-only Electron-launched Windows helper-hosted libmpv WID smoke
under `tools/libmpv-spike/`.

Frozen decisions:

| Decision | RD-06 first-unit choice |
| --- | --- |
| Owner path | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.*` |
| Source-controlled status | Dev-only source and optional test may be tracked after clean review; generated evidence stays local-only |
| Helper boundary | Separate privileged helper child owns libmpv, native handles, dummy media load, events, crash behavior, and redaction |
| Helper custody channel | One-shot private `child_process` stdio initialization channel from dev Electron harness main to helper; no renderer/preload/product IPC, args/env, logs, tests, tracked docs beyond conceptual policy, diagnostics, or evidence exposure of raw native values |
| Helper payload lifetime | Current request only; helper validates Windows mode, rejects missing/duplicate/late parent attachment, keeps the value in memory only, and drops it during stop/crash/cleanup |
| Standalone vs Electron-launched | Preflight may be standalone; WID smoke is Electron-launched to provide BrowserWindow parent surface and overlay/focus/fullscreen proof |
| Electron/render harness | Required, minimal, dev-only, not product renderer/preload/main |
| Libmpv mode | `wid` native window embedding first; render API only after reviewed replan |
| Binding/toolchain path | Source-controlled C# P/Invoke helper compiled to a temp output with pre-existing Windows .NET SDK only; no NuGet, generated bindings, copied headers, package metadata, lockfile, or checked-in binary |
| Windows proof environment | Windows desktop session with display/GPU, Node `>=22.12.0`, Electron install from repo, pre-existing .NET SDK, and local libmpv/mpv availability |
| Local library/tool proof | Record local libmpv version/API/provenance and `dotnet --info` before smoke; no install or redistribution authorized |
| Dummy input policy | Generated local dummy media and local dummy HTTP only |
| Dummy header policy | Dummy non-secret header only, for example `X-Lineup-RD06: dummy`; no `Authorization`, `Cookie`, Plex, token, bearer, credential, or real server headers |
| Args/env policy | No media URLs, headers, tokens, native parent identifiers, native handles, libmpv object ids, or secret material in process args/env; use the private one-shot helper channel and redact all local paths |
| Log policy | Persist only redacted summary/events/manifest; raw logs deleted or quarantined locally |
| Crash policy | Induce helper crash only with dummy media; prove Electron harness survives, helper is reaped, temp files are cleaned, and no raw crash output is committed |
| Evidence format | Redacted JSON manifest, redacted NDJSON events, redacted Markdown summary |
| Redaction proof | Mandatory RD-06 schema/static unit tests assert evidence contains only approved redacted fields and no raw URLs, headers, local paths, parent-window values, native handles, libmpv objects, engine ids, process args/env, raw IPC payloads, or crash/log bodies |
| Durable conclusion target | `docs/architecture/playback-architecture.md` records helper-vs-addon conclusion from redacted evidence; `docs/roadmap/desktop-port-roadmap.md` records RD-06 status before RD-07 handoff |
| Verification closeout | `npm run verify` before implementation complete; `npm run verify:docs` for plan/status doc changes |

Forbidden shortcuts:

- No renderer privilege concession.
- No broad preload RPC.
- No arbitrary channel strings from renderer code.
- No raw media URL/header/native-handle/libmpv object/engine id in
  renderer-facing state.
- No real Plex access.
- No package metadata or dependency changes.
- No checked-in native binaries or copied upstream source.
- No claiming helper-vs-addon direction from macOS proof.

Stop before implementation if plan review finds the helper/WID seam too broad,
if Windows proof access is unavailable, or if the unit requires unplanned
dependency/install/package/lockfile changes.

## Verification Commands

Plan/review commands:

```sh
git status --short --branch
```

Expected outcome: shows branch `main`; unrelated dirty plan files may remain,
but no RD-06 implementation files should exist before reviewed implementation.

```sh
npm run verify:docs
```

Expected outcome: passes after the plan is applied to
`docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md`.

Current-host blocker command:

```sh
node -p "process.platform + ' ' + process.arch"
```

Expected outcome on this controller: `darwin arm64`. This means RD-06
implementation proof is blocked here and must not be called complete.

Windows preflight commands after clean plan review only:

```sh
node -p "process.platform + ' ' + process.arch"
```

Expected outcome: `win32 x64` unless a reviewed replan explicitly accepts
another Windows architecture.

```sh
dotnet --info
```

Expected outcome on Windows with prerequisites: exits 0 and records only
redacted SDK version/provenance in local evidence. If unavailable, RD-06 blocks
without implementation.

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode preflight --out docs/runs/rd-06-native-libmpv-host-spike
```

Expected outcome on Windows with prerequisites: writes only redacted local
evidence showing OS/arch, Node/Electron versions, local libmpv availability,
libmpv API/version, local library provenance, licensing note, and no forbidden
persisted fields. On non-Windows, missing .NET SDK, or missing libmpv, exits
blocked with a clear blocked reason and no partial success claim.

Windows WID smoke command after successful preflight only:

```sh
node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode wid-smoke --out docs/runs/rd-06-native-libmpv-host-spike --duration-ms 5000 --dummy-input local-and-http
```

Expected outcome: on Windows only, with dummy data only, records redacted proof
of local playback, dummy HTTP playback without renderer secrets, overlay
visibility, windowed and borderless fullscreen behavior, renderer focus/input
continuity, audio/subtitle track observation and selection if dummy media
exposes tracks, stop/channel-switch ordering, stale event handling, helper
crash detection, helper cleanup, DPI/multi-monitor notes, and redacted logs. If
any required proof cannot run, output is blocked or failed, not complete.

Static/local proof commands after implementation source exists:

```sh
npm run test:harness-docs
npm run verify:redaction
```

Expected outcome: tests pass, including RD-06 schema/static tests proving
command construction, helper initialization policy, and evidence redaction
fields; redaction verifier reports no forbidden content in tracked
docs/tests/tools.

Closeout command before implementation is called complete:

```sh
npm run verify
```

Expected outcome: passes on the implementation host after RD-06 source/status
changes. If Windows-only smoke cannot run in that environment, RD-06 remains
blocked/replan and must not be marked complete.

Evidence closeout checks:

```sh
git status --short --branch
```

Expected outcome: no generated `docs/runs/rd-06-native-libmpv-host-spike/*`
files staged; no package metadata, lockfile, product runtime, or unrelated
dirty files touched.

On Windows PowerShell, inspect local evidence before closeout:

```powershell
Get-ChildItem -Recurse docs/runs/rd-06-native-libmpv-host-spike | Select-Object FullName
```

Expected outcome: only redacted evidence files remain outside any explicitly
local quarantine folder. Raw scratch logs, screenshots, crash output, helper
binaries, temp media, and native traces are deleted or quarantined and never
staged.

## Acceptance Criteria

Plan acceptance:

- This plan exists as the active tracked RD-06 plan with the required headings.
- Read-only plan review via `lineup-desktop-feature-review` reports no
  blockers.
- The plan explicitly blocks implementation completion on the current macOS
  controller unless a Windows proof runner is provided.

First-unit implementation acceptance after clean review and Windows proof
access:

- The first implementation unit is limited to
  `windows-libmpv-environment-and-wid-smoke`.
- The unit runs only on Windows for native proof and blocks cleanly elsewhere.
- Local libmpv/mpv availability, version, API, provenance, licensing concern,
  ABI/platform, pre-existing .NET SDK version/provenance, and
  no-redistribution/no-install status are recorded in redacted local evidence
  before smoke.
- The only approved helper binding path is the source-controlled C# P/Invoke
  helper compiled locally with a pre-existing Windows .NET SDK into a temporary
  output directory. No NuGet packages, copied headers, generated bindings,
  package metadata, lockfiles, or checked-in binaries are introduced.
- The dev-only Electron harness and helper prove or fail WID native window
  embedding with dummy local and dummy HTTP media.
- The dev Electron harness main sends the native parent attachment to the helper
  once over a private stdio initialization channel; the renderer/preload/product
  IPC, args/env, logs, tests, diagnostics, tracked docs beyond conceptual
  policy, and evidence never receive or persist the raw value.
- Renderer-facing state and persisted evidence contain no real Plex data,
  tokens, tokenized URLs, auth headers, raw media URLs, raw Plex payloads,
  native handles, libmpv objects, engine ids, Electron/Node APIs, or secret
  diagnostics.
- Process args/env do not carry media URLs, headers, tokens, native HWNDs,
  native handles, libmpv object ids, or secret material.
- RD-06-specific static/schema tests prove evidence manifests/events/summaries
  contain only allowed redacted fields and no raw URLs, headers, local paths,
  native parent values, native handles, libmpv objects, engine ids, process
  args/env, raw helper IPC payloads, raw logs, or crash bodies.
- Redacted evidence records local media, dummy HTTP/header behavior, overlay,
  fullscreen, focus/input, tracks when available, stop/stale event ordering,
  helper crash, cleanup, DPI/multi-monitor observations, and redaction proof.
- Raw scratch/logs/screenshots/crash output is deleted or quarantined before
  closeout.
- Helper-vs-addon decision evidence is recorded before RD-07. If WID passes all
  required proof, helper-hosted WID remains viable for RD-07 planning. If WID
  fails overlay/focus/fullscreen/DPI/crash requirements, stop and replan toward
  render API or addon exploration.
- `docs/architecture/playback-architecture.md` records the durable
  helper-vs-addon conclusion from redacted evidence, and
  `docs/roadmap/desktop-port-roadmap.md` records RD-06 status before any RD-07
  handoff.
- `npm run verify` passes before implementation closeout.

Controller acceptance on this macOS host:

- Clean plan review can be the only completion claim.
- Implementation remains blocked/replan, not complete, until a Windows proof
  environment runs the required proof.

## Replan Triggers

Stop and replan if any of the following occurs:

- No Windows proof runner is available after clean plan review.
- The proof host is not Windows desktop with a usable display/GPU.
- Local libmpv/mpv is unavailable or provenance/version/API cannot be recorded.
- Pre-existing Windows .NET SDK is unavailable or its version/provenance cannot
  be recorded.
- Implementation requires installing a native library, helper binary, build
  tool, npm dependency, NuGet package, native addon, package script, package
  metadata, or lockfile change.
- The C# P/Invoke helper needs copied headers, generated bindings, vendored
  binaries, or unreviewed ABI assumptions.
- The private helper initialization channel would need to persist or expose the
  raw native parent value through renderer, preload, product IPC, args/env,
  logs, tests, diagnostics, or evidence.
- WID embedding cannot prove overlay visibility, renderer focus/input
  continuity, windowed/fullscreen behavior, DPI/multi-monitor behavior, or
  acceptable crash cleanup.
- Render API becomes necessary. That requires a reviewed replan because
  official mpv docs impose render-thread constraints and deadlock risks.
- Real Plex servers, tokens, tokenized URLs, auth headers, raw Plex payloads,
  checked-in media, raw native logs, crash dumps, native handles in
  renderer-facing state, libmpv objects, or engine ids appear in code, evidence,
  docs, tests, logs, screenshots, or Codex output.
- Product renderer/preload/main/contracts/Plex/scheduler/package/import-ledger
  files need changes.
- Any RD-05 stale post-stop behavior appears capable of corrupting the current
  playback request without a bounded mitigation plan.
- `npm run verify:docs`, redaction checks, smoke proof, or `npm run verify`
  fails and cannot be resolved inside the reviewed scope.
- Unrelated dirty files would need to be modified, staged, reverted, or
  interpreted as RD-06 evidence.

## Rollback Notes

Rollback for plan-only work:

- Remove or revert only
  `docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md` changes made
  by the RD-06 planner.
- Do not touch unrelated dirty plans or user work.

Rollback for reviewed implementation work:

- Delete `tools/libmpv-spike/rd-06-native-libmpv-host-spike.*`.
- Delete `tools/__tests__/rd-06-native-libmpv-host-spike.test.mjs` if added.
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
- Revert only RD-06 conclusion updates in `docs/architecture/playback-architecture.md`,
  `docs/roadmap/desktop-port-roadmap.md`, or `docs/architecture/CURRENT_STATE.md`
  if those tracked docs were updated by the reviewed RD-06 unit and the
  controller explicitly chooses rollback.

Rollback for prerequisite provisioning outside RD-06:

- Do not treat outside-task dependency installation as RD-06 implementation.
- If `npm install`, local mpv/libmpv provisioning, PATH changes, or Windows
  environment setup changes package metadata, lockfiles, global tools, native
  libraries, or machine state, verify those changes separately before resuming
  this plan.
- RD-06 resumes only after the Windows proof-runner starts with prerequisites
  already present.

## Commit Checkpoints

Checkpoint 1: plan artifact only.

- Commit only after the plan is applied and `npm run verify:docs` passes.
- Suggested commit: `docs: add rd-06 native libmpv host spike plan`
- Do not include unrelated dirty plans unless the owning session explicitly
  asks.

Checkpoint 2: reviewed Windows spike tooling only.

- Commit only after clean plan review, Windows proof execution, redaction
  cleanup, and `npm run verify` pass.
- Suggested commit: `test: add rd-06 windows libmpv smoke spike`
- Include only reviewed dev-only tooling/tests and tracked status updates. Do
  not include `docs/runs/*`, helper binaries, native libraries, generated
  screenshots, crash dumps, package metadata, or lockfiles.

Checkpoint 3: blocked closeout, if no Windows runner is available.

- If plan review is clean but no Windows runner exists, do not create
  implementation commits.
- Record blocked/replan status in the plan only if the controller is authorized
  to edit the file, then run `npm run verify:docs`.
- Suggested commit if a blocked status update is applied:
  `docs: mark rd-06 windows proof blocked`

MODEL_SUGGESTION
PLANNER: planner with high reasoning; exact `gpt-5-codex` may be approximated by available models.
IMPLEMENTER: worker with high reasoning on a Windows host; exact `gpt-5-codex` may be approximated by available models.
REVIEWER: reviewer with high reasoning; exact `gpt-5-codex` may be approximated by available models.
WHY: RD-06 touches native playback, Electron process ownership, helper boundaries, security/redaction, and Windows proof gates.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Resume RD-06 after Windows prerequisite provisioning
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
ARTIFACT: docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
FILES:
- docs/plans/2026-05-08-rd-06-native-libmpv-host-spike-plan.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/roadmap/desktop-port-roadmap.md
- src/contracts/player.ts
- src/contracts/ipc.ts
BLOCKERS: Windows proof-runner host exists, but the 2026-05-09 prerequisite gate found repo Electron dependencies missing and no local mpv/libmpv availability. RD-06 implementation proof remains blocked until prerequisite provisioning happens outside the task and the Windows session starts with display/GPU, Node >=22.12.0, repo Electron install, pre-existing .NET SDK, and local mpv/libmpv availability already present.
MESSAGE:
Resume the RD-06 feature quality loop from `execution-unit-select` only after Windows prerequisite provisioning has happened outside the RD-06 task. A prior Windows proof-runner confirmed `win32 x64`, Node `v22.21.1`, npm `11.13.0`, and .NET SDK `7.0.317`, but blocked because repo Electron dependencies were not installed and no local mpv/libmpv was available. Do not use Codanna. Do not install dependencies, native libraries, .NET, mpv/libmpv, NuGet packages, build tools, helper binaries, package scripts, package metadata, or lockfile changes inside the RD-06 implementation task. If the Windows proof host still cannot satisfy repo Electron install plus local libmpv/mpv provenance checks at task start, keep RD-06 blocked/replan. If prerequisites are already present, implement only the reviewed dev-only `tools/libmpv-spike/` `windows-libmpv-environment-and-wid-smoke` unit with dummy data, private one-shot helper parent-window custody, RD-06-specific redaction tests, local ignored evidence only, and the plan's exact verification commands.
