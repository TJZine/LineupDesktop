# Portable UI parity

This document is the source record for Prompt 3B and Prompt 4B portable UI
parity, with Prompt 4C recorded as supplemental source, diff, and test coverage.
It does not claim Windows media validation.

The earlier “Parity” classifications below are historical records of those
accepted source-based passes. Prompt 4C does not promote them to live visual
acceptance; its current locked-host classification matrix is recorded at the
end of this document.

## Provenance and authority

- LineupDesktop starting commit:
  `eb3a88505a44cabf10a9724376520b32ac293fee` on
  `replatform/flutter-native`.
- LineupDesktop ending commit: the `feat(ui): close portable Lineup structural
  parity gaps` commit containing this document. Its exact SHA is recorded in
  the Prompt 3B closeout because a Git commit cannot contain its own SHA.
- Upstream product reference: sibling clone `TJZine/Lineup`, inspected read-only
  on branch `code-health` at
  `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`.
- Upstream remote `main` was also checked and pointed to the initial README-only
  commit `5f01be6a719174ae1f89a70b8cab1095bf17c8b9`; it was not the implemented
  product reference.
- Historical Desktop evidence was inspected at the Electron first parent of
  `origin/initial-build`,
  `bfaee636748f2a0d442f3690b7ba5262d32ff17c`. It was used only for valid
  resizable-window, focus-restoration, and destructive-confirmation behavior.

The upstream application was not run with a real Plex account during this
pass. No credential-bearing or private media surface was captured. The parity
evidence is current committed source, tests, copy, and styles.

Relevant upstream paths included:

- `src/styles/tokens.css`, `themes.css`, and `shell.onboarding.*.css`;
- `src/modules/ui/common/ScreenShell.ts` and `ScreenShellView.ts`;
- `src/modules/ui/splash/SplashScreen.ts`;
- `src/modules/ui/auth/AuthScreen.ts` and `AuthPinDisplay.ts`;
- `src/modules/ui/profile-select/**`;
- `src/modules/ui/server-select/**`;
- `src/modules/ui/audio-setup/AudioSetupScreen.ts`;
- `src/modules/ui/channel-setup/**` and `src/core/channel-setup/**`;
- `src/modules/ui/settings/**`;
- `src/modules/navigation/contracts/interfaces.ts` and
  `src/modules/navigation/manager/NavigationManager.ts`;
- `src/core/app-shell/chrome/AppBlockingErrorOverlayPresenter.ts` and
  `AppToastPresenter.ts`.

## Parity matrix

The classifications describe the ending Flutter state. “Parity” means the
user-visible intent and state ownership match; it does not imply literal CSS or
TV pixel copying.

| Surface or state | Classification | Evidence and disposition |
| --- | --- | --- |
| Startup progress | Parity | Branded, semantic progress while player and application owners initialize. |
| Fatal startup failure | Parity | Sanitized, live error with restart guidance. Upstream fatal bootstrap also has no in-process retry. The exact Windows engine failure remains explicit. |
| Auth welcome and PIN request | Parity | Upstream title, explanatory copy, primary action, QR/PIN hierarchy, expiry, cancel, request-new-code, busy, error, and stale-result ownership are retained. |
| Account validation and authenticated transition | Parity | `LineupController` remains the transition owner; UI does not invent routing policy. |
| Profiles populated | Parity | Avatar/fallback, protected badge, sign-out, and disabled interaction while switching. |
| Profiles loading or unexpectedly empty | Insufficient evidence | Transport ownership exposes a global busy/error surface; an empty successful Plex Home response falls through to account scope. No fake profile is introduced. |
| Protected-profile PIN | Parity | Four-digit keypad, Backspace, Cancel, numeric/numpad keyboard input, semantic progress, and automatic submit. A rejected PIN returns an actionable live error on the profile surface; keeping the modal open would require a different controller result seam. |
| Server discovery, empty, retry, selection failure | Parity | Busy/error, owner/shared rows, empty guidance, retry, and switch-profile are deliberate. |
| Server health, latency, relay quality, clear saved server | Insufficient evidence | Current Dart models do not project upstream health facts. The UI does not fabricate them. |
| Saved-server auto-connect | Parity | Controller tries the persisted profile-scoped server and falls back to selection; global progress is the current portable presentation. |
| First-run audio intent | Parity | Upstream ordering, choices, advanced fallback, disabled Continue, and persistence failure are retained. TV-specific wording is retained because it is upstream product copy pending broader hardware acceptance. |
| Channel Setup library state | Parity | Selected/empty/loading/error gates, select/clear actions, and compact scrolling are deliberate. |
| Channel Setup strategies and controls | Parity | Eight strategies, priority, cross-library scope, build modes, ordering, variants, and bounded limits remain Dart-owned. |
| Channel Setup estimate, review, confirmation, apply | Parity | Empty/capped estimate, replace confirmation, impact summary, build progress, and atomic controller application remain intact. |
| Channel Setup cancellation details | Present but materially divergent | Existing setup can be cancelled when re-entered from Channels; upstream also exposes progress cancellation. Flutter atomic apply is currently short-lived and has no cancellable public seam, so no pretend cancel was added. |
| Channels management and custom editing | Intentional Desktop adaptation | Upstream has no implemented management/editor surface. Flutter keeps the accepted owner, adds local form validation, preserves `includeWatched`, prevents duplicate save, reports failures, and confirms deletion. |
| Channels loading and success toast | Obsolete/not applicable | Channels are persisted local product state, not a separately loaded screen. Durable success is immediately reflected by the authoritative list. |
| Settings hierarchy | Parity | Category rail/detail pane, selected-versus-focused category state, compact horizontal categories, readable width, local saving progress, rollback error, and human-readable values. Only settings with current portable consumers are exposed. |
| Upstream-only settings | Obsolete/not applicable | Theme switching, TV-only playback toggles, dev logging, and unsupported output/HDR controls are not reintroduced. Persisted Dart fields without implemented product behavior are not advertised. |
| Diagnostics | Intentional Desktop adaptation | Upstream diagnostics is a dev surface. Desktop keeps its credential-safe support destination, with grouped summary, empty/disabled guidance, bounded contexts, and no token/URL exposure. |
| Global navigation | Intentional Desktop adaptation | Upstream is a TV screen stack. Desktop uses Guide, Channels, Settings, Diagnostics, Player in that order, with pointer/Tab support and visible focus entry for each destination. |
| Dialogs and destructive confirmation | Parity | Flutter dialog semantics, Cancel-first action order, destructive styling, focus restoration, and inline error ownership are used. |
| Transient feedback | Present but materially divergent | Repeated errors use one semantic notice primitive. A generic toast owner was not added because only persistence errors have current consumers and remain more actionable inline. |
| Compact 800×600 management/setup layout | Parity | Headers, action groups, category selectors, empty states, and scroll owners reflow without a window-management dependency. |
| 1280×720 through 3840×2160 | Intentional Desktop adaptation | Widget tests verify management-page reachability and absence of layout errors throughout this range. The capped 1,120-pixel management workspace and extended navigation are asserted at 2560×1440 and 3840×2160. Guide/player retain their specialized full-area owners. Windows runtime DPI behavior remains Windows-only validation. |
| Windows focus, native video layering, HDR and playback | Windows-only validation | Not modified or claimed by Prompt 3B. |

## Shared portable UI ownership

`lib/ui/app_theme.dart` owns the small repeated visual vocabulary: background
and elevated surfaces, brass primary treatment, the current error role, radii,
the used focus transition, and Material component states for navigation, cards,
forms, dialogs, chips, lists, icon actions, buttons, dividers, and progress.

`lib/ui/app_ui.dart` owns only repeated application composition:

- compact, ordinary, and expanded-navigation layout thresholds;
- responsive readable-width page/title/action composition;
- semantic section headings;
- inline status notices;
- reusable empty states; and
- destructive confirmation.

Feature state and policy remain in their existing owners. Channel Setup keeps a
small private footer because its step layout is not a general application
primitive. No dependency, state framework, service locator, catalog package,
or generic utility layer was added.

## Intentional Desktop adaptations

- A persistent NavigationRail replaces TV-only screen-stack navigation so all
  primary destinations remain discoverable with mouse and keyboard.
- Tab/Shift+Tab and pointer interaction are primary; arrow navigation remains
  limited to spatial owners such as the Guide.
- Management pages use desktop-readable content width rather than scaling a
  ten-foot UI across a large resizable window.
- Settings categories become a horizontal scroll owner at compact widths rather
  than duplicating the detail pane or nesting vertical scrolling.
- Diagnostics is an ordinary, redacted support destination. Upstream’s dev
  overrides, console dumps, and raw diagnostic controls are not copied.
- Channels management remains a Desktop/product continuation because upstream
  has no implemented equivalent.

The practical compact target is 800×600 because the macOS runner currently
launches at that size and neither runner enforces a minimum. Windows launches
at 1280×720. Large-window coverage extends through 3840×2160; management
content stays readable while Guide/player owners retain the full available
area. No window-management or resolution-scaling package was added.

## Test-only visual states

`test/support/ui_fixture.dart` supplies a deterministic controller/player/store
composition for widget tests. Tests mutate only public production seams to
exercise loading, empty, error, populated, protected-profile, validation, and
confirmation states. It is under `test/`, is not imported by `lib/main.dart`,
contains no real Plex data, and cannot be reached from production navigation.

Focused validation:

```sh
flutter test test/app/ui_parity_test.dart
```

The focused suite verifies destination order and focus entry, responsive
management pages at 800×600, 1280×720, 1600×900, 1920×1080, 2560×1440 and
3840×2160, destructive confirmation, local editor validation, physical
protected-PIN keys, Settings category scrolling, and all three Channel Setup
stages. At 2560×1440 and 3840×2160 the tests also assert the deliberate
1,120-logical-pixel management workspace and extended navigation. The
1,180-pixel onboarding workspace and 1,440-pixel Channel Setup workspace are
asserted only at 3840×2160. Diagnostics reachability is verified at every
listed management-page size. Flutter lays out in logical pixels; a
deterministic 3840×2160 at DPR 2 case verifies the 1920×1080 logical regime.
Actual Windows DPI mapping and physical readability still require Windows
runtime observation. The full validation commands remain in
`docs/DEVELOPMENT.md`.

`flutter run -d macos` built, launched, attached to the Dart VM service, and
reported the Metal Impeller backend. The host Mac was locked and could not be
automatically unlocked, so the window could not be foregrounded for a truthful
real-UI mouse/keyboard/resize inspection. No Plex session was opened and no
private data was observed. The portable window/state claims in this document
therefore rest on deterministic widget tests plus the successful macOS build;
manual visual acceptance remains outstanding on an unlocked host.

## Remaining work

Prompt 4B still owns broad Guide/player/OSD presentation, player fullscreen,
native video layering, and shared-component adoption where that later work
proves a real second consumer. Prompt 3B did not modify those owners.

Windows-only acceptance still includes DirectComposition runtime evidence,
native presentation/transparency, libmpv playback, HDR/tone mapping, remote
stream acceptance, audio passthrough, fullscreen behavior, and the broader
codec/container campaign. Packaging, signing, updating, and approval of a
redistributable libmpv dependency also remain outside this pass.

## Prompt 4B Guide and player refinement

### Provenance

- LineupDesktop starting commit:
  `a3f6f84e6f29b083d25e70b62045cb290d679ba6` on
  `replatform/flutter-native`.
- LineupDesktop ending commit: the
  `feat(guide): refine portable Guide and player parity` commit containing this
  section. Its exact SHA is recorded in the Prompt 4B closeout because a commit
  cannot contain its own SHA.
- Upstream product reference: sibling `TJZine/Lineup`, fetched and inspected
  read-only at `origin/code-health`
  `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`. Upstream `origin/main` remained
  the README-only `5f01be6a719174ae1f89a70b8cab1095bf17c8b9` and was not used as the product
  implementation reference.
- The upstream application was not run with a Plex account. Evidence came from
  committed source, tests, styles, input policy, and timing constants. No
  credential-bearing or private media surface was captured.

Relevant upstream paths included:

- `src/modules/ui/epg/**`, including `EPGFocusNavigator`, `EPGVirtualizer`,
  `EPGShellView`, cell/info-panel views, constants, tests, and styles;
- `src/modules/ui/player-osd/**`;
- `src/modules/ui/mini-guide/**`;
- `src/modules/ui/playback-options/**`;
- `src/modules/navigation/**`; and
- `src/core/channel-tuning/**`.

### Ending parity matrix

| Surface or behavior | Classification | Evidence and disposition |
| --- | --- | --- |
| Guide header, channel identity rail, time ruler, current-time line, program grid, progress, focused/current/past treatment and details | Parity | Flutter uses responsive proportions rather than copying webOS coordinates. Channel logos remain not applicable because the current Desktop `Channel` model has no safe logo fact. |
| Focused program, selected program, tuned channel, currently airing program and pointer hover | Parity | `GuideController` owns distinct focused and selected identities; tuning remains in `LineupController`/`PlayerCoordinator`; airing is clock-derived; hover is local visual state and cannot retune or replace logical focus. |
| Vertical/time navigation and jump to now | Parity | Left/right follows scheduled geometry. Up/down carries a focus time into the adjacent row and chooses the overlapping or nearest program. Page navigation is viewport-sized and Play/P jumps to now, matching upstream input intent. |
| Guide context restoration | Parity | The persistent Guide owner retains channel/program identity, time window, and vertical offset across Guide/PiP/player route disposal and return. Focus repair cannot tune. |
| Vertical virtualization and bounded derived work | Parity | Fixed-extent lazy rows, bounded overscan, 64-row schedule/index caches, four concurrent schedule loads, a 256-program per-row projection ceiling, 12-entry artwork cache, four artwork loads, and generation rejection remain explicit. A 1,000-channel fixture is covered. |
| Horizontal ownership | Intentional Desktop adaptation | The visible `guideHours` window is the horizontal viewport and `windowStart` is its owner; navigation advances the window in 30-minute steps. There is no second pixel scroll owner or competing jump-to-now animation. |
| Guide with PiP allocation | Parity | `PlayerSurface` is the single Flutter/native presentation geometry used by both PiP and full player. Tuning remains in Guide; PiP can then open the full shell. The macOS unsupported surface never fabricates video. |
| Tune, replacement tune, loading, retry, stopped/ended and stale work | Parity | The retained coordinator serializes tune operations, uses tune generations, releases playback leases, rejects optional stale public-seam generations, and projects recoverable versus terminal failures without adding widget playback state. |
| Ready, playing, paused, buffering, seeking, track and output metadata projection | Parity | The public seam accepts these contract-valid states. The OSD exposes only available tracks/telemetry, disables unsupported actions honestly, and does not add native handles. Production Windows still rejects stale load IDs before Dart. |
| OSD structure and status-sensitive auto-hide | Parity | One coordinator timer uses an epoch, resets on interaction, stays visible for paused/buffering/seeking, suspends while controls have accessibility focus, and cannot hide a reopened overlay. Error and track surfaces are untimed. |
| Mini Guide | Parity | Five bounded nearby rows match upstream structure and expose channel identity, current title/progress, next title, tuned state, logical focus, paging, replacement tune, full-Guide entry and exact input guidance. |
| Responsive Guide/player layout | Intentional Desktop adaptation | Central Guide policy controls padding, rail width, showcase/PiP allocation and compact details. OSD and mini Guide use capped safe-area surfaces. Widget coverage includes 800×600, 1280×720, 1360×840, 1600×900, 1920×1080 and 3840×2160 logical sizes. |
| Accessibility | Parity | Only lazy visible rows/cells enter the tree; channel, program, time range, airing/ended/upcoming, selected/focused/tuned, progress, loading/buffering, modal labels, action names and disabled availability are exposed. |
| Exact TV pointer behavior and animation timing | Insufficient evidence | Upstream is remote-first and source does not establish a Desktop pointer contract. Flutter uses click-to-focus, double-click current program to tune, visible hover, Tab focus, reduced motion, and short focus transitions. |
| Native video, transparency, HDR, fullscreen and media acceptance | Windows-only validation | No runner, C++, DirectComposition, engine patch, libmpv, CMake or packaging code changed. macOS layout evidence does not prove native composition. |

### Deterministic evidence

`test_driver/ui_harness.dart` is a separate development composition root. It
contains 1,000 synthetic channels with 12 synthetic programs each and a
public-seam player fake. It contains no native handle, URL credential, private
metadata, or production import path from `lib/main.dart`.

Focused tests cover geometry, visible ranges, bounded widget/load counts,
1,000-channel traversal, overlap navigation, focus/selection distinction,
lineup replacement, stale schedule and native events, Guide scroll restoration,
Guide/PiP/player transitions, OSD fake-time reset/suspension/currentness,
mini-Guide paging/replacement, state projection, unsupported macOS behavior,
representative responsive sizes, semantics, and retry/terminal errors.

Host-dependent pixel goldens are not used as portable evidence. Flutter's
test raster differs across operating systems, and a synthetic colored PiP box
cannot validate the Windows native presentation stack. CI instead runs the
responsive Guide/player widget, focus, semantics, and geometry suites on
Windows in addition to the portable Dart suite. Real video composition,
libmpv, HDR, and presentation quality still require the Windows runtime
evidence described below.

### macOS runtime and profile evidence

The synthetic 1,000-channel × 12-program harness built and launched in ordinary
debug mode and profile mode at the runner's initial 800×600 logical window.
Both used the Metal Impeller backend; the profile bundle was 74.0 MB. The host
was locked, `open` could not foreground the application, and Computer Use could
not unlock it. Consequently no claim is made for manually observed traversal,
resize, pointer, keyboard, VoiceOver, frame timing, or absence of jank from
those runs.

Deterministic widget instrumentation at 1280×800 observed 1,000-channel first
viewport construction with 1,171 widgets, 13 cached/loaded rows, roughly 61–75
ms in the debug test process depending on the run, about 0.3–3.3 ms for 500
logical downward moves before the following frame, and roughly 7–10 MB RSS
growth. These are diagnostic observations, not profile-mode frame claims and
not Windows evidence.

Remaining acceptance is the unlocked-host manual campaign plus all Windows-only
native presentation/media items already listed above. In particular, these
portable tests and macOS builds do not prove DirectComposition layering,
transparent video, HDR, hardware decode, fullscreen/multi-monitor behavior,
remote Plex streams, audio passthrough, lifecycle, packaging, signing, or
installer behavior.

## Prompt 4C source-defined theme and shell refinement

### Provenance and evidence boundary

- LineupDesktop starting commit: `dfa5f505290a2f4cbda12b496da10e88db86b057`
  on `replatform/flutter-native`.
- Upstream product reference: sibling `TJZine/Lineup`, inspected without
  modification at `origin/code-health`
  `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`. Upstream `origin/main` remains
  the README-only `5f01be6a719174ae1f89a70b8cab1095bf17c8b9`.
- The upstream development command defined in `package.json` is `npm run dev`
  (`vite`). It was not run because the remotely controlled macOS display was
  locked. No viewport or browser dimensions were observed, and no private Plex
  state was rendered.
- LineupDesktop was likewise not foregrounded. Evidence in this pass is limited
  to committed upstream source, Flutter source, deterministic tests, semantics,
  layout constraints, static analysis, and build results. It is not evidence of
  live visual parity.

Exact upstream theme sources inspected were
`src/modules/ui/theme/themeDefinitions.ts`, `src/styles/tokens.css`,
`src/styles/themes.css`, `src/modules/settings/ThemePreferencesStore.ts`,
`src/core/app-shell/runtime/AppThemeController.ts`, and its tests. Structural
sources inspected included `src/modules/ui/epg/view/shell/EPGShellView.ts`, the
EPG `styles.shell.css`, `styles.classic.css`, `styles.info-panel.css`,
`styles.cells.css`, and `styles.theme.css`; `src/modules/ui/player-osd/**`;
`src/modules/ui/mini-guide/**`; `src/modules/ui/playback-options/**`;
`src/modules/ui/auth/AuthScreen.ts` and `AuthPinDisplay.ts`; Settings,
onboarding, profile/server/audio setup, and Channel Setup component/style
sources; and `src/modules/settings/EpgPreferencesStore.ts`.

### Source-defined changes

- `LineupThemeName` defines the exhaustive upstream order: Ember & Steel,
  Slate & Pine, Swiss Minimal, DirecTV Classic, and Glassmorphism. Ember & Steel
  is the invalid/missing-value default.
- `LineupSettings` persists the theme and Guide presentation. The existing
  controller save/rollback owner remains authoritative; successful changes
  rebuild the root `MaterialApp` immediately, while failed writes retain the
  previous theme.
- One `ThemeData` builder and one `LineupThemeRoles` extension own deep,
  surface, elevated, overlay, focus, selected, tuned, live, text, border,
  progress, scrim, radius, and overlay-safe-area semantics. Onboarding, Channel
  Setup, management, Settings, Guide, PiP, program cells, player surfaces, OSD,
  mini Guide, selectors, dialogs, and notices consume these roles. The QR card
  intentionally remains white for scan contrast.
- Reduced motion and large focus indicators remain independent persisted
  accessibility preferences. Mechanical checks cover primary text and focused
  control contrast for every theme.
- The persistent management `NavigationRail` remains on Channels, Settings,
  and Diagnostics, but is absent from Guide and Player. Both immersive surfaces
  use one shared Lineup menu that calls the existing route-selection owner.
  Guide/player transitions retain explicit Escape/Back behavior and focus
  restoration without a second navigation model.
- Classic Guide with application-owned PiP remains the default. Overlay Guide
  is persisted as a secondary mode and structurally layers the same Guide over
  the same `PlayerSurface`. The branded header, Now Playing/showcase allocation,
  16:9 PiP, information area, channel rail, time ruler, duration-based grid,
  current-time line, library filter, and current/focused/selected/tuned roles
  remain in one Flutter geometry model.
- OSD surfaces use semantic overlay/scrim roles; track selectors are a
  media-oriented right rail; mini Guide retains bounded shelf content; channel
  entry retains its two-second auto-commit digit buffer; unsupported macOS,
  loading, buffering, retry, sleep timer, telemetry omission, and overlay
  timing remain truthful public-contract behavior.
- Accepted QR/PIN, protected-profile keypad, measured server facts, audio
  choice, and staged Channel Setup ownership were retained after source
  inspection rather than reimplemented.

### Prompt 4C locked-host classification matrix

No row in this matrix is classified as visual parity.

An independent source/diff/test review of the Prompt 4C commit identified and
the follow-up remediation closed these mechanical gaps: focused Mini Guide
foreground contrast (including DirecTV), long native track-list scrolling,
rendered 16:9 PiP constraints, persistent tuned Now Playing identity beside
focused-program details, real welcome-button autofocus and remote activation,
root-level reduced-motion propagation, shared large-focus width, and stronger
persistence/contrast/layout tests. Source-only differences in exact OSD,
mini-Guide, selector, typography, gradient, shadow, hint, and artwork treatment
remain Prompt 4E visual-adjudication inputs rather than accepted visual claims.

| Surface or state | Temporary classification | Source/test evidence and deferred acceptance |
| --- | --- | --- |
| Startup, auth welcome, QR/PIN, waiting, retry | Source-aligned theme mechanics implemented | Semantic theme roles reach the existing branded hierarchy; unlocked comparison remains required. |
| Profiles and protected PIN | Existing implementation retained after source inspection | Card/keypad ownership and semantics remain; proportions, focus-ring appearance, and all themes require unlocked acceptance. |
| Server discovery/selection/retry | Existing implementation retained after source inspection | No health, latency, or relay facts are fabricated; presentation remains subject to unlocked acceptance. |
| Audio Setup and all Channel Setup stages | Source-aligned theme mechanics implemented | Existing staged header/content/footer and state owners remain; live spatial acceptance is deferred. |
| Channels empty/populated/editor/delete/persistence error | Intentional Desktop structural adaptation | Management rail and readable-width workspace remain. Upstream has no equivalent implemented channel editor. |
| Settings | Source-aligned structure implemented | Existing category/detail layout now exposes persisted theme and Guide presentation; live typography and spacing acceptance is deferred. |
| Diagnostics | Intentional Desktop structural adaptation | Credential-safe management destination retained; no upstream consumer-equivalent surface exists. |
| Guide without playback | Source-aligned structure implemented | Immersive shell, branded header, information area, time geometry, semantic states, filters, and bounded rows are deterministic; requires unlocked visual acceptance. |
| Guide with default PiP | Source-aligned structure implemented | Classic/PiP is default and the single 16:9 `PlayerSurface` geometry remains authoritative; video composition requires Windows-native validation. |
| Overlay Guide | Source-aligned structure implemented | Persisted secondary layout layers Guide over `PlayerSurface`; scrim/readability and transitions require unlocked visual acceptance. |
| OSD, mini Guide, channel entry, track selectors, loading/error | Source-aligned structure implemented | Hierarchy, safe area, right rail, digit buffer, bounded shelf, truthful telemetry, and timer behavior are testable; visual motion/contrast requires unlocked acceptance. |
| Five-theme coverage across major surfaces | Source-aligned theme mechanics implemented | Inventory/default/persistence/immediate update/semantic roles/contrast are deterministic. Visual balance of every theme requires unlocked acceptance. |
| Responsive 1280×720, 1600×900, 1920×1080 | Visual acceptance must occur on an unlocked host | Existing layout tests exercise these logical regimes; no live side-by-side state was observed. |
| Native video, transparency, HDR, hardware decode, fullscreen | Requires Windows-native validation | No Windows, C++, engine, libmpv, or native-presentation source changed or was claimed. |

No new golden baselines were generated or accepted. Existing approved goldens
were not rewritten. Prompt 4E must perform the foreground side-by-side campaign
on an unlocked Mac at 1280×720, 1600×900, and 1920×1080 across all required
onboarding, management, Guide, PiP, overlay, OSD, mini-Guide, selector,
buffering, error, and unsupported-backend states. It must adjudicate composition,
proportions, typography, spacing, artwork, action placement, focus visibility,
theme balance, transitions, and compact-window behavior. Windows still owns
native video/presentation acceptance.
