**Plan Status:** complete

**Task family:** feature/design

**Tier:** Tier 3

**Controller phase:** done

**Verification classification:** broader integration/manual proof required

**Closeout evidence:** Implemented the reviewed
`external-mpv-poc-dev-script` unit in
`tools/mpv-poc/rd-05-external-mpv-poc.mjs` and
`tools/__tests__/rd-05-mpv-poc.test.mjs` on 2026-05-08. Clean plan review and
clean read-only implementation review both reported no findings. Controller
observed the POC command writing only ignored redacted evidence under
`docs/runs/rd-05-external-mpv-poc/`; the redacted summary recorded local dummy
HTTP playback, dummy header observation, one normalized audio track, nonzero
start-offset/time-position observation, successful stop, complete process/IPC
socket/HTTP/temp cleanup, and a passing forbidden-field evidence scan. The POC
also observed four sanitized events after stop before quit; this is an
RD-06/RD-07 stale-event follow-up risk, not accepted production behavior.
Controller-observed `npm run verify` passed after closeout doc updates. No
package metadata, dependencies, production source, contracts, renderer,
preload, main, helper, Plex, scheduler, import-ledger, checked-in media, or
original Lineup source changed.

## Goal

Create the first bounded RD-05 External `mpv` POC execution unit: a disposable,
dev-only proof harness that invokes local external `mpv` with dummy non-secret
input, records redacted local evidence, and proves whether the next native
playback spike can rely on external `mpv` observations for command, track,
header, start-offset, and cleanup behavior.

First execution unit: `external-mpv-poc-dev-script`.

Chosen owner path: `tools/mpv-poc/rd-05-external-mpv-poc.mjs`.

Source-controlled status:

- Source-controlled after clean plan review: the dev-only POC script at
  `tools/mpv-poc/rd-05-external-mpv-poc.mjs` and focused static/unit proof at
  `tools/__tests__/rd-05-mpv-poc.test.mjs`.
- Local-only: generated POC evidence under
  `docs/runs/rd-05-external-mpv-poc/`, which already exists and is gitignored.
- No package script, package metadata, runtime dependency, production helper,
  renderer, preload, main, IPC, or installer surface is introduced.

Invocation command for the reviewed implementation unit:

```sh
node tools/mpv-poc/rd-05-external-mpv-poc.mjs --out docs/runs/rd-05-external-mpv-poc --input local-dummy-http --duration-ms 3000
```

The command must stop blocked, without partial success claims, when `mpv` is not
available or cannot be invoked safely with dummy data.

## Non-Goals

- Do not create production playback architecture or bless external `mpv` as the
  production path.
- Do not implement native helper production code, libmpv bindings, renderer UI,
  preload bridge, main IPC, secure storage, Plex auth, Plex discovery, Plex
  stream resolution, scheduler/player adapter imports, or installer work.
- Do not add package metadata, package scripts, lockfile changes, dependencies,
  build config, broad test harnesses, or runtime feature flags.
- Do not contact real Plex servers or use real tokens, tokenized URLs, auth
  headers, raw Plex payloads, checked-in media, native logs with secrets, crash
  dumps, sensitive filesystem paths, or original Lineup product source.
- Do not check in generated media or POC run evidence.
- Do not expose raw media URLs, auth headers, process args, filesystem paths,
  native handles, engine ids, or `mpv` JSON IPC payloads to renderer-facing
  contracts.

## Parent Architecture Alignment

Current Desktop architecture says playback is not implemented. The production
hypothesis remains Electron plus helper-hosted native libmpv, while external
`mpv` is allowed only as a private disposable POC. RD-03 owns renderer-safe
player contracts, and RD-04 owns upstream behavior guardrails.

RD-05 advances only the dev-tool/evidence seam:

- `tools/mpv-poc/rd-05-external-mpv-poc.mjs` owns local POC process invocation,
  dummy input generation, JSON IPC probing, diagnostics redaction, and cleanup.
- `tools/__tests__/rd-05-mpv-poc.test.mjs` owns static/unit proof that command
  construction and redaction policy stay dummy-only and non-secret.
- `docs/runs/rd-05-external-mpv-poc/` owns local, untracked, redacted evidence
  for this POC run.
- `src/contracts/player.ts` and `src/contracts/ipc.ts` remain reference inputs
  only; they must not change in this unit.

Specific upstream playback behaviors probed in this first unit:

| Upstream behavior area | Desktop proof surface in RD-05 unit | Intentional divergence or unknown | RD-04 forbidden shortcuts |
| --- | --- | --- | --- |
| Stream loading with URL/header split | Local dummy HTTP server receives one `mpv` request for generated local media and records only redacted request facts. `mpv` receives only a localhost dummy URL and `--http-header-fields=X-Lineup-POC: rd-05-dummy`. | This does not prove Plex transport, token custody, retry policy, transcoding, or remote server behavior. | No real Plex servers, tokens, tokenized URLs, raw auth headers, raw Plex payloads, or renderer custody of transport fields. |
| Start offset behavior | Invocation uses `--start=0.5` against generated dummy media and records whether observed playback position/time or `mpv` startup state reflects a nonzero start. | Exact production seek semantics remain unknown until the native host spike. | Do not encode webOS or `mpv` behavior as Desktop contract truth. |
| Command/event loop behavior | JSON IPC sends bounded commands such as `get_property track-list`, `get_property time-pos`, and `stop`, and evidence records redacted command names, request ids, result status, and stale-event observations. | The POC may identify risk; it does not implement Desktop stale-event handling. | No broad RPC bridge, arbitrary renderer IPC, or raw JSON IPC exposure outside the dev script. |
| Audio/subtitle track observation | Generated local media plus optional generated sidecar subtitle input are loaded, and `track-list` is summarized into safe fields: kind, selected, language, codec/format, and channel count when present. | If local dummy input cannot expose subtitle tracks reliably, subtitle behavior is recorded as unknown and routed to RD-06 or a reviewed RD-05 replan. | No engine ids, source ids, Plex stream ids, file paths, or subtitle URLs in tracked evidence. |
| Stop/channel-switch cleanup | The unit performs one stop and one second dummy load or explicit cleanup sequence, then records whether late events arrived after stop and whether `mpv`, IPC socket, HTTP server, and temp files were cleaned up. | Channel-switch timing is a POC observation only; production adapter policy remains RD-07/RD-06 work. | No stale playback events may be blessed as acceptable without explicit evidence and later contract proof. |
| Redacted diagnostics | Script and unit test prove generated evidence never persists raw headers, token-like fields, raw URLs, native logs, absolute paths, crash dumps, or process args. | Redaction proof covers the POC harness only, not future native helper logging. | Do not check in native logs with secrets, sensitive paths, auth headers, tokenized URLs, or crash dumps. |

## Required Reading

Read in this order before plan review or implementation:

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
11. `docs/plans/2026-05-08-rd-03-player-contract-capability-model-plan.md`
12. `docs/plans/2026-05-08-rd-04-upstream-behavior-guardrails-plan.md`
13. `src/contracts/player.ts`
14. `src/contracts/ipc.ts`
15. `src/__tests__/contracts.test.ts`
16. `package.json` scripts
17. This plan

Freshness gate: this plan was written on 2026-05-08 against
`/Users/tristan/Software/LineupDesktop` branch `main`. Before implementation,
rerun `git status --short --branch`, confirm the only unrelated dirty state is
pre-existing plan docs or user-approved work, and reread the files above if any
architecture, contract, roadmap, verifier, package script, or `mpv` behavior
changed materially. Stop for plan update or re-review when assumptions are
contradicted.

## Required Skills

- `lineup-desktop-feature-plan`: required launcher for this Tier 3
  feature/design plan.
- `execution-plan-authoring`: freezes the first execution unit, owner path,
  source-control policy, verification, rollback, and stop conditions.
- `architecture-boundaries`: applies because native playback process ownership
  and renderer/preload/main/helper non-ownership must stay explicit.
- `plex-integration-boundaries`: applies because the POC imitates stream header
  setup while forbidding real Plex servers, tokens, URLs, headers, payloads, and
  renderer custody.
- `verification-strategy`: external `mpv` behavior needs local integration
  proof plus static/unit redaction checks, not only docs verification.
- `review-request`: the next gate is read-only adversarial plan review.
- `closeout-verification`: required before calling this plan ready, before any
  implementation closeout, and before staging or committing future changes.

## Evidence And Discovery

- `semantic_search_with_context`: controller reported Codanna
  `get_index_info` with 12,106 symbols across 801 files and semantic search
  enabled, but semantic repo-doc results were noisy and referenced
  `/Users/tristan/Software/Lineup`. Direct reads are the fallback for Desktop
  docs in this plan.
- `semantic_search_docs` or repo-doc search: same fallback; Desktop
  architecture and plan docs were read directly.
- Impact analysis: not required for product symbols because this first unit
  must not change product source, contracts, renderer, preload, main, helper,
  Plex, scheduler, or packaging files.
- Direct reads: read the workflow runbook, feature-plan launcher, plan
  standard, current architecture, playback architecture, security/secret flow,
  upstream behavior guardrails, roadmap, import ledger, RD-03 plan, RD-04 plan,
  player contract, IPC contract, contract tests, and package scripts.
- Current workspace state observed: branch `main`; commit `476dd5f6e607`
  exists with the RD-03/RD-04 non-plan baseline; pre-existing dirty state before
  RD-05 planning was modified
  `docs/plans/2026-05-07-electron-shell-security-foundation-plan.md` plus
  untracked RD-02/RD-03/RD-04 plan docs. Those files are out of RD-05
  implementation scope unless read-only context is needed.
- Local run bundle observed:
  `docs/runs/rd-05-external-mpv-poc/` exists and is gitignored.
- Local `mpv` availability observed on 2026-05-08:
  `command -v mpv` returned `/opt/homebrew/bin/mpv`; `mpv --version` reported
  `mpv v0.41.0`, `libplacebo v7.360.1`, and `FFmpeg 8.1`.
- Local `mpv` manpage evidence checked on 2026-05-08: JSON IPC,
  `--input-ipc-server`, `--http-header-fields`, `--start`, `--idle`,
  `--no-config`, `--log-file`, `--term-playing-msg`, and `track-list` are
  documented. The manpage warns JSON IPC is not secure, recommends IPC for
  interactive control, explains socket/named-pipe behavior for
  `--input-ipc-server`, documents custom HTTP fields, and documents
  `track-list` properties including ids, selected state, codec, language, and
  channel fields.
- Official docs: no package, Electron, or API behavior changes are authorized
  in this unit. The local installed `mpv` manpage is the controlling external
  behavior evidence for the exact binary being invoked.

Evidence conclusions:

- External `mpv` can be invoked locally for a disposable POC, but JSON IPC is
  explicitly not a secure protocol and must stay private to the dev script.
- The POC should use `--no-config` to reduce local user configuration effects,
  `--idle` only as needed to keep the controlled process alive, and
  `--input-ipc-server` on a run-bundle-local socket path that is redacted from
  persisted evidence.
- Header behavior must be proved only with dummy non-secret data on a local
  HTTP server controlled by the script.
- `track-list` observations must be normalized before evidence is persisted so
  engine ids, external filenames, and source-specific values do not become
  Desktop renderer-facing truth.

## Impact Snapshot

Expected blast radius after clean plan review:

- Owners that may change: `tools/mpv-poc/rd-05-external-mpv-poc.mjs`,
  `tools/__tests__/rd-05-mpv-poc.test.mjs`, local untracked run-bundle files
  under `docs/runs/rd-05-external-mpv-poc/`, and this plan for factual status
  or closeout updates only.
- Public contracts: no changes.
- Dependency, build-tool, configuration, package, lockfile, or package-script
  changes: none allowed.
- Runtime behavior: no user-visible product behavior changes.
- Local-only artifacts: POC evidence remains untracked under the gitignored run
  bundle and must not be staged.
- Review requirement: plan review before implementation, then implementation
  review before closeout.

The first unit remains single-owner at the dev-tool/evidence seam. If
implementation needs preload/main IPC, renderer UI, Plex stream owners,
production helper code, dependencies, package scripts, or contract changes,
stop and replan.

## Files In Scope

- `docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md`
- `tools/mpv-poc/rd-05-external-mpv-poc.mjs` after clean plan review only
- `tools/__tests__/rd-05-mpv-poc.test.mjs` after clean plan review only
- `docs/runs/rd-05-external-mpv-poc/manifest.redacted.json` local-only after
  clean plan review only
- `docs/runs/rd-05-external-mpv-poc/events.redacted.ndjson` local-only after
  clean plan review only
- `docs/runs/rd-05-external-mpv-poc/summary.redacted.md` local-only after
  clean plan review only

## Files Out Of Scope

- `package.json`, lockfiles, package manager metadata, and package scripts
- `src/main/**`
- `src/preload/**`
- `src/renderer/**`
- `src/contracts/**`
- `src/__tests__/contracts.test.ts`
- Future `src/native-helper/**` or any production playback helper
- Plex auth, discovery, library, stream, subtitle, token, URL, selected-server,
  or secure storage implementation under any path
- Scheduler, channel, player adapter, settings, UI, or upstream product imports
- `docs/architecture/import-ledger.md`, because no original Lineup source is
  copied or adapted
- Checked-in media fixtures, native logs, crash dumps, generated media, or
  generated run evidence
- Original Lineup source under `/Users/tristan/Software/Lineup`

## Planner Self-Check

1. Product, architecture, ownership, dependency, verification, deletion, and
   evidence decisions are resolved for the first RD-05 unit.
2. No adjacent contract, IPC, renderer, preload, main, helper, Plex, package,
   or source changes are required.
3. Files out of scope are not hidden dependencies; the POC uses only a dev
   script, dummy generated input, local HTTP, external `mpv`, and local
   redacted evidence.
4. Evidence path and Codanna fallback are recorded.
5. The repo-preferred owner is used: a narrow dev tool owns the disposable POC,
   while production playback remains unimplemented.
6. A fresh implementer should not need to invent security, IPC, playback,
   Plex, persistence, packaging, import, redaction, or verification policy.
7. Exact verification commands, expected outcomes, acceptance criteria,
   rollback notes, commit checkpoints, and stop/replan triggers are recorded.

## Architecture Seam Decision Gate

Chosen seam: dev-only external `mpv` process POC plus local redacted evidence.

Implementation decisions:

- Use `child_process.spawn` with an explicit argument array. Do not use shell
  interpolation.
- Allowed `mpv` flags are limited to the POC needs:
  `--no-config`, `--idle=yes`, `--input-ipc-server=<redacted-local-socket>`,
  `--http-header-fields=X-Lineup-POC: rd-05-dummy`, `--start=0.5`,
  `--log-file=<redacted-local-log>` only if the log is immediately redacted
  before any evidence is persisted, `--term-playing-msg=<dummy-marker>`, and
  safe output suppression options when needed for headless local execution.
- The dummy input shape is generated at runtime inside the local run bundle:
  a short synthetic non-secret media file, an optional generated sidecar
  subtitle file, and a local HTTP server route such as `/media.wav`. The
  persisted evidence may describe this as `local-dummy-http` only and must
  redact absolute paths, ephemeral ports, and raw URLs.
- The only header allowed is dummy non-secret data:
  `X-Lineup-POC: rd-05-dummy`. `Authorization`, `X-Plex-Token`, cookie, bearer,
  token, credential, and Plex-specific headers are forbidden even with fake
  values.
- JSON IPC is private to the script. Persist command names, request ids, result
  categories, and sanitized summary values only. Do not persist raw IPC
  requests/responses.
- Process args, environment variables, logs, native stderr/stdout, HTTP request
  facts, and generated file paths must be redacted before writing evidence.
- Track evidence may record only renderer-safe normalized fields: `kind`,
  `selected`, normalized `language`, normalized `codec` or `format`, optional
  `channelCount`, and a POC-local opaque track label. Do not persist `mpv`
  track ids, source ids, external filenames, demux paths, raw URLs, or engine
  object shapes.
- Cleanup proof must record, at minimum, that the child process exited or was
  killed by the harness, the IPC socket path no longer exists, the HTTP server
  closed, temporary generated inputs were removed or left only in the local
  run bundle as non-secret generated files, and no run-bundle file contains
  forbidden strings.
- Deletion/quarantine rule: if the implementation review finds secret leakage,
  unsafe invocation, broad ownership, or product-code coupling, delete the POC
  script and local run evidence before closeout unless the controller asks for
  forensic preservation. If review is clean, quarantine the script under
  `tools/mpv-poc/` as dev-only with no package script and keep generated
  evidence local-only until RD-06 consumes or supersedes it. Delete or replan
  the quarantined POC before any production playback adapter or packaging work
  attempts to reuse it.

Forbidden shortcuts:

- No renderer privilege concession, broad IPC bridge, arbitrary JSON IPC
  passthrough, preload/main handler, native helper production code, or product
  adapter.
- No real Plex inputs, auth material, token-like fields, raw headers, raw Plex
  payloads, checked-in media, sensitive paths, native logs with secrets, crash
  dumps, package scripts, dependencies, or package metadata changes.
- No original Lineup source copy/adaptation and no import-ledger update in this
  unit.

Stop and replan if any implementation step needs an out-of-scope file, real
media, real server data, package metadata, dependency installation, product
runtime wiring, or a broader playback architecture decision.

## Verification Commands

Plan-authoring verification for this planning pass:

- `npm run verify:docs`
  - Expected: docs verification passes and accepts this active plan shape.

Required verification after clean plan review and implementation:

- `git status --short --branch`
  - Expected: branch is `main`; pre-existing unrelated plan-doc dirty state is
    not staged or modified by RD-05; RD-05 changes are limited to the reviewed
    in-scope source/test files and local run-bundle evidence remains untracked.
- `command -v mpv`
  - Expected: prints an executable path. On the current machine this was
    `/opt/homebrew/bin/mpv`.
- `mpv --version`
  - Expected: exits 0 and prints version details. On 2026-05-08 this machine
    reported `mpv v0.41.0`, `libplacebo v7.360.1`, and `FFmpeg 8.1`. If `mpv`
    is missing or the documented options are unavailable, stop with a blocked
    handoff.
- `node tools/mpv-poc/rd-05-external-mpv-poc.mjs --out docs/runs/rd-05-external-mpv-poc --input local-dummy-http --duration-ms 3000`
  - Expected: exits 0; invokes only local external `mpv` with dummy data;
    writes `manifest.redacted.json`, `events.redacted.ndjson`, and
    `summary.redacted.md` under the local run bundle; records stream load,
    dummy header receipt, start-offset observation, track-list summary,
    stop/cleanup summary, and redaction proof; writes no raw secrets, raw
    headers, token-like fields, raw URLs, absolute paths, raw IPC payloads,
    crash dumps, or native logs with secrets.
- `npm run test:harness-docs`
  - Expected: Node tests pass, including the focused POC command-construction
    and redaction tests.
- `npm run verify:redaction`
  - Expected: redaction verification passes for tracked files and does not
    report RD-05 POC source/test content.
- `npm run verify`
  - Expected: typecheck, lint, contract tests, harness/docs tests, docs
    verification, and redaction verification pass. No package scripts or
    production source are required to run the POC.

## Acceptance Criteria

- The tracked plan receives clean read-only feature review before any script,
  test, or source implementation begins.
- The first implementation unit creates only the reviewed dev-only POC script,
  focused static/unit tests, and local untracked run-bundle evidence.
- The POC verifies local `mpv` availability and records the observed version in
  redacted evidence.
- The POC uses dummy local HTTP input and dummy non-secret headers only.
- Evidence records what was proven, what failed, and what remains unknown for
  stream loading, header handling, start offset, track-list observation,
  command/event loop behavior, stop/channel-switch cleanup, and redaction.
- Evidence contains no real Plex data, tokenized URLs, raw auth headers, raw
  Plex payloads, checked-in media, native logs with secrets, crash dumps,
  sensitive filesystem paths, raw process args, raw IPC payloads, or generated
  media in source control.
- Cleanup proof shows `mpv`, IPC, HTTP server, and temp/generated artifacts were
  handled according to the plan.
- No package metadata, dependency, runtime, renderer, preload, main, IPC,
  secure storage, Plex, scheduler, player adapter, native helper production
  code, import ledger, or original Lineup source is changed.
- Required verification commands pass, or a blocked handoff records the exact
  failing command and why it invalidates the plan.
- Read-only implementation review is clean before RD-05 is called complete.

## Replan Triggers

- `mpv` is missing, cannot be invoked, or local manpage/version behavior no
  longer supports the required flags or JSON IPC observations.
- Dummy local media cannot safely prove the selected behavior without checked-in
  media, real Plex data, token-like values, real network services, or new
  dependencies.
- Header proof would require `Authorization`, `X-Plex-Token`, cookies, bearer
  strings, tokenized URLs, or raw auth headers.
- JSON IPC, logs, process args, stdout/stderr, crash output, or evidence would
  persist raw secrets, raw URLs, sensitive paths, native handles, engine ids, or
  raw payloads.
- Track-list proof requires exposing engine ids, source ids, Plex stream ids,
  external filenames, or paths in tracked evidence.
- Implementation needs package scripts, package metadata, dependencies,
  production helper code, renderer UI, preload/main IPC, secure storage, Plex,
  scheduler, player adapter, or contract changes.
- Cleanup cannot prove child-process exit, IPC socket removal, HTTP server
  closure, and run-bundle redaction.
- Verification fails in a way that invalidates the dev-tool/evidence seam.
- Plan or implementation review finds material scope, security, redaction,
  ownership, or verification gaps.

## Rollback Notes

Planning pass rollback is deletion of this new plan file only, leaving
pre-existing dirty plan docs untouched.

After implementation, rollback should revert the focused RD-05 source/test
commit and delete or ignore local run-bundle evidence under
`docs/runs/rd-05-external-mpv-poc/`. Because no package, dependency, runtime,
storage, Plex, renderer, preload, main, helper, installer, import-ledger, or
checked-in media changes are authorized, rollback must not require data
migration, credential cleanup, package restoration, or upstream repo edits.

If implementation partially edits in-scope files and then hits a replan
trigger, stop, preserve only redacted local evidence needed to explain the
blocker, and revert only RD-05 edits when the user or controller requests
rollback. Do not revert unrelated pre-existing dirty worktree changes.

## Commit Checkpoints

Planning pass: do not stage or commit. This pass creates only
`docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md` and routes to plan
review.

After clean plan review, use one focused implementation commit only after the
POC script, static/unit proof, local run evidence, required verification, and
read-only implementation review are clean:

```text
test(playback): add dev-only external mpv poc
```

Do not stage pre-existing plan docs, local run-bundle evidence, generated media,
native logs, package metadata, product source, original Lineup files, or any
unrelated changes. If implementation review requires deleting rather than
quarantining the POC, commit the final reviewed state, not an unsafe
intermediate.

MODEL_SUGGESTION
PLANNER: gpt-5
IMPLEMENTER: gpt-5-high
REVIEWER: gpt-5-high
WHY: Tier 3 native playback/security POC touches external process invocation, redaction, and future helper boundaries.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: RD-05 External mpv POC plan review
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md
ARTIFACT: docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md
FILES:
- docs/plans/2026-05-08-rd-05-external-mpv-poc-plan.md
- docs/architecture/playback-architecture.md
- docs/architecture/security-and-secret-flow.md
- docs/architecture/upstream-behavior-guardrails.md
- docs/roadmap/desktop-port-roadmap.md
- src/contracts/player.ts
- src/contracts/ipc.ts
BLOCKERS: none
MESSAGE:
Review the RD-05 External mpv POC active plan for implementation readiness. Prioritize native process invocation safety, JSON IPC security boundaries, dummy-only header/media policy, redaction proof, local run-bundle evidence shape, cleanup proof, source-controlled versus local-only scope, and whether a fresh implementer could execute the first bounded dev-only POC unit without inventing playback, IPC, Plex, packaging, or verification policy. Stay read-only and route clean review to lineup-desktop-feature-implement; route material decision gaps back to lineup-desktop-feature-plan.
