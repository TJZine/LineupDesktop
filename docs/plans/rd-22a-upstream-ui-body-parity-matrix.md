# RD-22A Upstream UI Body Parity Matrix

**Task family:** feature/design
**Tier:** Tier 3
**Parent plan:** `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
**Unit:** RD-22A Unit 2, upstream UI body inventory and parity matrix

## Scope Boundary

RD-22A is fixture/injected renderer-safe shell and body work only. It may import
or adapt upstream UI structure, visual hierarchy, copy, focus/back behavior,
CSS, renderer-safe view models, and tests for the Desktop renderer.

RD-22A cannot claim live Plex, channel creation, scheduler runtime, playback,
media-option runtime behavior, production native-helper behavior, or
runtime-backed guide/player parity. RD-22B owns live Plex onboarding/library
runtime wiring into the RD-22A body. RD-23 owns live channel creation and
settings persistence. RD-24 owns scheduler-backed guide/player runtime data.
RD-25 and RD-26 own production playback and runtime media options.

No live Plex calls were made for this matrix. No source, package, dependency, or
lockfile edits are authorized by Unit 2.

## Evidence

- Desktop workspace status during this freshness refresh:
  `## initial-build...origin/initial-build`; no short-status file changes were
  reported. Desktop HEAD was
  `3eb38d376d0077456ea55b6475f7f0747c376f65`.
- Codanna: `semantic_search_with_context` was attempted for renderer route/body
  ownership, but semantic search failed because no embeddings were available.
  Direct `rg` and source reads were used as the fallback evidence path.
- Upstream root: `C:\Software\Lineup` is present.
- Upstream branch/HEAD/status after this freshness refresh: branch
  `code-health`, HEAD `613b1c516c7c9e37f9c18ea3e92c474013472b11`,
  remote `origin/code-health` at the same commit, short status
  `## code-health...origin/code-health` with no file rows.
- Current upstream freshness delta from the previously reviewed matrix HEAD
  `e6b94b2b364b4e3421cb0c7c5e7b77f126f71a0e` to current HEAD
  `613b1c516c7c9e37f9c18ea3e92c474013472b11`: 25 commits were inspected by
  changed path and scoped hunk reads. RD-22A-relevant UI/body changes are
  channel setup guide-order compaction and DOM-id handling, guarded review
  renders, EPG channel-name identity/overflow behavior, removal of guide and
  mini-guide category color cues, playback options focus/subtitle option
  policy, settings subtitle-language/HDR copy changes, now-playing playback
  summary wording, and safer playback diagnostics copy. Non-RD-22A runtime,
  Plex stream, subtitle fallback, scheduler, and workflow-doc changes do not
  change the renderer-only Unit 3 scope.
- Upstream source inspected:
  `src/App.ts`, `src/index.ts`, `src/core/app-shell/**`,
  `src/modules/navigation/**`, `src/modules/ui/common/**`,
  `src/modules/ui/auth/**`, `src/modules/ui/profile-select/**`,
  `src/modules/ui/server-select/**`, `src/modules/ui/channel-setup/**`,
  `src/modules/ui/settings/**`, `src/modules/ui/epg/**`,
  `src/modules/ui/player-osd/**`, `src/modules/ui/now-playing-info/**`,
  `src/modules/ui/mini-guide/**`, `src/modules/ui/channel-badge/**`,
  `src/modules/ui/channel-number-overlay/**`,
  `src/modules/ui/playback-options/**`, `src/modules/ui/splash/**`, and
  `src/styles/**`, plus scoped supporting UI/copy helpers
  `src/modules/ui/common/channelDisplay.ts`, `src/utils/playbackSummary.ts`,
  `src/utils/redact.ts`, and `src/shared/subtitle-language.ts`.
- Upstream tests inventoried:
  `src/core/app-shell/__tests__/**`,
  `src/modules/navigation/__tests__/**`,
  `src/modules/ui/**/__tests__/**`, and `src/styles/__tests__/**`, including
  app container, screen visibility, ScreenShell, auth, profile, server,
  channel setup, settings, EPG, OSD, now-playing, mini-guide, channel badge,
  channel number, playback options, runtime chrome, and CSS token tests.
- Desktop renderer owners inspected:
  `src/renderer/staticDom.ts`, `src/renderer/routeDom.ts`,
  `src/renderer/workflow.ts`, `src/renderer/navigation.ts`,
  `src/renderer/desktopInput.ts`, `src/renderer/focusDom.ts`,
  `src/renderer/epg.ts`, `src/renderer/overlays.ts`,
  `src/renderer/overlayViewModels.ts`, `src/renderer/settingsSetup.ts`,
  `src/renderer/plexRuntimeDom.ts`, `src/renderer/plexRuntimeRows.ts`,
  `src/renderer/plexRuntimeState.ts`, `src/renderer/plexRuntimeActions.ts`,
  `src/renderer/styles/**`, and `src/__tests__/renderer/**`.

## Freshness Decision

The Unit 2 matrix remains implementation-ready with this addendum. The upstream
delta does not invalidate RD-22A renderer-only scope, does not require live Plex
proof, and does not require Desktop main/preload/contracts/runtime/persistence/
player/package changes before Unit 3.

Unit 3 must treat upstream `613b1c516c7c9e37f9c18ea3e92c474013472b11` as the
fresh source baseline. Implementation should update import-ledger provenance to
that HEAD for any copied/adapted upstream UI, CSS, copy, asset, or test slice.
The parent RD-22A plan does not need amendment because its existing boundaries,
verification class, import-ledger obligation, and replan triggers already cover
the refreshed upstream delta.

## Unit 3 Freshness Addendum By Surface

These notes supersede stale "final freshness" details in the matrix rows below
without changing the RD-22A ownership boundary.

- App shell/body, route shell, and common shell: no scoped upstream app shell or
  navigation structural change requires Desktop main/preload or contract work.
  Playback diagnostics text changed under app-shell runtime diagnostics, but it
  is source material for safe UI copy only in RD-22A.
- Onboarding/profile/server: no scoped upstream auth, profile-select, or
  server-select body changes landed after `e6b94b2b`; existing Unit 2 rows
  remain current for shell/body implementation.
- Channel setup: include upstream commits `d5a62c2b`, `a3d462ab`, and
  `c25ac0f9`. Unit 3 should account for guarded review renders, compact guide
  order reordering, active-enabled strategy rows only, reset order, pickup/
  move/place/cancel copy, disabled one-category state, stable DOM-encoded ids,
  and compact/floating preview treatment. This remains fixture shell work; live
  channel authoring, review calculation, persistence, and scheduler/channel
  domain behavior stay RD-23 or later.
- Settings: include upstream commits `215e9c34`, `7869c9a8`, and `19eaa0fd`.
  Unit 3 should not carry forward the guide category-colors toggle as a parity
  requirement. Subtitle language labels/aliases and HDR fallback labels are
  display/copy references only until RD-23/RD-26 runtime ownership exists.
- Guide/EPG: include upstream commits `215e9c34` and `f87c1450`. Unit 3 should
  prefer textual channel identity/provenance over build-strategy color cues,
  support long channel-name expansion/wrapping, and avoid category-color legend
  or settings dependencies. Scheduler-backed guide data, virtualization depth,
  current program state, and persisted channels remain RD-24.
- OSD/player chrome: no scoped OSD structural delta after `e6b94b2b` changes
  the RD-22A shell boundary. Player chrome remains fixture host-plane and
  overlay stack work over the existing Desktop player presentation surface.
- Now-playing: include upstream commit `b30f0f3a`. Playback summary wording can
  distinguish Direct Play, Direct Stream, HLS Session, Audio Transcode, and
  Video Transcode as fixture copy. RD-22A must not claim real PMS playback
  decision fidelity.
- Mini guide and channel badge/number: include upstream commit `215e9c34`.
  Mini guide should not rely on build-strategy color borders as the primary
  channel category cue. Badge and channel-number shell rows remain current.
- Playback options: include upstream commits `5f7cc1d3`, `c1da0437`, and
  `613b1c51`. Unit 3 should model enabled/disabled audio/subtitle rows,
  direct/extract/burn-in/unavailable labels, empty states, selected focus, and
  scroll-stable focus behavior as fixture shell states only. Do not import the
  deleted upstream UI-owned subtitle probe URL policy, and stop if real player
  track mutation, subtitle probing, Plex URL construction, auth headers, stream
  descriptors, burn-in runtime, or player contract changes are required.
- CSS/tokens/copy/tests: include upstream commit `215e9c34`, which removed EPG
  category-color tokens. Unit 3 must not add category-color tokens/settings as
  required parity unless a later reviewed runtime plan owns that behavior.

## Implementation Matrix

| Surface | Upstream source/test anchors | Desktop renderer owners | Fixture or injected data need | Import-ledger obligation | Exact tests/proof | Desktop divergence rationale | RD-22A vs later ownership | Stop/replan triggers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| App shell/body and route structure | `src/App.ts`; `src/index.ts`; `src/core/app-shell/chrome/AppContainerFactory.ts`; `src/core/app-shell/chrome/AppScreenVisibilityCoordinator.ts`; `src/modules/ui/common/appShellContainerIds.ts`; `src/core/app-shell/__tests__/AppContainerFactory.test.ts`; `src/core/app-shell/__tests__/AppScreenVisibilityCoordinator.test.ts` | `src/renderer/staticDom.ts`; `src/renderer/routeDom.ts`; `src/renderer/workflow.ts`; `src/renderer/navigation.ts`; `src/renderer/index.ts`; `src/renderer/styles/base.css`; `src/renderer/styles/responsive-accessibility.css`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/navigation.test.ts`; `src/__tests__/renderer/workflow.test.ts` | Renderer-safe route/body view model with startup/onboarding/player/guide/settings/setup shell states and fake app readiness. No main route state or preload expansion. | Required if any upstream container IDs, shell markup, copy, CSS, or tests are copied/adapted into Desktop. Record source paths, HEAD, Desktop owners, retained tests, divergence, and follow-up trigger. | Focused renderer tests named above; active-plan full renderer command; `npm run verify`; `npm run smoke:electron`; sanitized visual/focus/manual proof; read-only implementation review. | Upstream app shell owns browser/webOS startup and lazy screen orchestration. Desktop must render the body in an unprivileged Electron renderer without importing webOS platform services or main/preload policy. | RD-22A owns fixture shell/body parity. RD-22B only data-binds live Plex into the body. RD-24 later wires runtime guide/player states. | Stop if parity requires main/preload/contracts/runtime changes, broad IPC, renderer Electron/Node access, dependency/package changes, or growing renderer hotspots without reviewed decomposition. |
| Shared screen shell, loading, empty, error, and focus/back treatment | `src/modules/ui/common/ScreenShell.ts`; `src/modules/ui/common/ScreenShellView.ts`; `src/modules/ui/__tests__/ScreenShell.test.ts`; `src/modules/navigation/**`; `src/modules/navigation/__tests__/**` | `src/renderer/staticDom.ts`; `src/renderer/routeDom.ts`; `src/renderer/focusDom.ts`; `src/renderer/desktopInput.ts`; `src/renderer/navigation.ts`; `src/__tests__/renderer/focusDom.test.ts`; `src/__tests__/renderer/desktopInput.test.ts`; `src/__tests__/renderer/navigation.test.ts` | Fixture route state must include loading, empty, error, active, disabled, back, and focus-restoration states without touching runtime owners. | Required if ScreenShell layout/copy/CSS/focus patterns or navigation tests are adapted. | Renderer focus/back/text-entry tests; active-plan full renderer command; visual/focus/manual proof for first focus, nested back, route isolation, text-entry bypass, and error states. | Upstream focus manager and screen shell integrate with browser screen routing. Desktop already has renderer-local route/focus owners and must preserve sandboxed renderer limits. | RD-22A owns shell states and focus/back shell behavior. Runtime owners later provide real status/error sources. | Stop if focus/back cannot be represented without upstream navigation manager import, hidden runtime wiring, or renderer access to privileged state. |
| Onboarding auth/PIN shell | `src/modules/ui/auth/AuthScreen.ts`; `src/modules/ui/auth/plexLinkQrSvg.ts`; `src/modules/ui/auth/__tests__/AuthScreen.test.ts`; `src/styles/shell.onboarding.auth.css`; `src/styles/shell.onboarding.shared-shell.css` | `src/renderer/staticDom.ts`; `src/renderer/plexRuntimeDom.ts`; `src/renderer/plexRuntimeRows.ts`; `src/renderer/plexRuntimeState.ts`; `src/renderer/plexRuntimeActions.ts`; `src/renderer/styles/plex-onboarding.css`; `src/__tests__/renderer/plexRuntime.test.ts`; `src/__tests__/renderer/routeDom.test.ts` | Injected renderer-safe auth snapshot with signed-out, PIN requested, PIN pending, cancel, retry, failed, and empty states. Use fake codes only. | Required for copied/adapted auth layout, QR/link affordance, copy, CSS, or tests. Do not ledger live auth transport. | `src/__tests__/renderer/plexRuntime.test.ts`; route isolation test; visual proof that labels fixture/demo state; redaction verifier. | Upstream AuthScreen calls Plex auth ports and renders QR/link behavior. RD-22A may only show product-shaped shell states; RD-22B owns live PIN request/poll/cancel. | RD-22A owns shell/body. RD-22B owns live Plex auth and credential availability. | Stop if implementation needs live Plex calls, credential custody, auth headers, token-bearing URL, preload contract changes, or tracked private evidence. |
| Profile/Plex Home setup shell | `src/modules/ui/profile-select/ProfileSelectScreen.ts`; `src/modules/ui/profile-select/styles*.css`; `src/modules/ui/profile-select/__tests__/ProfileSelectScreen.test.ts`; `src/modules/navigation/__tests__/FocusManager.test.ts` | `src/renderer/plexRuntimeRows.ts`; `src/renderer/plexRuntimeDom.ts`; `src/renderer/focusDom.ts`; `src/renderer/styles/plex-onboarding-cards.css`; `src/__tests__/renderer/plexRuntime.test.ts`; `src/__tests__/renderer/focusDom.test.ts` | Injected renderer-safe profile rows with admin/restricted/locked labels, selected profile, PIN modal/numpad shell, failed PIN, empty profiles, and loading states. No real user names in tracked fixtures. | Required for profile row/card/PIN modal/CSS/copy/test adaptation. | Renderer Plex row tests; focus/back/manual proof for PIN modal shell, first focus, cancel/back, and no private profile names. | Upstream profile screen switches Plex Home users and stores profile session state. Desktop RD-22A must avoid profile tokens and runtime switching. | RD-22A owns profile picker shell. RD-22B owns live Plex Home and profile switch behavior. | Stop if real profile switching, persisted active profile, profile token handling, or renderer secret custody is needed. |
| Server setup shell | `src/modules/ui/server-select/ServerSelectScreen.ts`; `src/modules/ui/server-select/ServerSelectListView.ts`; `src/modules/ui/server-select/ServerSelectRuntimeCoordinator.ts`; `src/modules/ui/server-select/__tests__/**`; `src/styles/shell.onboarding.server-selection.css` | `src/renderer/plexRuntimeRows.ts`; `src/renderer/plexRuntimeDom.ts`; `src/renderer/plexRuntimeState.ts`; `src/renderer/styles/plex-onboarding.css`; `src/renderer/styles/plex-onboarding-cards.css`; `src/__tests__/renderer/plexRuntime.test.ts` | Injected renderer-safe server summaries with no connection URI, selected/healthy/unavailable/stale/loading/empty/error states, saved-server hint, refresh, clear, and retry controls. | Required for server row/status/action/CSS/copy/test adaptation. | Renderer Plex server row tests; redaction verifier; visual/manual proof for empty, loading, failed, selected, and change-server states. | Upstream server screen performs discovery, restore, auto-connect, and selected-server runtime. Desktop must keep connection details and selected connection custody in main. | RD-22A owns server selection body shell. RD-22B owns live discovery, restore, selection, and relaunch restore. | Stop if raw URI, token, selected connection, server private names, live discovery, or preload/main contract changes are required. |
| Channel setup shell | `src/modules/ui/channel-setup/ChannelSetupScreen.ts`; `src/modules/ui/channel-setup/ChannelSetupWorkflowPresenter.ts`; `src/modules/ui/channel-setup/steps/**`; `src/modules/ui/channel-setup/focus/**`; `src/modules/ui/channel-setup/__tests__/**`; `src/core/channel-setup/__tests__/**`; `src/modules/ui/channel-setup/styles*.css`; final freshness commit `ab634d8d` adds review impact UX and `e6b94b2b` adjusts impact segment contrast | `src/renderer/staticDom.ts`; `src/renderer/settingsSetup.ts`; `src/renderer/routeDom.ts`; `src/renderer/workflow.ts`; `src/renderer/focusDom.ts`; `src/renderer/styles/workflow-screens.css`; `src/renderer/styles/plex-onboarding.css`; `src/__tests__/renderer/workflow.test.ts`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/focusDom.test.ts` | Fixture setup state for library, strategy, review/build-progress shell, review impact panel, current-to-after channel counts, stay/leave/new composition segments, strategy category chips, replace-confirm state, warnings, validation, disabled controls, empty library, and loading/error states. No committed channel output. | Required for any setup wizard structure, review impact treatment, step copy, controls, CSS, or tests copied/adapted. | Workflow/route/focus tests; visual/manual proof that setup review impact and replacement confirmation are shell-only fixture states; proof that fake draft controls are removed or isolated from product routes; redaction verifier. | Upstream setup owns real library-driven channel building, review preloading, replacement confirmation, and commit. RD-22A may only create renderer-safe shell states that RD-23 will wire to live authoring. | RD-22A owns setup shell/body and review-impact presentation with fixture data. RD-23 owns live review calculation, channel creation, validation, commit, and persisted recovery. | Stop if channel authoring, persistence IPC, live review calculation, live library commit, scheduler/channel domain changes, or package/dependency changes are needed. |
| Settings shell | `src/modules/ui/settings/SettingsScreen.ts`; `src/modules/ui/settings/SettingsScreenStateController.ts`; `src/modules/ui/settings/SettingsScreenFocusCoordinator.ts`; `src/modules/ui/settings/SettingsToggle.ts`; `src/modules/ui/settings/SettingsSelect.ts`; `src/modules/ui/settings/__tests__/**`; `src/modules/ui/settings/styles*.css` | `src/renderer/settingsSetup.ts`; `src/renderer/routeDom.ts`; `src/renderer/workflow.ts`; `src/renderer/supportBundleExport.ts`; `src/renderer/styles/workflow-screens.css`; `src/__tests__/renderer/workflow.test.ts`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/supportBundleExport.test.ts` | Fixture settings categories, toggles/selects, support-bundle action state, profile switch row, loading/error/disabled states, and unsaved-state copy. | Required for settings category/control/copy/CSS/test adaptation. | Workflow/route/support-bundle renderer tests; manual proof for category rail, detail panel, profile switch row shell, and safe support-bundle status. | Upstream settings persists preferences and talks to runtime controllers. Desktop RD-22A must keep settings local/injected until RD-23/RD-26 runtime ownership exists. | RD-22A owns Settings shell. RD-23 owns setup/settings persistence needed for MVP. RD-26 owns media-option runtime settings. | Stop if real persistence IPC, playback preference mutation, profile switch runtime, or private support-bundle evidence is required. |
| Guide/EPG shell | `src/modules/ui/epg/view/shell/EPGShellView.ts`; `src/modules/ui/epg/component/EPGComponent.ts`; `src/modules/ui/epg/view/**`; `src/modules/ui/epg/focus/EPGFocusNavigator.ts`; `src/modules/ui/epg/runtime/**`; `src/modules/ui/epg/__tests__/**`; `src/modules/ui/epg/styles*.css` | `src/renderer/epg.ts`; `src/renderer/routeDom.ts`; `src/renderer/workflow.ts`; `src/renderer/styles/workflow-screens.css`; `src/__tests__/renderer/epg.test.ts`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/workflow.test.ts` | Fixture guide rows, time slots, selected program, no-data rows, loading/error shells, classic/overlay hierarchy cues, now-watching shell labels, and focus movement. | Required for EPG layout/CSS/copy/test adaptation. | `src/__tests__/renderer/epg.test.ts`; route/workflow tests; visual/focus/manual proof for guide density, selected row/program, empty/loading/error shells, and no scheduler claim. | Upstream EPG runtime virtualizes persisted channels and schedule refresh. Desktop RD-22A can mirror the shell with deterministic fixture rows only. | RD-22A owns guide shell/body. RD-24 owns persisted-channel scheduler data, virtualization depth, current-program state, and runtime-backed guide/player parity. | Stop if scheduler runtime, channel persistence, live library data, current-channel runtime, or private media names are needed to prove shell parity. |
| OSD shell | `src/modules/ui/player-osd/PlayerOsdOverlay.ts`; `src/modules/ui/player-osd/PlayerOsdCoordinator.ts`; `src/modules/ui/player-osd/__tests__/**`; `src/modules/ui/player-osd/styles*.css`; `src/styles/shell.player-runtime-chrome.css` | `src/renderer/staticDom.ts`; `src/renderer/overlays.ts`; `src/renderer/overlayViewModels.ts`; `src/renderer/routeDom.ts`; `src/renderer/styles/player-overlays.css`; `src/__tests__/renderer/overlays.test.ts`; `src/__tests__/renderer/routeDom.test.ts` | Fixture player snapshot for title, subtitle, status, progress, up-next, audio/subtitle labels, sleep action shell, disabled/hidden states, and route gating. | Required for OSD markup, CSS, copy, icons, or tests copied/adapted. | Overlay/route tests; active-plan full renderer command; visual/manual proof over player presentation surface. | Upstream OSD reads video player and runtime schedule state. Desktop RD-22A must not claim playback or track runtime. | RD-22A owns OSD shell. RD-24 owns runtime now-playing/channel data. RD-25 owns production playback-state presentation. RD-26 owns real media options. | Stop if real player state, playback descriptor, URL/header/native handle, or media option runtime is needed. |
| Now-playing shell | `src/modules/ui/now-playing-info/NowPlayingInfoOverlay.ts`; `src/modules/ui/now-playing-info/NowPlayingInfoCoordinator.ts`; `src/modules/ui/now-playing-info/__tests__/**`; `src/modules/ui/now-playing-info/styles*.css` | `src/renderer/staticDom.ts`; `src/renderer/overlays.ts`; `src/renderer/overlayViewModels.ts`; `src/renderer/routeDom.ts`; `src/renderer/styles/player-overlays.css`; `src/__tests__/renderer/overlays.test.ts` | Fixture metadata summary with safe placeholder artwork slots, title/subtitle, badges, cast-count placeholder, progress/live states, empty art fallback, and auto-hide shell. No remote image URLs. | Required for copied/adapted now-playing structure/CSS/copy/tests. | Overlay tests; visual/manual proof for title fallback, progress/live, empty art, and no tokenized/remote assets. | Upstream can resolve Plex artwork and current playback metadata. Desktop renderer must not hold tokenized URLs or private media details. | RD-22A owns now-playing shell. RD-24/RD-25 own runtime data and playback-state fidelity. | Stop if remote/tokenized artwork, raw media metadata, native playback state, or runtime current-program data is required. |
| Mini guide shell | `src/modules/ui/mini-guide/MiniGuideOverlay.ts`; `src/modules/ui/mini-guide/MiniGuideCoordinator.ts`; `src/modules/ui/mini-guide/__tests__/**`; `src/modules/ui/mini-guide/styles*.css`; `src/modules/ui/common/channelBrandingIcons.ts` | `src/renderer/staticDom.ts`; `src/renderer/overlays.ts`; `src/renderer/overlayViewModels.ts`; `src/renderer/routeDom.ts`; `src/renderer/styles/player-overlays.css`; `src/__tests__/renderer/overlays.test.ts`; `src/__tests__/renderer/focusDom.test.ts` | Fixture five-row mini guide with selected row, now/next labels, progress bars, channel branding placeholders, loading rows, and channel up/down shell. | Required for mini-guide row layout, icons, CSS, copy, or tests copied/adapted. | Overlay/focus tests; visual/focus/manual proof for row count, selection, progress, and channel navigation shell. | Upstream mini guide reflects scheduler/current channel runtime. Desktop RD-22A can only show fixture channel rows. | RD-22A owns mini guide shell. RD-24 owns runtime-backed channel switching, schedule state, and current-channel selection. | Stop if persisted channels, schedule runtime, or real switch requests are needed. |
| Channel badge and channel-number shell | `src/modules/ui/channel-badge/ChannelBadgeOverlay.ts`; `src/modules/ui/channel-number-overlay/ChannelNumberOverlay.ts`; `src/modules/ui/channel-badge/__tests__/**`; `src/modules/ui/channel-number-overlay/__tests__/**`; `src/modules/ui/channel-badge/styles.css`; `src/modules/ui/channel-number-overlay/styles.css` | `src/renderer/staticDom.ts`; `src/renderer/overlays.ts`; `src/renderer/overlayViewModels.ts`; `src/renderer/routeDom.ts`; `src/renderer/styles/player-overlays.css`; `src/__tests__/renderer/overlays.test.ts` | Fixture selected channel, not-found channel number state, max digits, badge visible/hidden, stable label, and no layout-shift error states. | Required for badge/number markup, CSS, icon, copy, or tests copied/adapted. | Overlay tests; visual/manual proof for badge stack, number entry, clear/commit, and not-found shell. | Upstream badge/number overlays are tied to channel tuning runtime. Desktop RD-22A cannot tune channels. | RD-22A owns badge and number shells. RD-24 owns real channel switch/tuning state. | Stop if real channel switching, persisted lineup, or runtime errors are required. |
| Player chrome shell | `src/styles/shell.player-runtime-chrome.css`; `src/styles/video.css`; `src/styles/__tests__/player-runtime-chrome-host-plane.test.ts`; `src/modules/ui/player-osd/**`; `src/modules/ui/playback-options/**`; `src/core/app-shell/config/AppOrchestratorConfigFactory.ts` | `src/renderer/staticDom.ts`; `src/renderer/styles/player-overlays.css`; `src/renderer/styles/base.css`; `src/renderer/styles/responsive-accessibility.css`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/overlays.test.ts` | Fixture host plane, overlay stack, route chrome, loading/error/no-signal surfaces, and fullscreen-safe layout over existing player presentation. | Required for runtime chrome CSS or host-plane tests copied/adapted. | Route/overlay tests; `npm run smoke:electron`; sanitized visual proof over the Desktop player presentation surface. | Upstream player chrome sits over browser/video runtime. Desktop must preserve native-video boundary assumptions and existing Electron fullscreen bridge. | RD-22A owns chrome shell. RD-25 owns production playback controls over native video. | Stop if production helper, native handles, real playback events, or video runtime changes are required. |
| CSS, copy, assets, and style contracts | `src/styles/tokens.css`; `src/styles/themes.css`; `src/styles/shell.css`; `src/styles/shell.chrome.css`; `src/styles/shell.onboarding.*.css`; `src/modules/ui/**/styles*.css`; `src/modules/ui/common/brandGlyph.ts`; `src/modules/ui/common/brandGlyphSource.ts`; `src/modules/ui/auth/plexLinkQrSvg.ts`; `src/styles/__tests__/**`; `src/modules/ui/__tests__/runtime-token-style-contracts.test.ts`; `src/modules/ui/__tests__/runtime-overlay-style-contracts.test.ts` | `src/renderer/styles.css`; `src/renderer/styles/base.css`; `src/renderer/styles/workflow-screens.css`; `src/renderer/styles/player-overlays.css`; `src/renderer/styles/plex-onboarding.css`; `src/renderer/styles/plex-onboarding-cards.css`; `src/renderer/styles/responsive-accessibility.css`; `src/__tests__/renderer/routeDom.test.ts`; `src/__tests__/renderer/overlays.test.ts`; `src/__tests__/renderer/plexRuntime.test.ts` | Renderer-safe fixture copy and local inline/vector assets only. No raw screenshots, no remote/tokenized image URLs, no private Plex names/media titles, no new dependency/assets pipeline. | Required for all copied/adapted CSS, copy, inline SVG, branding glyph, or style tests. Include retained-test mapping and provenance notes. | Renderer tests plus `npm run verify:redaction`, `npm run verify:maintainability` through `npm run verify`, `git diff --check`, visual/manual proof across desktop/mobile-ish window sizes if implemented. | Upstream CSS assumes browser/webOS body, video plane, and theme runtime. Desktop CSS must fit the Electron shell, existing focus policy, reduced motion, forced colors, and file-shape guardrails. | RD-22A owns shell/body visual parity. Later slices own runtime-specific visual states as data arrives. | Stop if raw/private visual evidence, new assets/dependencies, one-file CSS hotspot growth, or style changes outside renderer scope are required. |

## Verification Commands

Unit 2 docs/source-audit verification from the active plan:

- `npm run verify:docs` should pass.
- `npm run verify:redaction` should pass.
- `git diff --check` should pass.
- Freshness refresh closeout should also run
  `git diff --check -- docs/plans/rd-22a-upstream-ui-body-parity-matrix.md`
  so the modified tracked matrix is included explicitly.
- Read-only review of this matrix should report no material blockers before
  Unit 3 implementation.

RD-22A implementation verification after Unit 2 review, copied exactly from the
active plan:

- `node --import tsx --test src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/navigation.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/desktopInput.test.ts src/__tests__/renderer/epg.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/plexRuntime.test.ts` should pass.
- `npm run verify` should pass.
- `npm run smoke:electron` should pass.
- Sanitized visual/focus/manual proof should show the fixture-backed,
  upstream-shaped app body across onboarding, channel setup shell, Settings,
  Guide/EPG, OSD, now-playing information, mini guide, channel badge, and
  player chrome without raw/private evidence or any claim of live Plex,
  channel creation, scheduler, playback, or media-option runtime completion.
- Read-only implementation review should report no material blockers.

## Review Status

Read-only adversarial plan review completed for this matrix. The reviewer found
no material blockers and judged the matrix implementation-ready for RD-22A Unit
3. One low verification caveat was accepted: plain `git diff --check` does not
inspect an untracked file. Closeout for Unit 2 must therefore include either a
direct whitespace check on this file or a staged/cached diff check before
commit.

Freshness refresh status: read-only review completed and clean. The subsequent
Unit 3 implementation review found a product-copy blocker in reachable renderer
routes; this bounded fix removes the visible proof/scaffold terms while
preserving renderer-safe local setup data internally.

Unit 3 closeout status: complete and reviewed. The controller observed the
exact renderer command passing 75/75 tests, `npm run verify` passing,
`npm run smoke:electron` passing, and `git diff --check` passing with only CRLF
warnings. Sanitized local proof exercised the built renderer through the local
safe mock bridge across route switching, overlay/player chrome, guide,
Settings, channel setup, and focus targets. It found no old setup hooks and no
forbidden token, header, path, or raw private text. No screenshots, raw logs,
account names, server names, library/media titles, raw paths, endpoint URLs,
tokens, headers, payloads, native handles, or other private proof are tracked.
The import ledger already records the RD-22A Unit 3 upstream provenance row at
upstream HEAD `613b1c516c7c9e37f9c18ea3e92c474013472b11`.

## Unit 3 Acceptance Gates

- The reachable Desktop body no longer reads as the RD-13 scaffold with isolated
  real controls dropped into it.
- Fixture/injected data is renderer-safe and contains no credentials, tokens,
  auth headers, raw URLs, raw Plex payloads, local paths, native handles, raw
  IPC, private names, or private media details.
- Every copied/adapted upstream UI, CSS, copy, asset, or test has an
  import-ledger row before or with the import.
- Guide/player surfaces are explicitly labeled as RD-22A shell/body parity only
  unless RD-24 or later runtime ownership has completed.
- Fake/debug/smoke/draft controls are removed from or isolated outside product
  routes where RD-22A owns the visible body.

## Completion Handoff

NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop
TASK: Complete RD-22B Live Plex Onboarding Runtime Wiring Into Parity Body
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
ARTIFACT: RD-22A completed parity matrix and closeout summary
FILES:
- `docs/plans/rd-22a-upstream-ui-body-parity-matrix.md`
- `docs/plans/rd-22-live-plex-auth-discovery-library-runtime-ui.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/import-ledger.md`
- `docs/architecture/CURRENT_STATE.md`
- `src/contracts/plex.ts`
- `src/main/plex/**`
- `src/main/persistence/**`
- `src/renderer/**`
- `src/__tests__/**`
BLOCKERS: none for RD-22B planning. Live proof and implementation remain gated
by redaction-safe Plex account/server availability and any active Plex rate
limiting.
MESSAGE:
Use this matrix as completed RD-22A body-surface context, not as an RD-22B
implementation packet. Start RD-22B planning through the quality loop for live
Plex auth/profile/server/library runtime wiring into the RD-22A body. Preserve
RD-22A body shape except for reviewed data-binding adjustments. Keep Plex
credentials, tokens, selected connections, raw payloads, auth headers, endpoint
details, app paths, and diagnostics in main-owned custody. Do not claim channel
creation, scheduler-backed guide/player runtime, playback, media-option
runtime, production native-helper behavior, package/release behavior, or public
release readiness. Require redaction-safe Windows proof and read-only review
before RD-22B closeout.
