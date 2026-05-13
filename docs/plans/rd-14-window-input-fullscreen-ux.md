**Plan Status:** active
**Task family:** feature/design
**Workflow route:** Tier 3 feature-quality loop for the whole RD-14 roadmap item.
**Controller owner:** the quality-loop controller owns planning, review, bounded
unit selection, implementation orchestration, implementation review,
verification, platform proof, and closeout for RD-14 Window, Input, And
Fullscreen UX.

No next-session handoff block is included in this parent plan because the
controller will route the plan directly into plan review.

Execution state as of 2026-05-13:

- Plan review: clean after re-review.
- Unit 1, Renderer desktop input and focus policy: complete. Implementation
  review reported no material blockers; `npm run typecheck`, the focused
  renderer input command, `npm run verify:architecture`, and `npm run verify`
  passed.
- Unit 2, Main window/fullscreen/display owner module: complete.
  Implementation re-review reported no material blockers after fixes for
  asynchronous fullscreen leave handling and same-display stale work-area
  fitting. `node --import tsx --test
  src/__tests__/main/shellWindowController.test.ts`, `npm run typecheck`, `npm
  run verify:architecture`, and `npm run verify` passed.
- Unit 3, Foreground app-command/media-key bridge: complete.
  Implementation re-review reported no material blockers after fixing
  `browser-backward` forwarding to use a valid Electron accelerator key and
  leaving media commands unhandled for the later Windows/manual proof unit.
  `node --import tsx --test
  src/__tests__/main/shellAppCommandController.test.ts`, `npm run typecheck`,
  `npm run verify:architecture`, and `npm run verify` passed.
- Unit 4, Renderer cursor and fake-backed route/overlay integration: complete.
  Implementation review reported no material blockers. `node --import tsx
  --test src/__tests__/renderer/desktopCursor.test.ts`, all renderer tests,
  `npm run typecheck`, `npm run verify:architecture`, and `npm run verify`
  passed.
- Current controller phase after Unit 4 closeout:
  `platform-proof-blocked`.
- Selected execution unit: Unit 5, Electron smoke and Windows
  manual/native-presentation proof matrix closeout.
- Unit 5 status: blocked in this workspace because the observed local platform
  is `darwin`; RD-14 parent closeout requires Windows proof. Mac/local
  `npm run smoke:electron` passed on 2026-05-13, but it is supporting evidence
  only and does not replace the required Windows native-presentation and manual
  matrix proof.
- Unit 3 public API decision: no new preload method, IPC channel, contract
  event, or renderer-facing payload. The selected path maps foreground
  `BrowserWindow` `app-command` events to synthetic renderer keyboard input
  through `webContents.sendInputEvent`, preserving the existing renderer input
  owner and avoiding a new main-to-renderer bridge.
- RD-14 parent platform proof: still pending. Windows native-presentation and
  manual matrix proof remain required before RD-14 parent closeout.

## Goal

Complete the RD-14 parent planning surface for Desktop window, input, cursor,
display, and fullscreen UX. This plan freezes the parent scope, owner seams,
security invariants, verification policy, platform proof, rollback rules, and
candidate bounded execution units. Implementation must not begin until this
plan has a clean read-only plan review and the quality-loop controller selects
one bounded unit.

RD-14 must make the app feel like a Desktop TV app while preserving the current
Electron security model: renderer-local navigation and focus, a narrow typed
preload bridge, main-owned Electron window/display/fullscreen behavior, and no
Plex or native playback secret leakage into renderer-facing surfaces.

Bounded execution units, subject to clean plan re-review and later controller
selection:

1. Unit 1, Renderer desktop input and focus policy: complete. This unit
   normalized keyboard,
   remote-like, gamepad-derived, text-input, route/back, and fullscreen actions
   into renderer-safe input vocabulary while preserving current navigation and
   focus ownership. It added a focused renderer input owner and tests without
   touching main, preload, contracts, Plex, native/helper, package, lockfile, or
   local Windows evidence files.
2. Unit 2, Main window/fullscreen/display owner module: complete. This unit
   moved durable
   BrowserWindow, display, fullscreen, bounds, and restore policy into a focused
   main-owned owner. This unit is separate from media keys and cursor unless
   re-reviewed. In scope: `src/main/index.ts` only for small wiring, a focused
   main-owned module such as `src/main/window/**`, focused main tests or smoke
   assertions, and contract/preload files only if a reviewed packet names the
   exact narrow public vocabulary. Out of scope: media keys, gamepad, cursor,
   Plex, player/native-helper production playback, broad preload growth, raw
   Electron objects in renderer-facing state, packaging, and dependencies.
   Verification must include `npm run typecheck`, `npm run verify:architecture`,
   relevant focused tests or `npm run smoke:electron` if Electron behavior
   changes, and `npm run verify` before unit closeout unless review approves
   narrower proof. Replan if a new public window state event/channel is needed
   and not named in the selected packet, if display identifiers must leave main,
   or if `src/main/index.ts` would become the durable policy owner.
3. Unit 3, Foreground app-command/media-key bridge: complete. This unit
   handles foreground app-window app-command behavior without defaulting to
   `globalShortcut`. In scope: focused main window/app-command owner code,
   `src/main/index.ts` registration wiring, focused tests/smoke assertions, and
   a reviewed narrow renderer-safe contract/preload addition only if required.
   Out of scope: system-wide capture by default, player/Plex/native-helper
   behavior, persistent shortcuts, global OS hooks, broad input rewrites, and
   overriding keys claimed by the OS or another app. Verification must include
   `npm run typecheck`, `npm run verify:architecture`, focused tests or
   Electron smoke for foreground app-command behavior, Windows manual matrix
   rows for observed/unavailable/claimed keys, and `npm run verify` before unit
   closeout unless review approves narrower proof. Replan before any
   `globalShortcut` use, before adding a new preload/channel not named in the
   unit packet, or if foreground events cannot provide acceptable MVP behavior.
4. Unit 4, Renderer cursor and fake-backed route/overlay integration:
   complete. This unit implemented renderer-owned DOM cursor hide/show
   presentation and integrated approved input state over fake-backed routes and
   overlays. In scope: focused renderer
   modules, `src/renderer/index.ts` wiring, `src/renderer/focusDom.ts` only for
   small focus integration, route/overlay tests, and CSS limited to cursor/state
   presentation. Out of scope: main/native-helper cursor control, production
   native surface ownership, player/Plex behavior, broad visual restyling, and
   OS hooks. Verification must include `npm run typecheck`, focused renderer
   tests for cursor timers/focus cleanup/route integration,
   `npm run verify:architecture`, and `npm run verify` before unit closeout
   unless review approves narrower proof. Replan if cursor behavior needs
   main/native-helper control or route-level UI redesign.
5. Unit 5, Electron smoke and Windows manual/native-presentation proof matrix
   closeout: collect and redact Windows OS/manual proof plus native-presentation
   evidence before RD-14 parent closeout. In scope: `tools/smoke-electron.mjs`,
   `src/main/smokeAssertions.ts`, focused smoke tests/assertions, local ignored
   evidence under `docs/runs/rd-14-window-input-fullscreen-ux/`, and durable
   closeout updates to roadmap/current-state docs only after observed proof.
   Out of scope: production native-helper playback, live Plex, committing raw
   logs, changing app behavior to satisfy smoke only, packaging/signing/updater,
   and source imports. Verification must include `npm run verify:docs`,
   `npm run smoke:electron` when smoke assertions change,
   `npm run verify:redaction` for redacted evidence/docs, the required Windows
   native-presentation preflight and smoke commands, the
   `windows-manual-matrix.redacted.md` artifact, and `npm run verify` before
   RD-14 parent closeout. Replan or block if prerequisites are unavailable,
   redaction fails, native-presentation status is not `passed`, or Windows proof
   contradicts planned OS behavior.

The parent plan identifies Unit 1 as the exact first execution packet if the
controller selects it, but controller selection still happens only after clean
plan re-review. No worker may start any unit until the controller explicitly
selects that unit.

## Unit 1 Closeout Record

Completed unit: Unit 1, Renderer desktop input and focus policy.

Files in scope:

- `src/renderer/navigation.ts` if the change stays small and cohesive.
- A new focused renderer input module under `src/renderer/**` if needed to keep
  durable input policy out of the renderer composition root.
- `src/renderer/index.ts` only for registration/dispatch wiring.
- `src/renderer/focusDom.ts` only if the focus API needs small integration.
- Renderer tests under `src/__tests__/renderer/**`.

Files out of scope:

- `src/main/**`, `src/preload/**`, `src/contracts/**`, `src/main/player/**`,
  `src/main/plex/**`, `src/domain/**`, production native-helper playback, Plex
  runtime or transport, broad CSS/theme changes, packaging, signing, updater,
  dependencies, lockfiles, and local Windows evidence logs.

Unit 1 constraints and invariants:

- Renderer remains unprivileged and uses browser-safe input concepts only.
- Text-input policy must bypass TV navigation shortcuts for `input`,
  `textarea`, `select`, `contenteditable`, and ARIA text-entry roles.
- Gamepad mapping, if implemented in Unit 1, uses browser Gamepad API concepts
  normalized to the existing renderer-safe input vocabulary. It must include
  connect/disconnect, polling lifetime, repeat/debounce, and focus cleanup
  policy.
- No preload/main gamepad API, no persistent device identifiers, no raw gamepad
  object exposure, and no privileged OS hooks.
- Existing RD-13 route and focus behavior must remain intact.

Unit 1 verification:

- `npm run typecheck`
  - Expected outcome: TypeScript succeeds with no renderer or test type errors.
- `node --import tsx --test --test-name-pattern "renderer route|focus registry|desktop key mapping|desktop input|text input|gamepad|fullscreen dispatch" "src/__tests__/renderer/**/*.test.ts"`
  - Expected outcome: only matching renderer tests run: currently renderer
    route/focus/key-mapping tests, plus future Unit 1 desktop-input,
    text-input, gamepad, and fullscreen-dispatch tests by name.
- `npm run verify:architecture`
  - Expected outcome: renderer/preload/main/domain boundaries and file-shape
    guardrails pass.
- `npm run verify`
  - Expected outcome: full repository verification passes before Unit 1
    closeout unless implementation review explicitly approves a narrower proof.

Mac/local proof is sufficient for Unit 1 only if it remains pure renderer,
fake-backed, and OS-independent. Stop and replan if Unit 1 needs a main,
preload, contract, player, Plex, native-helper, OS hook, filesystem, dependency,
or broad CSS/theme change; if browser/Electron gamepad behavior cannot support
the planned renderer-safe policy; or if text-entry/focus behavior requires a
route-level redesign.

Observed Unit 1 closeout:

- Changed files: `src/renderer/desktopInput.ts`, `src/renderer/index.ts`,
  `src/renderer/navigation.ts`, and
  `src/__tests__/renderer/desktopInput.test.ts`.
- Verification observed by the controller: `npm run typecheck` passed; the
  focused renderer input command passed with 14 tests; `npm run
  verify:architecture` passed; `npm run verify` passed.
- Implementation review: clean, with no material blockers. Residual risk:
  future shell changes that disable or block `navigator.getGamepads()` may need
  a reviewed follow-up, but that does not block this pure renderer unit.

## Unit 2 Closeout Record

Completed unit: Unit 2, Main window/fullscreen/display owner module.

Observed Unit 2 closeout:

- Changed files: `src/main/index.ts`,
  `src/main/window/shellWindowController.ts`, and
  `src/__tests__/main/shellWindowController.test.ts`.
- Behavior: BrowserWindow creation/options, fullscreen intent execution, normal
  bounds capture, display id custody, and restore/fallback placement policy now
  live in a focused main-owned controller. `src/main/index.ts` remains
  composition/IPC wiring and the existing `window.setFullscreen(boolean)`
  response shape remains `{ enabled }`.
- Review fixes: fullscreen restore now waits for the stable
  `leave-full-screen` event instead of relying on immediate
  `BrowserWindow.isFullScreen()` after `setFullScreen(false)`, and restore
  bounds are fitted against the current work area even when the saved display id
  still exists.
- Verification observed by the controller: `node --import tsx --test
  src/__tests__/main/shellWindowController.test.ts` passed with 8 tests; `npm
  run typecheck` passed; `npm run verify:architecture` passed; `npm run verify`
  passed.
- Implementation re-review: clean, with no material blockers. Residual risk:
  platform transition ordering, native titlebar fullscreen controls, DPI, and
  real multi-monitor work-area changes still require the planned RD-14
  Windows/manual proof before parent closeout.

## Unit 3 Execution Packet

Selected unit: Unit 3, Foreground app-command/media-key bridge.

Files in scope:

- `src/main/window/**` for focused foreground app-command policy.
- `src/main/index.ts` only for registration wiring on the existing shell
  window.
- Focused main tests under `src/__tests__/main/**`.
- `src/renderer/desktopInput.ts` and renderer tests only if the existing
  renderer input vocabulary needs closed, browser-safe media-key names.

Files out of scope:

- `src/preload/**`, `src/contracts/**`, new IPC channels, new preload methods,
  system-wide `globalShortcut`, production player/Plex/native-helper behavior,
  persistent shortcuts, OS hooks beyond foreground `BrowserWindow`
  `app-command`, broad renderer input rewrites, and raw OS command exposure to
  renderer.

Unit 3 decision and constraints:

- Official Electron docs checked on 2026-05-13 identify `BrowserWindow`
  `app-command` as the foreground Windows/Linux event for app commands and
  media keys. The event normalizes command names to lowercase, hyphenated
  strings with the `APPCOMMAND_` prefix removed. Linux explicitly supports
  `browser-backward` and `browser-forward`.
- `globalShortcut` remains prohibited for this unit because it is system-wide,
  can trigger when Lineup is not foregrounded, may fail when the OS or another
  app owns a shortcut, and carries platform authorization/Wayland caveats.
- `webContents.sendInputEvent` is the selected forwarding mechanism because it
  sends keyboard input to the focused page without adding a public bridge. The
  containing `BrowserWindow` must be focused; the main owner must map only known
  app-command strings to valid Electron accelerator key codes and must ignore
  unknown commands.
- Browser navigation commands map to existing renderer-safe input:
  `browser-backward` maps to the existing back behavior, and
  `browser-forward` is observed but intentionally ignored for the current app
  workflow.
- Media commands may map only to renderer-safe closed input vocabulary. If
  playback-facing behavior needs production player dispatch, Plex state, or a
  new public event/channel, stop and replan before implementation.

Unit 3 verification:

- `node --import tsx --test src/__tests__/main/shellAppCommandController.test.ts`
  for foreground command mapping and ignored-command policy.
- Focused renderer input tests if renderer media-key vocabulary changes.
- `npm run typecheck`.
- `npm run verify:architecture`.
- `npm run verify`.

Windows/manual proof for observed or unavailable media keys remains pending for
Unit 5 and is required before RD-14 parent closeout.

## Unit 3 Closeout Record

Completed unit: Unit 3, Foreground app-command/media-key bridge.

Observed Unit 3 closeout:

- Changed files: `src/main/index.ts`,
  `src/main/window/shellAppCommandController.ts`, and
  `src/__tests__/main/shellAppCommandController.test.ts`.
- Behavior: foreground `BrowserWindow` `app-command` handling now lives in a
  focused main-owned controller. `browser-backward` is prevented and forwarded
  to the existing renderer back path with synthetic `Escape` key down/up events
  through `webContents.sendInputEvent`; `browser-forward` is prevented and
  intentionally ignored for the current workflow; media app commands are not
  prevented or forwarded until the later Windows/manual proof unit decides
  observed behavior. Forwarding requires the shell window to be focused and both
  the window and webContents to be alive.
- API surface: no preload method, IPC channel, contract event, renderer-facing
  OS command payload, `globalShortcut`, Plex/player/native-helper behavior, or
  renderer input rewrite was added.
- Review fixes: the initial implementation mapped `browser-backward` to
  `BrowserBack`, which Electron does not document as a valid synthetic
  keyboard accelerator. The fix maps it to `Escape`, which the existing
  renderer input owner already maps to `back`, and stops swallowing media
  commands that RD-14 has not implemented.
- Verification observed by the controller: `node --import tsx --test
  src/__tests__/main/shellAppCommandController.test.ts` passed with 6 tests;
  `npm run typecheck` passed; `npm run verify:architecture` passed; `npm run
  verify` passed with 308 source tests and 101 harness/doc tests.
- Implementation re-review: clean, with no material blockers. Residual risk:
  real Windows/Linux app-command delivery, unavailable/claimed media keys, and
  observed media-key behavior still require the planned Unit 5 Windows/manual
  matrix proof before RD-14 parent closeout. The returned registration teardown
  is unused, which is acceptable for the current single-window app lifetime but
  should be revisited if window recreation without process quit is introduced.

## Unit 4 Closeout Record

Completed unit: Unit 4, Renderer cursor and fake-backed route/overlay
integration.

Observed Unit 4 closeout:

- Changed files: `src/renderer/desktopCursor.ts`, `src/renderer/index.ts`,
  `src/renderer/styles/base.css`, and
  `src/__tests__/renderer/desktopCursor.test.ts`.
- Behavior: renderer-owned DOM cursor presentation now starts visible, hides
  after an inactivity timer, hides immediately on mapped desktop keyboard or
  gamepad input, shows again on pointer or mouse movement, and restores visible
  state during cleanup. The state is stored on `document.documentElement` via a
  renderer-safe `data-desktop-cursor` attribute and a focused CSS rule.
- API surface: no main, preload, contract, Plex/player/native-helper,
  production native surface, native cursor control, package, dependency, or
  lockfile behavior was added.
- Verification observed by the controller: `node --import tsx --test
  src/__tests__/renderer/desktopCursor.test.ts` passed with 5 tests;
  `node --import tsx --test "src/__tests__/renderer/**/*.test.ts"` passed with
  43 tests; `npm run typecheck` passed; `npm run verify:architecture` passed;
  `npm run verify` passed with 313 source tests and 101 harness/doc tests.
- Implementation review: clean, with no material blockers. Residual risk:
  cursor hiding is tied to mapped desktop input, not arbitrary keyboard input,
  which matches the current desktop input owner and text-entry bypass policy.
  Windows/native cursor behavior over a real native video surface remains part
  of Unit 5 proof before RD-14 parent closeout.

## Unit 5 Proof Status

Selected unit: Unit 5, Electron smoke and Windows manual/native-presentation
proof matrix closeout.

Current status: blocked on required Windows platform proof.

Observed local proof:

- Local platform observed by the controller: `darwin`.
- `npm run smoke:electron` passed on 2026-05-13 after Units 1 through 4.
- `npm run verify` passed on 2026-05-13 after Units 1 through 4.

Required proof still missing:

- Run the RD-06 native-presentation preflight command on Windows:
  `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-14-window-input-fullscreen-ux/native-presentation-preflight`
- Run the RD-06 native-presentation smoke command on Windows:
  `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --fullscreen-mode native-presentation-host --duration-ms 5000 --dummy-input local-and-http --out docs/runs/rd-14-window-input-fullscreen-ux/native-presentation-smoke`
- Create the redacted Windows manual matrix at
  `docs/runs/rd-14-window-input-fullscreen-ux/windows-manual-matrix.redacted.md`.
- Run the required redaction/docs/full verification after promoting only
  durable conclusions into tracked docs.

RD-14 parent closeout remains blocked until the Windows native-presentation
proof passes and the manual matrix records the required windowed/fullscreen,
display/DPI, focus-over-video, cursor, media-key, gamepad, native surface,
helper cleanup, and forbidden-field observations.

## Non-Goals

- Do not implement source changes in the planning session.
- Do not add preload or renderer Plex APIs.
- Do not expose raw Plex payloads, credentials, auth headers, tokenized URLs,
  runtime filesystem paths, Electron objects, Node objects, native/helper
  internals, private playback descriptors, or production native-helper playback
  setup to renderer or preload.
- Do not wire live Plex transport, real Electron app-path or safeStorage runtime
  behavior, backup/restore, packaging, signing, updater behavior, or release
  channel behavior.
- Do not import or adapt upstream Lineup UI source, upstream webOS lifecycle
  assumptions, webOS player assumptions, or webOS packaging assumptions.
- Do not create broad preload RPC, arbitrary channel strings, compatibility
  barrels, old upstream path shims, temporary adapters, or fallback API variants.
- Do not move Plex, scheduler, player, native-helper, persistence, or packaging
  policy into renderer UI or focus/input code.
- Do not harden production native video playback in RD-14; RD-14 can require
  platform proof over the existing fake-backed or evidence-backed native surface,
  but production native-helper playback remains future scope.

## Parent Architecture Alignment

RD-14 follows the current architecture truth in
`docs/architecture/CURRENT_STATE.md`:

- Renderer remains unprivileged and owns renderer-local route, focus, fake UI
  workflow, and input mapping state.
- Preload remains narrow, typed, validated, and single-file-compatible. Any new
  preload method or channel is prohibited unless a reviewed unit names the exact
  contract, owner, guard/parity tests, IPC safety proof, and verification.
- Main owns Electron `BrowserWindow`, display, OS fullscreen/window behavior,
  shell IPC authorization, and shell/window event custody.
- Contracts own renderer-safe public vocabulary only. They must not contain
  Electron objects, Node objects, runtime paths, native handles, token-bearing
  data, raw Plex payloads, or private playback descriptors.
- Plex secrets, live Plex transport, and private playback setup stay out of
  renderer and preload. RD-14 must not open a Plex-facing bridge.
- Native/helper internals stay private. RD-14 may verify focus and fullscreen
  behavior over the current native-surface evidence path, but it must not turn
  on production native-helper playback.

Platform proof is mandatory for this roadmap item. Windows proof is required
before RD-14 closeout for real OS window/display/fullscreen behavior, focus over
native video, media-key and gamepad behavior, multi-monitor and DPI behavior,
cursor behavior, and native video surface behavior. Mac/local proof may close
only fake-backed pure contract/domain/renderer input-mapping units that are
independent of OS-specific behavior; those units still cannot close the RD-14
parent item without the Windows matrix.

RD-14 Windows evidence lives only in the ignored local bundle
`docs/runs/rd-14-window-input-fullscreen-ux/`. Durable conclusions get promoted
into roadmap/current-state docs at closeout; raw logs are not committed.

Native-video proof uses the existing dev-only RD-06 native-presentation harness,
not production native-helper playback and not live Plex. Required commands on
Windows:

- `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-preflight --out docs/runs/rd-14-window-input-fullscreen-ux/native-presentation-preflight`
- `node tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs --mode native-presentation-smoke --fullscreen-mode native-presentation-host --duration-ms 5000 --dummy-input local-and-http --out docs/runs/rd-14-window-input-fullscreen-ux/native-presentation-smoke`

Passing native-video evidence requires redacted `manifest.redacted.json`,
`events.redacted.ndjson`, and `summary.redacted.md`; `status` must be `passed`.
The evidence must show local/dummy HTTP visual media, a video surface, overlay,
fullscreen, fullscreen composition, the native-presentation host, input/focus
behavior, helper crash/cleanup behavior, no forbidden header, and redacted
evidence scan success. If prerequisites are unavailable, the native-video proof
status is `blocked` and the RD-14 parent cannot close.

RD-14 OS policy decisions:

- Window/display/fullscreen: main owns `BrowserWindow`, display, fullscreen,
  bounds, and restore policy. Durable policy belongs in a focused main-owned
  module, for example under `src/main/window/**`, with only small registration
  wiring in `src/main/index.ts`. Main may store prior bounds/display internally
  and project only renderer-safe state. Renderer never receives raw Electron
  `Display`, `Rectangle`, `BrowserWindow`, native handles, or filesystem paths.
  Display identifiers are internal unless a later reviewed contract proves a
  renderer-safe opaque id is necessary.
- Existing `window.setFullscreen(boolean)` stays the only public window method
  unless a reviewed unit explicitly adds a narrow contract plus preload
  parity/source-shape tests. Any new window state event/channel is a replan
  unless named in a current-unit packet.
- Media keys/app commands: RD-14 MVP uses foreground app-window input only.
  Prefer `BrowserWindow`/`webContents` foreground events such as Electron
  `app-command` where available and renderer `keydown`/browser-safe input for
  keyboard. Do not use Electron `globalShortcut` for system-wide capture in
  RD-14 unless a reviewed replan names registration failure behavior,
  unregister lifecycle, user impact, verification, and fallback. If the OS or
  another app claims a media key, record it as unavailable/claimed in the
  Windows manual matrix rather than overriding system ownership.
- Gamepad: renderer owns browser-safe gamepad mapping via browser Gamepad API
  concepts, normalized to existing renderer-safe input vocabulary. No
  preload/main gamepad API, no persistent device identifiers, no raw gamepad
  object exposure, and no privileged OS hooks. Renderer policy must include
  connect/disconnect, polling lifetime, repeat/debounce, and focus cleanup. If
  a browser/Electron limitation prevents this, stop and replan rather than
  adding native hooks.
- Cursor: renderer owns DOM cursor hide/show presentation through
  renderer-safe state, CSS, and timers for current fake-backed UI.
  Main/native-helper cursor control is out of scope until production native
  surface ownership exists. Windows native-presentation proof may observe cursor
  behavior over the dev evidence path but must not add product native-helper
  behavior.
- Text input: renderer input policy must bypass TV navigation shortcuts for
  editable targets: `input`, `textarea`, `select`, `contenteditable`, and ARIA
  text-entry roles. Current fake UI may have no actual text inputs, but policy
  and tests must preserve future settings/channel setup behavior.

## Required Reading

Read in this order before plan review or implementation:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/session-prompts/feature-quality-loop.md`
4. `docs/agentic/session-prompts/feature-plan.md`
5. `docs/agentic/session-prompts/feature-review.md`
6. `docs/agentic/plan-authoring-standard.md`
7. `docs/architecture/CURRENT_STATE.md`
8. `docs/roadmap/desktop-port-roadmap.md`
9. `docs/architecture/file-shape-guardrails.md`
10. `docs/architecture/playback-architecture.md`
11. `docs/architecture/security-and-secret-flow.md`
12. `docs/architecture/import-ledger.md`
13. Current source seams named in this plan, especially `src/main/index.ts`,
    `src/contracts/shell.ts`, `src/contracts/ipc.ts`,
    `src/preload/index.cts`, `src/renderer/navigation.ts`,
    `src/renderer/index.ts`, `src/renderer/focusDom.ts`, and
    `src/__tests__/renderer/navigation.test.ts`.
14. Official Electron docs for the exact OS APIs a reviewed unit uses. The
    planning sweep checked these docs on May 13, 2026:
    - `https://www.electronjs.org/docs/latest/api/browser-window`
    - `https://www.electronjs.org/docs/latest/api/screen`
    - `https://www.electronjs.org/docs/latest/api/global-shortcut/`
    Electron docs are used only for API policy. Refresh this evidence if the
    installed Electron version or official docs change before implementation.

Freshness gate: if any required source file, architecture doc, Electron API
behavior, preload contract, IPC channel, player/native surface fact, or
file-shape guardrail row changed materially after this plan was written, stop
and update or re-review the plan before editing.

## Required Skills

- `lineup-desktop-feature-plan`: parent plan authoring for serious
  feature/design work.
- `lineup-desktop-feature-quality-loop`: Tier 3 controller route for the whole
  RD-14 roadmap item.
- `execution-plan-authoring`: durable scope, ownership, verification, rollback,
  acceptance criteria, and replan triggers.
- `architecture-boundaries`: Electron main/preload/renderer ownership,
  contracts, IPC, and forbidden boundary shortcuts.
- `ui-composition-patterns`: renderer focus, keyboard/remote/gamepad input,
  overlay interaction, and media-surface UX constraints.
- `verification-strategy`: exact automated, smoke, manual, and platform proof
  selection.
- `plex-integration-boundaries`: negative scope guard for Plex secrets, live
  transport, token-bearing playback setup, raw payloads, and renderer/preload
  Plex APIs.
- `review-request`: required read-only plan and implementation reviews for Tier
  3 gates.
- `closeout-verification`: final changed-file, command-output, manual-proof,
  docs, import-ledger, and unresolved-risk check before calling any unit or the
  parent item complete.

## Evidence And Discovery

- `semantic_search_with_context`: attempted for BrowserWindow/fullscreen,
  preload window API, renderer keydown, focus, and navigation ownership.
  Codanna reported semantic search failure because embeddings count is `0`.
- `semantic_search_docs`: attempted for RD-14 window/input/fullscreen roadmap
  and architecture context. Codanna reported semantic search failure because
  embeddings count is `0`.
- Codanna index status: symbol index exists with 3774 symbols across 137 files;
  semantic search is enabled but has `Embeddings: 0`.
- Impact analysis: not used for this parent plan because semantic anchors were
  unavailable and no source implementation unit is selected yet. Use Codanna
  symbol search or direct source reads during each reviewed unit if symbol
  ownership changes.
- Direct reads and `rg`: used for the required docs, roadmap RD-14 section,
  file-shape guardrails, playback architecture, security/secret flow, import
  ledger, current source seams, renderer navigation tests, preload parity test
  evidence, package scripts, git status, and file line counts.
- Official docs: Electron BrowserWindow, screen, and globalShortcut docs were
  checked on May 13, 2026 because RD-14 touches OS
  window/fullscreen/display and media-key behavior. These docs are used only for
  API policy and must be refreshed if the installed Electron version or official
  docs change.

Current source evidence observed:

- `src/main/index.ts` creates the `BrowserWindow`, owns shell IPC
  authorization, registers `lineup:window:intent`, validates
  `WindowFullscreenIntentEnvelope`, and calls
  `BrowserWindow.setFullScreen(enabled)`.
- `src/contracts/shell.ts` defines `LineupDesktopPreloadApi.window.setFullscreen`,
  `WindowFullscreenState`, and the closed fullscreen intent guard.
- `src/contracts/ipc.ts` includes `window.enterFullscreen` and
  `window.exitFullscreen` renderer intents plus the `lineup:window:intent`
  channel.
- `src/preload/index.cts` exposes a single `window.setFullscreen` method,
  validates boolean input, creates the closed window intent envelope, and invokes
  `lineup:window:intent`.
- `src/renderer/navigation.ts` owns `APP_ROUTES`, `FocusRegistry`, and
  `mapDesktopKeyEvent`.
- `src/renderer/index.ts` owns the renderer-local `keydown` listener,
  fullscreen toggle state, route/focus action dispatch, and cleanup of the
  keydown/status listeners on unload.
- `src/renderer/focusDom.ts` owns DOM focus registration, focus rendering, and
  click dispatch for the active focus target.
- `src/__tests__/renderer/navigation.test.ts` covers route/focus behavior and
  current desktop key mapping.
- `src/__tests__/contracts/contracts.test.ts` covers closed shell status and
  fullscreen intent validation.
- `src/__tests__/integration/preloadContractVocabulary.test.ts` verifies the
  single preload bridge shape and approved `ipcRenderer` method/channel pairs.

Import ledger evidence:

- RD-14 is not authorized to copy or adapt upstream Lineup source. No import
  ledger row is required unless a reviewed replan changes that decision before
  or with an import.

## Impact Snapshot

Potential owners that may change after review:

- Renderer input/focus: `src/renderer/navigation.ts`,
  `src/renderer/focusDom.ts`, `src/renderer/index.ts`, and narrowly scoped new
  renderer modules if needed to avoid growing composition roots.
- Main shell/window/display: `src/main/index.ts` only for small registration
  wiring, or narrowly scoped new main-owned shell/window modules if window,
  display, foreground app-command, or fullscreen policy would otherwise grow the
  composition root.
- Contracts: `src/contracts/shell.ts` and `src/contracts/ipc.ts` only if a
  reviewed unit proves a renderer-safe contract vocabulary change is necessary.
- Preload: `src/preload/index.cts` only if a reviewed unit approves a narrow
  typed bridge change with runtime validation and parity/source-shape tests.
- Tests and smoke: contract tests, renderer input/focus tests, preload parity
  tests, main shell/window tests, Electron smoke assertions, and manual Windows
  proof records may change as required by the reviewed unit.
- Docs: this plan and, at closeout, current-state, roadmap, architecture health,
  playback, or import-ledger docs only when observed ownership or provenance
  actually changes.

Expected behavior changes:

- Desktop input should support keyboard, remote-like, media-key, and gamepad
  behavior at the right owner boundary.
- Fullscreen/window/display behavior should be main-owned and observable through
  renderer-safe state only.
- Cursor behavior should be deterministic and manually proved over video and UI
  surfaces.
- Text input must not be hijacked by TV-style navigation shortcuts.
- Existing RD-13 navigation/focus behavior must remain intact.

Expected non-impact:

- No dependency, package, lockfile, packaging, signing, updater, live Plex
  transport, safeStorage runtime, app-path runtime, production native-helper
  playback, or upstream source-import changes are authorized by this parent
  plan.

## Architecture Health

RD-14 must not regrow the hotspots ARCH-01 stabilized before this item. Use
`docs/architecture/file-shape-guardrails.md` as the source of truth for current
oversized production files and triggers.

Current allowlisted production hotspots:

- `src/main/player/desktopPlayerAdapter.ts` at baseline 1275 lines: leave out
  of RD-14 unless a reviewed replan proves player-adapter behavior is required.
- `src/domain/channel/channelManager.ts` at baseline 1017 lines: out of scope.
- `src/main/player/plexPlaybackRuntime.ts` at baseline 798 lines: out of scope;
  production native-helper playback remains future scope.
- `src/domain/channel/channelRepository.ts` at baseline 766 lines: out of scope.
- `src/contracts/player.ts` at baseline 695 lines: out of scope unless a later
  reviewed player-facing media-key unit proves a public player contract change
  is necessary.
- `src/main/plex/streamResolver.ts` at baseline 662 lines: out of scope.
- `src/main/player/streamPolicy/desktopStreamPolicy.ts` at baseline 625 lines:
  out of scope.
- `src/preload/index.cts` at baseline 575 lines: avoid growth. Replan before
  adding bridge methods, channels, arbitrary RPC, extra contextBridge exposure,
  preload bundling, or bridge vocabulary not covered by parity/shape tests.
- `src/domain/channel/channelAuthoringService.ts` at baseline 521 lines: out of
  scope.
- `src/main/player/nativePlayerHostProcess.ts` at baseline 501 lines: out of
  scope.

Affected owner hotspots and decisions:

- Main composition: `src/main/index.ts` currently owns BrowserWindow creation
  and the minimal fullscreen intent handler. It is below the file-shape
  threshold, but RD-14 must split durable window/display/fullscreen policy, and
  any later reviewed foreground app-command policy, into a focused main-owned
  module before growth becomes broad. Small registration wiring may remain in
  `src/main/index.ts`.
- Renderer composition: `src/renderer/index.ts` currently owns keydown listener
  dispatch and fullscreen state. It is below the threshold after ARCH-01, but
  new durable input policy should live in focused renderer owners rather than
  expanding the route composition root.
- Renderer navigation/focus: `src/renderer/navigation.ts` and
  `src/renderer/focusDom.ts` are cohesive and below threshold. They may grow
  only with focused input/focus vocabulary or should be split if gamepad/text
  input policy makes the owner ambiguous.
- Preload bridge: avoid unless the selected unit needs a reviewed public
  shell/window contract. If touched, parity/source-shape tests are mandatory and
  the bridge must remain single-file-compatible.

Maintainability verification route:

- Run `npm run verify:maintainability` after any production file-shape or
  guardrail change.
- Run `npm run verify:architecture` after source topology or ownership changes.
- Run `npm run verify` before implementation closeout unless the reviewed unit
  is explicitly pure/fake-backed and names a narrower proof.

Do not raise file-shape baselines to pre-authorize RD-14 growth. Any temporary
allowlist update requires plan review, owner rationale, expected line count,
verification, and a decomposition/revisit trigger.

## Files In Scope

Parent planning artifact:

- `docs/plans/rd-14-window-input-fullscreen-ux.md`

Potential implementation files after clean plan review and unit selection:

- `src/main/index.ts`
- New narrowly owned main shell/window/display modules under `src/main/**` if
  they prevent composition-root growth.
- `src/contracts/shell.ts`
- `src/contracts/ipc.ts`
- `src/preload/index.cts`
- `src/renderer/navigation.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/index.ts`
- New narrowly owned renderer input/focus modules under `src/renderer/**` if
  they preserve current owner boundaries.
- `src/__tests__/contracts/**/*.test.ts`
- `src/__tests__/renderer/**/*.test.ts`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- New focused main, integration, or Electron smoke tests under existing test
  owner rules if the selected unit changes main/window behavior.
- `tools/smoke-electron.mjs` and `src/main/smokeAssertions.ts` only when the
  reviewed unit needs Electron smoke proof for route/window behavior.
- `docs/architecture/CURRENT_STATE.md`, `docs/roadmap/desktop-port-roadmap.md`,
  `docs/architecture/file-shape-guardrails.md`,
  `docs/architecture/playback-architecture.md`, and
  `docs/architecture/import-ledger.md` only when closeout evidence changes
  durable architecture, roadmap status, file-shape decisions, playback proof, or
  import provenance.

## Files Out Of Scope

- Any preload or renderer Plex API file or new Plex renderer/preload bridge.
- `src/main/plex/**` live transport composition, auth/discovery/library runtime
  wiring, selected-server live transport, and stream URL setup.
- `src/main/persistence/**` app-path or safeStorage runtime wiring, credential
  backup/restore, and channel persistence runtime composition.
- `src/main/player/plexPlaybackRuntime.ts`,
  `src/main/player/plexPlaybackBridge.ts`,
  `src/main/player/plexPlaybackComposition.ts`,
  `src/main/plex/streamResolver.ts`, and production native-helper playback
  setup.
- `src/main/player/nativePlayerHostProcess.ts` and native/helper internals
  unless a reviewed platform-proof unit is explicitly limited to smoke/evidence
  observation without production behavior changes.
- `src/domain/**` scheduler/channel/content owners.
- Packaging, signing, installer, updater, release, CI release-artifact, or
  dependency/lockfile files.
- Upstream Lineup source paths, copied UI modules, compatibility barrels,
  old-path shims, and webOS lifecycle/player/packaging assumptions.
- Local ignored run evidence under `docs/runs/**`, except as an untracked manual
  proof location named by the controller. Do not commit raw run logs.

## Planner Self-Check

1. Is any product, architecture, ownership, dependency, or verification decision
   still unresolved? The parent seams and proof policy are frozen. Unit 1 has an
   execution-ready packet, but the first implementation unit remains unselected
   until clean plan re-review and controller selection.
2. Does the plan depend on adjacent files needing contract or type changes that
   are not in scope? No. Contract/preload changes are in scope only behind a
   reviewed narrow contract decision; otherwise renderer-local and main-local
   units must work without new public bridge vocabulary.
3. Did the plan freeze any file out of scope while still relying on hidden wiring
   inside it? No. Plex, persistence, player runtime, native-helper, domain, and
   packaging files are out of scope and cannot be hidden dependencies for RD-14
   behavior.
4. Did the plan record the evidence path and fallback reads? Yes. Codanna
   semantic fallback, direct reads, `rg`, source evidence, package scripts, and
   official Electron docs are recorded.
5. Is the work assigned to the repo-preferred owner, or is it growing a hotspot?
   Preferred owners are named. Hotspot growth is avoided; any required growth
   needs decomposition or reviewed allowlist change.
6. Did Tier 3 work include Architecture Health evidence and a decomposition,
   avoidance, or allowlist decision for affected owner hotspots? Yes.
7. Would a fresh implementer need to invent security, IPC, playback,
   persistence, packaging, import, or verification policy? No. Those policies
   are explicit here; ordinary local implementation choices remain with the
   implementer.
8. Did the plan record exact verification commands, expected outcomes, and stop
   or replan triggers? Yes.

## Architecture Seam Decision Gate

Chosen parent seam:

- Renderer owns renderer-safe input mapping, route/focus state, DOM focus, and
  UI dispatch. Renderer also owns browser-safe gamepad mapping and DOM cursor
  presentation for the current fake-backed UI.
- Main owns Electron `BrowserWindow`, display, fullscreen, bounds, restore
  policy, foreground app-command/media-key observation when a reviewed unit
  needs it, shell IPC authorization, and OS-specific proof. Durable
  window/display/fullscreen policy belongs in a focused main-owned module with
  only small registration wiring in `src/main/index.ts`.
- Preload owns only narrow validated method calls and event listeners that are
  explicitly part of `LineupDesktopPreloadApi`.
- Contracts own renderer-safe vocabulary and guards only.

Forbidden shortcuts:

- No broad `window.lineupDesktop` RPC or arbitrary channel forwarding.
- No raw `ipcRenderer`, Electron, Node, filesystem, native handle, token,
  auth-header, tokenized URL, private playback descriptor, raw Plex payload, or
  runtime path in renderer-facing state.
- No compatibility shims, old upstream path mirrors, or duplicated fallback
  input APIs.
- No direct renderer control of BrowserWindow, Electron `screen`,
  globalShortcut, app paths, safeStorage, Plex transport, or native-helper
  internals.
- No Electron `globalShortcut` capture for RD-14 media keys unless a reviewed
  replan names registration failure behavior, unregister lifecycle, user
  impact, verification, and fallback.
- No preload/main gamepad API, persistent device identifiers, raw gamepad object
  exposure, native OS gamepad hooks, or product native-helper cursor behavior.
- No production native-helper playback enablement under the cover of fullscreen
  or focus verification.

Stop and replan if:

- A unit needs a new preload method, new IPC channel, or new renderer-facing
  contract that was not named and reviewed.
- A unit needs a new window state event/channel not named in its current-unit
  packet.
- Text input, accessibility, or focus behavior requires a route-level redesign
  rather than a focused input/focus policy change.
- Media-key or gamepad support cannot be represented safely without moving OS
  or player policy across owner boundaries.
- Browser/Electron gamepad limitations require native hooks or raw device
  identifiers.
- Windows proof contradicts Mac/local assumptions for fullscreen, display, DPI,
  native video surface, focus, cursor, media-key, or gamepad behavior.
- Native-presentation proof prerequisites are unavailable, fail, lack required
  redacted artifacts, or cannot satisfy redaction scan success.
- Any selected unit would grow an allowlisted hotspot or composition root
  without a reviewed split or allowlist decision.
- Implementation discovers a need for live Plex transport, app-path/safeStorage
  runtime wiring, packaging/signing/update behavior, upstream UI imports, or
  production native-helper playback.

## Verification Commands

Verification classification: broader integration/manual proof required.

Planning-session verification:

- `npm run verify:docs`
  - Expected outcome: active plan shape passes, all required headings are
    present, plan classification is valid, roadmap/workflow/doc references stay
    consistent, and no docs verifier errors are reported.

Per-unit automated verification, selected according to the reviewed unit:

- `npm run typecheck`
  - Expected outcome: TypeScript succeeds with no source, contract, preload, or
    test type errors.
- `npm run verify:architecture`
  - Expected outcome: ESLint architecture rules and maintainability guardrails
    pass; renderer/preload/main/domain boundaries remain intact.
- `npm run verify:maintainability`
  - Expected outcome: no production file exceeds file-shape thresholds or
    allowlist baselines without a reviewed guardrail update.
- `npm run test:contracts`
  - Expected outcome: contract, renderer, main, preload integration, and
    architecture-owned tests pass; added tests cover stable public seams rather
    than brittle helper internals.
- `npm run verify:redaction`
  - Expected outcome: docs, tests, fixtures, diagnostics, and contracts contain
    no raw Plex tokens, tokenized URLs, auth headers, filesystem paths, native
    handles, secret diagnostics, or raw Plex payloads.
- `npm run smoke:electron`
  - Expected outcome: Electron build and smoke run pass; the app boots through
    `lineup://shell/index.html`, renderer privilege denial remains intact,
    approved preload bridge works, containment assertions pass, and any
    reviewed smoke additions prove primary route/window behavior without
    weakening sandbox/context isolation.
- `npm run verify`
  - Expected outcome: full repository verification passes before any source,
    contract, IPC/security, runtime, or implementation unit is called complete,
    unless a reviewed pure fake-backed unit names a narrower observed proof.

Focused automated proof expected where feasible:

- Renderer input mapping tests cover keyboard, remote-like keys, text-input
  bypass rules, gamepad-derived action normalization if added, focus movement,
  route/back behavior, and fullscreen dispatch invariants.
- Contract tests cover shell/window vocabulary, closed intent guards, and
  renderer-safe payloads if any contract changes.
- Preload parity/source-shape tests cover any new approved channel, method,
  runtime guard, and `ipcRenderer` usage if preload changes.
- Main/window tests or smoke assertions cover BrowserWindow fullscreen/display
  state vocabulary, authorization, foreground app-command/media-key event
  handling, and renderer-safe result projection if main behavior changes.

Manual and platform proof:

- Windows proof required before RD-14 parent closeout:
  - Store raw and redacted local evidence only under ignored
    `docs/runs/rd-14-window-input-fullscreen-ux/`.
  - Run the RD-06 native-presentation preflight and smoke commands listed in
    `## Parent Architecture Alignment` on Windows.
  - Passing native-video proof requires redacted
    `manifest.redacted.json`, `events.redacted.ndjson`, and
    `summary.redacted.md`; `status: passed`; local/dummy HTTP visual media;
    video surface; overlay; fullscreen; fullscreen composition;
    native-presentation host; input/focus; helper crash/cleanup; no forbidden
    header; and redacted evidence scan success.
  - If native-presentation prerequisites are unavailable, mark the local proof
    `blocked`; RD-14 parent closeout remains blocked rather than substituting
    Mac/local proof.
  - Create the local redacted manual artifact
    `docs/runs/rd-14-window-input-fullscreen-ux/windows-manual-matrix.redacted.md`.
    Expected row fields are: surface, steps, observed result, pass/blocked,
    redaction notes, and linked local evidence directory.
  - Manual matrix rows must cover windowed/fullscreen/restore; display
    selection primary/secondary; multi-monitor movement and restore; DPI at
    non-100% scale when available; focus over native video and renderer
    overlays; native video surface windowed/fullscreen; cursor hide/show over
    video and controls; media-key observed/unavailable/claimed-key behavior;
    gamepad connect/disconnect/repeat/debounce; text input in
    settings/channel setup; and app quit/back from all primary routes.
- Mac/local proof may close only reviewed pure units that are fake-backed and
  independent of OS-specific behavior. It cannot close the RD-14 parent item.

## Acceptance Criteria

- Plan review is clean before any implementation unit is selected.
- The quality-loop controller selects exactly one bounded implementation unit at
  a time after plan review.
- Renderer remains unprivileged and keeps input/focus behavior renderer-safe.
- Main owns Electron window/display/fullscreen and any reviewed foreground
  app-command/media-key observation, returning only renderer-safe state through
  reviewed contracts.
- Preload remains narrow, typed, validated, and single-file-compatible.
- No prohibited Plex, persistence, native-helper, packaging, Electron, Node,
  filesystem, secret, or upstream webOS assumption crosses into renderer-facing
  state.
- Existing RD-13 route/focus behavior remains intact.
- Automated tests cover stable input mapping, focus/navigation invariants,
  shell/window contract vocabulary, IPC safety, and renderer-safe payloads where
  those seams change.
- Electron smoke covers primary route/window behavior added by reviewed units.
- Manual Windows matrix records the required OS/window/display/fullscreen,
  focus-over-video, cursor, media-key, gamepad, DPI, multi-monitor, text input,
  quit/back, and native video surface outcomes in
  `docs/runs/rd-14-window-input-fullscreen-ux/windows-manual-matrix.redacted.md`
  before parent closeout.
- Native-video proof uses the RD-06 native-presentation harness on Windows and
  produces redacted `manifest.redacted.json`, `events.redacted.ndjson`, and
  `summary.redacted.md` with `status: passed`; blocked prerequisites block the
  RD-14 parent rather than being bypassed.
- `npm run verify` passes before implementation closeout unless the reviewed
  unit is a pure fake-backed unit with a narrower observed proof, and the parent
  RD-14 item cannot close without the Windows platform matrix.
- Architecture docs, roadmap, file-shape guardrails, and import ledger are
  updated only for observed durable changes.

## Replan Triggers

- Plan review finds a material blocker or unresolved seam.
- Implementation needs a new preload API, IPC channel, public contract, or
  renderer-facing state not explicitly approved by this plan and the selected
  unit.
- A selected unit needs a new window state event/channel that is not named in
  the current-unit packet.
- Media-key support requires Electron `globalShortcut`, system-wide capture, or
  overriding OS/other-app key ownership without a reviewed replan.
- Gamepad support requires preload/main APIs, persistent device identifiers,
  raw gamepad objects, or native OS hooks.
- Cursor behavior requires main/native-helper control before production native
  surface ownership exists.
- OS proof shows different behavior on Windows than assumed locally for
  fullscreen, display, cursor, media keys, gamepad, DPI, multi-monitor, focus,
  or native video surface behavior.
- Native-presentation proof cannot produce redacted `manifest.redacted.json`,
  `events.redacted.ndjson`, and `summary.redacted.md` with `status: passed`, no
  forbidden header, and redacted evidence scan success.
- A unit would grow `src/preload/index.cts` or another allowlisted hotspot
  beyond its reviewed baseline.
- A unit would turn `src/main/index.ts` or `src/renderer/index.ts` back into a
  broad composition hotspot instead of adding a focused owner.
- Text input or accessibility behavior cannot be protected with focused tests
  and requires a broader UI interaction model.
- The work appears to require live Plex transport, app-path or safeStorage
  runtime wiring, production native-helper playback, packaging/signing/update
  behavior, upstream UI imports, or webOS lifecycle/player/packaging behavior.
- `npm run verify`, required focused commands, Electron smoke, redaction checks,
  or Windows manual proof fail for reasons inside RD-14 scope.
- External Electron docs or installed Electron behavior contradict the planned
  API usage.

## Rollback Notes

- Parent plan rollback: remove or supersede
  `docs/plans/rd-14-window-input-fullscreen-ux.md` through a reviewed planning
  change if RD-14 scope is replaced before implementation begins.
- Per-unit rollback: each reviewed unit should be revertible as one focused
  commit. Revert the unit commit and restore any associated docs or guardrail
  rows changed by that unit.
- Contract/preload rollback: remove the public contract vocabulary, channel,
  preload guard, and tests together. Do not leave unused preload methods or
  channel constants behind.
- Main/window rollback: remove new registration, event, display, cursor, or
  fullscreen ownership together with tests and smoke assertions. Preserve the
  existing `window.setFullscreen` behavior unless the reviewed unit explicitly
  replaces it.
- Renderer input rollback: revert input/focus modules and tests together while
  preserving RD-13 route/focus behavior.
- Manual proof rollback: failed or contradicted Windows evidence blocks
  closeout; do not paper over it with Mac/local proof.

## Commit Checkpoints

- Plan artifact checkpoint: docs-only plan change, verified with
  `npm run verify:docs`.
- Plan review checkpoint: read-only review must report no material blockers
  before implementation selection.
- Implementation checkpoints: prefer one conventional commit per reviewed
  bounded unit, for example `feat: add desktop input focus policy` or
  `feat: add main-owned window display shell`, with no unrelated local changes
  staged.
- Verification checkpoint: each implementation commit records observed commands
  and any manual proof required by that unit.
- Parent closeout checkpoint: after all reviewed units, clean implementation
  review, `npm run verify`, Windows platform matrix, and durable doc updates,
  update the roadmap/current architecture as appropriate and archive the
  completed full plan body locally per workflow policy.

Planning artifact report:

- Changed files: `docs/plans/rd-14-window-input-fullscreen-ux.md`.
- Unresolved risks: plan review has not run, no implementation unit has been
  selected, Windows platform proof is still pending, and any future preload/API
  or hotspot growth must re-enter review before implementation.
