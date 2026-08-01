# Current Architecture State

> **Parity audit correction (2026-07-22):** Packages 0–8 remain valid historical
> local renderer-regression evidence: 138 screenshots, 8 reduced-motion rows,
> 12 forced-colors rows, and 3 local fullscreen-continuity rows. They do not
> establish current-upstream feature or UI completion. The one-by-one audit in
> `docs/product/lineup-product-parity-matrix.md` reopens parity work, including
> deferred Channel Builder proof plus Settings, Guide, input/lifecycle, and
> production playback capability gaps. WS2's platform-neutral implementation
> gate is closed. WS3's final product source is Unit 3C-F checkpoint
> `87662b5`; prior Unit 3C-D `5f368d4`, viewport repair `77d09ad`, test-only
> harness checkpoint `f0e2817`, and focus-plan amendment `c59124a` remain
> accepted history.
> Windows/native/live/manual/current-upstream proof remains open.
> Unit 3D is accepted and WS3's local gate is closed. WS4's local input and
> overlay implementation gate closes through final product checkpoint
> `3258511`; Windows/native/physical-device/paired/package proof remains
> `WS4-PROOF-01` through `WS4-PROOF-04`. WS5 targeted scope-load/planning is
> next, and its product work requires a decision-complete plan plus fresh first-
> unit approval.
> RD-27 Windows observation, `WS2-POST-VALIDATION-01` native proof, and other
> environment-specific evidence remain required but are accumulated for the
> final consolidated Windows campaign; none can close missing code.
> Established 2026-05-07. This is the canonical current-state architecture
> document for Lineup Desktop.

## Scope

Lineup Desktop is a new Windows-first Electron repository. It currently has a
secure Electron shell frame, the RD-13 renderer app shell/navigation, workflow,
settings/channel setup, RD-23/RD-24 runtime-backed channel setup, guide, and
channel surfaces implemented for the current code state, Package 6 runtime-backed
player/overlay behavior and corrected focus/accessibility ownership, Package 7
upstream-adapted overlay presentation, the former RD-22A fixture/injected app body,
docs, workflow, contract, harness scaffolding, main-owned Plex
auth/discovery/library domain seams, RD-22B live Plex onboarding/library runtime
wiring, and RD-25/RD-26 playback foundations. Their historical slices remain
complete only at their recorded scope; WS2 now closes the current
platform-neutral playback implementation gate, but the 2026-07-22 master audit found missing upstream
behavior and conservative production capability gates. The local visual-proof
run is closed; feature/UI parity is reopened. The active nine-workstream
parity-correction plan has landed and reviewed WS1 Channel Builder
implementation, while WS1 remains open for deferred proof and performance debt.
WS2 Packages 2A and 2B are published and cleanly reviewed, Package 2D is a
reviewed conservative no-op, and `358e8de` adds post-closeout recovery and
teardown lifecycle hardening. This does not close WS1. WS3 Units 3A, 3A-R, 3B,
and 3C are committed at `81bc0b7`, `e8445e5`, `11dd704`, and `1540de3`;
their planned product scope is present without promoting the conservative
production profile. A controller-observed narrow-viewport Settings rail defect
returned Unit 3C to implementation-revise; reviewed repair `77d09ad` closes the
local visibility/focus gate after clean focused/full verification and repeated
Unit 3C-D adds production fixed-schema Settings/subtitle diagnostic producers
and honest missing-output fallback presentation without changing public
contracts, persistence, capability state, or stable-row classification.
Unit 3C-F then repaired category-Right focus derivation inside two files and is
accepted at final product checkpoint `87662b5` after focused 17/17, aggregate
265/265, and clean implementation review. Unit 3D's final verification,
authority review, and docs gates passed; WS3's local gate is closed. WS4 Units
4A–4D and its isolated smoke correction land at `f4570df`, `a78228b`,
`a654cdd`, `c4dadcf`, and `3258511`. Its local production-build proof passed
36/36 with controller visual inspection, and final full verification passed
1,110 tests with one intentional skip plus 177/177 harness/docs. This closes
the local implementation gate only; `WS4-PROOF-01`–`WS4-PROOF-04` remain open.
WS5 targeted scope-load/planning is next; WS5 product edits require its own
decision-complete plan and fresh first-unit approval, while WS6–WS9 remain
unopened.
The accepted 227-row audit remains the program baseline, so WS3 entry validates
only its assigned rows and affected current owners rather than repeating the
program-wide audit.
There is no installer
implementation, public release/signing pipeline, production native-helper media
binary redistribution, or Windows-observed production playback closeout proof
yet. Historical paragraphs below preserve the sequence of earlier RD slices;
later RD notes supersede earlier "unsupported", "not wired", or "in progress"
statements where they describe completed code but not completed Windows product
proof.
RD-04 adds documentation and harness ownership for upstream behavior guardrails
only; it does not import product runtime code. RD-05 produced disposable,
dev-only external `mpv` POC observations and ignored redacted local evidence
only; its superseded source/test harness has since been removed and it does not
create production playback architecture. RD-06 adds dev-only Windows
native libmpv WID, render API, and app-owned native presentation spike modes
with ignored redacted local evidence only. The spike must use dummy visual
media, active-playback overlay/focus/fullscreen checks, and libmpv client API
evidence. The Windows WID and helper-owned render API proofs are blocked on
fullscreen video-surface evidence; render API also failed composition and
render-thread-discipline proof. The revised Windows app-owned native
presentation probe records fresh redacted proof under the stricter fullscreen,
cleanup, and render-thread semantics. Clean implementation re-review reported no
material blockers, so RD-06 can route RD-07 toward the app-owned native
presentation boundary. RD-07 adds the first main-owned Desktop player adapter
boundary core with a fakeable native host port and public-seam tests, runtime
main/preload player IPC delivery through a development/smoke fake host, and a
native-host process seam with lifecycle/reap, safe failure normalization, and
redaction tests. Windows closeout proof now covers the process seam with a real
spawned helper test double and reruns the RD-06 app-owned native-presentation
smoke as the native surface proof inherited by RD-07. Production player
commands still return renderer-safe unsupported failures until a later product
native-helper plan enables real Plex-backed playback. RD-07 does not wire
renderer UI, Plex stream setup, or a production native helper. RD-08 adds the
first deterministic Desktop stream policy fixture core under
`src/main/player/streamPolicy/*`. The policy is capability-driven and
fixture-only, with tests for direct play, direct stream, transcode, unsupported
decisions, audio/subtitle fallback, HDR/Dolby Vision, stable reasons, explicit
unknowns, and forbidden-field invariants. Windows closeout adds a conservative
RD-06/RD-07 capability/sample matrix and keeps container, codec, audio,
subtitle, direct stream, transcode, track switching, HDR, Dolby Vision, and
Plex HTPC parity as unknown or unsupported where the Windows proof does not
establish them. RD-08 does not contact Plex, add secure storage, wire renderer
UI, launch native playback, change package/dependencies, or import/adapt
upstream source. RD-09 adds the first main-owned secure storage and persistence
boundary core under `src/main/persistence/*`, plus renderer-safe persistence
summary contracts in `src/contracts/persistence.ts`. The boundary uses an
injected Electron `safeStorage` codec seam, app-data path resolver,
file-backed encrypted Plex credential records, selected-server state,
unavailable/corrupt classification, fail-closed behavior with no plaintext
fallback, and tests for renderer-safe snapshots and forbidden fields. RD-09
does not wire Plex auth/discovery/library runtime, preload or renderer APIs,
network transport, scheduler/channel persistence, backup/restore
implementation, package/dependency changes, or copied/adapted upstream source.
RD-10 adds main-owned Plex library, auth, discovery, selected-server, and
renderer-safe Plex contract seams under `src/main/plex/*` and
`src/contracts/plex.ts`. The imported/adapted upstream behavior is kept behind
injected transports and RD-09 storage adapters: library parsing is metadata and
summary only, auth uses injected transport plus fail-closed credential storage,
and discovery restores by persisted server id plus fresh probing while keeping
connection details in main-owned memory only. RD-10 does not wire live Plex
network transport, preload/renderer Plex APIs, `src/main/index.ts`
composition, real Electron safeStorage/app paths, package/dependency changes,
stream resolver/runtime playback URL setup, scheduler/channel persistence, or
backup/restore implementation.
RD-11 adds pure scheduler and channel/content domains plus a main-owned channel
persistence adapter; these owners remain runtime-free, use injected
clocks/timers/library/persistence ports, and keep Electron, Node, browser
globals, live Plex transport, raw Plex payloads, auth headers, tokenized URLs,
and native playback details out of domain state. RD-12 adds the first
main-owned Plex-to-player runtime path through
`src/main/player/plexPlaybackRuntime.ts`, `src/main/plex/streamResolver.ts`,
`src/main/player/plexPlaybackBridge.ts`, and
`src/main/player/plexPlaybackComposition.ts`. The runtime resolves current
scheduled/channel media through injected main-owned seams, applies the RD-08
policy, dispatches renderer-safe load payloads through the RD-07 player adapter
boundary, and owns PMS cleanup for stop, switch, error, logout, server change,
profile change, helper crash, teardown, failed resolver/player paths, stale
events, and rejected leases. RD-12 keeps private Plex playback descriptors and
PMS lease custody out of renderer-facing contracts and does not add
preload/renderer Plex APIs, live transport composition, real Electron
safeStorage/app-path wiring, production native-helper playback, packaging, or
additional copied/adapted upstream product code. RD-13 Unit 1 adds a
renderer-owned app shell/navigation foundation under `src/renderer/**`: primary
route rail, player/guide/settings/channel-setup screen containers,
renderer-local route and focus state, Desktop key mapping, accessible primary
navigation, and Node-safe navigation tests. It also resolves the existing
sandboxed-preload smoke blocker by keeping preload guard vocabulary
single-file-compatible with Electron sandboxed preload runtime while preserving
the existing shell/window/player preload API shape and smoke containment checks.
RD-13 Unit 2 adds a renderer-local fake-backed route/workflow skeleton for the
player, guide, settings, and channel-setup routes. It uses renderer-safe fake
view models, local route action transitions, and Node-safe workflow tests; it
does not import domain code, add preload/main contracts, contact Plex, persist
settings, or wire runtime playback. RD-13 Unit 3 adds renderer-local
settings/channel setup details with fake settings sections, channel setup draft
state, local-only settings/setup actions, validation copy, and Node-safe tests.
It does not persist settings, use browser storage, contact Plex, add selected
server runtime, or import domain code. RD-13 Unit 4 adds a renderer-local
fake-backed EPG surface with deterministic UTC fake schedule formatting,
schedule slots, program span calculation, guide detail/grid rendering, guide
route smoke reachability assertions, and Node-safe EPG tests. It does not import
domain code, contact Plex, add renderer/preload APIs, load remote/tokenized
assets, or wire scheduler/runtime playback. RD-13 Unit 5 adds renderer-local
fake-backed player overlays: OSD controls, now-playing, mini guide, channel
number entry, channel badge, playback options, overlay stack state, focus
fallback behavior, smoke reachability assertions, and Node-safe overlay tests.
It uses renderer-safe player snapshot vocabulary only and does not wire runtime
playback, expose native/helper internals, contact Plex, or add preload APIs.
RD-13 Unit 6 adds renderer-local CSS-only assets/styles completion through CSS
custom-property tokens, theme hooks, focus-visible styling, reduced-motion and
forced-colors policies, responsive constraints, loaded-style smoke assertions,
and no protocol, static asset, dependency, or lockfile expansion. Units 1
through 6 used upstream Lineup UI/navigation/assets only as reference; no
copied/adapted upstream source landed, so no RD-13 import-ledger row was needed.
RD-13 is complete at the renderer UI and navigation import level.
ARCH-01 adds the architecture-health stabilization pass before RD-14. The pass
remediates the renderer composition, renderer static asset, main composition,
and renderer overlay hotspots through behavior-preserving same-owner splits;
keeps preload single-file-compatible while hardening the preload bridge
source-shape/parity harness for channel constants, the single `lineupDesktop`
exposure, and approved `ipcRenderer` method/channel use; and leaves the
remaining large player, Plex, channel, contract, policy, and native-helper
owners under the cohesion policy in `docs/architecture/file-shape-guardrails.md`.
ARCH-01 does not add RD-14 product behavior, native
video/fullscreen behavior, live Plex transport, production native-helper
playback, packaging/signing/update behavior, app-path or `safeStorage` runtime
wiring, new preload/renderer APIs, dependencies, or copied/adapted upstream
source.
RD-14 is complete. Unit 1 added the first focused renderer desktop input owner
under `src/renderer/desktopInput.ts`, keeping the renderer unprivileged and
fake-backed while preserving RD-13 route/focus behavior. The unit moves keyboard
shortcut mapping, text-entry bypass for editable targets, browser-safe gamepad
normalization/polling/repeat policy, fullscreen dispatch, and runtime input
cleanup out of the renderer composition root. Unit 2 added a focused main-owned
window controller under `src/main/window/shellWindowController.ts` for
BrowserWindow creation/options, fullscreen intent execution, normal bounds
capture, display id custody, and restore/fallback placement policy. It keeps
`src/main/index.ts` as composition/IPC wiring, preserves the existing
`window.setFullscreen(boolean)` response shape, waits for stable fullscreen
leave before restore, and fits restore bounds against current display work
areas. Unit 3 added a focused main-owned foreground app-command controller under
`src/main/window/shellAppCommandController.ts`. The controller listens only to
the shell `BrowserWindow` `app-command` event, uses no `globalShortcut`, maps
`browser-backward` to the existing renderer back path through synthetic
`Escape` input, intentionally ignores `browser-forward`, and leaves media app
commands unhandled by product code. Unit 4 added renderer-owned DOM cursor
presentation under `src/renderer/desktopCursor.ts`. The cursor state remains
renderer-local, starts visible, hides after inactivity or mapped desktop
keyboard/gamepad input, shows on pointer/mouse activity, and restores visible
state on unload cleanup through scoped CSS. Unit 5 closed the Windows platform
gate using the dev-only RD-06 native-presentation harness and local ignored
redacted evidence under `docs/runs/rd-14-window-input-fullscreen-ux/`.
Preflight and smoke passed on Windows with dummy local and HTTP media, active
video pixels, renderer overlay/native-boundary composition, fullscreen
composition, app-owned input/focus simulation, helper crash detection, cleanup,
no forbidden header, and redacted evidence scan success. The Windows matrix
records a two-display 100% DPI environment, media-key/gamepad availability
notes, and the lack of current text-entry controls in the fake settings/channel
setup UI while preserving Unit 1 automated text-input bypass proof. RD-14 added
no preload method, IPC channel, contract event, renderer-facing OS command
payload, main/native cursor control, production native-helper playback, Plex
runtime behavior, dependency, package, lockfile, or upstream source import.
RD-15 is complete. Units 1 and 2 hardened the renderer-owned fake-backed UI so
player overlays, OSD, mini guide, channel badge, guide/EPG, settings, and
channel setup compose predictably over the player presentation surface with
stable route reachability, z-order, fullscreen bridge continuity, deterministic
focus fallback, and Desktop-accurate local settings copy. Unit 3 extended and
ran the dev-only RD-06 native-presentation harness for RD-15 proof: Windows
preflight passed, Windows native-presentation smoke passed under
`docs/runs/rd-15-ui-over-native-video-integration/`, the manifest status is
`passed`, and the summary records `RD-15 native presentation UI: 16/16
observed` across windowed and fullscreen native-video composition, EPG, OSD,
mini guide, channel badge, settings, channel setup, overlays, renderer focus,
helper cleanup, and redaction gates. `npm run test:harness-docs`, `npm run
verify:redaction`, and `npm run verify` passed after the Unit 3 harness
revision, and implementation review found no blockers. RD-15 remains a
renderer/dev-harness integration closeout only: it adds no production
native-helper playback, live Plex transport, preload or contract expansion,
product IPC, packaging behavior, dependency or lockfile change, live renderer
Plex API, or upstream source import.
RD-16 is complete. Units 1 and 2 hardened the main/player stream-policy and
main/Plex resolver seams for subtitle, audio, HDR, and track identity behavior:
forced/default subtitles, subtitle-off, requested missing/incompatible audio
and subtitles, burn-in/conversion decisions, audio fallback, language metadata
preservation without language-preference selection, HDR10, Dolby Vision,
unknown dynamic range, explicit unsupported/unknown reasons, and public/private
track id separation are covered by deterministic tests. Unit 4 extended and ran
the dev-only RD-06 native-presentation harness for RD-16 proof: Windows
preflight passed, Windows native-presentation smoke passed under
`docs/runs/rd-16-subtitle-audio-hdr-hardening/`, and the summary records
`RD-16 media matrix: observed (multi-audio:observed,
subtitle-bearing:observed, hdr:observed, hdr-unavailable:observed)` while
keeping `tracks: not-proven-by-dummy-visual-media`. `npm run
test:harness-docs`, `npm run verify:redaction`, and `npm run verify` passed
during closeout. RD-16 remains policy/resolver/dev-harness hardening only: it
adds no production native-helper playback, live Plex transport, preload or
contract expansion, product IPC, packaging behavior, dependency or lockfile
change, live renderer Plex API, preferred-language selection, adapter
current-request membership validation, or upstream source import.
RD-17 is complete. It adds renderer-safe diagnostics contracts, RD-17 redaction
vocabulary, a main-owned diagnostic event store, support-bundle path/export
owners, diagnostics IPC/preload methods, a renderer settings export action, and
player/native-host/runtime diagnostic hooks for helper crash/restart and cleanup
reporting. Windows proof passed under ignored local evidence at
`docs/runs/rd-17-diagnostics-crash-recovery-support-bundle/windows-smoke`: the
summary records platform `win32`, status `passed`, helper crash detected, main
process alive, safe failed request state, helper cleanup/reap, replacement
helper use, a main-created bundle target under the injected parent,
renderer-visible output limited to bundle identity, completed-bundle scan status
`passed`, and no forbidden material. RD-17 adds no telemetry/cloud upload,
production native-helper playback, live Plex transport, packaging/signing or
release behavior, dependency or lockfile change, persisted credential/settings
schema change, or upstream source import.
RD-18 Unit 1 is complete for internal Windows x64 package tooling and proof.
The packaging/provenance owner is `tools/package-windows-internal.mjs`,
validated by `tools/verify-windows-internal-package.mjs` and
`tools/__tests__/package-windows-internal.test.mjs`. Windows closeout observed
`win32 x64`, `npm run build:electron`, internal package generation under
`out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/`, and package
verification passing with a clean tracked worktree. The generated artifact
contains `LineupDesktop.exe`, unpacked `resources/app` with main/preload/renderer
dist payload, provenance, deterministic checksums, internal notices, and blocked
native-helper/media-binary markers. RD-18 Unit 1 adds no package script,
dependency, lockfile, signing config, update metadata, native media
redistribution, Plex behavior, renderer/preload/IPC contract, runtime behavior,
or public release artifact.
RD-19 is complete for internal alpha/beta validation. The validation artifact is
`docs/development/rd-19-internal-validation-checklist.md`. Units A and B added
the redacted checklist and checklist-shape verifier, Unit C reran Windows x64
internal package proof, and Unit D executed the full RD-19 validation matrix on
Windows x64 using current fake-backed UI, injected/domain, package,
diagnostics, Electron smoke, and dev-only harness proof surfaces. Unit D
recorded only redacted summaries and blocker rows: auth, server selection,
channel creation, playback, switching, subtitles/audio, EPG, settings,
fullscreen, multi-monitor, crash recovery, diagnostics export, and
install/delete of the unpacked package have current passed proof for their
limited fake/injected/package/diagnostics surfaces; sleep/wake and real long
playback remain blocked and classified. RD-19 does not add live Plex transport,
renderer Plex APIs, production native playback, persistence IPC, signing/update
behavior, installer behavior, public release readiness, source/tool/package
script/dependency/lockfile changes, or tracked generated artifacts.
RD-20 is complete as docs/source-audit/provenance work only. The tracked
artifacts are
`docs/architecture/original-lineup-reference-compatibility-matrix.md` and
`docs/architecture/original-lineup-divergence-register.md`. The copied/adapted
M01-M07/D01-D07 import and ledger coverage audit reviewed clean, the
M08-M11/D08-D11 reference-only/proof-context audit reviewed clean. The later
Package 7 M13/D12 overlay presentation adaptation and Info divergence are now
linked to their exact import-ledger and renderer evidence, and import-ledger
coverage remains current. RD-20
adds no new copied/adapted upstream source, production source, tests,
verifiers, live Plex transport, renderer Plex APIs, persistence IPC, production
native playback, package/dependency/lockfile/signing/update/native-media, or
public-release behavior. Platform proof remains `Mac/local automated proof
sufficient` because the completed scope stayed docs/source-audit/provenance
only.
Historical RD-21 is complete as its 2026-06 product-parity and roadmap work
only; its status vocabulary and then-current missing-runtime inventory below
are superseded by later implementation slices and the 2026-07-22 master audit.
The tracked
artifacts are `docs/product/lineup-product-parity-matrix.md`,
`docs/development/windows-ui-proof-plan.md`, and the revised MVP sequence in
`docs/roadmap/desktop-port-roadmap.md`. The parity matrix classifies every
reviewed original Lineup workflow as fake-backed UI only, domain-only,
harness/dev-only proof, docs/provenance proof, blocked, or intentionally
divergent; no workflow is marked complete because the current app still lacks
live Plex runtime UI wiring, runtime channel persistence, scheduler-backed
guide data from persisted channels, production native playback, runtime media
options, Windows MVP soak proof, and package lifecycle proof at MVP depth.
Future Platform Review is deferred behind the RD-22 through RD-28 MVP
completion sequence. RD-21 adds no product runtime, source, tests, verifiers,
live Plex transport, renderer Plex APIs, persistence IPC, production native
playback, package/dependency/lockfile/signing/update/native-media, upstream
source import, or public-release behavior.
RD-22A is complete and reviewed as fixture/injected renderer-safe upstream UI
body parity only. Unit 3 adapted the reachable Desktop renderer body for
upstream-shaped route switching, onboarding/profile/server setup shells,
channel setup shell, Settings, Guide/EPG, overlay/player chrome, now-playing,
mini guide, channel badge/number shell, focus targets, and product route copy
without live Plex calls, main/preload/contract/runtime/persistence/player/
package changes, channel creation, scheduler runtime, playback, media-option
runtime, production native-helper behavior, or package/release behavior.
Controller-observed closeout evidence included the exact renderer command
passing 75/75 tests, `npm run verify` passing, `npm run smoke:electron`
passing, `git diff --check` passing with only CRLF warnings, clean
implementation re-review, and sanitized local safe mock bridge proof with no
old setup hooks and no forbidden token, header, path, or raw private text. No
raw screenshots, logs, account/server/library/media names, paths, endpoints,
tokens, headers, payloads, native handles, or private proof are tracked. The
RD-22A Unit 3 import-ledger provenance row records upstream HEAD
`613b1c516c7c9e37f9c18ea3e92c474013472b11`.
RD-22B is complete and reviewed as live Plex onboarding and library runtime
wiring inside the RD-22A body. It proves live Plex auth/PIN request, polling,
cancel, encrypted credential availability and restore, Plex Home/profile
selection including protected-user PIN failure handling, server discovery,
server selection, selected-server restore after relaunch, library sections,
browse, search, metadata summary, clear/back/cancel/text-entry/scroll
behavior, and sanitized failure/empty/loading/stale coverage through the
narrow main/preload/renderer runtime seam. Closeout evidence included focused
runtime tests, `npm run typecheck`, `npm run smoke:electron`, `npm run verify`,
`npm run verify:redaction`, `npm run verify:docs`, `git diff --check`, clean
plan/implementation/proof reviews, and redaction-safe Windows live proof with
only category/count/pass-fail facts tracked. RD-22B does not implement channel
creation, channel persistence, scheduler-backed guide/player data, production
playback, media options, package/release behavior, native-helper production
behavior, or public readiness claims.

RD-23's approved historical slice is complete. Its original implementation
turned selected Plex libraries into one `libraryFallback` channel per section,
plus replace/confirm-replace and settings recovery. WS1 has since replaced that
bulk-setup limitation with the deterministic Channel Builder domain/planner,
Plex facet session/discovery/materialization, main-owned asynchronous
review/apply operation runtime, atomic lineup mutation/persistence/startup,
five-operation preload bridge, and renderer configuration, review, progress,
result, and recovery flow. Cancellation is accepted before the synchronous
commit-barrier transition and rejected with `commit-started` after commit
becomes irrevocable; no partial commit is published. WS1 implementation and
independent review landed, but WS1 remains open for deferred visual,
multi-library/filter, append/replace, manual Windows, packaged ACL, and
performance proof. Preload validation and selection hardening prevent stale
data access.
RD-24 is complete. It integrates scheduler-backed guide data and the channel runtime. Persisted channel configurations feed the schedule DayRollover and EPG calculations. Player route, overlays, now-playing, mini-guide, and channel badge are wired to real scheduler state. The app handles manual channel switches, scheduling ticks, and program transitions cleanly.
Package 6 runtime player and overlay correction is implemented and reviewed.
Production overlay ancestry, busy focus custody, direct-action eligibility, and
single-owner native presentation are corrected with focused automated coverage.
Operator-assisted fullscreen platform completion remains pending: RD-27 must
run the named three-row Windows audit afresh. The Mac stable-window physical-
click failure is an external proof-tool limitation and does not establish a
product focus or fullscreen defect.
Packages 7 and 8 are complete. The reachable Player overlays now use the
upstream-adapted Desktop-owned hierarchy and stylesheet families without
changing Package 6 behavior, focus, timers, bridge custody, or process
boundaries. Fresh integrated proof passed 68 Packages 1–3 screenshots, 14
Package 4 screenshots, 12 Package 5 screenshots, and 44 Package 7 screenshots,
plus 8 reduced-motion, 12 forced-colors, and 3 local fullscreen-continuity rows.
The two 54-row interaction/disposition matrices and Package 4 two-launch
relaunch proof also validate. This closes renderer parity and local automated
verification only; RD-27 owns all Windows operational and production-native-
video claims.
Custom Channels Core is complete as a 2026-06-12 feature package on top of
RD-23/RD-24. It adds renderer-safe custom-channel contracts, main-owned custom
channel mutation runtime, safe Plex media picker/artwork projection, named
custom-channel IPC/preload methods, a desktop authoring workspace on the
channel setup route, and best-effort guide/runtime refresh after custom-channel
save, delete, hide/unhide, and reorder with safe stale-state degradation when
the post-commit refresh hook fails. Renderer authoring state stays
unprivileged: it receives safe summaries/cards only, invalidates stale media on
Plex source changes, resets selected cart state when source custody changes,
and does not fabricate direct edit drafts from saved-channel summaries. Direct
in-place edit of persisted channels remains deferred until a reviewed
main/preload edit-draft API returns full content with `expectedRevision`.
RD-25's historical code implementation is complete and reviewed at its recorded
scope; WS2 closes the current platform-neutral implementation gate, while
Windows/manual product proof remains pending in `WS2-POST-VALIDATION-01` and
RD-27 as applicable. The production native playback MVP
replaces the fake playback bootstrap with a production-shaped, main/helper-owned
native playback path for live Plex-backed scheduled media. A main-only
privileged load context propagates the private playback descriptor to the helper
host, which runs a repo-owned C# native helper process. The helper communicates
with the main process via an NDJSON protocol over stdin/stdout. Live Plex stream
resolution, media detail, and PMS session ports are composed and wired.
Renderer player UI state binds dynamically to safe player IPC events.
RD-26's historical code implementation is complete and reviewed at its recorded
scope; WS2 does not promote its conservative capability profile, and
Windows/manual product proof remains pending in `WS2-POST-VALIDATION-01` and
RD-27 as applicable. It implements runtime media options
and playback quality over the production native playback path. The C# native
helper is extended to manage audio and subtitle track states and video
parameters via libmpv. Main process validation gates renderer selection requests
against the player snapshot. The preload contract defines a clean command/event
interface for track selection and quality updates. The renderer OSD and overlay
views render options dynamically from the snapshot, and selection/volume actions
dispatch player command intents to the backend.
ARCH-02 is complete as behavior-preserving architecture hotspot stabilization.
The repair program split native-helper process framing, player adapter request
custody, Plex playback cleanup sequencing, preload bridge guard/channel
families, Plex runtime operation ownership, renderer action registration,
player bridge subscription, guide polling freshness, and renderer Plex action
dispatch into focused owners. The renderer remains unprivileged, preload still
exposes only the reviewed `window.lineupDesktop` bridge, main keeps privileged
Plex/player/persistence custody, and no new product feature, dependency,
package, renderer privilege, compatibility shim, or behavior change was added.
The watch-list owners that remain over 500 lines are reported by
`npm run verify:maintainability` and use reviewed architecture dispositions.

## Product Invariants

- Preserve the core Lineup product concept: local Plex-backed virtual channels
  with deterministic scheduling and a TV-style DOM UI.
- Keep the desktop app local-first with no Lineup cloud backend.
- Keep the renderer unprivileged.
- Keep persistent Plex credentials outside the renderer.
- Keep playback capability-driven; webOS browser playback assumptions do not
  define desktop support.
- Keep workflow and verification rules active before product implementation.

## Current Owners

| Surface | Current owner | Status |
| --- | --- | --- |
| Workflow/control plane | `AGENTS.md` and `docs/AGENTIC_DEV_WORKFLOW.md` | Scaffolded |
| Architecture truth | `docs/architecture/CURRENT_STATE.md` | Scaffolded |
| Port roadmap | `docs/roadmap/desktop-port-roadmap.md` | Scaffolded |
| Upstream behavior guardrails | `docs/architecture/upstream-behavior-guardrails.md` | RD-04 docs/harness owner |
| Repo genesis decision | `docs/architecture/desktop-repo-genesis-adr.md` | Accepted |
| Import provenance | `docs/architecture/import-ledger.md` | Current copied/adapted upstream source ledger, including the exact Package 7 overlay presentation slice at pinned `4bdb0e1b3370e7893a582ec80226557727832d0b` and observed-current `a1a7ea7dcb1cfc8aee7cfcf88cf5a1dac718bf30` |
| Original Lineup compatibility | `docs/architecture/original-lineup-reference-compatibility-matrix.md` and `docs/architecture/original-lineup-divergence-register.md` | Current copied/adapted/reference/proof-context memory, including Package 7 overlay presentation and the reviewed Package 6 Info-precedence divergence |
| Product parity and MVP roadmap | `docs/product/lineup-product-parity-matrix.md`, `docs/development/windows-ui-proof-plan.md`, `docs/plans/2026-07-22-tier3-parity-correction-plan.md`, and `docs/roadmap/desktop-port-roadmap.md` | WS1 implementation/review landed but proof remains deferred/open. WS2's platform-neutral implementation gate is closed at published `d2f1e97`, with lifecycle hardening at `358e8de`; `WS2-POST-VALIDATION-01` remains native/Windows debt. WS3's local gate is accepted/closed at `87662b5` with its proof/contribution packet open. WS4's local implementation gate closes at `3258511` with `WS4-PROOF-01`–`WS4-PROOF-04` open. WS5 targeted scope-load/planning is next; WS5 product edits require a decision-complete plan and fresh first-unit approval. WS6–WS9 remain unopened. Environment-specific proof accumulates for the final Windows campaign before RD-27/RD-28/program closeout. |
| File-shape guardrails | `docs/architecture/file-shape-guardrails.md` and `tools/verify-maintainability.mjs` | Architecture Health owner for production file-size evidence, cohesion-based dispositions, fresh hotspot review triggers, and Tier 3 file-shape verification |
| Electron main shell | `src/main/index.ts`, `src/main/applicationStartupCleanup.ts`, `src/main/protocol.ts`, `src/main/smokeAssertions.ts`, `src/main/window/shellWindowController.ts`, and `src/main/window/shellAppCommandController.ts` | Secure shell frame with split smoke/startup owners plus main-owned BrowserWindow/fullscreen/display/restore and foreground app-command custody. WS4 maps six reviewed focused media commands into the existing renderer input path, ignores unknown/next/previous commands, and never installs `globalShortcut`; `src/main/index.ts` remains composition and IPC wiring. |
| Preload bridge | `src/preload/index.cts`, `src/preload/channels.cts`, `src/preload/settingsBridge.cts`, `src/preload/settingsBridgeGuards.cts`, `src/preload/playerRecoveryBridge.cts`, `src/preload/channelSetupBridge.cts`, `src/preload/channelBridgeGuards.cts`, and `src/preload/diagnosticsBridgeGuards.cts` | Narrow shell/window/player/diagnostics/Plex/channel/Settings bridge with runtime payload guards. WS3 exposes three Settings operations and guarded play/pause; WS4 adds only the closed `player.stopIfCurrent`/`player.seekRelativeIfCurrent` intent literals plus required safe `seekSupport`, with snapshot identity stripped before host dispatch. WS2 recovery and WS1 Channel Builder operations remain unchanged; renderer stays unprivileged and the sandbox-compatible entrypoint remains the sole `contextBridge`/`ipcRenderer` value owner. |
| Renderer shell, Settings, Channel Builder, input, and overlays | [`docs/architecture/renderer-architecture.md`](./renderer-architecture.md), `src/renderer/index.ts`, `src/renderer/settings/**`, `src/renderer/settingsSetup.ts`, `src/renderer/playerErrorRecoveryController.ts`, `src/renderer/playerInputCommandController.ts`, `src/renderer/sleepTimerController.ts`, `src/renderer/desktopInput.ts`, `src/renderer/shell/navigationLifecycle.ts`, `src/renderer/channelSetup/builderConfigState.ts`, `src/renderer/workflow.ts`, and overlay/DOM/style owners | Unprivileged runtime-backed shell with WS1 Channel Builder, WS3 Settings, scheduler-backed Guide, and safe Player/overlay projection. WS4 adds semantic input aliases, context paging, source-aware 500 ms Back hold, serialized guarded direct commands, Subtitles/Sleep/Audio OSD, and session sleep-timer lifecycle. Main remains authoritative; `index.ts` is composition wiring. Local 36/36 production-build proof passed, while paired/Windows/native/device/package evidence remains `WS4-PROOF-01`–`WS4-PROOF-04`. |
| Shell contract vocabulary | `src/contracts/shell.ts` | Renderer-safe shell/window/player bridge contract |
| Settings contract vocabulary | `src/contracts/settings.ts` and `src/contracts/settingsAudioValidation.ts` | WS3 version-2 renderer-safe values, defaults, normalization, capability projection, opaque audio-output rows, centralized strict audio-list/label validation, three-operation request/result vocabulary, migration-compatible snapshots, and fixed safe failures. Conservative capabilities remain authoritative until later reviewed native/live proof. |
| Main Settings policy and audio owner | `src/main/settings/desktopSettingsPolicy.ts`, `src/main/settings/settingsAudioOutputOwner.ts`, `src/main/settings/settingsNativeHostComposition.ts`, and `src/main/settings/settingsIpc.ts` | Main-owned Settings snapshot projection, authorized IPC, stream/resolver/diagnostic/private-helper preference consumers, opaque audio-device identity, and raw native-key custody. The injectable composition factory creates the production host once, hydrates Settings policy, and shares the same host binding with the audio owner and player IPC; development/smoke do not invoke the production factory. Renderer never receives raw device keys or promotes capability support. |
| Player contract vocabulary | `src/contracts/player.ts` | Renderer-safe player command, state, event, request id, capability profile, opaque track, error, diagnostic, IPC result, and runtime event-guard contract |
| IPC contract vocabulary | `src/contracts/ipc.ts` | Shell/window/player/diagnostics/Plex IPC literals plus renderer-safe player intent and forbidden-field vocabulary |
| Persistence contract vocabulary | `src/contracts/persistence.ts` | Renderer-safe account, credential-handle, selected-server, storage-status, diagnostic, and persistence forbidden-field vocabulary |
| Plex contract vocabulary | `src/contracts/plex.ts` | Renderer-safe Plex profile, home-user, server, health, selection, library, media, collection, playlist, tag-directory, runtime operation, snapshot, and sanitized error summaries plus recursive forbidden-field checks for raw credentials, headers, URI-like fields, raw payloads, filesystem paths, and image keys |
| Diagnostics contract vocabulary | `src/contracts/diagnostics.ts` | Renderer-safe RD-17 diagnostic schema, result/error, summary, support-bundle export, redaction-scan, renderer-event, truncation, and sanitizer vocabulary |
| Main diagnostics and support bundle | `src/main/diagnostics/*` | Main-owned RD-17 diagnostic event store, support-bundle target/path creation, export assembly, redaction scanning, IPC authorization, renderer-event validation, and safe support-bundle result/failure envelopes; renderer never receives absolute export paths or raw diagnostic material |
| Desktop player adapter boundary | `src/main/player/desktopPlayerAdapter.ts`, `src/main/player/rendererIntentMapping.ts`, `src/main/player/playerAdapterRequestCustody.ts`, `src/main/player/nativePlayerHostPort.ts`, `src/main/player/nativePlayerHostProcess.ts`, `src/main/player/playerIpc.ts`, `src/main/player/productionNativeHostFactory.ts`, `src/main/player/nativeHelperProtocol.ts`, and `src/main/player/nativeHelperPlaybackSetup.ts` | Main-owned adapter core, renderer-intent validation/mapping, request-custody helper, shared native-host process seam, NDJSON helper protocol, and player IPC owner. WS3 maps guarded Settings pause/resume to existing internal play/pause commands plus nonforwarded expected snapshot identity and rejects stale identity before custody/host submission. It also correlates private audio-output queries and applies raw selected-device/DTS setup only inside main/helper custody. RD-25 wires the production native host factory and native helper process launch; ARCH-02 keeps request id membership and native process/protocol framing outside the adapter composition owner. |
| Desktop stream policy | `src/main/player/streamPolicy/desktopStreamPolicy.ts` and `src/main/player/streamPolicy/types.ts` | Main/player-owned deterministic capability policy for direct play, direct stream, transcode, unsupported decisions, subtitle/audio fallback, burn-in/conversion, dynamic-range handling, stable reason codes, explicit unknowns, and safe outputs. `src/main/plex/streamResolver.ts` calls `decideDesktopStreamPolicy`; production capabilities remain deliberately conservative, so richer policy branches do not imply enabled Windows production support. |
| Plex stream resolver boundary | `src/main/plex/streamResolver.ts`, `src/main/plex/streamResolverComposition.ts`, `src/main/plex/playbackMediaDetailPort.ts`, and `src/main/plex/pmsPlaybackSessionPort.ts` | Main-owned resolver and live composition. RD-25 resolves Plex media details, calls the Desktop stream policy, and manages PMS session leases with request-scoped start/release ports while retaining private playback custody. |
| Channel Builder pure domain and planner | `src/domain/channelBuilder/**` | Pure deterministic WS1 configuration normalization, facet/candidate strategy construction, semantic identity, priority/cap planning, alternate/ordering variants, warnings, estimates, and safe plan projection. No Electron, Plex transport, raw payload, persistence, or renderer custody. |
| Plex Channel Builder facets | `src/main/plex/channelBuilderFacetSession.ts`, `src/main/plex/channelBuilderFacetDiscovery.ts`, `src/main/plex/channelBuilderFacetMaterialization.ts`, and `src/main/plex/desktopPlexChannelBuilderFacetSource.ts` | Main-owned WS1 facet session, discovery, safe planner input, and apply materialization for selected Plex context. Live proof across multiple eligible libraries and the complete supported filter surface remains open. |
| Main Channel Builder operation and mutation runtime | `src/main/channel/channelBuilderProductionPlanner.ts`, `src/main/channel/channelBuilderPlanningWorker.ts`, `src/main/channel/channelBuilderOperationOwner.ts`, `src/main/channel/channelBuilderRuntime.ts`, `src/main/channel/channelLineupMutationCoordinator.ts`, `src/main/channel/channelIpc.ts`, and `src/main/channel/channelComposition.ts` | Main-owned WS1 planning worker, asynchronous review/apply operation custody, safe status, cancellation, atomic commit-barrier transition, lineup mutation, persistence, and guide refresh. Live evidence covers pre-barrier merge cancellation plus post-barrier merge apply/restart only; append/replace live proof remains open. |
| Channel Builder persistence and startup | `src/main/persistence/desktopChannelPersistenceStore.ts`, `src/main/persistence/channelPersistenceBootstrapOwner.ts`, `src/main/persistence/channelPersistenceStartupOwner.ts`, and `src/main/channel/channelPublicReferenceOwner.ts` | Main-owned versioned aggregate persistence, atomic mutation/recovery, startup restoration, and renderer-safe builder status. Packaged ACL proof remains open. |
| Plex playback runtime boundary | `src/main/player/plexPlaybackRuntime.ts`, `src/main/player/playbackProgramTransitionOwner.ts`, `src/main/player/playerRecoveryIpc.ts`, `src/main/player/plexPlaybackRuntimeCleanup.ts`, `src/main/player/plexPlaybackCleanupWiring.ts`, `src/main/player/plexPlaybackBridge.ts`, `src/main/player/plexPlaybackComposition.ts`, `src/main/player/playbackRuntimeBootstrap.ts`, and `src/main/player/privilegedPlaybackDispatchContext.ts` | Main-owned runtime, bounded recovery, authoritative Retry-current/Skip-next transition owner, closed recovery IPC, cleanup sequencing owners, and scheduler/channel bridge. Exact schedule identity, retry budget, transition serialization, cleanup custody, and privileged playback state remain main-owned. |
| Product native helper | `src/native-helper/Lineup.NativePlayerHost/**` | C#/.NET native player host executable source that instantiates libmpv and speaks the NDJSON protocol over stdin/stdout. Built binaries are untracked. |
| Desktop persistence boundary | `src/main/persistence/appDataPaths.ts`, `src/main/persistence/secureStorageCodec.ts`, `src/main/persistence/desktopPersistenceStore.ts`, `src/main/persistence/desktopSettingsStore.ts`, `src/main/persistence/desktopChannelPersistenceStore.ts`, `src/main/persistence/channelPersistenceBootstrapOwner.ts`, and `src/main/persistence/channelPersistenceStartupOwner.ts` | Main-owned app-data paths, Electron safeStorage codec, encrypted Plex credentials, selected-server state, fail-closed recovery, version-2 normalized Settings compare-and-swap/migration, and versioned channel aggregate persistence/startup. WS3 Settings storage is separate and non-secret; renderer receives only values, capability projection, safe audio rows, revisions, and fixed errors. RD-22B composes credential and server restoration; WS1 composes atomic lineup/config persistence and startup recovery. Backup/restore remains unimplemented. |
| Desktop Plex runtime | `src/main/plex/desktopPlexRuntime.ts`, `src/main/plex/plexRuntimeOperationOwner.ts`, `src/main/plex/desktopPlexLibraryOperationExecutor.ts`, `src/main/plex/desktopPlexRuntimeSupport.ts`, `src/main/plex/livePlexTransport.ts`, `src/main/plex/plexComposition.ts`, and `src/main/plex/plexIpc.ts` | Main-owned RD-22B live Plex onboarding/library runtime and IPC composition for auth/PIN, credential restore status, Plex Home/profile switching, selected-server restore, server discovery/selection, library sections/items/search/metadata, stale/cancel/error normalization, and renderer-safe snapshots while retaining tokens, selected connections, transport details, raw payloads, endpoint URLs, and app paths in main custody. ARCH-02 gives stale/cancel/error operation custody and library browse/search/metadata dedicated owners under the main Plex runtime boundary. |
| Desktop Plex library domain | `src/main/plex/library/*` | Main-owned RD-10 imported/adapted Plex library parser/domain owner for library sections, media metadata, seasons, collections, playlists, tag directories, search hubs, pagination, request intent, and renderer-safe summaries; RD-22B uses these seams through main-owned live runtime composition, with image URL construction, stream resolver runtime, and playback URL setup still out of scope |
| Desktop Plex auth domain | `src/main/plex/auth/*` | Main-owned RD-10 imported/adapted Plex auth owner for PIN/profile/token validation, Plex Home users, profile switching, injected auth transport, sanitized errors, Desktop identity metadata, and RD-09 credential storage adapter; RD-22B wires live auth/PIN, Plex Home/profile switching, credential restore status, and protected-user PIN failure handling through main/preload/renderer-safe runtime composition |
| Desktop Plex discovery domain | `src/main/plex/discovery/*` | Main-owned RD-10 imported/adapted Plex discovery and selected-server owner for resource parsing, connection probe policy, health classification, stale discovery-context invalidation, RD-09 selected-server summary persistence, and in-memory selected connection custody; RD-22B wires live discovery, selected-server persistence, and relaunch restore by server id plus fresh probing without persisting or returning connection URI/server URI state |
| Domain architecture verifier | `tools/architecture-rules/*` and `tools/__tests__/build-eslint-architecture-rules.test.mjs` | RD-11 domain-boundary verifier for `src/domain/**`; blocks Electron, Node, main/preload/renderer/native-helper imports, dynamic owner imports, and browser/runtime globals including direct `globalThis` runtime access. F-004 removes the blanket `src/**/__tests__/**` production-boundary exemption and adds explicit test-owner coverage for `src/__tests__/contracts/**`, `src/__tests__/domain/**`, `src/__tests__/main/**`, `src/__tests__/preload/**`, and `src/__tests__/renderer/**`; `src/__tests__/integration/**` is denied by default except for data-declared named seams. The current integration exception is `preload-contract-vocabulary-parity` at `src/__tests__/integration/preloadContractVocabulary.test.ts`, which may compare preload source text with renderer-safe contract vocabulary while keeping production preload single-file-compatible. |
| Scheduler domain | `src/domain/scheduler/**` | Pure RD-11 imported/adapted deterministic scheduler and playback-ordering owner for anchor-time schedule calculation, loop wrapping, current/next/previous lookup, schedule windows, shuffle seeds, block playback validation, injected clock/timer ports, and event emission; not wired to Electron main/preload, renderer, Plex runtime, stream resolution, or native playback |
| Channel and content domain | `src/domain/channel/**` | Pure RD-11 imported/adapted channel authoring, import/export normalization, content resolution through injected domain-safe library ports, stale fallback, source/channel resolution caches, retry scheduling, lineup navigation, and channel persistence port owner; no raw Plex payload, tokenized URL, auth header, Electron, Node, browser storage, preload, renderer, or live network ownership |
| Channel persistence adapter | `src/main/persistence/desktopChannelPersistenceStore.ts` | Main-owned versioned aggregate adapter behind injected paths and filesystem seams, with temp-file replacement, mode hardening, recovery, and typed domain storage. Its RD-11/RD-23 origin is now composed through WS1 bootstrap/startup and mutation owners; backup/restore remains unimplemented. |
| Redaction contract vocabulary | `src/contracts/redaction.ts` | RD-17 redaction boundary and forbidden diagnostic field vocabulary shared by diagnostics contracts, scanner, and tests |
| Native libmpv spike tool | `tools/libmpv-spike/rd-06-native-libmpv-host-spike.mjs` | Dev-only disposable RD-06 Windows WID/render API evidence harness |
| Internal Windows package tooling | `tools/package-windows-internal.mjs`, `tools/verify-windows-internal-package.mjs`, and `tools/__tests__/package-windows-internal.test.mjs` | RD-18 Unit 1 owner for internal Windows x64 unpacked package staging, provenance, checksums, internal notices, blocked native-helper/media-binary markers, and verifier coverage; generated artifacts stay ignored under `out/rd-18-windows-internal/**`, and public signing/update/native media redistribution remain blocked |
| Docs verifier | `tools/verify-docs.mjs` | Active |
| Redaction verifier | `tools/verify-redaction.mjs` | Active RD-17-aware scanner for secret-shaped values, raw auth/header material, privileged diagnostic fields, raw filesystem paths, process data, native handles, and raw IPC frames |
| RD-17 diagnostics smoke | `tools/rd17-diagnostics-smoke.mjs` | Windows-only ignored-evidence proof for diagnostics crash recovery and support-bundle redaction closeout |

## WS3 Settings Implementation Gate

WS3 closes its local gate through Unit 3A `81bc0b7`, Unit 3A-R `e8445e5`,
Unit 3B `11dd704`, Unit 3C `1540de3`, reviewed viewport repair `77d09ad`,
Unit 3C-D closeout repair `5f368d4`, and Unit 3C-F focus repair `87662b5`.
Test-only checkpoint `f0e2817` aligns the smoke harness with Unit 3B's shared
production-host wiring and restores full verification; it changes no runtime
owner, product source, capability, or row classification.
Unit 3C-D makes the persisted Debug Logging and Subtitle Debug Logging controls
drive fixed-schema production events and keeps diagnostic failure
nonauthoritative. Injected local proof now distinguishes an unavailable saved
audio output, visibly uses System Default, retains the saved opaque id until
explicit completion, and presents honest summary copy. Real Windows
enumeration, disappearance/relaunch, playback application, and support-bundle
observation remain consolidated proof.
The current path has one
version-2 main-owned Settings store, a focused main policy and audio-output
owner, three authorized and validated preload operations, a seven-category
renderer Settings surface, first-run System Default audio completion, a
persistent Switch Profile action, renderer-owned request-bound Settings
pause/resume, and capability-gated disabled states. The controller's first
approximately 900×700 inspection found that Recovery Down focuses Switch
Profile while the non-scrolling rail leaves most of the button below the
visible viewport. Reviewed repair `77d09ad` makes the Settings rail scrollable
and restricts nearest-scroll behavior to Settings-owned elements. It passed
16/16 focused and 261/261 complete Unit 3C tests, the named build/static gates,
clean re-review, and repeated local inspection at 1280×720 and approximately
900×700, including full Switch Profile/focus-ring visibility and the return
edge to Recovery.

This is local implementation authority, not platform completion. MP4/H.264/AAC
Direct Play remains the only supported production media path. Audio output
selection, DTS, subtitles, HDR, Direct Stream/transcode, and artwork-backed
Settings remain unsupported or unproven where the capability projection says
so. `PB-22`–`PB-24` stay WS2-owned/open; `ST-11`–`ST-16` stay WS3-owned/open
through WS5; `ST-23` does not close WS8 `ON-08`. `WS3-PROOF-01` through
`WS3-PROOF-06`, both WS3 contribution packets, WS1 debt,
`WS1-PERF-01`, `WS2-POST-VALIDATION-01`, RD-27, and RD-28 remain open.
No upstream source was copied or adapted; `0258dbe` was reference-only and the
import ledger is unchanged.

## WS4 Input And Overlay Implementation Gate

WS4 closes its local implementation gate through Unit 4A `f4570df`, Unit 4B
`a78228b`, Unit 4C `a654cdd`, isolated smoke-harness correction `c4dadcf`, and
Unit 4D `3258511`. The renderer now owns exact semantic keyboard/remote-like/
gamepad aliases, Page context, one source-aware 500 ms Back hold, serialized
guarded direct commands, and the session-only sleep timer. Main's existing
`shellAppCommandController.ts` remains the sole foreground BrowserWindow
app-command owner. The OSD exposes Subtitles/Sleep/Audio without adding play,
seek, or stop buttons.

Guarded stop and relative-seek add only their two closed renderer intent
literals. Required safe `seekSupport` projects from the main-owned selected
capability profile through load/snapshot validation; exact `supported` alone
enables seek. Snapshot identity is compared before request custody and never
reaches the host. Sleep expiry uses the same serialized current-request pause
path, records bounded failure, never retries, and owns no persistence or power
lifecycle. Conservative production capabilities and main/preload/native/Plex
custody otherwise remain unchanged.

Final production-build local proof passed 36/36 scenarios at 1280x720,
1920x1080, and approximately 900x700 across keyboard, simulated D-pad/gamepad,
pointer/cursor, focus, reduced motion, forced colors, overlays, sleep states,
and exit; controller visual inspection passed. Final `npm run verify` passed
1,110 tests with one intentional skip and harness/docs passed 177/177, with all
required static gates clean. This is local proof only. `WS4-PROOF-01` retains
physical Windows media/app-command and production playback evidence;
`WS4-PROOF-02` retains real mixed-device navigation/focus evidence;
`WS4-PROOF-03` retains paired/current-upstream and Windows production-native-
video/Package 6 evidence; `WS4-PROOF-04` retains packaged close/teardown.
`UI-47` remains partial, `PB-22`–`PB-24` remain WS2-owned/open, and no upstream
source was copied or adapted.

## Local UI Proof Bundle Closeout

The 2026-07-10 reopen corrected the earlier 2026-06-12 visual claim. Packages
0–8 are implemented, locally proved, and reviewed at their historical owning
seams. The 2026-07-22 one-by-one audit supersedes any interpretation that this
bundle proved full current-upstream feature/UI parity. The complete plan body is
archived only in the ignored local run bundle; durable architecture, roadmap,
parity, divergence, provenance, and Windows-proof conclusions live in tracked
docs.

Main/preload continue to own Plex, persistence, playback, diagnostics, and IPC
custody. Local Package 8 evidence proves renderer semantics, exact viewports,
media-query behavior, relaunch, focus, and local fullscreen continuity; it does
not prove Windows operations, production native video, installer/release
readiness, sleep/wake, or soak behavior.

## Not Yet Implemented

- Windows manual proof pending: production native playback helper
- Windows manual proof pending: production playback host
- Production Plex-to-native-helper playback setup using the private RD-12 playback descriptor (code implemented, manual proof pending)
- Windows manual proof pending: production renderer-to-Plex/player playback
  wiring
- Windows/native/live proof pending: Settings audio enumeration/application,
  media preference effects, diagnostics/recovery, and first-run behavior
- current-upstream paired Settings viewport/state inspection and later
  Windows/native-video continuity proof pending
- preload, contract, and product IPC Windows/manual playback proof beyond the
  RD-17 local diagnostics and RD-22B Plex onboarding/library surfaces
- encrypted credential backup/restore implementation
- public signing/update pipeline
- production native-helper and media-binary redistribution inside packages

## Electron Shell Frame

The first shell frame registers the `lineup` scheme before app readiness as a
standard secure scheme and serves the renderer only from
`lineup://shell/index.html`. Electron main owns the `BrowserWindow`, local
protocol handler, containment handlers, and shell/window IPC authorization.

The renderer remains unprivileged. It receives only
`window.lineupDesktop.shell.getCapabilities()`,
`window.lineupDesktop.shell.onStatusChanged(listener)`, and
`window.lineupDesktop.window.setFullscreen(enabled)` from preload for shell
behavior. RD-07 also exposes the narrow `window.lineupDesktop.player` methods
`dispatch(envelope)`, `getSnapshot()`, `cleanup()`, and `onEvent(listener)`.
Player preload events are runtime-guarded before listener invocation.
Development and smoke modes still use the development/smoke host and fake
playback resolver for deterministic proof. In production mode, player IPC uses
the production native host factory when a Windows helper binary is available and
otherwise fails closed with renderer-safe unsupported-capability results.
RD-25/RD-26 historical slices are complete and reviewed only at their recorded
scope. WS2's platform-neutral gate, WS3's local Settings gate through
`87662b5`, and WS4's local input/overlay gate through `3258511` are closed.
Windows/native/manual proof remains `WS2-POST-VALIDATION-01`, the WS3 and WS4
consolidated packets, and RD-27 work as applicable.
Fullscreen requests map to the existing
`window.enterFullscreen` and `window.exitFullscreen` renderer intents.
RD-17 also exposes `window.lineupDesktop.diagnostics.recordRendererEvent()`,
`window.lineupDesktop.diagnostics.getSummary()`, and
`window.lineupDesktop.diagnostics.exportSupportBundle()` through preload; those
methods return renderer-safe diagnostics envelopes and never expose absolute
paths, raw helper output, process identifiers, native handles, raw Plex payloads,
credentials, auth headers, tokenized URLs, or raw IPC traces.

## Roadmap

Use [`docs/product/lineup-product-parity-matrix.md`](../product/lineup-product-parity-matrix.md)
for the current one-by-one gap order and
[`docs/roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md) for
durable historical slice context. The active reviewed Tier 3 nine-workstream
parity-correction plan owns that sequence. WS1 implementation and review
landed, but WS1 remains open for deferred proof and `WS1-PERF-01` (2,690.61 ms
against the unchanged 2,000 ms target). WS2 has since closed its platform-neutral
implementation gate without advancing WS1 stable IDs or evidence
classifications. WS3's product source is `87662b5`; `5f368d4` remains prior
Unit 3C-D, `77d09ad` the viewport repair, and `f0e2817` test-only harness
proof. Unit 3D is accepted and WS3's local gate is closed. WS4's local gate
closes through `3258511`; `WS4-PROOF-01`–`WS4-PROOF-04` remain open. WS5
targeted scope-load/planning is next; no WS5 product/test/package/config edit
begins before its decision-complete plan and fresh approval of an exact first
unit. WS6 through WS9 remain unopened. RD-27 remains later and is not
authorized to implement those gaps silently. The final consolidated Windows
campaign owns accumulated environment-specific proof, not another
implementation audit.
