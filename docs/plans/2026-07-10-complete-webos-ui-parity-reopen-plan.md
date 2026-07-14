# Complete WebOS UI Parity Reopen Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3
**Sequence gate:** This plan reopens UI parity as the active prerequisite between RD-26 and RD-27. RD-27 must not start until this plan's acceptance and review gates pass.
**Current execution unit:** Packages 1–3 upstream visual-fidelity correction is closed with fresh captures, full verification, and clean adversarial re-review. Package 4 is next and remains unstarted.
**Reference checkout:** Package 0 visual captures remain pinned to `/Users/tristan/Software/Lineup` commit `6ef20801019e1d1aae2a0158128eba9142d0d008`; the prior Package 1–3 behavior/focus evidence remains frozen; the correction compares directly with the clean scoped current upstream `HEAD` `4bdb0e1b3370e7893a582ec80226557727832d0b` observed on 2026-07-13.

## Goal

Replace the contradicted 2026-06-12 UI-parity closeout with observed, screen-by-screen WebOS-informed visual and interaction parity for the reachable Lineup Desktop MVP UI before RD-27.

The result must:

- remove the permanent route rail and top status/build chrome from the product experience;
- make player, guide, settings, and setup full-screen, state-owned surfaces instead of panels inside a static dashboard shell;
- remove product dependence on `createRendererPresentationFixtures()` and other fixture-backed player/overlay presentation;
- start the player without simultaneous default overlays and reproduce the upstream overlay precedence, open/close, timeout, focus, and restoration behavior using real renderer-safe runtime state;
- render scheduler-backed Guide content when persisted channels exist and an intentional, actionable upstream-shaped empty state when they do not;
- persist supported Settings through a main-owned versioned store and narrow validated bridge instead of describing controls as renderer-session-only;
- replace the one-page setup composition with one active stage at a time, preserving live Plex, channel authoring, custom-channel, confirmation, and recovery behavior;
- use the current WebOS checkout screen by screen as the visual, focus, input, state, and choreography reference while retaining reviewed Desktop security, native playback, accessibility, diagnostics, and platform divergences;
- complete one consolidated upstream visual-fidelity correction for the already-implemented Package 1 shell, Package 2 onboarding, and Package 3 setup surfaces before Package 4, without reopening their behavior, focus, accessibility, or runtime contracts;
- capture sanitized baseline, upstream reference, and final target evidence at exact renderer content viewports `1280x720` and `1920x1080`;
- complete a focus/interaction matrix for every reachable screen, stage, modal, overlay, and meaningful loading/empty/error state; and
- correct every tracked roadmap, parity, renderer-architecture, and current-state claim contradicted by the running app.

This is not a styling-only pass. UI parity is complete only when the visible hierarchy, runtime truth, focus graph, input behavior, overlay choreography, and persisted state agree with the target evidence.

## Non-Goals

- Do not begin RD-27 operational soak, package proof, or close RD-25/RD-26 Windows/manual playback proof in this plan.
- Do not copy upstream WebOS browser storage, direct Plex fetches, token-bearing URL construction, raw media payloads, player ownership, webOS lifecycle, or packaging behavior.
- Do not expose Electron, Node, filesystem, app paths, tokens, auth headers, Plex connection URIs, native handles, or private playback descriptors to renderer code.
- Do not add an always-visible Desktop navigation rail, diagnostic top bar, build label, or compatibility shell as a fallback in the product route. Smoke/debug-only diagnostics may exist only behind an explicit non-production mode and must be absent from target captures.
- Do not preserve fake player/channel/program data in the reachable production renderer. Deterministic fixtures remain allowed in tests and explicit smoke/dev harnesses.
- Do not invent upstream-only product behavior that Desktop does not support. Sleep timer, audio-setup, channel-edit, home, and artwork-rich states require an explicit matrix disposition of `adapt`, `Desktop divergence`, or `defer with blocker`; they may not silently disappear or be represented by fake controls.
- Do not add dependencies, alter package/lockfile state, change native-helper code, change release/signing/update policy, or add public distribution behavior.
- Do not use broad DOM snapshots or screenshot pixel equality as the sole behavior proof.
- Do not track captures, logs, account/server/library/media names, local paths, URLs, tokens, headers, native handles, or other private runtime material. Visual evidence stays in the ignored local run bundle and uses sanitized fixtures or redacted content.

## Parent Architecture Alignment

This is Tier 3 feature/design work across renderer composition, runtime-backed presentation, focus/input, main-owned settings persistence, narrow IPC/preload wiring, visual proof, and durable product memory. It runs through the feature-quality loop: plan review, one approved package at a time, verification, read-only adversarial review after every package, adjudication, and only then the next package.

Ownership is frozen as follows:

- **Renderer:** DOM/CSS composition, screen/stage/overlay state, renderer-safe view-model projection, focus graphs, keyboard/gamepad/pointer handling, accessible semantics, timers/listeners, and cleanup.
- **Contracts:** renderer-safe Settings request/result/snapshot shapes and existing renderer-safe player/guide/Plex/channel vocabulary. Contracts never carry secrets, raw URLs, app paths, Electron objects, or native handles.
- **Preload:** one narrow validated Settings namespace added to the existing `window.lineupDesktop` bridge. It is not a generic RPC channel and does not persist state.
- **Main/persistence:** a versioned Desktop settings record, app-data path resolution, strict parsing/default repair, atomic save, and settings IPC authorization. Browser storage is forbidden.
- **Existing main/player/guide/channel/Plex owners:** remain the sources of runtime player snapshot, schedule/channel state, auth/server/library state, and channel mutations. Renderer presentation must consume their safe results instead of fixture vocabulary.
- **Native/helper:** unchanged. UI layers above the current player presentation surface and does not gain native process custody.
- **Local proof bundle:** `docs/runs/complete-webos-ui-parity-reopen/` is ignored evidence, not tracked product authority.

The persisted settings schema is decided for this plan: version `1`, containing only `launchMode`, `guideDensity`, `previewBadgesEnabled`, and `setupReminderEnabled`. Unsupported or diagnostic runtime state is not persisted. Load failure or malformed data produces safe defaults plus renderer-safe status; writes are atomic and fail closed without browser-storage fallback. No legacy migration is needed because the current controls are session-only. Adding another setting family requires replan.

The upstream reference is presentation and interaction authority, not process architecture authority. Exact file/class sharing is not required. Any visible divergence needs a matrix row with owner, reason, verification, and revisit trigger.

## Required Reading

Read in this order before implementation or review:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/agentic/plan-authoring-standard.md`
4. this plan
5. `docs/architecture/CURRENT_STATE.md`
6. `docs/architecture/renderer-architecture.md`
7. `docs/architecture/file-shape-guardrails.md`
8. `docs/architecture/security-and-secret-flow.md`
9. `docs/architecture/import-ledger.md`
10. `docs/roadmap/desktop-port-roadmap.md`
11. `docs/product/lineup-product-parity-matrix.md`
12. `docs/development/windows-ui-proof-plan.md`
13. `ui_parity_audit_results.md`
14. `docs/runs/archive/plans/2026-06-12-ui-parity-implementation-plan.md` as contradicted historical evidence only
15. current Desktop source under `src/renderer/**`, plus package-specific contract/main/preload/tests
16. current reference checkout UI under `/Users/tristan/Software/Lineup/src/modules/ui/**`, `/Users/tristan/Software/Lineup/src/core/app-shell/**`, `/Users/tristan/Software/Lineup/src/modules/navigation/**`, and `/Users/tristan/Software/Lineup/src/styles/**`

Freshness gate: before each package, record Desktop `HEAD`, upstream `HEAD`, scoped status, and the relevant target/source files in the local run bundle. If either checkout's scoped UI files, contracts, ownership, dependency state, or this plan changed materially, stop for plan refresh and plan re-review. Unrelated dirty files in the upstream checkout are user-owned and must not be edited or used as target evidence.

## Required Skills

- `lineup-desktop-feature-plan`: owns this Tier 3 planning route.
- `execution-plan-authoring`: keeps scope, ownership, verification, rollback, and handoff decision-complete.
- `architecture-boundaries`: governs renderer/preload/main composition and the new narrow Settings seam.
- `persistence-boundaries`: requires main-owned versioned Settings persistence, no renderer/browser storage, strict safe summaries, and explicit no-migration policy.
- `plex-integration-boundaries`: keeps auth, profiles, servers, library data, tokens, and transport in existing main-owned Plex seams while setup is recomposed.
- `ui-composition-patterns`: governs full-screen screens, modal/overlay precedence, focus, keyboard/gamepad/pointer behavior, timers, cleanup, accessibility, reduced motion, and media-surface composition.
- `verification-strategy`: owns the mixed regression/integration/manual visual proof below.
- `review-request`: every package receives a bounded read-only adversarial review before advancement.
- `review-adjudication`: findings are accepted, modified, rejected, or deferred against current evidence before edits.
- `closeout-verification`: required before each package commit and before final completion/staging/handoff.
- `lineup-desktop-feature-review`: the immediate next session reviews this plan; it also reviews every implementation package.

## Evidence And Discovery

### Discovery tools

- `semantic_search_with_context`: queried for renderer route shell, rail/status chrome, overlays, fixture presentation, Guide, Settings, and setup. Results were dominated by unrelated contracts/player policy and did not identify renderer composition owners reliably.
- `semantic_search_docs` / repo-doc search: document search attempted the UI-parity closeout/RD-27 conflict, but the local document collection reported a vector-dimension mismatch and returned irrelevant historical plans.
- impact analysis: not used for the initial evidence pass because Codanna could not identify the renderer owners. Package 4 must run impact analysis for any shared Settings contract symbol after it exists; all other shared-seam changes use targeted symbol lookup when useful.
- direct reads / `rg`: authoritative fallback for `src/renderer/**`, relevant tests, current docs, the archived plan, the audit, and the sibling WebOS checkout. The plan records this fallback because the current Codanna UI/document results were stale or noisy.
- official docs: Electron latest [`protocol`](https://www.electronjs.org/docs/latest/api/protocol) and [`net`](https://www.electronjs.org/docs/latest/api/net/) documentation checked 2026-07-13. They confirm `protocol.handle` is main-process API whose handler returns `Response | Promise<Response>`, privileged scheme registration occurs before app readiness, normal handler registration occurs after readiness, and `net.fetch(pathToFileURL(...))` is supported for local-file responses. The correction preserves the existing standard/secure/default-session architecture and changes no CSP or session behavior.

### Observed Desktop runtime contradictions

Current built Electron production-mode evidence observed through CDP at an outer `1280`-wide window (CSS content viewport `1280x688`, DPR `2`; therefore not a substitute for the required exact captures) showed:

- Player retained the permanent `Player / Guide / Settings / Channel setup` rail and top title/status/build chrome.
- Player showed fixture channel/program copy and simultaneous visible `nowPlaying` plus `playerOsd` overlays at startup.
- Guide retained the global chrome and showed `No channels available / Add channels from setup` rather than a proven schedule-backed target state.
- Settings explicitly described controls as local-only and not persisted.
- Channel Setup mounted a large scrolling composition with six stage buttons and Sign In/Server/Library/Build content in one document.
- route focus remained on `nav-*`; an early raw `Down` plus `Enter` sequence from Player entered a blank fullscreen state, proving that inferred focus behavior is insufficient.

### Source evidence for the contradictions

- `src/renderer/index.html` permanently mounts `.app-shell__topbar` and `.route-rail`.
- `src/renderer/styles/base.css` defines the two-column topbar/rail/screen grid and leaves route/top chrome in the product shell.
- `src/renderer/index.ts` initializes `presentationFixtures`, passes fixture overlays into every render, and seeds workflow/overlay/player state from them.
- `src/renderer/presentationFixtures.ts`, `src/renderer/epg.ts`, and `src/renderer/overlayViewModels.ts` contain product-reachable default presentation data.
- `src/renderer/overlays.ts` initializes `stack: ['channelBadge', 'nowPlaying', 'playerOsd']`.
- `src/renderer/staticDom.ts` mounts the four broad route panels and all setup sections in a single static document.
- `src/renderer/settingsSetup.ts` labels multiple controls as renderer-session-only and supplies only local state.
- `src/renderer/guidePresentationPolling.ts` and existing Guide IPC prove that the correct seam is runtime presentation, not a new renderer-owned scheduler.

### Reference evidence

The scoped upstream UI/navigation/styles paths were clean at observed upstream `HEAD`; unrelated upstream user files were dirty and remain untouched. Reference families include:

- app shell/screen visibility/loading/error/toast: `src/core/app-shell/**`, `src/modules/ui/splash/**`, `src/modules/ui/common/**`;
- navigation and focus: `src/modules/navigation/**`, `docs/user-guide/remote-keys.md`;
- onboarding: `src/modules/ui/auth/**`, `profile-select/**`, `server-select/**`, `audio-setup/**`;
- channel setup: `src/modules/ui/channel-setup/**`;
- Guide: `src/modules/ui/epg/**`;
- Settings: `src/modules/ui/settings/**` and upstream settings stores;
- player/overlays: `player-osd/**`, `now-playing-info/**`, `mini-guide/**`, `playback-options/**`, `channel-badge/**`, `channel-number-overlay/**`, `channel-transition/**`, `exit-confirm/**`, and `sleep-timer/**`;
- shared design language: `src/styles/**` and component-local UI styles.

### Package 1 upstream freshness disposition — 2026-07-12

The Package 1 freshness trigger compared frozen Package 0 commit
`6ef20801019e1d1aae2a0158128eba9142d0d008` with current upstream commit
`f109cf0c704cfea3da51606c51c31e0d04e72a5d`. Direct `git diff`, scoped path
logs, and focused source/test reads were used because this is an exact
two-commit comparison and Codanna would add no ownership signal.

- No upstream production file changed after `5b52ab984490ea170cf1d53245e2e01e3d258198`
  under any scoped Package 1 path; current `f109cf0c...` only normalizes
  persisted channel order outside this package. Across the full comparison, no
  production file changed under `src/modules/ui/common/**`,
  `src/modules/ui/splash/**`, `src/modules/ui/audio-setup/**`,
  `src/modules/ui/exit-confirm/**`, or `src/styles/**`. Package 0 reference
  PNGs, target capture ids, visual dispositions, and Home/audio-setup/exit
  mapping therefore remain the frozen authority.
- Commit `5256e14879caaa942ae92a0abffcff524812edbb` changed
  `AppScreenVisibilityCoordinator` so a deferred screen-load failure is
  ignored after its route loses ownership. This is a lifecycle-currentness
  hardening that reinforces the frozen cleanup/late-work rules; it changes no
  target state, focus neighbor, key rule, accessibility state, or capture id.
- Commit `3fd52e2bf487c1984273554ca8f4b191c374ecf7` added a protected
  quarantine variant to the existing blocking-error owner: Retry/Exit actions,
  disabled/busy pending state, retry restoration, non-dismissible Back, blocked
  background commands, and pending channel-number cancellation. Those semantics
  are already required by the frozen `shell-error-blocking` row. The change is
  corroborating source evidence, not a new Package 1 target or a new Desktop
  server-swap/quarantine feature.
- The same `3fd52e2b...` commit changed server-selection readiness/result types
  and runtime recovery ownership outside the approved Package 1 renderer seam.
  Package 1 does not copy, adapt, expose, or reproduce those owners. If the
  Desktop shell would need a new main/preload/runtime contract to represent a
  source-only quarantine distinction, stop and replan rather than broadening
  Package 1.
- Remaining commits and dirty/untracked upstream files in the range are either
  outside the scoped shell/navigation/UI paths or user-owned. They are not
  target evidence and remain untouched.

Disposition: the user authorized a narrow Package 0 return only for contradictory
shell rows. `shell-splash`, `shell-loading`, `shell-error-blocking`,
`shell-error-inline`, `shell-toast`, and `exit-confirm` are revised and refrozen
to existing Desktop-owned producers and the observed upstream toast/close
lifecycle. All other Package 0 behavior, ownership, accessibility, disposition,
and capture ids remain frozen. The revised shell visuals still use the existing
reference captures, so no reference PNG regeneration is required; deterministic
sanitized target capture states keep the existing target ids. Package 1 may cite
the upstream commits above as reference-only evidence. Copying or adapting
upstream code, markup, CSS, assets, or tests still requires an exact
import-ledger entry in the same implementation commit.

### Package 2 upstream freshness disposition — 2026-07-12

Compared with the Package 1 pin `196a54765c0c6f782ef78c52382de92f1ca1bfd2`,
current upstream `5a96aaf52680107a8090db88d5bd8268bbea1c61` changes only
`src/modules/ui/profile-select/ProfileSelectScreen.ts` and its tests inside the
scoped auth/profile/server families. Auth and server-select production sources
are unchanged. The profile delta contains invalid-auth recovery failures,
sanitizes their cause, ignores stale hide/destroy completion, and leaves the
profile chooser usable.

Package 2 adopts the containment lesson as reference-only: existing Desktop
`switchHomeUser` failures remain sanitized, current-generation, retryable UI
state and stale completion cannot mutate a hidden owner. Desktop exposes no
renderer-safe Plex sign-out operation, so Package 2 does not reproduce the
upstream sign-out recovery call or render an unsupported Sign Out action. It
also omits upstream persisted Forget/Clear Server behavior because Desktop has
no approved renderer-safe operation for it. No main/preload/contract expansion
is implied by upstream freshness.

The Package 2 auth/profile/server rows are pragmatically refrozen to these
existing Desktop producers. Their capture ids are unchanged. The static
`plex.tv/link` QR asset is the sole planned adapted upstream source slice; add
or update its exact import-ledger row in the same implementation commit. All
other hierarchy, state, focus, and CSS comparison is reference-only and is
independently expressed in Desktop owners.

### Conflicting tracked claims

At minimum, `docs/roadmap/desktop-port-roadmap.md` claims UI parity closeout complete and routes RD-01 through RD-26 directly to RD-27; its RD-22A/RD-23/RD-24 status/exit claims also conflict with the running app. `docs/architecture/CURRENT_STATE.md` has a `UI Parity Closeout` section claiming the reachable UI is complete. `docs/product/lineup-product-parity-matrix.md`, `docs/architecture/renderer-architecture.md`, `ui_parity_audit_results.md`, and the original-reference compatibility/divergence docs must be searched for the same stale posture. Package 0 corrects every conflict it finds; closeout refreshes the same set with observed final evidence.

## Impact Snapshot

- **Renderer owners changed:** shell/static DOM, navigation/focus/input, screen/stage state, workflow, player/overlay view models, Guide composition, Settings composition, setup composition, CSS modules, and focused new renderer submodules.
- **Main/tool exception before Package 4:** the Packages 1–3 fidelity correction extracts the existing guarded self-only renderer URL/path/MIME policy into one pure owner, adds only `.png` → `image/png`, and recursively copies `src/renderer/assets/**` into the built renderer. No IPC, preload, contract, persistence, Plex, player, native, CSP/session, or broader protocol behavior changes. Package 4 remains the only planned product cross-process package.
- **Tests changed:** public renderer behavior/focus/state tests, Settings contract/persistence/IPC/bridge tests, Electron smoke assertions, and any package-specific architecture rules.
- **Docs changed:** roadmap, current state, renderer architecture, security/secret flow, Windows UI proof plan, product parity, audit, original-reference compatibility/divergence, import ledger when applicable, and this active plan at closeout.
- **Dependencies/build/config:** no dependency, package, lockfile, CSP, native-helper, packaging, signing, or update change is approved. The sole protocol/build-tool change is the narrow self-hosted PNG serving/copy seam above; other MIME types, remote/private assets, directory listing, query-bearing requests, traversal, and non-shell hosts remain rejected.
- **User-visible change:** all reachable MVP screens and overlays change hierarchy and interaction. Player/guide runtime behavior, live Plex operations, channel mutations, native playback, diagnostics export, fullscreen, and support-bundle behavior must remain functionally correct.
- **Local-only artifacts:** all PNGs, capture manifests, CDP/browser logs, matrices containing observed local state, and review run notes stay under ignored `docs/runs/complete-webos-ui-parity-reopen/`.

The first package is docs/evidence-only. Subsequent packages are deliberately owner-bounded. The Packages 1–3 correction crosses renderer/main-tool ownership only for two static upstream PNGs; Package 4 is still the only planned product cross-process package. No implementation package may absorb adjacent business logic merely to match upstream structure.

## Files In Scope

Tracked files authorized across the plan, only in the package that names them:

- `src/renderer/index.html`
- `src/renderer/index.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/navigation.ts`
- `src/renderer/desktopInput.ts`
- `src/renderer/rendererActionRegistration.ts`
- `src/renderer/workflow.ts`
- `src/renderer/presentationFixtures.ts` only to remove product imports while retaining test/dev use
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`
- `src/renderer/overlayViewModelHelpers.ts`
- `src/renderer/playerOverlayActions.ts`
- `src/renderer/playerBridgeSubscription.ts`
- `src/renderer/epg.ts`
- `src/renderer/epg/**`
- `src/renderer/guidePresentation.ts`
- `src/renderer/guidePresentationPolling.ts`
- `src/renderer/settingsSetup.ts`
- `src/renderer/settingsSetupDom.ts`
- `src/renderer/settings/settingsRuntime.ts` (new)
- `src/renderer/channelSetup/**`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/profilePinModal.ts`
- `src/renderer/onboarding/plexLinkQr.ts` (new, Package 2 only)
- `src/renderer/onboarding/lineupBrandGlyph.ts` (new, Packages 1–3 fidelity correction only)
- `src/renderer/assets/lineup-logo-mark.png` and `src/renderer/assets/lineup-wordmark.png` (new, exact upstream assets in the Packages 1–3 fidelity correction only)
- `src/renderer/customChannels/**`
- focused new files under `src/renderer/shell/**`, `src/renderer/player/**`, `src/renderer/settings/**`, `src/renderer/guide/**`, or `src/renderer/setup/**` only when they take an owner named by a package
- `src/renderer/styles.css` and `src/renderer/styles/**`
- renderer tests under `src/__tests__/renderer/**`
- `src/contracts/settings.ts` (new), plus exact Settings channel additions in `src/contracts/ipc.ts`
- exact Settings API composition in `src/contracts/shell.ts`
- `src/main/persistence/appDataPaths.ts` only for injected Settings path resolution
- `src/main/persistence/desktopSettingsStore.ts` (new)
- `src/main/settings/settingsIpc.ts` (new)
- exact Settings composition wiring in `src/main/index.ts`
- `src/preload/channels.cts`, `src/preload/settingsBridge.cts` (new), `src/preload/settingsBridgeGuards.cts` (new), and exact Settings bridge wiring in `src/preload/index.cts`
- `src/__tests__/contracts/contracts.test.ts`, `src/__tests__/contracts/settingsContracts.test.ts` (new), `src/__tests__/main/settingsPersistence.test.ts` (new), `src/__tests__/main/settingsIpc.test.ts` (new), `src/__tests__/integration/preloadContractVocabulary.test.ts`, `src/__tests__/renderer/settingsSetup.test.ts`, `src/__tests__/renderer/settingsRuntime.test.ts` (new), `src/__tests__/renderer/workflow.test.ts`, and `src/__tests__/renderer/supportBundleExport.test.ts`
- `src/main/smokeAssertions.ts` and smoke/harness tests only for changed product-shell assertions
- `src/main/protocol.ts` only for the exact `.png` → `image/png` self-only allowlist addition
- `src/main/rendererProtocolPolicy.ts` (new) for pure renderer URL/path/content-type authorization and resolution
- `tools/copy-renderer-assets.mjs` only to recursively copy `src/renderer/assets/**`
- new `src/__tests__/main/rendererProtocolPolicy.test.ts`, new `src/__tests__/renderer/lineupBrandGlyph.test.ts`, and new `tools/__tests__/copy-renderer-assets.test.mjs` only for the static PNG/brand-glyph seam
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/renderer-architecture.md`
- `docs/architecture/security-and-secret-flow.md` for Package 4 persistence ownership and Package 8 closeout truth
- `docs/architecture/file-shape-guardrails.md` only to remove obsolete rows after decomposition, never to raise baselines pre-emptively
- `docs/architecture/import-ledger.md`
- `docs/architecture/original-lineup-reference-compatibility-matrix.md`
- `docs/architecture/original-lineup-divergence-register.md`
- `docs/product/lineup-product-parity-matrix.md`
- `docs/development/windows-ui-proof-plan.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `ui_parity_audit_results.md`
- this plan until closeout/archive

## Files Out Of Scope

- `src/native-helper/**`
- `src/main/player/**`
- `src/main/plex/**`
- `src/domain/**`
- existing player, Plex, Guide, channel, diagnostics, shell, persistence, and custom-channel contracts except the exact new Settings contract/channels above
- existing preload namespaces except exact Settings channel/guard/composition additions
- `package.json`, `package-lock.json`, Electron/build config, CSP/session behavior, protocol behavior other than the pure existing-policy extraction plus exact self-only `.png` MIME addition, packaging/signing/update/install code, and generated `dist/**` or `out/**`
- upstream `/Users/tristan/Software/Lineup/**` (read-only reference)
- unrelated user changes in either checkout
- RD-27 or RD-28 run bundles and closeout docs

An implementer must stop before touching an out-of-scope file. “Mechanical wiring” is not approval to broaden scope.

## Architecture Health

Current file-shape evidence from `docs/architecture/file-shape-guardrails.md` and fresh line counts identifies the renderer hotspots most likely to be touched:

- `src/renderer/epg.ts`: 725 lines, over the 500-line guardrail; must be decomposed before new Guide behavior.
- `src/renderer/index.ts`: approximately 601 lines, over the guardrail; must lose route/overlay/setup composition rather than grow.
- `src/renderer/styles/player-overlays.css`: 717 lines; split by overlay family before parity work grows it.
- `src/renderer/styles/plex-onboarding.css`: approximately 648 lines; split stage/screen styles before setup work.
- `src/renderer/styles/workflow-screens.css`: approximately 590 lines; extract Settings and screen-shell owners before growth.
- `src/renderer/styles/guide-epg.css`: 506 lines; split shell/grid/cell styles before Guide expansion.
- `src/preload/index.cts`: a hard-overage owner; Package 4 must extract Settings guards/builders and add only minimal namespace binding in the entrypoint.
- `src/renderer/staticDom.ts`, `focusDom.ts`, `routeDom.ts`, `overlayViewModels.ts`, and `workflow.ts` are near enough to the guardrail that packages must extract focused owners instead of consolidating more behavior there.

Decisions:

- **Decision:** decompose the named renderer/CSS owners before behavior grows them, avoid growing the preload entrypoint by extracting Settings guards, and use no new or raised allowlist row for planned work.
- **Packages 1–3 correction evidence:** `src/renderer/index.ts` is currently 637 lines and remains untouched; `staticDom.ts` is 322; `shellDom.ts` is 158; `shell.css` is 186; `plex-auth.css` is 62; `plex-profile-server.css` is 15; `plex-onboarding-cards.css` is 187; `profile-pin-modal.css` is 161; `setup-workflow.css` is 169; `custom-channels.css` is 212; `src/main/protocol.ts` is 94; and `tools/copy-renderer-assets.mjs` is 19. Keep each new pure protocol/brand helper at or below 250 lines. The correction may refactor within the exact files below but may not grow `index.ts`, create a new owner over 500 lines, raise a baseline, or move behavior into CSS/markup.
- No baseline increase is authorized for any renderer/CSS/preload hotspot.
- Packages 1, 2, 3, 4, 5, 6, and 7 must perform same-owner extraction before adding behavior if their touched hotspot would grow.
- `index.ts` remains only a composition root; package-specific coordinators own timers, subscriptions, stage/overlay state, and rendering.
- `staticDom.ts` stops being the monolithic owner for all product screens; focused screen DOM owners may retain trusted static templates.
- Settings guards live outside `preload/index.cts`; the entrypoint keeps the single `lineupDesktop` exposure.
- Run `npm run verify:maintainability` in every source package and remove allowlist rows when files fall to 500 lines or below.

## Target Surface And Interaction Contract

The local matrix must enumerate each upstream reference family and record `adapt`, `Desktop divergence`, or `defer/block`. At minimum it covers:

| Surface family | Required Desktop posture |
| --- | --- |
| Shell, splash/loading, blocking/nonblocking error, toast | No permanent route/status chrome; one full-screen owner at a time; honest loading/error states; diagnostic detail remains redacted. |
| Auth, profile/PIN, server selection | Remote-first upstream hierarchy, PIN/modal focus containment, live renderer-safe Plex state, cancel/back/error recovery, no raw token/URI data. |
| Audio setup | Record whether current Desktop runtime needs an equivalent. If unsupported, keep it absent with an explicit Desktop capability divergence; do not add a fake screen. |
| Channel setup and custom channels | One active stage/detail surface at a time; live source/build/replacement/custom-channel state preserved; no long all-stages form. |
| Settings | Upstream category/detail behavior and focus; compare current upstream audio/subtitles, playback/HDR, appearance, account, and developer categories row by row. Persist all user-visible Desktop preferences that remain in Settings through the main-owned store. Unsupported upstream rows are reviewed divergences, not fake settings; support bundle remains Desktop-specific. |
| Guide/EPG | Scheduler-backed rows and time geometry, current marker, focused cell detail, channel/time navigation, tune/back, loading/empty/error states. |
| Player | Native presentation surface is primary; no product fixture copy, route card, or default overlay stack. |
| OSD, now playing, mini guide, options, badge, number entry, transition | Upstream visual hierarchy and mutually coherent modal/transient choreography; runtime-safe player/guide/channel state only. |
| Exit confirm and sleep timer | Explicit disposition. Implement only if a real Desktop action/state exists; otherwise record a reviewed platform/product divergence and omit fake controls. |
| Home/channel-edit | Explicitly map to current Desktop player/setup/custom-channel journeys or record a reviewed divergence; no unreachable decorative route. |

Every focus/interaction matrix row records: entry action; initial focus; Up/Down/Left/Right neighbors; OK/Enter result; Back/Escape result; Guide/Settings/Info/digit/PageUp/PageDown/Space behavior where relevant; pointer/click equivalent; text-entry bypass; scroll behavior; modal/overlay precedence; focus restore target; timeout/repeat behavior; listener/timer cleanup; accessibility name/state; loading/empty/error variants; automated proof; and manual capture id.

Global invariants:

- product launch cannot focus a removed `nav-*` target;
- Player idle has no visible overlay unless a real transient event requires one;
- only the intended modal/transient combination is visible; opening a modal closes or suspends conflicting surfaces exactly as the matrix specifies;
- Back closes the top modal/overlay before changing screens or exiting;
- Guide and Settings shortcuts work from Player and restore meaningful focus on return;
- editable targets bypass global shortcuts except the modal-specific keys explicitly recorded;
- hidden screens, stages, and overlays contain no tabbable/focusable elements;
- timers, polling, global handlers, and bridge subscriptions stop on hide, route change, modal close, or unload as applicable;
- pointer accessibility remains available without making desktop control-panel chrome the primary visual language;
- reduced-motion and forced-colors behavior remains usable;
- exact captures use CSS renderer content viewport `1280x720` and `1920x1080`, not outer BrowserWindow size. The local ignored CDP/visual harness fixes `deviceScaleFactor=1` or independently verifies both CSS viewport and output PNG pixel dimensions before accepting a capture. Capture manifests record viewport, DPR, PNG dimensions, build mode, Desktop commit, upstream commit, surface/state id, sanitization mode, and pass/fail.

## Execution Packages

### Package 0 — Reopen truth, exact baseline, and parity matrices

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only. Visual judgment and authority correction make this ineligible for `worker_luna`.

This is the explicit first bounded execution unit. It is docs/evidence-only and must complete before product source changes.

Scope:

- create ignored `docs/runs/complete-webos-ui-parity-reopen/` with a local CDP/visual capture harness, capture manifest, surface-disposition matrix, focus/interaction matrix, and `baseline/`, `reference-webos/`, and later `target/` directories; the harness must set `deviceScaleFactor=1` or reject any capture whose CSS viewport and PNG dimensions are not both exactly the requested size;
- fully observe and decide the target behavior for every screen, stage, modal, overlay, loading/empty/error state, supported Desktop setting, and explicit Desktop divergence before Package 1: the matrix must freeze target visual state, entry action, initial focus, every directional neighbor, OK/Enter, Back/Escape, shortcuts/digits/channel keys, pointer equivalent, text-entry bypass, scroll, modal/overlay precedence, focus restoration, timeout/repeat policy, cleanup, accessibility state, owner, and acceptance proof; no required target cell may be blank, `unknown`, `TBD`, or deferred to an implementer;
- capture every currently reachable Desktop state at exact `1280x720` and `1920x1080`, including player default, Guide empty, every Settings category, all six setup stages, auth/profile/server states available through sanitized proof, and each overlay state that can be opened safely;
- capture an equivalent upstream reference PNG for every matrix state at both sizes using sanitized deterministic state injection where live runtime preconditions would otherwise block it; inability to produce the reference PNG is a stop condition, not a source-only substitute;
- record the running-app contradictions above and the blank-fullscreen focus symptom in the matrix;
- change conflicting tracked docs, including `docs/development/windows-ui-proof-plan.md`, to `reopened/blocked before RD-27`, insert this active plan as the roadmap prerequisite, and remove direct-to-RD-27 claims;
- audit all parity/current-state/roadmap claims with `rg`; do not limit corrections to the already-known paragraphs;
- update import-ledger/reference-matrix posture only if this truth reset changes provenance classification, without claiming new imports.

Verification and expected outcome:

- `npm run verify:docs` passes; all tracked docs agree UI parity is reopened and RD-27 is blocked.
- `npm run verify:redaction` passes; tracked docs contain no private evidence.
- `git diff --check` passes.
- local manifests show a three-way row at both exact viewports for every state: current WebOS reference PNG, Desktop pre-package baseline PNG, and a reserved Desktop post-package target PNG id. When a state does not exist in the Desktop baseline, its baseline PNG must show the closest owning screen and visibly document the absence; a prose-only baseline is insufficient.
- the entire target focus/interaction matrix is decision-complete with no blank/unknown required cell, and the Package 0 reviewer explicitly accepts the target behavior, divergence decisions, ownership, and proof mapping; later packages may update only implementation/evidence/result columns unless a reviewed replan returns to Package 0.
- read-only adversarial package review reports no material authority, evidence, privacy, or scope findings.

Stop and replan before Package 1 if any target behavior, focus neighbor, key/back/overlay rule, supported/divergent surface, owner, or acceptance proof remains undecided; if the Package 0 review finds a material matrix ambiguity; if exact viewport control is unavailable; if sanitized reference states cannot be produced without private material; or if another active plan now owns the RD-26→RD-27 sequence. Later packages may not invent target behavior to bypass this gate.

### Package 1 — Full-screen shell, navigation lifecycle, and global state surfaces

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_luna` eligible by explicit user override. Package 1 is exact and bounded by the refrozen shell rows, existing Desktop producers, direct tests/smoke/captures, and the escalation conditions below.

Scope is limited to `src/renderer/index.html`, `index.ts`, `staticDom.ts`,
`domBindings.ts`, `routeDom.ts`, `focusDom.ts`, `navigation.ts`,
`desktopInput.ts`, `rendererActionRegistration.ts`, `workflow.ts`, the exact new
owners `src/renderer/shell/shellState.ts`, `src/renderer/shell/shellDom.ts`,
`src/renderer/shell/shellController.ts`, and
`src/renderer/shell/navigationLifecycle.ts`, `src/renderer/styles.css`, shell/base
style owners under `src/renderer/styles/**`, the six named renderer tests below,
and `src/main/smokeAssertions.ts` plus `src/main/smokeFullscreenAssertions.ts`
only for changed shell assertions. Package 1 must not change contracts, preload,
main IPC/composition, player/Plex/Guide/channel owners, dependencies, or later
package behavior.

Shell owner responsibilities are frozen without prescribing private helper or
constructor shape:

- `shellState.ts` owns renderer-only shell state vocabulary and pure state
  transitions; it contains no DOM, timers, bridge calls, or product data.
- `shellDom.ts` owns shell/global-surface DOM creation, querying, visible/hidden/
  inert/ARIA rendering, and exact focus ids. `staticDom.ts` delegates shell
  composition to it and remains a narrow assembly entrypoint; later-package
  screen internals may move mechanically but are not redesigned here.
- `shellController.ts` binds only the existing `shell.getCapabilities` and
  `window.setFullscreen` producers to splash/loading/error/toast state, owns
  their current generations and the refrozen toast timers, and cleans them up.
- `navigationLifecycle.ts` owns route focus memory, Player Back/exit-confirm,
  Guide/Settings shortcuts, fullscreen focus continuity, and unload cleanup.
  `index.ts` composes these owners and must not grow beyond its current 601-line
  evidence.

Implementation must:

1. Extract these owners before adding Package 1 behavior.
2. Remove the permanent topbar, route rail, route cards, and every `nav-*`
   product focus target. Keep shell status/capability output available to smoke
   and diagnostics without rendering permanent product chrome. Exactly one
   `[data-screen]` owner is visible and interactive; every other screen and
   global owner is hidden, inert, `aria-hidden`, and absent from the focus
   registry.
3. Implement only the refrozen Package 1 states and transitions:
   `shell-splash`, `shell-loading`, `shell-error-blocking`,
   `shell-error-inline`, `shell-toast`, `exit-confirm`, and the omitted/mapped
   `home`, `audio-setup`, and `shell-blank-fullscreen` rows, with these exact
   producers:
   - first `window.lineupDesktop.shell.getCapabilities()` request ->
     `shell-splash`; valid success -> Player; typed/defensively normalized
     failure -> recoverable `shell-error-blocking`;
   - `shell-error-retry` -> one fresh `getCapabilities()` generation shown as
     `shell-loading`; success -> Player; failure -> the same safe blocking error
     with retry focus restored;
   - failed `window.lineupDesktop.window.setFullscreen(desired)` ->
     `shell-error-inline` over the continuously visible Player, with Dismiss or
     one retry of the same desired boolean and `player-fullscreen` restoration;
   - accepted fullscreen result -> passive `shell-toast`, visible 5000ms then
     fading 200ms, with a 1500ms duplicate throttle. Toast never captures focus
     or consumes Back/shortcuts;
   - Player Back -> `exit-confirm`; Cancel/Escape restores the exact Player
     invoker; Exit calls `window.close()` once. `window.close()` has no promise
     or renderer acknowledgement, so the UI must not invent pending/success/
     failure state. Smoke must observe the existing BrowserWindow close,
     `window-all-closed`, `before-quit`, and teardown lifecycle.
   Home and audio setup create no DOM, route, focus target, listener, or timer.
4. Preserve Guide/Settings shortcuts from Player, route focus memory on return,
   pointer equivalents, editable-target bypass, and the existing narrow
   fullscreen bridge. A fullscreen request keeps the Player/native presentation
   continuously visible and preserves the active Player focus/owner on both
   accepted and renderer-safe failed results; it must never synthesize a blank
   screen or focus a removed navigation target.

All copy and accessible names come from the refrozen matrix. Async capabilities
and fullscreen actions use one current generation, pending disablement where
specified, late-result rejection, and cleanup on hide/route change/unload; toast
uses only its exact timers; close actions own no fake async state. This package
fills only implementation/evidence/result columns for the refrozen launch,
shortcut navigation, Back, fullscreen, pointer, editable-bypass, stale-load,
and blank-fullscreen rows. Any changed behavior, missing focus neighbor,
unavailable exit/cleanup mechanism, required cross-process contract, or new
upstream-only state is a stop condition requiring reviewed planning; it is not
worker discretion. The explicit user override authorizes `worker_luna` for this
package despite the usual Tier 3 eligibility default; the worker must escalate
rather than decide when any stop condition is met.

Verification: `node --import tsx --test src/__tests__/renderer/navigation.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/workflow.test.ts`, then `npm run typecheck`, `npm run verify:maintainability`, `npm run smoke:electron`, `npm run verify:redaction`, `npm run verify`, and `git diff --check`. Capture target-in-progress evidence at exact DPR-1 CSS viewports `1280x720` and `1920x1080` for `shell-splash`, `shell-loading`, `shell-error-blocking`, `shell-error-inline`, `shell-toast`, `shell-blank-fullscreen`, `exit-confirm`, `home`, and `audio-setup`, preserving the Package 0 target reservation ids. Expected: the six named files pass; `index.ts` does not grow and its extracted lifecycle owners are focused; no permanent product chrome or `nav-*` launch focus remains; hidden owners are inert/nonfocusable; stale global work cannot replace the current owner; blocking error and exit-confirm precedence/restoration match the matrix; the blank fullscreen transition is covered and absent; exactly one screen is visible; shell/security/fullscreen smoke assertions pass; and fresh adversarial review reports no material finding before Package 2.

Package 1 stop/escalation conditions: any refrozen matrix field must change; an exact target
capture cannot be reached safely; an out-of-scope contract/main/preload/player/
Plex/Guide/channel change appears necessary; `window.close()` does not exercise
the observed main-owned quit/teardown path; the refactor would preserve route
chrome or introduce a compatibility shim; `index.ts` grows or another touched
owner crosses a guardrail without the planned extraction; a required check or
review has a material failure outside this package seam; a producer above is
unavailable or needs invented behavior; or visual/accessibility judgment cannot
be resolved directly from the refrozen matrix and captures. `worker_luna` must
stop, preserve the current diff, record the exact evidence, and escalate to the
controller. Return to Package 0 only when the refrozen target itself is at issue.

### Package 2 — Onboarding and server/profile interaction parity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_luna` eligible by explicit user override. The seven refrozen rows, exact existing Plex actions, file boundary, visual references, direct checks, and escalation gates below leave no product or process decision to the implementer.

Exact production scope:

- `src/renderer/staticDom.ts`, `domBindings.ts`, `plexRuntimeDom.ts`,
  `plexRuntimeRows.ts`, `profilePinModal.ts`, `focusDom.ts`, `routeDom.ts`,
  `rendererActionRegistration.ts`, `plexRuntimeActions.ts`,
  `plexRuntimeState.ts`, and `index.ts` only for composing the seven Package 2
  onboarding states and their existing privileged actions plus the new
  renderer-local auth-error dismissal described below;
- `src/renderer/onboarding/plexLinkQr.ts` (new) for the adapted static
  `plex.tv/link` QR only; it contains no account code, token, URL parameter, or
  runtime data;
- `src/renderer/styles.css`, deletion of the 648-line
  `src/renderer/styles/plex-onboarding.css`, and exact replacement owners:
  `plex-auth.css` for link-code/waiting/error, `plex-profile-server.css` for
  profile cards/server rows/error and their shared full-screen frame, and
  `setup-stages.css` for mechanically carried setup rail/detail/library/media
  selectors that Package 3 still owns. Existing `profile-pin-modal.css` and
  `plex-onboarding-cards.css` may change only where the refrozen profile/PIN/
  server targets require it;
- `docs/architecture/import-ledger.md` only for the exact static QR adaptation.

Exact test scope is
`src/__tests__/renderer/plexRuntime.test.ts`, `profilePinModal.test.ts`,
`focusDom.test.ts`, `rendererActionRegistration.test.ts`, `routeDom.test.ts`,
and `rendererRuntimeOwners.test.ts`. Exact ignored proof scope is
`capture-target.mjs`, `target-entry.ts`, `target-index.html`, a new
`package-2-target-manifest.json`, a new `update-package-2-evidence.mjs`, and the
seven existing target PNG ids at both resolutions. No other product, test, doc,
or proof file is approved for Package 2.

Refrozen target rows are `auth-link-code`, `auth-waiting`, `auth-error`,
`profile-select`, `profile-pin`, `server-select`, and `server-error`:

- Auth uses existing `requestPin`, automatic `pollPin`, `cancelPin`, and
  `clearPinSubflow` ownership. Idle registers, enables, and focuses Request
  only; Cancel is absent from its focus graph and Back is ignored because no
  active PIN exists. Waiting shows the real safe code/expiry and registers and
  focuses only Cancel for the active PIN/poll. Failure focuses Retry with
  Cancel below. In `auth-error`, Cancel and Back invoke one renderer-local
  `dismissPinError` controller action: increment/invalidate the current
  operation generation, clear the poll timer and active renderer PIN id, clear
  pending PIN flags, safe error text, PIN snapshot/input state, and return to
  clean `auth-link-code` with Request focused. That dismissal makes no bridge,
  main, preload, cancellation, or persistence call; `plexRuntimeActions.ts`
  owns the generation/timer invalidation and `plexRuntimeState.ts` owns the
  pure state clear. Normal waiting Cancel may still use the existing
  renderer-safe cancellation path. Hide invalidates polling and clears
  timers/current PIN state. The QR is static `plex.tv/link`; the renderer-safe
  code remains text and is never encoded into the asset.
- Profile Select is a full-screen card owner populated only by existing
  `getHomeUsers` safe summaries. A protected row opens the PIN modal; an
  unprotected/main row calls existing `switchHomeUser(userId)`. There is no
  Sign Out action because the Desktop bridge does not expose one. The current
  upstream invalid-auth delta is reference-only: safe current-generation error,
  stale completion ignored, and the attempted row restored.
- Profile PIN opens with `btn-profile-pin-5` focused, makes the profile list and
  every other screen inert/nonfocusable, contains digits/Backspace/Delete/
  Cancel and directional input, and submits exactly four digits through
  existing `setHomeUserPin(pin)` plus `switchHomeUser(userId)`. A safe switch
  failure keeps the modal open, renders only the contained sanitized error,
  clears all four digits, and restores the exact last activated digit/keypad
  target. Cancel or Back clears digits, closes the modal, and restores the
  invoking profile row. Success clears digits, closes, and advances to Server
  Select. Hide/unload also clears digits and invalidates late completion.
- Server Select uses only existing `restoreSelectedServer`, `refreshServers`,
  `selectServer`, and local Setup/Switch Profile navigation. Rows expose only
  renderer-safe name, ownership, health/status, and selected truth. There is no
  persisted Forget/Clear Server action because no approved Desktop contract
  owns it. Discovery failure focuses Refresh with Switch Profile below. Back
  returns to the invoking profile row without clearing authentication.

All seven states replace the old long-form Desktop account/server panels while
they are active: no setup rail, multi-stage form, library/media controls,
summary cards, route card, or other onboarding state remains visible or
focusable behind them. Only the active owner is visible. Hidden states and the
PIN-modal background are `hidden`/inert/`aria-hidden` and absent from the focus
registry. Pointer activation equals OK/Enter, editable/global shortcut bypass
follows the refrozen matrix, and every request/poll/switch/discovery generation
ignores stale completion after state change, modal close, route change, or
unload.

Plex credentials, tokens, connection URIs, raw payloads, transport policy,
selected-server persistence, app paths, and retries remain in current
main/preload owners. No main, preload, contract, Plex transport, persistence,
dependency, package, lockfile, CSP, or protocol change is approved. Sanitized
proof uses deterministic public fixtures only; no real account, profile, server,
library, code, token, URL, or local path may appear.

Verification is decisive without making native smoke a gate:

- `node --import tsx --test src/__tests__/renderer/plexRuntime.test.ts src/__tests__/renderer/profilePinModal.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts` passes;
- `npm run typecheck`, `npm run verify:maintainability`,
  `npm run verify:redaction`, `npm run verify`, and `git diff --check` pass;
- exact DPR-1 `1280x720` and `1920x1080` target captures pass for all seven
  rows and are visually compared against their preserved WebOS reference and
  Desktop baseline ids, with sanitized semantics and no long-form/background
  panel leakage;
- `npm run smoke:electron` may be attempted and recorded but is nonblocking and
  optional for this user-authorized package; focused automation, full verify,
  captures, visual comparison, and fresh adversarial review are mandatory.

Expected acceptance: the CSS split leaves each new owner at or below the
500-line guardrail without raising a baseline; the seven states are visibly
WebOS-comparable full-screen owners; fake QR cells and old long-form onboarding
panels are absent; unsupported Sign Out/Forget controls are absent; PIN/input/
Back/restoration/stale-cleanup contracts pass; renderer privilege and Plex
custody remain unchanged; the QR import-ledger row is exact; proof is private-
data-free; and fresh adversarial review has no material finding before Package
3.

`worker_luna` must stop, preserve the diff, and escalate if a refrozen target is
contradictory; a main/preload/contract/Plex transport/persistence change appears
necessary; proof would contain private values; copied/adapted upstream material
beyond the static QR appears; an unlisted file is required; a CSS/source owner
would exceed its guardrail or need a raised baseline; or focused/full/capture/
review evidence fails outside this package seam. Routine DOM structure, helper
names, and local test arrangement inside the exact files remain implementer
choices.

### Package 3 — Staged channel setup and custom-channel parity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_luna` eligible by explicit user
override through `.codex/agents/worker-luna.toml`. This unit is bounded to
existing renderer-safe Plex, channel-setup, custom-channel, and player actions;
the target ids, state transitions, file boundary, direct tests, exact captures,
and escalation rules below leave no cross-process or product decision to the
implementer.

**PACKAGE STATUS:** behavior/state/focus/accessibility ownership closed on
2026-07-13 after the renderer-only structure correction, exact 11-file 126/126
suite, full 749/162 verification, 36 exact target captures with 684/684
semantic assertions and clean adversarial re-review. That evidence remains
accepted, but its visual-fidelity conclusion is superseded by the consolidated
Packages 1–3 correction below. Package 4 has not started. The prior Package 3
inertness, stale-generation, safe error, custom-channel, and atomic-commit
behavior remains accepted together with the corrected library selection,
truthful Step 2, inline replacement confirmation, recovery origins, and exact
focus/action graphs.

#### Reopened current unit — upstream setup structure correction

This is one bounded recomposition, not a new package or a request to implement
the upstream browser setup runtime. The full-screen `channelSetup` route remains
the active route owner, but all 11 Package 3 states must render inside one
compact, centered, ScreenShell-like setup panel. Adapt the current upstream
hierarchy and density: a stable `Channel Setup` title/subtitle, step label,
status/detail/error region, bounded scrollable body, and footer action row.
Use upstream-equivalent panel geometry (`width: min(1440px, 92vw)`,
`max-height: 85vh` at the normal target viewports), compact title/body type,
moderate panel padding, and dense cards/rows. Remove the Package 3 giant
per-state headings, page-scale empty spacing, full-screen spinner/success/error
compositions, and viewport-wide modal treatment.

The visible hierarchy is exactly the upstream three-step model, adapted only
where the existing Desktop runtime is genuinely narrower:

- `setup-library` is visibly `Step 1 of 3`. Add real setup-local multi-library
  selection over the existing renderer-safe section summaries and existing
  `channelSetup.commit({ sectionIds })` array seam. Only movie/show sections are
  eligible. `selectedSectionIds` is an ordered setup-owner set normalized to
  current server section order; it is cleared on setup close, server/profile
  change, route invalidation, or disappearance from a refreshed section list.
  It is deduplicated and capped at the existing request limit of 24. If more
  than 24 eligible libraries exist, Select All selects the first 24 in server
  order and shows a safe limit message; activating another unselected row at
  the cap retains state/focus and shows the same message, while selected rows
  remain removable. This is an existing Desktop contract limit, not permission
  to change that contract.
  The existing Plex `selectedSectionId` remains only the preview/browse cursor.
  Row activation toggles membership, keeps focus on that row, and makes that row
  the cursor before loading its preview items. `Select All` selects every
  eligible row up to the exact 24-row cap in server order and makes the first
  selected row the cursor only when the current cursor is not selected. `Clear
  All` clears only the setup selection and leaves the browse cursor intact.
  Commit passes the complete normalized selected id array; no contract,
  preload, or main change is needed.
  Entering this owner with a selected server automatically calls the existing
  `listLibrarySections()` operation exactly once when the section snapshot is
  absent or is not tagged by the coordinator to that selected server's current,
  noninvalidated generation. Server/profile change, explicit library Retry,
  route close, and unload invalidate that tag/generation. Loading
  remains inside the shared Step 1 panel with truthful status; bulk actions,
  rows, and Next are disabled and omitted from focus while Back remains enabled
  and focused. Success retains only still-eligible selected ids, normalizes them
  to server order, deduplicates/caps them at 24, and restores focus to the first
  selected eligible row, else the first eligible row, else Select All. A valid
  response with no movie/show section renders the exact in-panel
  `No movie or show libraries are available.` empty state with
  `setup-library-retry` then `setup-back`; Retry reruns
  `listLibrarySections()`, and Back returns to the Package 2 server-selection
  owner when that was the entry path or otherwise closes setup to the recorded
  Player/Guide/Settings invoker. A request failure is the distinct Step 1
  origin-recovery state frozen below, not the empty state.
- `setup-preview` is visibly `Step 2 of 3 — Configure channels`. It is one
  truthful reduced strategy pane, not a simulated copy of six unsupported
  upstream strategy families. Remove `sourceMode`,
  `selectRecentlyAddedSource`, and the functional `Recently added` option from
  renderer state, actions, DOM, and tests. Preserve upstream split geometry with
  one real selected/focusable `Build mode` category in the 280px rail, exact
  focus id `setup-category-build`, and Append/Replace/Custom in its detail pane.
  Render those real choices with exact ids `channel-strategy-build-append`,
  `channel-strategy-build-replace`, and `channel-strategy-build-custom`, followed
  by the upstream-style collapsible preview strip below the split using existing
  safe cursor items/metadata and `setup-preview-toggle`. Do not add genre,
  collection, playlist, priority, limit, series-ordering, alternate-lineup, or
  other controls that lack current Desktop behavior. The sole category is fixed
  and selected, so no category-switching state or additional pane exists.
  Preview is optional evidence, never a source-selection gate. Row activation
  keeps its valid membership/cursor change even when `listLibraryItems()` fails,
  and Library Next remains enabled whenever `selectedSectionIds` is nonempty.
  The expanded preview strip has exact `loading`, `ready`, `empty`,
  `items-error`, and `metadata-error` states. Loading shows truthful busy copy
  without removing Step 2 strategy/Next/Back actions; empty shows
  `No preview items are available.` and no retry; either error shows safe
  `Preview unavailable.` copy plus exact `setup-preview-retry` without replacing
  the Step 2 owner or clearing selection. Retry in `items-error` reruns only
  `listLibraryItems()` for the current preview cursor. Retry in
  `metadata-error` reruns only the failed metadata request for its current safe
  preview rating key. Success/empty clears the corresponding inline error;
  failed Retry retains it and restores `setup-preview-retry`. Stale item or
  metadata completion after cursor/server/route change is ignored.
- `setup-build` is visibly `Step 3 of 3 — Review and build`. Present the selected
  libraries, current saved summary, chosen mode, safe warnings, and truthful
  impact language in the upstream dense review treatment. The planned after-
  count is exact from current commit semantics: Append shows current saved
  count plus normalized selected-id count; Replace shows normalized selected-id
  count. Label it as planned until commit succeeds and do not fabricate a
  progress percentage. Replace the old `confirm-replace` modal
  owner with the upstream inline `setup-replace-confirm` toggle inside Step 3;
  it uses the existing renderer-local `replacementConfirmed`/
  `confirmReplace` truth and `aria-pressed`. `setup-confirm` is disabled in
  Replace mode until that toggle is selected. The reserved
  `setup-confirm-replace` target capture id now captures the Step 3 build owner
  in Replace mode with the inline toggle visible and focused; it is not a modal
  owner. Progress uses an indeterminate upstream-style bar plus honest atomic-
  operation detail. Result reuses the same Step 3 panel/status/detail/body/
  footer structure; recovery uses the origin step frozen below. Existing atomic
  Cancel-view, result Watch/Done, and stale-generation behavior remains
  unchanged.

`setup-custom`, `custom-list`, `custom-edit`, and
`custom-delete-confirm` remain a Desktop extension. Give them the same compact
panel, list/card, detail-pane, footer, and in-panel dialog treatment, with an
explicit visible `Desktop extension` label. Do not present custom-channel CRUD
as upstream WebOS behavior and do not change any new/duplicate/save/delete/
hide/reorder/media/metadata action, pending guard, focus id, or restoration
rule.

The revised dispatch vocabulary is exact. Add staged flow actions
`librarySelectAll`, `libraryClearAll`, `libraryRetry`, `previewRetry`,
`selectBuildCategory`, and `toggleReplaceConfirm`; retain `libraryNext`,
`previewToggle`, `previewNext`, `buildConfirm`, `buildBack`, `progressCancel`,
`resultDone`, `resultWatch`, `recoveryRetry`, `setupBack`, `openSetupCustom`, and
the reviewed custom actions.
Section rows continue through the existing `selectPlexSection` handler, whose
revised index composition toggles setup membership and updates the browse cursor
once. Retain channel-setup actions `selectAppendBuildMode` and
`selectReplaceBuildMode`; remove `selectRecentlyAddedSource`, `replaceCancel`,
and `replaceAccept` from types, validators, markup, and dispatch. No alias or
compatibility action remains.

The exact actions, availability, and focus graph are frozen as follows:

- Step 1 action ids are `setup-select-all`, `setup-clear-all`, the existing
  sanitized `plex-dyn-section-<id>` rows, `setup-next`, and `setup-back` in that
  registration order. Select/Clear and rows are disabled during library work;
  Select/Clear are also disabled when there is no eligible movie/show row.
  Next is disabled while pending or when selection is empty. Disabled controls
  are omitted from the focus registry. Select All has Right Clear All and Down
  first enabled row; Clear All has Left Select All and Down first enabled row.
  Rows run vertically in server order, first-row Up returns Select All, and
  last-row Down reaches Next. Next runs Down to Back; Back runs Up to Next.
  Missing disabled neighbors are skipped to the next enabled control. If the
  focused control becomes disabled during pending work, focus falls to Back.
  Select/Clear restore the first eligible row; row activation restores itself.
  During automatic load, only `setup-back` is registered and focused. The empty
  result registers `setup-library-retry` then `setup-back`; Retry runs Down to
  Back and Back runs Up to Retry. Activating Retry immediately enters the
  loading graph and moves focus to its sole enabled `setup-back`. Step 1 request
  failure instead registers `setup-error-retry` then `setup-error-back` in the
  shared Step 1 recovery panel with the same two-control vertical graph.
- Step 2 action ids and registration order are `setup-category-build`,
  `channel-strategy-build-append`,
  `channel-strategy-build-replace`, `channel-strategy-build-custom`,
  `setup-preview-toggle`, conditional `setup-preview-retry`, `setup-next`, and
  `setup-back`. Append/Replace are the existing
  `selectAppendBuildMode`/`selectReplaceBuildMode` renderer-local actions;
  Custom uses existing `openSetupCustom`. The fixed selected category uses
  staged action `selectBuildCategory`; OK/Enter or Right moves to the selected
  enabled Append/Replace control, falling back to Append, while its Up/Down/Left
  self-loop. Entry from Step 1 focuses `setup-category-build`. Detail controls
  run Up/Down in Append, enabled Replace, Custom order and Left returns
  `setup-category-build`; disabled Replace is skipped. Custom Down moves to the
  preview-strip toggle. Preview Toggle runs Up to Custom and Left to
  `setup-category-build`; its Down target is Retry when an expanded inline
  preview error exists, otherwise Next. Retry runs Up to the toggle and Down to
  Next. Next runs Up to Retry when present, otherwise the toggle, and Down to
  Back; Back runs Up to Next. Step 3 Back focuses the selected enabled mode
  control, falling back to Append. Custom Back restores
  `channel-strategy-build-custom`; closing the preview strip restores
  `setup-preview-toggle`.
- Step 3 Append order is `setup-back`, `setup-confirm`. Replace order is
  `setup-replace-confirm`, `setup-back`, `setup-confirm`; disabled Confirm is
  skipped until the inline toggle is selected. Toggling confirmation keeps
  focus on `setup-replace-confirm`; Confirm starts the one existing commit;
  Back restores the selected Step 2 mode button. Remove `setup-replace-cancel`,
  `replaceCancel`, `replaceAccept`, modal inertness, and modal focus restoration.
- Progress remains `setup-progress-cancel`; result remains `setup-done` then the
  enabled `setup-result-watch`; custom/editor/delete graphs remain as previously
  reviewed. Pointer activation equals OK/Enter. One central delegated-action
  eligibility helper in `rendererActionRegistration.ts` must reject the target
  itself or any ancestor matching `[hidden]`, `[inert]`, or
  `[aria-hidden="true"]`, as well as a target that is disabled or
  `aria-disabled="true"`, before either staged-flow or Plex-row dispatch. Both
  delegated paths must use that helper and dispatch an eligible activation
  exactly once.

Whole-panel recovery records exact `originStep: 'library' | 'build'`,
`operation: 'listLibraries' | 'refreshStatus'`, and the exact invoker focus id.
Library-list failure renders recovery inside Step 1; Retry reruns
`listLibrarySections()`, prunes/normalizes the selected set on success, and
restores the first still-selected eligible row, else the first eligible row,
else the empty-state Retry. Back returns to the Package 2 server-selection owner
when that was the entry path or otherwise closes setup to the recorded
Player/Guide/Settings invoker without retrying. Build/status/commit failure
renders recovery as Step 3; Retry refreshes authoritative channel status and
returns to Step 3 at `setup-confirm` or `setup-replace-confirm` without
automatically repeating the atomic commit; Back returns to Step 2 at the
selected mode control. Failed whole-panel Retry remains in recovery with
`setup-error-retry` focused. These are the only whole-panel recovery origins;
empty libraries use the Step 1 empty state, empty selection is disabled
validation, and optional item/metadata preview failures remain inline in the
Step 2 strip under `setup-preview-retry`.

Every other Package 3 control role/name, pending rule, invoker restoration,
active-owner registration, and hidden owner `hidden`/`inert`/`aria-hidden`
lifecycle remains frozen. Existing target ids and reservations remain unchanged
apart from the explicit non-modal meaning of `setup-confirm-replace`.

Exact `worker_luna` production write scope for this reopened unit is:

- `src/renderer/staticDom.ts` for the shared panel and state markup only;
- new `src/renderer/setup/setupLibrarySelection.ts` for the pure ordered
  movie/show selection operations (normalize, toggle, select all, clear, and
  cursor fallback); keep it at or below 250 lines and free of DOM/bridge calls;
- new `src/renderer/setup/setupRuntimeCoordinator.ts` for current-server
  section-snapshot freshness, automatic `listLibrarySections()` entry loading,
  item/metadata preview generations and inline status, exact Retry routing, and
  stale completion rejection; keep it at or below 250 lines and call only the
  already-composed renderer-safe Plex callbacks;
- new `src/renderer/setup/setupComposition.ts` for extracting setup controller/
  runtime construction, callback wiring, and render-input projection from
  `index.ts`; keep it at or below 250 lines and do not create a second event or
  state owner;
- `src/renderer/setup/stagedSetupController.ts` for setup-local ordered section
  selection, exact bulk/inline-confirm/build-recovery actions, complete
  `sectionIds` commit input, and the frozen restoration state; it is already
  near its guardrail and must not absorb automatic load, preview request, or
  composition ownership; keep it at or below 500 lines;
- `src/renderer/setup/stagedSetupDom.ts` for shared-panel state/status,
  selected-row/bulk/preview/inline-confirm/recovery projection;
- `src/renderer/setup/stagedSetupFocus.ts` for the exact enabled-control graphs
  above and no other navigation change;
- `src/renderer/channelSetup/liveSelection.ts`, `viewModel.ts`, and `dom.ts` for
  ordered selected-library safe summaries, removal of fake source mode, the
  three real Step 2 choices, preview strip, review, and result markup;
- `src/renderer/plexRuntimeRows.ts` and `plexRuntimeDom.ts` for library-row
  `aria-pressed`/selected truth from the setup-local set while preserving
  `selectedSectionId` as the preview cursor;
- `src/renderer/settingsSetup.ts` and `workflow.ts` only to remove `sourceMode`/
  `selectRecentlyAddedSource` and retain the real Append/Replace draft state;
- `src/renderer/domBindings.ts` for exact revised setup action validation;
- `src/renderer/rendererActionRegistration.ts` for one central delegated-action
  eligibility helper shared by staged-flow and Plex-row click dispatch;
- `src/renderer/index.ts` only to replace existing inline setup construction/
  wiring with `setupComposition.ts`; at its current approximately 645/650-line
  state it may not grow, compress unrelated statements, or absorb new load/
  recovery logic, and must finish at or below 650 lines;
- `src/renderer/styles/setup-workflow.css` and
  `src/renderer/styles/custom-channels.css` for the compact upstream-shaped
  composition; refactor instead of appending and keep each at or below 500
  lines.

The exact test write scope is the prior seven Package 3 files, the two existing
pointer/row-owner suites, and two focused new suites:
`src/__tests__/renderer/channelSetupLiveSelection.test.ts`,
`channelRuntimeActions.test.ts`, `customChannelController.test.ts`,
`customChannelDom.test.ts`, `workflow.test.ts`, `focusDom.test.ts`, and
`routeDom.test.ts`, plus `rendererActionRegistration.test.ts` and
`plexRuntime.test.ts`, plus new `setupRuntimeCoordinator.test.ts` and
`setupWorkflowStyles.test.ts`. Extend them to prove automatic current-server
load success/loading/empty/failure/Retry/Back, optional item and metadata
preview loading/empty/error/Retry/stale behavior, ordered multi-selection,
Select All/Clear All, dedupe/24-item limit, cursor separation, complete commit
arrays, planned after-count arithmetic, removal of sourceMode, real Step 2
rail/detail choices and edges, inline replacement confirmation, whole-panel
recovery origins, single pointer dispatch, ancestor hidden/inert/aria-hidden
and disabled rejection, shared-panel DOM/style contracts, and the exact focus/
restoration graphs. Do not add snapshot or pixel-equality tests.

All other production and test files are out of scope. In particular,
`routeDom.ts`, `focusDom.ts`, `styles.css`, `plexRuntimeActions.ts`,
`plexRuntimeState.ts`,
`plexRuntimeActionDispatch.ts`, custom-channel controllers/actions, contracts,
preload, main, domain, persistence, player/native, package, lockfile, CSP, and
protocol owners may not change. No dependency is added.

The existing `rendererActionRegistration.ts` delegated section-row and staged-
flow click owners remain the only listener owners. Revise them only to share the
central eligibility helper frozen above: the setup-composed section-row handler
gives eligible pointer/OK activation its one setup-local toggle/cursor meaning,
while bulk, fixed-category, strategy, preview, Retry, and inline-confirm controls
continue through one validated staged dispatch. The focused registration test
must prove single dispatch plus disabled/aria-disabled and ancestor hidden/
inert/aria-hidden rejection; do not add another listener owner.

Upstream markup/class organization and CSS patterns may be materially adapted
only from this exact clean source list at
`cbdeaf57b3f59e52330e843005fcf02b3fbd586d`:

- `/Users/tristan/Software/Lineup/src/modules/ui/common/ScreenShellView.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/ChannelSetupScreen.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/steps/LibraryStepController.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/steps/LibraryStepPresenter.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/steps/StrategyStepController.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/steps/BuildReviewStepController.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/steps/BuildProgressStepController.ts`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/styles.core.css`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/styles.library.css`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/styles.strategy.css`;
- `/Users/tristan/Software/Lineup/src/modules/ui/channel-setup/styles.review-progress.css`;
- `/Users/tristan/Software/Lineup/src/styles/shell.onboarding.shared-shell.css`;
- `/Users/tristan/Software/Lineup/src/styles/shell.onboarding.setup.css`.

No style glob or adjacent channel-setup source is authorized. This covers the
reviewed setup behavior and visual DOM/CSS expression only, not upstream browser
session/runtime ownership. The controller—not `worker_luna`—must add or update
the exact provenance row in
`docs/architecture/import-ledger.md` and minimally qualify the historical
reference-only wording in RD20-M09 of
`docs/architecture/original-lineup-reference-compatibility-matrix.md` and
RD20-D09 of `docs/architecture/original-lineup-divergence-register.md`: RD-13
itself was reference-only, while this later Package 3 setup-only behavior/DOM/CSS
adaptation is ledgered separately. No other architecture or workflow doc change
is authorized by this correction.

This unit remains eligible for the configured tracked `worker_luna` role: the
ordered setup-local selection model, exact action ids/focus edges, reduced Step
2, inline confirmation, recovery origins, destination files, direct tests,
capture manifest, and escalation boundary are now exact and cheap to verify.
`worker_luna` must not choose another selection, strategy, confirmation,
recovery, contract, source-owner, or proof model. Rollback removes only this
reopened renderer correction, its fresh
ignored captures/review notes, and its exact provenance qualification while
leaving the previously reviewed Package 3 state/action implementation intact.

Package 3 preserves the clean Package 1 shell and Package 2 auth/profile/PIN/
server owners. `setup-account` and `setup-server` remain mapped evidence for
those already-reviewed onboarding owners and are not redesigned or recaptured
here. The exact Package 3 target ids are `setup-library`, `setup-preview`,
`setup-build`, `setup-custom`, `setup-confirm-replace`, `setup-progress`,
`setup-result`, `setup-recovery-error`, `custom-list`, `custom-edit`, and
`custom-delete-confirm`. These 11 ids retain their existing target reservations
at both DPR-1 viewports, for 22 core Package 3 PNGs. The exact supplemental ids
are `setup-preview-expanded`, `setup-preview-replace`,
`setup-library-loading`, `setup-library-empty`, `setup-preview-error`,
`setup-library-limit`, and the nonduplicative existing
`setup-library-recovery-error`. They prove, respectively, the expanded preview,
Replace-selected Step 2 pane, automatic Step 1 load, valid no-eligible-library
empty result, inline optional preview failure/Retry, 24-item limit message, and
Step 1 request recovery distinct from the core build-origin
`setup-recovery-error`. Seven supplemental ids at both viewports add 14 PNGs;
the reopened manifest therefore contains exactly 36/36 PNGs.

No wholesale `docs/runs/complete-webos-ui-parity-reopen/**` write grant exists.
The exact ignored proof files are:

- `docs/runs/complete-webos-ui-parity-reopen/capture-target.mjs`;
- `docs/runs/complete-webos-ui-parity-reopen/target-entry.ts`;
- `docs/runs/complete-webos-ui-parity-reopen/target-index.html`;
- `docs/runs/complete-webos-ui-parity-reopen/package-3-target-manifest.json`;
- `docs/runs/complete-webos-ui-parity-reopen/update-package-3-evidence.mjs`;
- `docs/runs/complete-webos-ui-parity-reopen/focus-interaction-matrix.json`;
- `docs/runs/complete-webos-ui-parity-reopen/surface-disposition-matrix.json`;
- `docs/runs/complete-webos-ui-parity-reopen/freshness.json`;
- `docs/runs/complete-webos-ui-parity-reopen/package-3-plan-review-handoff.md`;
- `docs/runs/complete-webos-ui-parity-reopen/package-3-implementation-review.md`;
- `docs/runs/complete-webos-ui-parity-reopen/package-3-closeout.md`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-library__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-preview__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-build__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-custom__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-confirm-replace__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-progress__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-result__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-recovery-error__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/custom-list__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/custom-edit__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/custom-delete-confirm__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-preview-expanded__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-preview-replace__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-library-loading__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-library-empty__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-preview-error__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-library-limit__{1280x720,1920x1080}.png`;
- `docs/runs/complete-webos-ui-parity-reopen/target/setup-library-recovery-error__{1280x720,1920x1080}.png`.

`worker_luna` may write only the five ignored harness/manifest files and the 36
exact capture paths above. The controller/reviewer owns the three exact ignored
plan-review/implementation-review/closeout notes. Before delegation and again
for visual closeout as needed, the controller refreezes
`focus-interaction-matrix.json` and `surface-disposition-matrix.json`; after
verification/review it writes `freshness.json` and closeout status as
appropriate. The controller alone owns those three ignored JSON outputs, the
tracked plan, and `docs/architecture/import-ledger.md`,
`docs/architecture/original-lineup-reference-compatibility-matrix.md`, and
`docs/architecture/original-lineup-divergence-register.md`; `worker_luna` must
not edit those ignored controller outputs or tracked docs.

This reopened plan-revise supersedes the initial singular-library and
replacement-modal decisions while retaining the reviewed custom-channel,
renderer-only progress Cancel, and deterministic result Watch corrections.
Capture reservations remain frozen; exact affected focus ids, names, roles,
pending disablement, inertness, and restoration are refrozen here and in the
ignored matrix. The approved renderer-safe API has no
operation that loads an existing channel as an update draft and no public
revision-token builder. Therefore the implementer must not reconstruct main's
private revision string or treat `duplicateChannelDraft` as in-place editing:

- `custom-list` and the list portion of `setup-custom` expose New plus the
  existing per-row Duplicate, Hide/Show, Up, Down, and Delete actions through
  exact ids `custom-channel-new`, `custom-channel-duplicate-<id>`,
  `custom-channel-hide-<id>`, `custom-channel-up-<id>`,
  `custom-channel-down-<id>`, and `custom-channel-delete-<id>`. `custom-list`
  ends at `custom-channel-back`; `setup-custom` ends at `setup-done` then
  `setup-back`. The ignored focus matrix owns the exact linear edges, names,
  button roles, pending disablement, and restoration for the deterministic
  `custom-1` proof row. Hide/reorder restores the corresponding action on the
  changed row. Successful deletion uses post-delete list order to restore the
  nearest surviving row's exact `custom-channel-duplicate-<id>`, or
  `custom-channel-new` when no row survives.
- `custom-edit` is the dedicated editor for either a new blank draft or the
  draft returned by existing `duplicateChannelDraft`. Save uses the existing
  `validateDraft` then `saveDraft` create/duplicate-safe path. Success returns
  to exact `custom-channel-duplicate-<changedChannelId>` when Save returns a
  valid changed channel id, otherwise `custom-channel-new`; validation or safe
  failure retains the draft and restores Save. Cancel discards only the
  uncommitted draft and restores the exact New or Duplicate invoker. While
  `duplicateChannelDraft` is unresolved, its Duplicate invoker is
  disabled/`aria-disabled`, busy, and rejects duplicate key/pointer dispatch;
  safe failure restores that exact Duplicate action.
- `custom-delete-confirm` is a list-level destructive modal opened from the
  exact row Delete action. Cancel/Back restores that Delete invoker. Confirm is
  pending-disabled and, on success, restores the nearest surviving row's exact
  `custom-channel-duplicate-<id>` by post-delete order, or
  `custom-channel-new` when no row survives; safe failure keeps the modal and
  restores Confirm. Its background list and
  editor are inert/nonfocusable while the modal owns input.

This correction is part of the Package 3 plan-review gate and must be reflected
only in the affected implementation/evidence wording when the ignored matrices
are updated; it does not reopen any other Package 0 disposition or Package 1/2
contract. A requirement for true in-place edit is a stop condition requiring a
future reviewed custom-channel contract package.

Initial Package 3 production scope (closed behavior ownership; not the reopened
unit's write scope):

- `src/renderer/setup/stagedSetupController.ts`,
  `src/renderer/setup/stagedSetupDom.ts`, and
  `src/renderer/setup/stagedSetupFocus.ts` (new) own, respectively, renderer-
  local stage/modal/focus-restoration state, the single active setup owner DOM,
  and the frozen Package 3 focus graphs. They consume existing controllers and
  do not call main/preload APIs directly except through already-composed safe
  controller callbacks.
- `src/renderer/staticDom.ts`, `domBindings.ts`, `routeDom.ts`, `focusDom.ts`,
  `rendererActionRegistration.ts`, `workflow.ts`, `index.ts`,
  `plexRuntimeDom.ts`, and `plexRuntimeRows.ts` may change only to remove the
  all-stages setup rail/page, delegate Package 3 composition, register the
  active owner's controls, and preserve Package 2 onboarding. `index.ts` must
  shrink or remain at/below its reviewed 650-line baseline; setup lifecycle,
  Back, and focus policy belong in the new setup owner rather than the
  composition root.
- `src/renderer/channelSetup/liveSelection.ts`, `viewModel.ts`, and `dom.ts`,
  plus `channelRuntimeState.ts` and `channelRuntimeActions.ts`, may change only
  to project the selected safe library, preview/review/build/result/error
  states, duplicate-pending guards, and renderer-generation invalidation.
- `src/renderer/customChannels/controller.ts`, `actionDispatch.ts`, and
  `dom.ts` own only the existing safe operations and the corrected list/new-or-
  duplicate editor/delete-modal presentation. Move request-generation,
  pending, media, and metadata invalidation into new
  `src/renderer/customChannels/operationOwner.ts` before adding view-state
  behavior so `controller.ts` returns to 500 lines or below; do not raise its
  535-line guardrail baseline.
- The initial pass replaced the carried `src/renderer/styles/setup-stages.css` with focused
  `src/renderer/styles/setup-workflow.css` and
  `src/renderer/styles/custom-channels.css`, and update `styles.css` only for
  those imports. The reopened current-unit packet above supersedes the initial
  sparse full-screen active-pane direction with the compact shared upstream
  setup-panel structure. Each stylesheet remains at or below 500 lines and no
  file-shape baseline is raised.

Initial Package 3 test scope was
`src/__tests__/renderer/channelSetupLiveSelection.test.ts`,
`channelRuntimeActions.test.ts`, `customChannelController.test.ts`,
`customChannelDom.test.ts`, `workflow.test.ts`, `focusDom.test.ts`, and
`routeDom.test.ts`. The reopened current-unit scope above retains those seven,
adds the existing `rendererActionRegistration.test.ts` and
`plexRuntime.test.ts` suites, and adds focused
`setupRuntimeCoordinator.test.ts` and `setupWorkflowStyles.test.ts` suites, for
exactly 11 files. Exact initial ignored
proof scope was `capture-target.mjs`,
`target-entry.ts`, `target-index.html`, new
`package-3-target-manifest.json`, new `update-package-3-evidence.mjs`, the 22
reserved target PNGs, and Package 3 review/closeout notes. No other production,
test, tracked doc, or proof file was approved for the initial pass. The reopened
current-unit and controller-owned provenance scope above now supersede that
historical boundary exactly.

The Package 3 state lifecycle is frozen at the seam level without prescribing
routine helper names:

- Entry from the reviewed Package 2 Setup action opens `setup-library` and
  immediately resolves current-server section freshness through
  `setupRuntimeCoordinator`. An absent/stale snapshot starts one automatic
  `listLibrarySections()` generation with Back as the only enabled/focused
  action; a current snapshot normalizes immediately and uses the exact
  selected-row/eligible-row/Select-All focus fallback above. Empty and failed
  results use their distinct Step 1 states and exact Retry/Back behavior. The
  setup-local ordered selected-id set—not Plex `selectedSectionId`—owns channel
  sources. The exact bulk/row/footer graph, disabled skipping, row toggle/cursor
  behavior, source-context invalidation, and restoration are frozen in the
  reopened packet above. Library Next opens `setup-preview` at
  `setup-category-build` whenever at least one id remains selected, regardless
  of optional item/metadata preview status.
- `setup-preview` is the single reduced Step 2 strategy/preview owner. Append,
  Replace, and Custom are real actions; `Recently added`/`sourceMode` is absent.
  The preview strip uses only the current Plex browse cursor and safe metadata;
  it does not change the selected library set. Item/metadata loading, empty, and
  inline error/Retry states follow the exact optional-preview contract above and
  never become whole-panel recovery. Back restores the last selected Step 1
  row, or `setup-select-all` after Clear All. Next opens `setup-build` at
  `setup-confirm` for Append or `setup-replace-confirm` for unconfirmed Replace.
- `setup-build` reviews the complete selected set and persisted safe summary.
  Append Confirm invokes one existing `channelSetup.commit` generation with all
  selected ids in current server order. Replace mode renders the inline
  `setup-replace-confirm` toggle; only its selected state permits Confirm, which
  invokes the same commit with `{ mode: 'replace', confirmReplace: true }`.
  There is no `confirm-replace` staged owner, cancel button, modal inertness, or
  second acceptance transition. Duplicate OK/pointer dispatch is ignored while
  pending. Build Back returns to the selected Step 2 mode control.
- A commit owns `setup-progress` until its current renderer generation settles.
  `setup-progress-cancel` stays enabled while that generation is unresolved;
  activation invalidates only the renderer transition, returns immediately to
  `setup-build`, restores `setup-confirm`, and schedules an authoritative
  status refresh after the underlying promise settles. Duplicate Cancel is
  ignored after invalidation. It never claims to abort the atomic main/domain
  mutation. A true cross-process cancellation requirement stops this package.
- Current-generation commit success opens `setup-result` and focuses
  `setup-done`; Done/Back closes setup and restores the exact Player, Guide, or
  Settings invoker. Watch targets only a deterministic safe returned channel:
  append chooses the lowest-number returned channel whose id was absent from
  the captured pre-commit summary; replace chooses the lowest-number returned
  channel. Ties use channel id ascending. If no such id exists, Watch is absent
  or disabled and omitted from the active focus graph while Done remains.
  Otherwise Watch uses existing renderer-safe `player.tuneChannel`, then
  returns to Player; safe failure retains the result and restores Watch.
  Retryable library and build/status/commit failures use only the exact whole-
  panel origin-specific recovery behavior frozen above; optional preview
  failures remain inline, and no Retry silently repeats an atomic commit.
- `setup-custom` is one list pane, not a simultaneous list/media/editor grid.
  New or Duplicate opens `custom-edit`; media browse/search/filter/metadata and
  draft add/remove remain available inside that active editor through existing
  operations. Delete uses the corrected list-level modal above. Done closes
  setup to its recorded invoker; Back returns to `setup-preview` and restores
  `channel-strategy-build-custom`. Successful save/
  delete/hide/reorder refreshes existing channel status and Guide presentation
  exactly as current dispatch does.

Every transition hides the prior owner with `hidden`, `inert`, and
`aria-hidden="true"`, unregisters its focus ids, and registers only the exact
active focus graph from the Package 3 matrix subject to the correction above.
Pointer equals OK/Enter; editable inputs keep the existing global-shortcut
bypass; Back closes metadata, delete confirmation, or editor before moving one
setup level; the active overflow pane alone scrolls with nearest-focus
visibility. Route, server/profile, Back, modal close, and unload changes
invalidate the affected renderer generations before visible state is mutated.
Setup-library membership changes invalidate channel action state and custom
media/metadata generations but preserve the Step 1 owner and normalized selected
set; changing the Plex browse cursor alone is not a source-context reset. Late
Plex/channel/custom/player completion cannot reopen or overwrite a newer owner.
Safe errors remain actionable and renderer-safe.

Upstream freshness was rechecked for the reopened visual correction at
`cbdeaf57b3f59e52330e843005fcf02b3fbd586d`. The scoped upstream channel-setup,
ScreenShell, and setup-shell files are clean; their scoped delta after
`f91ebe8575bb756adacc5999db8727922a53874a` is empty. The reopened packet above
authorizes the exact setup-local selection/focus behavior and visual DOM/CSS
adaptation from those sources with controller-owned provenance updates; it does
not authorize upstream browser session/runtime ownership, assets, or tests.

No contract, preload, main, domain, Plex transport, persistence, player/native,
dependency, package, lockfile, CSP, protocol, or imported-source change is
approved beyond the exact setup-only behavior/DOM/CSS provenance packet above.
No private account, server, library, media title, token, URL, path,
header, raw payload, native handle, or real persisted data may appear in proof.

Verification is decisive without making native smoke a gate:

- `node --import tsx --test src/__tests__/renderer/channelSetupLiveSelection.test.ts src/__tests__/renderer/channelRuntimeActions.test.ts src/__tests__/renderer/customChannelController.test.ts src/__tests__/renderer/customChannelDom.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/plexRuntime.test.ts src/__tests__/renderer/setupRuntimeCoordinator.test.ts src/__tests__/renderer/setupWorkflowStyles.test.ts` passes with all 11 files green and direct coverage of automatic section load success/loading/empty/failure/Retry/Back, optional item/metadata preview loading/empty/error/Retry/stale behavior, multi-selection/24-limit, exact focus graphs, ancestor hidden/inert/aria-hidden delegated rejection, shared DOM/style structure, and complete commit behavior;
- `npm run typecheck`, `npm run verify:maintainability`,
  `npm run verify:redaction`, `npm run verify:docs`, `npm run verify`, and
  `git diff --check` pass;
- all 11 core target ids plus the seven exact supplemental ids produce the 36
  enumerated DPR-1 captures at `1280x720` and `1920x1080`, with a fresh 36/36
  passing Package 3 manifest. Side-by-side comparison against
  the frozen Package 0 reference captures and the current upstream source must
  confirm the shared compact ScreenShell-like panel, upstream three-step visible
  hierarchy, real multi-library rows/bulk actions, truthful reduced Step 2 and
  its 280px selected Build-mode rail/detail split and preview strip, upstream-
  style review and inline replacement confirmation,
  in-panel progress/result/error, integrated but explicitly
  Desktop-only custom-channel presentation, exact active focus/ARIA semantics,
  no giant sparse owner compositions, and no hidden Package 1/2 owner leakage;
- `npm run smoke:electron` is optional and nonblocking by explicit user
  direction. Focused automation, full verification, exact captures, visual
  inspection, and fresh adversarial implementation review are mandatory.

The initial 67-test/730-test/22-capture Package 3 evidence is retained only as
history and is superseded by the reopened closeout. The controller-observed
exact 11-file renderer suite passed 126/126; controller-owned `npm run verify`
passed 749 source/contract tests and 162 harness-doc tests; typecheck, lint,
maintainability, docs, redaction, and `git diff --check` passed. The final
manifest has 36/36 exact DPR-1 captures and 684/684 semantic assertions; two
complete filename/SHA-256 maps and the post-source-fix recapture are byte-
identical. Direct high-risk inspection plus isolated header pixel crops prove
the complete shared panel/header/step/body/footer paint. Final fresh
adversarial re-review has no material finding. Package 3 is closed and Package
4 has not started.

`worker_luna` must stop, preserve the diff, and escalate if an unlisted file is
required; a frozen target id/role/focus/accessibility/transition contract beyond
the exact multi-select/Step 2/inline-confirm/recovery correction above must
change; the existing `sectionIds` array cannot carry the complete normalized
selection; another strategy family, in-place edit, real progress reporting, or
main build cancellation appears necessary; an existing safe action lacks
indispensable data; a main/preload/contract/domain/Plex transport/persistence/
player/dependency change appears necessary; upstream browser session/runtime
ownership or an unlisted source must be adapted; either setup stylesheet or
`stagedSetupController.ts` would exceed its limit,
`setupRuntimeCoordinator.ts` or `setupComposition.ts` would exceed 250 lines,
`index.ts` would grow from its current approximately 645 lines or exceed 650,
or another hotspot would grow/need a baseline raise; the central delegated-
eligibility helper cannot guard both exact listener paths; exact proof cannot
be reached or sanitized; or any mandatory check/review has a material failure
outside this renderer-only seam. Routine markup/class/CSS and test-assertion
choices inside the exact reopened files remain with the worker.

Replan only if one of those stop conditions proves that visual equivalence
cannot be reached with the existing Desktop-safe capabilities. Do not weaken
the target, add fake controls, broaden contracts, or quietly revert to the
sparse full-screen composition merely to keep implementation moving.

### Reopened correction before Package 4 — Packages 1–3 upstream visual fidelity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_luna` is explicitly eligible. This is
one exact, bounded, cheap-to-verify visual/asset unit. The decisions, write
scope, proof, and stop conditions below leave no product, behavior, focus,
accessibility, IPC, persistence, or architecture choice to the worker.

**CORRECTION STATUS:** closed 2026-07-13. Prior Package 1–3 state machines,
actions, focus ids/graphs, hidden/inert/ARIA rules, keyboard/gamepad/pointer
behavior, accessibility names/states, timers, stale-result handling, errors,
restoration, and supported/omitted Desktop behavior remain frozen. The final
correction passed the exact focused seam, asset-copy, full repository,
two-viewport capture, direct visual-inspection, and clean adversarial re-review
gates. The first implementation review's sole material PIN-sheet finding was
accepted and resolved with the upstream 56px local avatar header, eleven-key
circular keypad, and separate Cancel pill while retaining all twelve frozen
focus/action ids. Package 4 is unblocked but remains unstarted.

Current comparison authority is clean scoped upstream `HEAD`
`4bdb0e1b3370e7893a582ec80226557727832d0b`. Its scoped delta after the reopened
Package 3 pin `cbdeaf57b3f59e52330e843005fcf02b3fbd586d` changes only profile-select
logic/tests, not the referenced CSS or assets. Frozen Package 0 captures remain
useful historical visual evidence, but acceptance for this correction is direct
side-by-side comparison with current upstream source and the matching current
upstream reference states. Relevant reference owners are
`public/lineup-logo-mark.png`, `public/lineup-wordmark.png`,
`src/modules/ui/splash/**`, `common/ScreenShell*`, `common/brandGlyph.ts`,
`common/brandGlyphSource.ts`, `exit-confirm/**`,
`profile-select/**`, `server-select/**`, `channel-setup/**`, and
`src/styles/shell.onboarding.*.css`.

The visual decisions are frozen:

- **Package 1 shell:** replace the CSS-generated splash emblem and text
  wordmark in `shellDom.ts`/`shell.css` with self-hosted copies of the two exact
  upstream PNGs at the frozen production URLs
  `./assets/lineup-logo-mark.png` and `./assets/lineup-wordmark.png`. Both
  `shell-splash` and `shell-loading` reserve and render these two images. Match
  the upstream splash hierarchy, spacing, and relative logo/wordmark scale while
  retaining the frozen Desktop splash/loading copy and lifecycle. Align the
  existing exit-confirm and shared blocking/inline/toast
  surfaces to the same upstream shell language where those selectors already
  apply; do not change their controls, focus, actions, precedence, or timing.
- **Package 2 onboarding:** use current upstream `ScreenShell` structure and
  density: content-sized centered surfaces, `width: min(1440px, 92vw)`, smaller
  upstream-equivalent title/body typography, moderate padding, and a subtle
  panel surface. Replace the profile/server header's generated `L` glyph with
  the canonical color layered-card inline SVG produced by the exact new
  `onboarding/lineupBrandGlyph.ts` helper; every glyph instance scopes all SVG
  ids and `url(#...)`/fragment references uniquely and remains decorative,
  nonfocusable, and `aria-hidden`. Use upstream-sized profile cards and server
  rows. Reshape
  the existing profile PIN owner into the upstream bottom sheet with four dot
  slots and a circular 72px keypad. Preserve all existing safe data, exact focus
  ids, supported actions, error behavior, and the deliberate absence of Sign
  Out and Forget Server.
- **Package 3 setup:** remove the forced `640px` minimum height. Retain
  `width: min(1440px, 92vw)`, `max-height: 85vh`, and bounded body scrolling.
  Restore the upstream visible hierarchy with `Channel Setup` as the primary
  title, the step label/content below it, the current-upstream responsive
  two-column library grid at both target viewports, pill controls, and actions
  adjacent to the relevant content rather than a giant
  pinned full-width footer. Carry that ScreenShell language through Step 2,
  Step 3, progress, result, recovery, and the explicitly labeled Desktop custom
  extension. Preserve the narrower truthful Build-mode behavior, exact setup
  state/action/focus contracts, and custom-channel behavior already reviewed.
  Library rows become one column only at the upstream `max-width: 600px`
  breakpoint; no target capture in this unit exercises that breakpoint.

The asset/runtime seam is exact:

- copy upstream `public/lineup-logo-mark.png` to
  `src/renderer/assets/lineup-logo-mark.png` and
  `public/lineup-wordmark.png` to
  `src/renderer/assets/lineup-wordmark.png` without modification. At the pinned
  commit their SHA-256 values are respectively
  `14f10fcf1af745ac156a5154d29ff4a31aa5c28b80b662a2a644551fa9aa1f4d`
  and `4293f5a3129d6edd38b602329a51cf5010f510326aebf02ab067204d9a771c95`.
- adapt upstream `src/modules/ui/common/brandGlyph.ts` and the `color` entry in
  `brandGlyphSource.ts` into one renderer-only
  `src/renderer/onboarding/lineupBrandGlyph.ts`: it owns the canonical color
  layered-card SVG string, creates the decorative host/SVG, and scopes ids per
  instance. It exposes no variant choice and performs no bridge/network work.
- extract a pure `src/main/rendererProtocolPolicy.ts` that owns the existing
  `lineup://shell` scheme/host/search/root/path/traversal checks plus the exact
  `.html`/`.js`/`.css`/`.png` content-type resolution. `protocol.ts` consumes
  that decision, adds no second validation path, and retains CSP header/file
  response composition and `net.fetch(pathToFileURL(...))`. The `.png` mapping
  is exactly `image/png`; all other rejection behavior remains unchanged. Its
  single exported resolver accepts `(urlText, rendererRoot)` and returns either
  `{ ok: true, filePath, contentType, isIndex }` or `{ ok: false }`; malformed
  URL/percent encoding, wrong scheme/host, nonempty search, root/empty path,
  traversal/absolute escape, and unlisted extension all return `{ ok: false }`
  without filesystem access or throw.
- make `tools/copy-renderer-assets.mjs` recursively copy
  `src/renderer/assets/**` to `dist/renderer/assets/**` in addition to its
  existing HTML/CSS/style copies. The existing CSP already permits only
  `img-src 'self'`; do not change it.
- no other MIME, private/remote asset, data URL, query-bearing asset request,
  broad asset handler, dependency, package/lockfile, or build configuration is
  authorized.

Exact production write scope is only:

- `src/renderer/assets/lineup-logo-mark.png` and `lineup-wordmark.png` (new);
- new `src/renderer/onboarding/lineupBrandGlyph.ts` for the exact canonical
  color SVG/scoping adaptation above;
- `src/renderer/shell/shellDom.ts`, `src/renderer/staticDom.ts`, and
  `src/renderer/profilePinModal.ts` for the exact image elements and upstream-
  shaped visual wrappers, without action/state/focus changes;
- `src/renderer/styles/shell.css`, `plex-auth.css`,
  `plex-profile-server.css`, `plex-onboarding-cards.css`,
  `profile-pin-modal.css`, `setup-workflow.css`, and `custom-channels.css` for
  the frozen geometry/style correction; `plex-onboarding-cards.css` is the
  canonical profile/server card geometry owner, while
  `plex-profile-server.css` owns screen/list/state treatment;
- new pure `src/main/rendererProtocolPolicy.ts`, `src/main/protocol.ts`, and
  `tools/copy-renderer-assets.mjs` for the exact static PNG seam above; and
- `docs/architecture/import-ledger.md` for the two exact asset rows and one
  exact brand-glyph adaptation row.

Exact automated test write scope is only new
`src/__tests__/main/rendererProtocolPolicy.test.ts`, new
`src/__tests__/renderer/lineupBrandGlyph.test.ts`,
`src/__tests__/renderer/profilePinModal.test.ts`,
`src/__tests__/renderer/rendererRuntimeOwners.test.ts`,
`src/__tests__/renderer/setupWorkflowStyles.test.ts`, and new
`tools/__tests__/copy-renderer-assets.test.mjs`. Assertions must prove the PNG
MIME allowlist remains guarded, nonapproved extensions/hosts/search/traversal
remain rejected, brand glyph instances have distinct ids with correctly scoped
references, both exact production URLs are referenced, the built assets are
copied recursively with SHA-256 equality to source, and the frozen PIN/setup
structural rules above are present. `shellSecurity.test.ts` remains unchanged
unless an actually observed existing security assertion requires adjustment;
that is otherwise a stop/escalation condition. Do not add broad snapshots or
duplicate the existing behavior/focus suites.

Exact ignored proof scope is existing
`docs/runs/complete-webos-ui-parity-reopen/capture-target.mjs`,
`target-entry.ts`, `target-index.html`, and new `vite-target.config.mjs` only
where needed to reach the frozen states and serve/map `src/renderer` assets for
this harness; new `packages-1-3-fidelity-target-manifest.json` and
`update-packages-1-3-fidelity-evidence.mjs`; and exactly 68 PNGs under
`target/packages-1-3-fidelity/`: both `1280x720` and `1920x1080` DPR-1 variants
for the nine Package 1 ids, seven Package 2 ids, and eighteen Package 3 ids
already enumerated in their package sections. The controller owns the ignored
`packages-1-3-fidelity-implementation-review.md` and
`packages-1-3-fidelity-closeout.md`; no other capture id, tracked doc, source,
test, or proof file is approved.

The target harness must wait for both branded `<img>` elements on splash and
loading before capture and fail rather than capture a fallback when either
image is not ready. For each image, readiness requires `complete === true`,
`naturalWidth > 0`, and `naturalHeight > 0`. Both state/viewports' manifest rows
record those positive assertions, the exact production URL, source/build asset
SHA-256, and equality status. The two reserved splash/loading PNG pairs are
mandatory members of the 68 captures.

Verification is mandatory and direct:

1. `node --import tsx --test src/__tests__/main/rendererProtocolPolicy.test.ts src/__tests__/renderer/lineupBrandGlyph.test.ts src/__tests__/renderer/profilePinModal.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/setupWorkflowStyles.test.ts` passes.
2. `node --test tools/__tests__/copy-renderer-assets.test.mjs` passes.
3. Re-run the existing exact Package 1, Package 2, and Package 3 focused renderer
   commands printed above; all remain green with no behavior/focus contract
   change.
4. `npm run typecheck`, `npm run verify:maintainability`,
   `npm run verify:redaction`, `npm run verify:docs`, `npm run verify`, and
   `git diff --check` pass. Native/Electron smoke remains optional and
   nonblocking by explicit user direction.
5. Generate all 68 fresh exact-size captures. The manifest must prove DPR 1,
   exact PNG dimensions, sanitized state, and the pinned Desktop/upstream
   commits. Direct side-by-side inspection against current upstream source and
   reference states must confirm actual logo assets and splash scale; shared
   ScreenShell hierarchy/density; upstream-sized cards/rows and bottom-sheet PIN
   geometry; content-sized setup composition with the upstream two-column grid
   at both target viewports, pills, and nearby actions; positive image readiness
   and manifest/hash assertions for splash/loading; no reappearance of old
   dashboard/long-form layout; and no
   clipped, sparse, hidden-owner, reduced-motion, forced-colors, or 1280px
   regression.
6. A fresh read-only adversarial implementation review must report no material
   finding before the controller closes this correction and unblocks Package 4.

Acceptance requires visual structure/style to be materially equivalent to the
current upstream owners at both viewports while retaining the exact Desktop
adaptations above. Pixel identity is not required where copy, platform action,
or narrower supported behavior is intentionally different, but component
hierarchy, proportions, density, surface treatment, and control geometry must
match closely enough that the Desktop UI reads as the Windows port of the same
app rather than the prior layout. Specifically, both target viewports show the
upstream two-column library grid, profile/server headers use the uniquely scoped
canonical color glyph, and splash/loading show complete nonzero-dimension PNGs
at the frozen production URLs; one-column setup is accepted only at `<=600px`.

`worker_luna` must stop, preserve the diff, and escalate only if an out-of-scope
behavior/focus/accessibility/IPC/contract/persistence/player/Plex/native change,
new dependency, other MIME, private/remote asset, unlisted file, CSP change,
new owner boundary, baseline raise, or unsanitizable proof is required; if the
asset hashes/source pin do not match; the pure protocol-policy extraction cannot
preserve the existing default-session registration/response architecture; the
brand-glyph adaptation would require unsafe inline HTML or cannot scope every id
reference; the harness cannot prove image readiness/hash equality; or if a
mandatory test/capture/review
failure cannot be fixed inside this exact seam. Ordinary markup/class/selector
choices and small geometry fixes inside the exact scope are implementation
choices and must not block progress.

### Package 4 — Persisted Settings seam and Settings screen parity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only. This cross-process persistence unit is never eligible for `worker_luna`.

Scope is the exact Settings contract/store/IPC/preload/renderer files listed under `Files In Scope`, plus `docs/architecture/security-and-secret-flow.md`. `src/preload/index.cts` receives minimal namespace binding only; request/result guards and bridge construction live in the two new focused preload modules. Remove renderer-session-only copy and inert labels for persisted values.

The exact Package 4 renderer consumer list is frozen to `src/renderer/index.ts`, `src/renderer/workflow.ts`, `src/renderer/staticDom.ts`, `src/renderer/focusDom.ts`, `src/renderer/domBindings.ts`, `src/renderer/routeDom.ts`, `src/renderer/epg/guideDom.ts`, `src/renderer/plexRuntimeDom.ts`, `src/renderer/plexRuntimeRows.ts`, `src/renderer/settingsSetup.ts`, `src/renderer/settingsSetupDom.ts`, and new `src/renderer/settings/settingsRuntime.ts`. `src/renderer/plexRuntimeDom.ts` is required because it is the only current caller that can propagate `previewBadgesEnabled` into the setup-preview row renderers in `plexRuntimeRows.ts`.

The exact Package 4 CSS list is frozen to `src/renderer/styles.css`, `src/renderer/styles/workflow-screens.css`, new `src/renderer/styles/settings.css`, and `src/renderer/styles/guide-epg.css`. The focused `settings.css` extraction is already authorized and required by the Architecture Health decision and the global `src/renderer/styles/**` scope. `guide-epg.css` may not grow above its 506-line allowlist baseline: implement density behavior through net-neutral or shrinking rules, or stop for reviewed extraction.

`src/renderer/rendererActionRegistration.ts` remains excluded unless discovery proves that its existing action vocabulary or signature must change; if so, stop and return to the controller rather than self-authorizing it. `src/renderer/styles/player-overlays.css`, `src/renderer/styles/setup-workflow.css`, and `src/renderer/styles/responsive-accessibility.css` are also outside the exact Package 4 packet.

Frozen product values and consumers:

- `launchMode: 'windowed' | 'fullscreen'`, default `'windowed'`. After the initial Settings snapshot resolves and before the first stable product render, apply it through the existing `window.lineupDesktop.window.setFullscreen(value === 'fullscreen')` intent. On user change, issue that existing window intent immediately; persist only after the intent succeeds. If persistence fails, restore the last accepted value and issue the inverse fullscreen intent. Surface a renderer-safe failure if either forward or rollback intent fails.
- `guideDensity: 'comfortable' | 'compact'`, default `'comfortable'`. It controls a real Guide root `data-guide-density` state and materially different row height, cell padding, and visible-row density in Guide CSS at both target sizes.
- `previewBadgesEnabled: boolean`, default `true`. It controls actual renderer visibility of nonessential preview/quality/meta badges in Guide/player/setup previews. It must never hide channel identity, current/live state, errors, warnings, accessibility names, or media-option selection truth.
- `setupReminderEnabled: boolean`, default `true`. It controls an actual nonessential setup reminder banner/action shown from the no-channel Player/Guide journey. Hiding it must not remove Settings, Guide empty-state setup action, direct setup navigation, or any core recovery path.

No other user preference is added. Upstream audio/subtitle, HDR, appearance, account, and developer rows without existing Desktop runtime contracts remain reviewed divergences. Support-bundle export is an action/status, not persisted Settings data.

Frozen version-1 storage policy:

```text
{
  "schemaVersion": 1,
  "revision": <non-negative safe integer>,
  "values": {
    "launchMode": "windowed" | "fullscreen",
    "guideDensity": "comfortable" | "compact",
    "previewBadgesEnabled": <boolean>,
    "setupReminderEnabled": <boolean>
  }
}
```

- The main-owned path is `<appData>/lineup-desktop-settings.json`, resolved by a new focused `resolveDesktopSettingsFilePath` path owner; neither absolute path nor filename reaches renderer output.
- `ENOENT` returns defaults, revision `0`, status `'missing'`, and does not create a file. A valid record returns status `'ready'`.
- JSON parse failure, non-object input, unknown top-level or `values` keys, missing keys, invalid literal/type, unsafe revision, or schema version that is missing/non-integer is status `'corrupt'`: return defaults at revision `0`, do not rewrite on read, and allow a subsequent replacement with `expectedRevision: 0` to repair it.
- A well-formed integer `schemaVersion` other than `1` is status `'unsupported-version'`: return defaults at revision `0`, do not rewrite, and reject replacement with error code `'unsupported-version'` until a reviewed migration plan exists.
- All reads and replacements run inside one store-owned promise chain. A replacement rereads the authoritative record within that chain, compares `expectedRevision`, writes the complete next record with revision `current + 1`, and never merges fields in main.
- Write creates the parent directory, writes complete JSON plus newline to a same-directory `${settingsFilePath}.${process.pid}.${counter}.tmp` file with mode `0o600`, hardens the temp file to `0o600`, then atomically renames it over the authoritative file; no fallible step follows the rename. The authoritative old file and revision remain unchanged on mkdir/write/chmod/rename failure; the temp file is removed best-effort. Orphan temp files are never promoted and may be removed best-effort by the next successful replacement.
- Concurrent or stale replacements cannot overwrite newer state: an `expectedRevision` mismatch returns `'revision-conflict'` without writing. There is no renderer-owned filesystem retry or alternate storage fallback.

Frozen renderer-safe contract in `src/contracts/settings.ts`:

- `SETTINGS_SCHEMA_VERSION = 1`.
- `DesktopSettingsValues`, with exactly the four fields/literals above.
- `DesktopSettingsLoadStatus = 'ready' | 'missing' | 'corrupt' | 'unsupported-version'`.
- `DesktopSettingsSnapshot = { schemaVersion: 1; revision: number; status: DesktopSettingsLoadStatus; values: DesktopSettingsValues }`.
- `DesktopSettingsGetSnapshotRequest = { requestId: string }`.
- `DesktopSettingsReplaceRequest = { requestId: string; expectedRevision: number; values: DesktopSettingsValues }`; replacement is whole-snapshot, never patch semantics.
- A request id must match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$`; `expectedRevision` and snapshot `revision` are integers from `0` through `Number.MAX_SAFE_INTEGER`.
- `DesktopSettingsErrorCode = 'unauthorized' | 'validation-failed' | 'revision-conflict' | 'storage-unavailable' | 'unsupported-version' | 'operation-failed'`.
- `DesktopSettingsIpcResult<T>` is exactly `{ ok: true; value: T; requestId: string } | { ok: false; error: { code: DesktopSettingsErrorCode; message: string }; requestId: string }`. Messages are fixed renderer-safe copy with no path, raw error, persisted content, or process detail.
- `SETTINGS_INVALID_REQUEST_ID = 'settings-invalid-request'` is the valid constant fallback id for a missing or invalid request id.
- The one allowed message per error code is exact: `unauthorized` → `Desktop settings request was not authorized.`; `validation-failed` → `Desktop settings request or response was invalid.`; `revision-conflict` → `Desktop settings changed; refresh and try again.`; `storage-unavailable` → `Desktop settings storage is unavailable.`; `unsupported-version` → `Desktop settings require a newer compatible version.`; `operation-failed` → `Desktop settings operation failed.` No layer may substitute exception text, paths, record content, invoke details, or another message for these codes.

Frozen IPC/preload API:

- channel literals are `LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL = 'lineup:settings:getSnapshot'` and `LINEUP_SETTINGS_REPLACE_CHANNEL = 'lineup:settings:replace'` in `src/contracts/ipc.ts`;
- `window.lineupDesktop.settings.getSnapshot(input: DesktopSettingsGetSnapshotRequest): Promise<DesktopSettingsIpcResult<DesktopSettingsSnapshot>>`;
- `window.lineupDesktop.settings.replace(input: DesktopSettingsReplaceRequest): Promise<DesktopSettingsIpcResult<DesktopSettingsSnapshot>>`;
- both public methods are total: their promises never reject. Every expected renderer, preload, invoke, main-handler, or store failure resolves a typed `DesktopSettingsIpcResult`. Main handlers catch and translate failures; preload catches `ipcRenderer.invoke` rejection and resolves a typed failure; renderer code may retain a defensive catch for a nonconforming bridge but may emit only the same typed generic failure and never a raw error;
- a valid request id is echoed unchanged on every success or failure. Missing/invalid request id uses `SETTINGS_INVALID_REQUEST_ID` consistently in preload and main. A malformed request caught by preload returns `validation-failed` with the fallback id and must not invoke main. A malformed request reaching main returns the same code/fallback id;
- preload rejects non-exact request/result shapes, unsafe revisions, unknown keys, invalid settings literals, and result request-id mismatch by resolving `validation-failed`. A result-id mismatch uses the original valid request id, or the fallback when the original id was invalid;
- main authorizes both handlers through the existing shell sender/main-frame/origin policy. `getSnapshot` is read-only; `replace` validates then delegates the whole-record compare-and-swap to the store.

Frozen failure classification:

- sender, origin, or main-frame denial → `unauthorized`;
- malformed renderer request, malformed main request, malformed preload result, or result request-id mismatch → `validation-failed`;
- `ipcRenderer.invoke` rejection or an unexpected handler/store exception → `operation-failed`;
- non-`ENOENT` read/open/stat failure → `storage-unavailable`;
- supported-schema parse/shape corruption remains a successful snapshot with status `'corrupt'`;
- a well-formed but unknown schema version → `unsupported-version`;
- `expectedRevision` mismatch → `revision-conflict`;
- mkdir, write, chmod, rename, or a primary temp-cleanup failure during save → `operation-failed`, with old authoritative bytes and revision preserved. A best-effort temp-cleanup failure after another failure never replaces the primary classification/message or exposes cleanup detail.

Frozen renderer concurrency/lifecycle behavior:

- a focused Settings runtime controller owns monotonic request ids (`settings-get-<counter>` and `settings-replace-<counter>`), the last accepted snapshot, one in-flight replacement, and one coalesced latest desired whole snapshot;
- stale responses whose request id/generation is not current never mutate UI/runtime state;
- a revision conflict triggers one fresh `getSnapshot`, then one rebase of the latest desired whole snapshot against the returned revision. A second conflict surfaces an error and stops automatic retry;
- non-launch consumers update immediately and roll back to the last accepted snapshot on replacement failure. `launchMode` follows the window-intent ordering and rollback rule above;
- cleanup on unload invalidates the generation, drops queued desired state, and prevents late responses from rendering. The API has no event subscription or background timer to leak.

Exact regression/contract tests:

- `src/__tests__/contracts/settingsContracts.test.ts` (new): exact values/snapshot/request/result guards, forbidden unknown keys, literal/default vocabulary, fallback request id, exhaustive code-to-one-message mapping, error/status code coverage, and renderer-safe field audit.
- `src/__tests__/main/settingsPersistence.test.ts` (new): ENOENT, valid load, corrupt/unknown/missing-field success policy, unsupported version, non-ENOENT storage-unavailable mapping, repair from revision `0`, serialized replacements, revision conflict, monotonic revision, exact file shape/mode, temp rename, every fatal save failure mapping, failed write/rename/cleanup preserving old bytes and revision, secondary cleanup failure preserving the primary mapping, orphan-temp non-promotion, and no raw rejection/detail.
- `src/__tests__/main/settingsIpc.test.ts` (new): authorization, exact request validation, fallback/valid request-id behavior, echo on every result, get/replace channel/result behavior, every failure-class code/message mapping, handler/store exception capture, promises resolving instead of rejecting, no path/raw error leakage, and no write on validation/conflict/unsupported version.
- `src/__tests__/integration/preloadContractVocabulary.test.ts`: both exact channel literals, one Settings namespace, only `getSnapshot`/`replace`, request/result guard parity, malformed request short-circuit without invoke, invoke rejection capture, result-id mismatch, fallback/echo behavior, no rejected public promise, exhaustive code/message preservation, and no added direct `ipcRenderer` owner outside reviewed preload composition.
- `src/__tests__/renderer/settingsSetup.test.ts` and `src/__tests__/renderer/settingsRuntime.test.ts` (new): defaults, each real consumer, initial launch-mode intent, immediate changes, whole-snapshot replace, coalescing, conflict refetch/rebase-once, stale response ignore, all typed failure mappings, defensive catch producing only generic `operation-failed`, no rejected/raw error propagation, failure rollback, cleanup, support-bundle separation, focus restoration, and core setup navigation preserved when reminder is hidden.
- `src/__tests__/renderer/workflow.test.ts`: replace the renderer-session-only Settings expectation, local-only `applyWorkflowSettingsAction` behavior, and stale `settingsDraft` field assertions with truthful persisted-runtime integration expectations while preserving workflow navigation, focus, and support-status coverage.
- `src/__tests__/renderer/supportBundleExport.test.ts`: preserve safe support-bundle status behavior while updating the current `settingsDraft.guideDensity` and local Settings-action assertions to the persisted Settings runtime ownership.

Run Codanna impact analysis for the new public Settings symbols if indexed; otherwise record `rg` import fallback. Verification uses the exact Package 4 command below, all architecture/redaction/smoke/full gates, a real relaunch proof for all four values, malformed/corrupt/unsupported record proof without private/path output, and adversarial review. Expected: every visible Settings value has real behavior and survives relaunch; writes are compare-and-swap/atomic; failed or stale work cannot lose newer state; renderer/browser storage is absent; preload remains narrow; security/secret-flow docs are current; and support bundle still works.

Exact Package 4 command: `node --import tsx --test src/__tests__/contracts/contracts.test.ts src/__tests__/contracts/settingsContracts.test.ts src/__tests__/main/settingsPersistence.test.ts src/__tests__/main/settingsIpc.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts src/__tests__/renderer/settingsSetup.test.ts src/__tests__/renderer/settingsRuntime.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/supportBundleExport.test.ts`. All nine files must pass before `npm run typecheck`, `npm run test:contracts`, `npm run verify:architecture`, `npm run verify:maintainability`, `npm run verify:redaction`, `npm run smoke:electron`, and `npm run verify` are run and observed passing.

### Package 5 — Scheduler-backed Guide parity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only.

Scope is Guide renderer presentation/state/polling/DOM/focus/CSS/tests. Decompose `epg.ts` and `guide-epg.css` first. Use existing Guide runtime presentation and persisted channels; no fixture fallback in production. Prove ready, loading, actionable no-channel empty, no-program empty, failure, stale-result, refresh, time-window, channel/program navigation, current marker, clipped cell, detail, tune, back, focus restoration, and cleanup states at both sizes.

No new scheduler, channel, main, preload, or contract behavior is approved. If existing renderer-safe Guide data cannot represent a required target state, stop for a reviewed replan rather than synthesizing it.

Verification: `node --import tsx --test src/__tests__/main/guideRuntime.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/epgStateUpdate.test.ts src/__tests__/renderer/epg/guideDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/workflow.test.ts`; `npm run typecheck`; `npm run verify:maintainability`; `npm run smoke:electron`; `npm run verify`; both-size captures for every matrix state; adversarial review. Expected: the six named files pass; persisted-channel schedules render when present; empty is honest/actionable when absent; no default demo schedule reaches product; and navigation/tune behavior matches the frozen matrix.

### Package 6 — Runtime player surface and overlay state-machine parity

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only.

Scope is renderer player presentation aggregation, fixture isolation, overlay state/actions, focus/input, CSS foundation, and tests. Remove `createRendererPresentationFixtures()` from product `index.ts`; derive overlay/channel/program presentation from existing safe player snapshot plus Guide/channel runtime state. Player idle shows the native presentation surface with no default route card and no default overlay stack. Define upstream-informed actions and precedence for OSD, now-playing info, mini guide, options, badge, number input, transition/loading/error, fullscreen, tune, and Back.

The overlay state machine must enforce the matrix rather than “stack every requested overlay.” Default state is no overlay. Transient badges/transitions require real events and timers with cleanup. Modal overlays own focus and restore it on close. Fixture modules remain test/dev-only and an automated source test must prevent production imports.

Verification: `node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/workflow.test.ts`; `npm run typecheck`; `npm run verify:maintainability`; `npm run verify:redaction`; `npm run smoke:electron`; `npm run verify`; windowed/fullscreen captures at both sizes; adversarial review. Expected: the six named files pass; no fixture copy or simultaneous default overlays remain; modal/transient precedence matches the frozen matrix; player/guide state is runtime-safe; and no native/secret material leaks.

### Package 7 — Player overlay visual surfaces

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only.

Scope is focused overlay DOM/CSS/view-model owners and tests after Package 6 freezes behavior. Split `player-overlays.css` by OSD, now-playing, mini-guide, playback-options, and transient overlay families. Adapt upstream hierarchy/density for OSD, now playing, mini guide, playback options, badge, number entry, and channel transition while retaining only real Desktop actions. Unsupported Sleep/latency/artwork controls are omitted with explicit matrix divergences; honest artwork-empty states are allowed, fake artwork is not.

Verification: `node --import tsx --test src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts`; `npm run typecheck`; `npm run verify:maintainability`; `npm run verify:redaction`; `npm run smoke:electron`; `npm run verify`; every overlay state over the player surface in windowed/fullscreen at both sizes; reduced-motion/forced-colors checks; adversarial review. Expected: the five named files pass; each surface is visually/interactively comparable to the upstream reference; overlays remain readable over video; and Package 6 choreography does not regress.

### Package 8 — Integrated target proof, document correction, and closeout

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only.

Scope is verification/evidence and tracked memory only unless review finds a defect, in which case route back to the owning package instead of patching broadly here.

- recapture every target matrix row at exact `1280x720` and `1920x1080` in windowed mode and all player/overlay rows in fullscreen, completing the three-way WebOS reference → Desktop pre-package baseline → Desktop post-package target proof for every state/resolution;
- compare baseline → upstream reference → Desktop target, recording pass/fail/divergence with reviewer-visible reasoning;
- complete every focus/interaction row with automated/manual proof ids and no `unknown` cells;
- rerun redaction scan over the local proof bundle before review;
- run `npm run test:contracts`, `npm run typecheck`, `npm run verify:architecture`, `npm run verify:maintainability`, `npm run smoke:electron`, `npm run verify:redaction`, `npm run verify:docs`, `npm run verify`, and `git diff --check`; every command must exit successfully and its observed output must be recorded in the closeout packet;
- request final integrated adversarial review in addition to the per-package reviews;
- correct roadmap, current state, renderer architecture, `docs/architecture/security-and-secret-flow.md`, `docs/development/windows-ui-proof-plan.md`, product parity, audit, compatibility/divergence, import ledger, and plan conclusions to exactly match observed results;
- do not mark parity complete if any required capture, interaction row, reviewer finding, verification command, or runtime-backed state is missing;
- only after clean review and verification, archive this plan according to repo policy and route to a fresh RD-27 plan/quality-loop session.

Expected: the running app and all tracked claims agree; RD-27 is unblocked only by observed closeout, not by source/test inference.

## Dependencies, Order, And Parallelism

Order is strict:

1. Package 0 establishes truthful authority, baseline/reference evidence, and the reviewed decision-complete target focus/interaction matrix. Its behavior/ownership columns are frozen before Package 1; later packages update evidence/result columns only.
2. Package 1 removes the shell/focus structure that every later surface inherits.
3. Package 2 closes onboarding states before setup recomposition.
4. Package 3 closes the setup journey.
5. The consolidated Packages 1–3 visual-fidelity correction closes direct current-upstream structure/style parity without reopening behavior.
6. Package 4 adds the sole new product cross-process Settings seam.
7. Package 5 closes Guide runtime presentation.
8. Package 6 freezes player runtime truth and overlay choreography.
9. Package 7 applies overlay visual parity on the reviewed state machine.
10. Package 8 integrates proof and closeout.

No production package runs in parallel with another production package because all share renderer composition/focus/style owners and each next baseline depends on the prior review. Read-only upstream source comparison, capture manifest preparation, and review packet assembly may run in parallel only when they write no shared tracked files. One reviewed commit per package is preferred. A package cannot advance while a material finding remains unresolved.

## Import Ledger Obligations

- Package 0 visual capture/reference authority remains pinned to `6ef20801019e1d1aae2a0158128eba9142d0d008`. Package 1 closed against `196a54765c0c6f782ef78c52382de92f1ca1bfd2`; Package 2 onboarding freshness is reviewed through `5a96aaf52680107a8090db88d5bd8268bbea1c61`. Later packages refresh current upstream `HEAD` before copying/adapting without silently replacing earlier frozen captures.
- Package 2 adapts only `/Users/tristan/Software/Lineup/src/modules/ui/auth/plexLinkQrSvg.ts` at `5a96aaf52680107a8090db88d5bd8268bbea1c61` into `src/renderer/onboarding/plexLinkQr.ts`; its import-ledger row must name the static `plex.tv/link` payload, DOM-safe Desktop rendering adaptation, focused tests, Apache-2.0 provenance, absence of account/token/runtime data, and revisit trigger. All other Package 2 upstream auth/profile/server source is reference-only.
- Before or with the Packages 1–3 correction, add exact Apache-2.0 import-ledger rows for current-upstream `public/lineup-logo-mark.png` and `public/lineup-wordmark.png` at `4bdb0e1b3370e7893a582ec80226557727832d0b`, including their source/destination paths, unchanged-copy classification, SHA-256 values frozen above, splash/loading consumers, asset/protocol/copy tests, and revisit trigger. Add one exact adaptation row for `src/modules/ui/common/brandGlyph.ts` plus the `color` source in `brandGlyphSource.ts` into `src/renderer/onboarding/lineupBrandGlyph.ts`, naming unique SVG-id/reference scoping, decorative semantics, profile/server consumers, focused tests, removal of the unused variant/trusted-inline helper dependency, and the same commit/license. All compared DOM/CSS remains independently expressed and reference-only.
- Copied or adapted upstream TypeScript, CSS, markup, copy, assets, or tests require an import-ledger row before or in the same commit, naming exact source path, commit, Desktop owner, adaptation, retained/new tests, removed WebOS assumptions, license/provenance, and follow-up trigger.
- “Reference only” is valid only when the implementation is independently expressed; record the comparison paths in the package evidence without claiming copied source.
- The prior UI-parity/import-ledger posture is not blanket authorization for the current `6ef208...` checkout. Update an existing row only if the exact source slice/owner remains accurate; otherwise add a new row.
- Never copy upstream dirty/untracked user files or generated assets.

## Planner Self-Check

1. **Any unresolved product, architecture, ownership, dependency, or verification decision?** No. The current correction freezes its exact upstream pin, visual outcomes, asset hashes, PNG-only protocol/build seam, write scope, proof, and escalation rules. Package 4 retains the sole new product cross-process Settings seam.
2. **Adjacent contract/type changes omitted?** No. The correction needs no contract/type/IPC change; Package 4 includes its exact Settings contracts, IPC, preload, main, renderer, and tests.
3. **Any out-of-scope file relied on for hidden wiring?** Existing player/guide/Plex/channel owners are consumed through current public seams and are frozen. If those seams prove insufficient, the package stops.
4. **Evidence and fallback recorded?** Yes. Codanna UI/doc results were noisy/broken; direct reads, CDP runtime observation, and scoped upstream reads are the reliable evidence.
5. **Repo-preferred owners or hotspot growth?** Repo-preferred owners are used. Every affected hotspot has an extraction/avoidance decision.
6. **Tier 3 Architecture Health complete?** Yes. Current large files, no-growth decisions, decomposition requirements, and maintainability command are explicit.
7. **Would a fresh implementer invent security, IPC, playback, persistence, packaging, import, or verification policy?** No. Renderer/main/preload ownership, Settings schema/record/status/error/channel/method/revision/stale/write policies, frozen runtime seams, no-dependency policy, provenance, and proof are decided.
8. **Exact verification, expected outcomes, and replan triggers present?** Yes. Every package names an executable concrete test command or the exact full suite, expected outcomes, visual/focus proof, review gate, and replan triggers; no test-name placeholder remains.

## Architecture Seam Decision Gate

Chosen seams:

- renderer-owned screen/overlay composition consuming existing renderer-safe runtime APIs;
- new pure renderer-protocol policy plus the existing main protocol/build owners serving and copying two exact self-hosted PNGs without CSP/session drift;
- one new main-owned Settings persistence seam with renderer-safe contract and narrow preload bridge;
- local ignored visual/focus evidence with tracked conclusions only.

Forbidden shortcuts:

- broad preload RPC or arbitrary IPC channel strings;
- renderer/browser storage for persisted Settings;
- fixture fallback in reachable production player/Guide/overlay UI;
- raw Plex/media/artwork URLs, tokens, headers, payloads, file paths, native handles, or Electron/Node objects in renderer state;
- old upstream path/class compatibility shims;
- permanent product debug/navigation chrome;
- raising file-size baselines to permit growth;
- adding fake upstream-only controls to satisfy a screenshot;
- closing a package from source/test assertions without the required visual and focus evidence.

Stop and replan if a target state requires a new player/Guide/Plex/channel/artwork contract, protocol change beyond the exact `.png` MIME addition, CSP change, native-helper behavior, dependency, packaging change, or a settings schema beyond the four approved values.

## Verification Commands

**Verification classification:** broader integration/manual proof required

This classification fits because public renderer behavior, a new Settings contract seam, Electron runtime composition, focus, layout, fullscreen media UI, and visual parity all need different proof. New stable behavior tests are required inside packages; screenshots alone are insufficient.

Run after tracked docs-only Package 0:

- `npm run verify:docs` — active plan and corrected authority docs pass structural/link/policy checks.
- `npm run verify:redaction` — no forbidden private material lands in tracked files.
- `git diff --check` — no whitespace errors.

Run after every source package:

- the exact `node --import tsx --test ...` command printed in that package — every named current/new test file passes; Package 4 and Package 8 additionally run the full `npm run test:contracts` suite;
- `npm run typecheck` — renderer and cross-process types align;
- `npm run verify:maintainability` — no unreviewed hotspot or topology growth;
- `npm run smoke:electron` — built Electron shell reaches each owned surface with containment intact; Packages 2 and 3 are explicit user-authorized exceptions where this command is optional/nonblocking and recorded only if attempted;
- `npm run verify:redaction` — no forbidden contract/source/test/doc material;
- `npm run verify` — full repo closeout gate passes;
- `git diff --check` — package diff is mechanically clean.

The consolidated Packages 1–3 correction instead follows its exact two focused
commands, three existing package commands, 68-capture comparison, full gates,
and fresh review printed in that correction packet; native/Electron smoke is
optional and nonblocking for that unit.

Additional Package 4 proof:

- `npm run test:contracts` — Settings contract, persistence, IPC/preload, renderer, and existing contract suites pass;
- `npm run verify:architecture` — renderer/preload/main dependency direction and preload shape remain valid;
- manual relaunch proof — each approved value survives close/relaunch and malformed persistence recovers safely without private/path output.

Manual/visual proof after every surface package:

- exact CSS content viewports `1280x720` and `1920x1080`;
- package-owned ready/loading/empty/error/focus/modal/overlay states;
- keyboard-only, gamepad/remote-like mapping, pointer/click, text-entry bypass, Back, restoration, and scroll per matrix;
- player/overlay packages in windowed and fullscreen over the player presentation surface;
- reduced motion and forced colors for affected surfaces;
- sanitized capture manifest with baseline/reference/target ids;
- read-only adversarial review with findings adjudicated and material fixes reverified/re-reviewed.

Package 8 final proof additionally runs a local proof-bundle forbidden-material scan, full `npm run verify`, `npm run smoke:electron`, `npm run verify:redaction`, `npm run verify:docs`, and `git diff --check`. Expected outcome is zero missing matrix rows, zero missing required captures, zero unresolved material findings, and docs matching the observed app.

## Acceptance Criteria

- Package 0 corrected every known and discovered false closeout claim before implementation began.
- Package 0 observed, decided, and received clean review for the complete target focus/interaction matrix before Package 1; no later package invented target behavior outside a reviewed replan.
- Current WebOS reference, Desktop pre-package baseline, and Desktop post-package target PNGs exist at exact `1280x720` and `1920x1080` for every matrix surface/state; no prose-only or outer-window-size substitute is accepted.
- The focus/interaction matrix has no blank or `unknown` required cells and is backed by automated/manual evidence.
- Product UI has no permanent route rail, top title/status/build chrome, or route-card player shell.
- Player product code does not import or receive `createRendererPresentationFixtures()`/default demo channel data.
- Player idle has no simultaneous default overlays; every overlay appears only from a recorded event/action, follows reviewed precedence, restores focus, and cleans timers/listeners.
- Guide renders persisted scheduler-backed data when channels exist; no demo schedule reaches production. Honest no-channel/no-program/loading/error states are actionable and upstream-shaped.
- Settings values approved by this plan persist across relaunch through main-owned versioned storage, with strict guards, safe defaults, renderer-safe failures, and no browser storage.
- Settings public bridge promises never reject; request-id fallback/echo rules, exhaustive code/message mapping, failure classification, stale/concurrent ownership, and old-file/revision preservation pass at contract, preload, main, persistence, and renderer seams without raw error detail.
- Channel Setup presents one active stage at a time and preserves live auth/server/library/build/replacement/recovery/custom-channel behavior without hidden focusable stages.
- Before Package 4, Package 1–3 uses complete/nonzero exact splash/loading PNGs, uniquely scoped canonical profile/server glyphs, and current-upstream shell/onboarding/setup hierarchy, proportions, density, control geometry, and two-column setup grid at both target viewports while all frozen behavior/focus/accessibility contracts remain green.
- Each current upstream UI family has an accepted Desktop adaptation/divergence/defer disposition with evidence and revisit trigger.
- Electron containment, renderer privilege limits, Plex/token custody, player/native custody, diagnostics/support bundle, fullscreen, accessibility, redaction, and import provenance remain intact.
- No dependency/lockfile/CSP/native-helper/package/release change landed; protocol/build changes are limited to guarded self-only PNG serving and recursive copying of the two approved assets.
- Architecture hotspots shrink or remain within reviewed baselines; no baseline was raised to pre-authorize growth.
- Every package received clean/adjudicated adversarial review after fresh verification and visual/focus proof.
- Final full verification and integrated review pass, and all roadmap/parity/current-state documents agree with the observed running app.
- RD-27 remains blocked until all criteria above pass; then and only then may closeout route to a fresh RD-27 Tier 3 plan/quality-loop session.

## Replan Triggers

- Desktop or upstream scoped UI/architecture sources change materially from the pinned evidence.
- A later package discovers that a frozen target focus/interaction behavior is missing, ambiguous, internally inconsistent, or unimplementable; return to Package 0 plan/matrix review instead of deciding locally.
- Exact viewport captures cannot be produced or sanitized without hiding the behavior under review.
- A surface cannot be reached or focused deterministically in the built Electron app.
- Existing Guide/player/Plex/channel safe APIs lack data indispensable to a required state.
- Real artwork parity requires protocol/CSP/cache/token-bearing transport changes.
- The Packages 1–3 correction requires any MIME beyond PNG, any remote/private asset, a CSP change, or behavior/focus/accessibility changes.
- Settings needs credentials, secrets, raw paths, another schema family, migration, backup/restore, or renderer/browser persistence.
- Setup parity needs new channel-domain mutation, broader Plex browsing, or direct persisted-channel edit semantics.
- Overlay parity needs new native-helper/player commands, raw playback descriptors, or a new public media contract.
- Any package requires dependency, package/lockfile, native-helper, packaging, signing, update, installer, or public-release changes.
- A hotspot would grow past its reviewed baseline without the required decomposition.
- Smoke/fullscreen/focus behavior regresses outside the current package seam.
- Redaction scan, required command, capture matrix, or adversarial review has a material failure that cannot be fixed inside the package.
- Another tracked active plan or roadmap update supersedes this prerequisite ordering.

## Rollback Notes

- Keep one conventional commit per reviewed package; never mix unrelated user changes.
- Package 0 authority correction is retained even if implementation pauses: the contradicted closeout must not be restored without evidence.
- Roll back the current source package as a unit when behavior, focus, security, or visual proof fails. Do not add compatibility chrome, fixture fallbacks, or broad adapters to preserve partial work.
- Roll back the Packages 1–3 correction atomically, including both PNGs, the scoped brand glyph, pure protocol policy/copy support, and their import-ledger rows, if its guarded asset seam or direct visual proof fails; the earlier behavior/focus closeouts remain intact.
- Package 4 Settings storage uses a new versioned file; rollback removes the new IPC/preload/runtime wiring and leaves or deletes only that non-secret settings record according to the reviewed rollback test. It must not alter credential/channel storage.
- If a copied/adapted upstream slice is reverted, revert or amend its import-ledger entry in the same rollback.
- Local captures may be regenerated or removed because they are ignored; tracked conclusions must remain truthful.
- If closeout is blocked, leave this plan active, record the exact blocker in roadmap/current state, and hand back to planning/review. Do not archive it or unblock RD-27.

## Commit Checkpoints

Preferred focused conventional commits, each only after package review and verification:

1. `docs: reopen webos ui parity before rd-27`
2. `feat(renderer): replace dashboard chrome with fullscreen screens`
3. `feat(renderer): align onboarding focus and interaction parity`
4. `feat(renderer): align live channel setup with upstream structure`
5. `feat(renderer): match upstream shell onboarding and setup visuals`
6. `feat(settings): persist desktop ui preferences`
7. `feat(renderer): complete scheduler-backed guide parity`
8. `feat(renderer): bind player overlays to runtime state`
9. `feat(renderer): complete webos overlay presentation parity`
10. `docs: close complete webos ui parity proof`

Do not stage unrelated changes. Before each commit, inspect `git status --short`, package diff, evidence manifest, verification output, and review disposition.

## Model Guidance

- Planner: current tracked `planner` role with high reasoning for scope/authority refreshes.
- Implementer: the consolidated Packages 1–3 correction uses tracked `worker_luna` by explicit user override and its exact escalation gates. Packages 4–8 remain tracked `worker` unless a later reviewed plan revision explicitly changes eligibility.
- Reviewer: tracked `reviewer` role with high reasoning after every package and for final integrated review.
- Controller: `lineup-desktop-feature-quality-loop` for package sequencing, adjudication, and stop/replan enforcement.

MODEL_SUGGESTION
PLANNER: tracked planner role
IMPLEMENTER: tracked worker_luna for the Packages 1–3 correction; tracked worker for Packages 4–8
REVIEWER: tracked reviewer role
WHY: Tier 3 work spans renderer composition, focus/input, persisted Settings IPC, runtime-backed media UI, visual proof, and conflicting durable authority.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Execute Package 4 — Persisted Settings Seam and Settings Screen Parity
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
ARTIFACT: docs/runs/complete-webos-ui-parity-reopen/package-4-comprehensive-handoff.md
FILES:
- docs/plans/2026-07-10-complete-webos-ui-parity-reopen-plan.md
- docs/runs/complete-webos-ui-parity-reopen/package-4-comprehensive-handoff.md
- docs/runs/complete-webos-ui-parity-reopen/focus-interaction-matrix.json
- docs/runs/complete-webos-ui-parity-reopen/surface-disposition-matrix.json
- docs/runs/complete-webos-ui-parity-reopen/capture-manifest.json
- docs/runs/complete-webos-ui-parity-reopen/reference-manifest.json
- docs/runs/complete-webos-ui-parity-reopen/packages-1-3-fidelity-implementation-review.md
- docs/runs/complete-webos-ui-parity-reopen/packages-1-3-fidelity-closeout.md
- docs/runs/complete-webos-ui-parity-reopen/packages-1-3-fidelity-target-manifest.json
- src/contracts/settings.ts
- src/contracts/ipc.ts
- src/contracts/shell.ts
- src/main/persistence/appDataPaths.ts
- src/main/persistence/desktopSettingsStore.ts
- src/main/settings/settingsIpc.ts
- src/main/index.ts
- src/preload/channels.cts
- src/preload/settingsBridge.cts
- src/preload/settingsBridgeGuards.cts
- src/preload/index.cts
- src/renderer/index.ts
- src/renderer/workflow.ts
- src/renderer/staticDom.ts
- src/renderer/focusDom.ts
- src/renderer/domBindings.ts
- src/renderer/routeDom.ts
- src/renderer/epg/guideDom.ts
- src/renderer/plexRuntimeDom.ts
- src/renderer/plexRuntimeRows.ts
- src/renderer/settingsSetup.ts
- src/renderer/settingsSetupDom.ts
- src/renderer/settings/settingsRuntime.ts
- src/renderer/styles.css
- src/renderer/styles/workflow-screens.css
- src/renderer/styles/settings.css
- src/renderer/styles/guide-epg.css
- src/__tests__/contracts/contracts.test.ts
- src/__tests__/contracts/settingsContracts.test.ts
- src/__tests__/main/settingsPersistence.test.ts
- src/__tests__/main/settingsIpc.test.ts
- src/__tests__/integration/preloadContractVocabulary.test.ts
- src/__tests__/renderer/settingsSetup.test.ts
- src/__tests__/renderer/settingsRuntime.test.ts
- src/__tests__/renderer/workflow.test.ts
- src/__tests__/renderer/supportBundleExport.test.ts
- docs/architecture/security-and-secret-flow.md
BLOCKERS: none for Package 4; RD-27 remains blocked pending Packages 4–8 and plan closeout.
MESSAGE:
Load the comprehensive handoff and active plan, perform only the bounded
freshness audit and fresh scoped plan review, then execute Package 4 through the
Tier 3 quality loop. Preserve the clean Packages 0–3 baseline and upstream-port
parity priority. Package 4 uses tracked worker, not worker_luna, under the current
reviewed plan. Implement only the exact four-setting main-owned atomic/CAS
persistence, authorized total IPC/preload seam, real renderer consumers, and
upstream-shaped Settings UI. Before worker delegation, the controller must
confirm the frozen exact renderer/CSS consumer list against the freshness audit;
any required owner outside that list returns for focused replan and re-review,
and the worker receives no wildcard write scope. Run the exact focused/full/smoke/
relaunch/failure/visual/reduced-motion/forced-colors proof and obtain clean fresh
adversarial review. Small in-scope fixes do not require replanning. Pause after
Package 4; do not begin Package 5.
