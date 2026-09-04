# Portable UI parity

> [!IMPORTANT]
> This is a historical, campaign-scoped visual evidence record. For current
> product classifications, evidence gaps, priorities, and release conclusions,
> use [Definitive Product Parity](product-parity.md). In particular, current
> `scheduleWindow` caps current per-row projection at 1,000 programs, and
> `GuideController` inherits that bound. The historical 256-program statement
> below was a documentation error rather than an implemented limit and is
> corrected in place.

This document is the source record for Prompt 3B and Prompt 4B portable UI
parity, the full Prompt 4C source-defined theme and shell refinement, Prompt 4D
portable functionality and recovery hardening, and Prompt 4E unlocked portable
visual acceptance. Historical parity classifications belong to the Prompt 3B
and Prompt 4B sections that contain them; Prompt 4C, 4D, and 4E claims are
limited to their named sections. None of these sections claims Windows media
validation; that remains Prompt 5 work.

The earlier “Parity” classifications below are historical records of the
Prompt 3B and Prompt 4B source-based passes. Prompt 4C does not promote those
historical classifications to live visual acceptance; its locked-host
classification matrix is recorded in the Prompt 4C section below. Prompt 4E's
visual classifications are recorded only in its own visual-acceptance section.

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
| Vertical virtualization and bounded derived work | Parity | Fixed-extent lazy rows, bounded overscan, 64-row schedule/index caches, four concurrent schedule loads, a 1,000-program per-row projection ceiling, 12-entry artwork cache, four artwork loads, and generation rejection remain explicit. A 1,000-channel fixture is covered. |
| Horizontal ownership | Intentional Desktop adaptation | The visible `guideHours` window is the horizontal viewport and `windowStart` is its owner; navigation advances the window in 30-minute steps. There is no second pixel scroll owner or competing jump-to-now animation. |
| Guide with PiP allocation | Parity | `PlayerSurface` is the single Flutter/native presentation geometry used by both PiP and full player. Tuning remains in Guide; PiP can then open the full shell. The macOS unsupported surface never fabricates video. |
| Tune, replacement tune, loading, retry, stopped/ended and stale work | Parity | The retained coordinator serializes tune operations, uses separate tune and native-load generations, rejects stale events, and projects recoverable versus terminal failures without adding widget playback state. |
| Ready, playing, paused, buffering, seeking, track and output metadata projection | Parity | The public seam accepts these contract-valid states. The OSD exposes only available tracks/telemetry, disables unsupported actions honestly, and does not add native handles. Production Windows still rejects stale load IDs before Dart. |
| OSD structure and status-sensitive auto-hide | Parity | One coordinator timer uses an epoch, resets on interaction, stays visible for paused/buffering/seeking, suspends while controls have accessibility focus, and cannot hide a reopened overlay. The classic-TV default hides transport UI and blocks Player-local transport shortcuts; DVR playback controls restores them without changing native/libmpv behavior. Error and track surfaces are untimed. |
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

For Prompt 4B, remaining acceptance is the unlocked-host manual campaign plus
all Windows-only native presentation/media items already listed above. In
particular, those portable tests and macOS builds do not prove
DirectComposition layering, transparent video, HDR, hardware decode,
fullscreen/multi-monitor behavior,
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
  remain in one Flutter geometry model. Overlay details omit the poster slot
  only when synchronous program metadata contains no poster reference; loading
  and failed referenced artwork retain the normal geometry so the rare fallback
  cannot flash during ordinary Plex selection changes.
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
| Channel Setup stages | Source-aligned theme mechanics implemented | Existing staged header/content/footer and state owners remain; live spatial acceptance is deferred. |
| Channels empty/populated/editor/delete/persistence error | Intentional Desktop structural adaptation | Management rail and readable-width workspace remain. Upstream has no equivalent implemented channel editor. |
| Settings | Source-aligned structure implemented | The category/detail layout exposes the five themes as labeled palette rows with explicit selected and focus states; Guide presentation remains in the same settings owner. |
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

## Prompt 4D portable functionality and recovery hardening

### Provenance and evidence boundary

- LineupDesktop starting commit:
  `dc4d369bb4b77128fad27fbf9189898a9a3c9237` on
  `replatform/flutter-native`.
- Upstream product reference: sibling `TJZine/Lineup`, fetched and inspected
  read-only at authoritative implemented branch `origin/code-health`, commit
  `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`.
- Upstream `origin/main` remains the README-only initial commit and was not
  treated as the implemented product.
- Evidence is committed source, deterministic controller/widget tests,
  temporary-file persistence, the public `NativePlayer` seam, static analysis,
  and the macOS build. The host display remained locked. No live visual,
  pointer, keyboard, VoiceOver, or perceived-performance claim is made.

### Functional classification

| Behavior | Prompt 4D classification | Evidence and disposition |
| --- | --- | --- |
| Splash/startup and blocking startup failure | Behavior implemented and tested | Startup has one semantic progress surface and one sanitized blocking failure. The known engine-marker failure uses fixed safe copy; arbitrary exception text is not presented. Appearance remains Prompt 4E. |
| Authentication failure and expired PIN | Behavior implemented and tested | The onboarding owner keeps retry/new-code/cancel actions, non-overlapping polling, epoch rejection, and safe Plex messages. Secure credential writes are serialized with cancel/logout; failed secure cancellation stays visibly retryable until the queued token is cleared. |
| Blocking, recoverable, warning, transient, and validation ownership | Intentional Desktop adaptation | Startup alone is blocking. Onboarding owns auth/server recovery, player owns playback retry/close, settings/channels/Channel Setup own write or validation failures, and ordinary success is reflected by authoritative state. No event bus, universal modal, or unused toast service was added. |
| Persistence failures and corrupt-state recovery | Behavior implemented and tested | File state is atomically replaced and corrupt input is quarantined. Settings, channels, Channel Setup, current-channel, selected-server clearing, and logout retain or restore prior safe state on failed writes. There is no browser quota lifecycle consumer on Desktop. |
| Network/offline and reconnect | Behavior implemented and tested | Bounded Plex requests return actionable safe errors. Discovery and playback expose explicit retry; a failed discovery does not silently change profile scope, and a later refresh reconnects through the saved selection. Continuous connectivity polling was omitted because there is no current consumer. |
| Profile switching | Behavior implemented and tested | Settings exposes the current Plex Home profile and enters the existing protected-PIN picker. Cancel returns to the prior route only while that recovery remains current; selecting a new profile invalidates the old action. |
| Server switching, saved-server clearing, and disappearance | Behavior implemented and tested | Settings enters the existing server selector with reconnect, cancel, clear-saved-server, retry discovery, and switch-profile actions. Clearing removes only the profile-scoped selection and retains saved per-server lineups. A disappeared selected server clears live libraries/media/lineup instead of reusing another profile or stale endpoint. |
| Direct/local/relay and latency facts | Behavior implemented and tested | Only a successfully selected connection is labeled. The label uses its real direct-local, direct-remote, or Plex Relay flags and its measured probe duration. Priority is applied before an eight-endpoint bound, each tier is probed concurrently with per-request timeout, and no background health claim or fabricated status is shown. |
| Audio Setup | Intentionally omitted | Desktop uses the system-selected output without asking the user to dismiss an explanation-only onboarding step. Optional passthrough is separately specified and deferred until Windows can report and consume it accurately. |
| Direct-play audio fallback | Behavior omitted because it has no current consumer | The legacy persisted field and nonfunctional toggle were removed. Current Dart stream selection cannot safely promise alternate-track fallback without native selected-track coordination. |
| Channel Setup cancellation and progress | Behavior intentionally adapted for Desktop | Proposal/review remains user-cancellable before commit; applying the accepted 1,000-channel plan is one atomic local save. Cancellation/failure preserves the old lineup. Timing output is diagnostic only and does not establish a perceived-performance or foreground acceptance claim. |
| Channel reorder, copy, import/export, bulk administration | Behavior omitted because it has no current consumer | Channel number editing provides ordering, provenance is visible, and deletion is confirmed. Upstream import/export internals do not establish a current Desktop workflow, so no administration suite was invented. |
| Guide theme, layout, density/time/past window | Behavior implemented and tested | Existing persisted settings continue to update the Guide owner and rollback on write failure. Labels now include descriptions. |
| Library filters | Behavior implemented and tested | The persisted setting shows or hides the real Guide library filter. Disabling it clears an active filter so hidden state cannot keep channels excluded. |
| Now Playing context | Behavior implemented and tested | The persisted setting directly controls the tuned channel/program context in the Guide toolbar. |
| Player controls auto-hide | Behavior implemented and tested | A validated 2–15 second setting feeds the existing epoch-safe coordinator timer. Paused, buffering, and seeking events reveal the OSD and restart that timer. |
| Reduced motion, large focus indicators, profile picker, diagnostics | Behavior implemented and tested | These persisted settings retain their existing root theme, focus, startup, and redacted-diagnostics consumers. |
| Subtitle mode/language/forced preference | Behavior omitted because it has no current consumer | Legacy persisted fields were removed. The public native track projection lacks reliable forced/default preference facts, so applying them would fabricate behavior. Manual available-track selection remains implemented. |
| Video quality, HDR/tone mapping, audio output/passthrough controls | Deferred to Windows | Unvalidated fields are neither persisted nor exposed as ordinary settings. No hardware, output-device, HDR, or passthrough capability is claimed. |
| Now Playing, current/next context, channel transition, OSD, playback options | Behavior implemented and tested | The retained player coordinator supplies current/next metadata, status-sensitive OSD, available track selectors, telemetry only when present, retry, and immediate tuning/loading presentation. A second delayed transition coordinator was unnecessary. |
| Mini Guide, channel badge, number entry, sleep timer | Behavior implemented and tested | Five bounded rows, current/next context, tuned/focused states, direct channel-number commit, channel identity in the OSD, and cancellable sleep timers remain under the one overlay owner. |
| Exit/back confirmation | WebOS-only/not applicable | Upstream confirmation exits to the webOS Home screen via `window.close()`. Desktop Escape/Back closes overlays or returns to Guide/menu; native desktop window closing is not replaced with a browser-style exit modal. |
| App restart/restore and logout | Behavior implemented and tested | Temporary persistence restores profile-scoped server, libraries, a 1,000-channel lineup, current settings, and ready state. The player coordinator orders successful logout with native playback stop; pending secure writes are cleared first, late operations are rejected, and a cleanup failure leaves both session and playback intact with a safe retry. |
| Stale async work and disposal | Behavior implemented and tested | One application epoch rejects PIN/profile/server/library work; settings use a current write generation; content-scope changes invalidate player tune/load work and Guide schedule/artwork caches; credential writes are serialized with clear; timers, subscriptions, isolates, test streams, and caches retain bounded disposal. |
| Diagnostic/developer upstream modules | Developer-only | Credential-safe, bounded diagnostics remains the Desktop support surface. Upstream developer overrides, raw console controls, private probes, and aggressive experimental preload are not product settings. |
| webOS lifecycle/network/browser behavior | WebOS-only/not applicable | Browser online/offline events, localStorage quota lifecycle, background-page policy, webOS exit, and TV runtime APIs are not copied into Flutter. Equivalent current Desktop failures are handled at their real persistence or Plex seams. |
| Native video, DirectComposition, libmpv, HDR, audio, fullscreen, packaging | Missing but Windows-native | Prompt 4D neither modifies nor validates these owners. They remain Prompt 5 and physical Windows acceptance work. |

### Deterministic product-spine and bounded-work evidence

`test/app/product_spine_test.dart` is a test-only composition. It uses a
synthetic `PlexClient` subclass at the existing transport seam, a synthetic
`NativePlayer` at the public player seam, a controlled Guide clock, explicit
event order, an actual temporary `FileAppStore`, and an in-memory credential
store. Production does not import it and it contains no Plex account data,
credential, native handle, or private media URL.

The scenario covers first launch, PIN creation/polling, authentication, Plex
Home profile and protected PIN, discovery, server selection and measured
connection facts, libraries, Channel Setup, Guide scheduling,
tune/loading/playing coordinator state, OSD, mini Guide,
track selection, settings writes, redacted playback failure, retry, network
failure/reconnect, a 1,000-channel atomic rebuild, process-style
dispose/recreate restore, and controller logout. Focused coordinator tests cover
live playback logout and scope cleanup. Separate widget suites retain keyboard,
controller-like logical keys, focus restoration, modal containment, semantics,
responsive layout, and bounded visible Guide work.

The deterministic tests assert that first-viewport Guide loading and caches
remain bounded independently of 200, 500, or 1,000-channel cardinality and
that a 1,000-channel lineup survives persistence/restart. Emitted timing,
widget-count, and RSS values remain debugging diagnostics only; they are not
profile-mode frame timing, perceived smoothness, or native playback evidence.

Prompt 4D was completed on a locked macOS host. Functional claims are based on
source, deterministic tests and build evidence. Live visual and interaction
acceptance remains deferred to Prompt 4E.

Prompt 4E must still perform the unlocked foreground matrix already recorded
above, including onboarding, profile/server recovery, settings descriptions,
all five themes, Guide library/Now Playing states, PiP/overlay, tuning/loading,
OSD timing, mini Guide, track selectors, errors, focus visibility, pointer and
keyboard/controller behavior at 1280×720, 1600×900, and 1920×1080. Windows
native acceptance remains Prompt 5.

## Prompt 4E unlocked portable visual acceptance

### Provenance and evidence boundary

- LineupDesktop started at
  `2f5cbbe1dafacc35be5163545109871f27ffcbe7` on
  `replatform/flutter-native`. The implementation and accepted visual evidence
  ended at `db6234952cec6b799fe90daeb0cbdb948a3b7a74`; the following docs-only
  closeout commit records that immutable implementation SHA.
- The authoritative implemented upstream remains the read-only sibling
  `TJZine/Lineup` branch `origin/code-health` at
  `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`. The local `code-health` branch
  had one unrelated tooling commit, so comparisons used the exact remote SHA.
  `origin/main` remains the README-only
  `5f01be6a719174ae1f89a70b8cab1095bf17c8b9`.
- Upstream ran with `npm run dev` (`vite`) at a clean local origin. It has Jest
  mocks and synthetic test data but no production-reachable demo/fixture
  switch. Account-only onboarding was inspected through the user's existing
  authenticated browser session; private names, server/library labels, media,
  credentials, and artwork URLs were neither committed nor retained.
- LineupDesktop used the repository-pinned Flutter framework
  `4cf24164269a5ebf0c16a028a00727d0e77bbb05` (Flutter 3.47.0, Dart 3.13.0).
  `test_driver/ui_harness.dart` supplied 1,000 synthetic channels with 12
  synthetic programs each and the existing fake-player seam. It remains
  unreachable from the production composition root.

### Viewports and accepted evidence

Upstream was visually inspected at exact logical 1280×720, 1600×900,
1920×1080, and compact 1100×800 browser viewports. Flutter was observed in its
initial 800×600, compact 1100×800, large 1600×900, and maximized 1728×1084
macOS windows, while deterministic layout tests exercised 1280×720, 1600×900,
1920×1080, compact desktop, 4K, and Windows-style 200 percent DPR regimes. The
accepted golden viewport is 1280×720 at DPR 1 with pinned Flutter
Roboto/Material Icons, synthetic assets and media, a fixed UTC Guide clock,
and a fake player.

Working browser/window captures remained in ignored temporary storage. Every
committed baseline was regenerated after font and theme correction and then
opened and visually inspected. The accepted focused contracts are:

- profile selection;
- Channel Setup review;
- Ember & Steel Guide without playback;
- Ember & Steel Guide with deterministic PiP allocation;
- overlay Guide;
- full-width Player OSD;
- full-width mini-Guide shelf;
- Settings in representative alternate Slate & Pine.

QR/PIN authentication was rendered live upstream and remains covered by
Flutter widget tests, but it was deliberately not accepted as a golden because
the production expiry countdown reads wall-clock time. A moving countdown is
not a deterministic baseline, and adding a second time architecture solely for
one image would be disproportionate.

### Visual acceptance classification

"Insufficient evidence" below means the state retained source/test coverage but
was not both rendered and visually adjudicated during the unlocked interval.
It does not mean the state is absent.

| Surface or state | Final Prompt 4E classification | Evidence and disposition |
| --- | --- | --- |
| Splash/startup | Structural parity with acceptable Flutter adaptation | Branded Flutter startup and upstream startup sources were inspected; Flutter's native-process startup is intentionally not a browser boot sequence. |
| Auth welcome | Structural parity with acceptable Flutter adaptation | Upstream rendered live; Flutter branded hierarchy, primary action, focus and responsive cases rendered in deterministic tests. |
| QR/PIN waiting | Structural parity with acceptable Flutter adaptation | Upstream rendered live and Flutter rendered in tests. QR remains white for scan contrast; no golden was accepted because the countdown is not frozen. |
| Auth failure/retry | Insufficient evidence | Recovery ownership and tests passed, but no credential-safe live failure was induced during this pass. |
| Profile selection | Visual parity | Deterministic golden accepted after direct inspection; protected state is distinct without exposing a real profile. |
| Protected-profile PIN | Structural parity with acceptable Flutter adaptation | Focus containment, autofocus, semantics, cancel and completion are tested; the complete keypad was not accepted as a separate golden. |
| Server discovery/selection | Structural parity with acceptable Flutter adaptation | Upstream server selection rendered live; Flutter fixture/tests retain measured connection facts without private server data. |
| Server error/retry | Insufficient evidence | Safe retry behavior is deterministic, but a live private-account failure was not manufactured. |
| Audio Setup | Intentionally omitted | The former explanation-only Flutter step was retired. No device, status, or passthrough behavior is fabricated. |
| Channel Setup libraries, strategies/options, progress and completion | Structural parity with acceptable Flutter adaptation | Upstream rendered live through all stages including completion; Flutter stages and progress are exercised by tests. |
| Channel Setup review | Visual parity | Inspected deterministic golden accepted. The staged header/workspace/footer and destructive replacement priority are preserved. |
| Channels empty/populated, editor and destructive confirmation | Intentional Desktop adaptation | Responsive management layout and explicit confirmation are rendered/tested. Upstream has no equivalent implemented desktop channel editor. |
| Settings | Structural parity with acceptable Flutter adaptation | Category/detail hierarchy and compact theme chooser render at 800×600, 1280×720, and 1920×1080; immediate persistence, all-theme selection, semantics, focus, and rollback are tested. |
| Diagnostics | Intentional Desktop adaptation | Credential-safe support surface retained; upstream has no consumer-equivalent management page. |
| Persistence failure | Structural parity with acceptable Flutter adaptation | Local error ownership and rollback rendered in widget tests; no destructive live disk failure was induced. |
| Guide no channels, loading, loading row, error/retry row | Structural parity with acceptable Flutter adaptation | Empty/loading/error rows, retry focus and bounded geometry are rendered in deterministic tests. |
| Guide populated without playback | Visual parity | Ember & Steel golden accepted and live 1,000-channel harness inspected. |
| Default active-playback PiP | Structural parity with acceptable Flutter adaptation | Golden accepts only the Flutter 16:9 allocation and information hierarchy. It does not claim video composition. |
| Overlay Guide | Structural parity with acceptable Flutter adaptation | Golden accepted; the same Guide and player surface are layered without another layout owner. |
| Focused current/future, tuned distinct from focus, current-time indicator | Visual parity | Live keyboard traversal and golden evidence show separate focus, tuned and current-time roles. |
| Library filter/tabs and information/showcase | Structural parity with acceptable Flutter adaptation | Existing filtered Guide and detail-region tests passed; private upstream library names were not captured. |
| Compact/comfortable density and 1,000-channel navigation | Structural parity with acceptable Flutter adaptation | Responsive and bounded-work tests passed; unlocked debug traversal showed no blank rows or obvious focus lag. |
| Full player shell | Structural parity with acceptable Flutter adaptation | Deterministic player surface is truthful on macOS; real media remains Windows-native. |
| OSD | Visual parity | Corrected from a centered generic card to the upstream-recognizable bottom safe-area gradient; inspected golden accepted. |
| Mini Guide | Visual parity | Corrected from a centered list dialog to a full-width top shelf with row-level focus; inspected golden accepted. |
| Audio/subtitle selectors, number entry and sleep timer | Structural parity with acceptable Flutter adaptation | Keyboard, scrolling, availability, digit timeout, and timer tests passed; no unsupported controls were added. |
| Loading/buffering and playback error/retry | Structural parity with acceptable Flutter adaptation | Truthful fake-player states and recovery are tested; no native playback claim is made. |
| Unsupported macOS backend | Intentional Desktop adaptation | The user-facing unsupported state remains explicit and disables controls that cannot work. |
| Ember & Steel primary matrix | Structural parity with acceptable Flutter adaptation | Primary Guide/player/onboarding/setup surfaces were inspected; browser-specific gradients, font raster and shadows were not treated as defects. |
| Slate & Pine representative matrix | Structural parity with acceptable Flutter adaptation | Settings golden accepted and all representative theme-role surfaces pass shared contrast/layout tests. |
| Swiss Minimal, DirecTV Classic and Glassmorphism representative states | Structural parity with acceptable Flutter adaptation | Settings, Guide/PiP, OSD and focused controls were switched and inspected live in each theme. Shared onboarding/error roles, contrast and responsive behavior remain deterministic-test evidence rather than separate accepted goldens. |

### Focused corrections and intentional adaptations

The only demonstrated composition changes were localized to the Player. OSD
content now spans the bottom safe area over a vertical gradient with responsive
horizontal insets. The mini Guide now spans the top edge, removes the generic
card/heading treatment, and uses row separators plus a dedicated focus edge.
Existing coordinator, focus, semantics, track, timing, and fake-player owners
were retained. Button typography now derives from the application's text theme,
which removed a cross-surface family mismatch exposed by deterministic
rendering. The existing Guide clock seam is passed through the bootstrap only
for deterministic test composition; no service, dependency, or alternate state
owner was introduced.

Management navigation remains a Desktop adaptation. Guide and Player remain
immersive and do not inherit the management rail. PiP is a Flutter allocation
only, diagnostics remains Desktop-specific, and audio controls remain deferred
rather than presenting unimplemented platform claims.

### Interaction and profile observations

During the unlocked debug run, keyboard navigation exercised vertical and
horizontal Guide movement, Page Down, jump/play-to-now, tune, Guide-to-player,
OSD, mini Guide, Escape/Back, and overlay closure. Focused details changed with
navigation, the tuned channel remained distinct, and focus restoration did not
show a dead endpoint. Browser pointer interaction exercised upstream profile,
server, audio and Channel Setup progression. Widget acceptance additionally
covers profile/server/PIN cancellation, management/Settings navigation,
dialogs, track selectors, theme switching, resize regimes, pointer actions,
focus restoration, and controller-style logical keys. No physical gamepad was
available; Windows gamepad acceptance remains Prompt 5.

The profile harness built a 74.2 MB bundle and launched with Metal Impeller.
The fixture contained 1,000 channels × 12 programs. Forty Page Down events
reached channel 401; 80 right moves, 20 left moves, jump-to-now, tune,
player/OSD/mini-Guide transitions, theme changes, and compact/large resizing
were exercised in the foreground. No obvious blank rows, clipping, focus lag,
or visual jank was observed. Two rapid route-and-window resize attempts emitted
`Resize timed out`; the application remained responsive and the same compact
and large sizes rendered correctly when inspected after the route settled.
Process RSS moved from about 167 MB after launch to 221 MB after traversal,
overlay, resize, and five-theme work. No growing cache, blank-cell, or process
failure was visible, but these observations are not sampled frame timings.

Deterministic 1,000-channel instrumentation at 1280×800 reported about 94 ms
for first viewport construction, 1.4 ms for 500 logical navigation moves before
the following frame, 1,181 widgets, 13 cached rows, and about 9.9 MB RSS growth
in the test process. These figures are diagnostics, not Windows-native or
profile-frame proof.

### Remaining Windows-native validation

Prompt 4E did not modify or validate `windows/**`, the patched engine, C++,
DirectComposition, libmpv, D3D11, decode, HDR, tone-mapping, passthrough,
native fullscreen, packaging, or the native video layer. The macOS
deterministic player rectangle proves Flutter layout only. Prompt 5 remains
solely responsible for real video inside that region, Windows media behavior,
native PiP composition, hardware performance and gamepad acceptance.

## 2026-08-25 upstream UI parity campaign

### Provenance and evidence boundary

This current campaign began at implementation baseline
`3a4b5e33507b354edf76a2959fceaaa5b88d93b3` and comprises seven sequential UI
packages ending at implementation commit
`e4033169bceb8d06284c06a22fb9321751dcdfa3`. The immutable upstream source
authority was `b30e27c0025d254b7c3c8fb7a9335070542362bd`. All 12 supplied screenshots
were available and re-inspected at original pixels, but their commit, logical
viewport, and display scale remain unknown; they are supplemental composition
evidence only. No private screenshot facts are reproduced here.

The pinned Flutter checkout was revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` (Flutter 3.47.0, Dart 3.13.0).
The campaign retains all 20 committed 1280×720 macOS goldens. UI-8 regenerated
or added no PNGs.

### Current campaign adjudication

| Surface/state | Classification | Current evidence |
| --- | --- | --- |
| Welcome and terminal authorization failure | Structural parity with acceptable Flutter adaptation | Deterministic routing, semantics, recovery, and accepted synthetic-fact pixels. |
| Profiles and protected-profile PIN | Visual parity | Accepted profile/PIN pixels preserve the remote-first card and keypad hierarchy. |
| Server selection | Structural parity with acceptable Flutter adaptation | Accepted pixels preserve the staged hierarchy and measured connection facts. The former explanation-only audio step is intentionally omitted. |
| Channel Setup libraries, strategies, review, progress, failure, and completion | Visual parity with structural failure coverage | Accepted pixels cover libraries, strategies, review, progress, and completion; widget tests cover the failed state and complete staged flow. Step 3 owns an indeterminate noncancelable apply plus failed/complete outcomes. |
| Guide without playback, Classic PiP, and Overlay | Visual parity for Flutter composition | Three accepted goldens plus row, aperture, focus, density, and viewport tests; native video visibility is excluded. |
| Rich Now Playing | Visual parity | Accepted lower-left shelf leaves the playback canvas visible and remains mutually exclusive with other overlays. |
| OSD and mini Guide | Visual parity | Accepted bottom-edge and top-edge compositions follow the source-defined free-edge language. |
| Audio and long subtitle rails | Visual parity | Direct accepted pixels plus selected-focus, scrolling, and long-list widget coverage. |
| Settings with and without active playback | Structural parity with acceptable Flutter adaptation | The Ember & Steel playback golden and Slate & Pine no-playback golden show one immersive category rail; widget tests prove exactly one Player surface only when playback is active. |
| Channels and Diagnostics | Intentional Desktop adaptation | Their persistent management rail and credential-safe support workflow have deterministic regression coverage. |
| Five themes | Structural parity with acceptable Flutter adaptation | The same semantic roles, text/focus contrast, and responsive behavior are tested across every theme; only the stated primary and alternate surfaces carry accepted pixels. |

### Matrix and deterministic verification

Responsive coverage includes 800×600, 1100×800, 1280×720, 1600×900,
1920×1080, and logical 4K at DPR2. The focused UI-8 command passed 216 tests,
including every committed golden comparison and the Channels/Diagnostics
regressions. All 18 campaign-changed or added goldens were re-inspected at
original pixels; file dimensions/color space, intended alpha, and synthetic
visible labels were independently checked to distinguish preview artifacts
from clipping. The remaining format, analysis, full-suite, and macOS-build
results are recorded in the current verification section of
[Definitive Product Parity](product-parity.md).

The pinned macOS synthetic harness separately confirmed PageDown traversal from
the first viewport through channel 1,000, horizontal browsing in both the
standard and compact 12-hour Guide, jump-to-now, tune, Player/OSD/mini Guide,
all five themes, and compact/ordinary/large resizing. Rapid automated traversal
emitted Flutter macOS accessibility-bridge warnings, although subsequent full
accessibility snapshots remained usable and correctly named the visible
controls. This runtime smoke is not physical screen-reader evidence.

### Windows boundary

These Flutter goldens prove composition only. Physical Windows validation of
native video layering, DirectComposition, hardware media behavior, input,
accessibility, fullscreen, and packaging remains pending at the exact resulting
UI-8 commit with the pinned engine recorded in that evidence.

## 2026-08-26 visual-parity polish campaign

### Provenance and scope

This campaign used implementation baseline
`30003ddddcc611ea4920bad3d6f591a8e5bf2afa`, the locked plan SHA-256
`23e10f7ef660b8eec061321a6ea658fec779013c6e5c8fedd1b560293e1e2a52`, and
ended its product work at
`6714eed8b25b6305934ac90a1a84b9eb3604cee7`. The sequential package commits
were:

- Mini Guide: `05b7aecc70d56b46f7c62f0f815b8ac748c0ba95`;
- Player OSD: `dfdc82956d933a624c07414cc458f6b2da555422`;
- Rich Now Playing: `fdefb61fd7586330d9173d66819c86d7103ea78e`;
- Profiles and protected PIN: `b64d101847f4991653e3a82377232323d4cd5e55`;
- Channel Setup: `6714eed8b25b6305934ac90a1a84b9eb3604cee7`.

The comparison retained immutable upstream source
`b30e27c0025d254b7c3c8fb7a9335070542362bd`. The supplied Player OSD/Mini
Guide/Now Playing, Profiles/PIN, and Channel Setup screenshot groups were
reviewed at original pixels during the locked review gate and owning packages.
The final deterministic-acceptance worker could not re-access those supplied
files, which limits that worker's independent reinspection but does not erase
the earlier comparisons. No private screenshot fact, artwork, or personal path
is reproduced here.

The implementation changed only Flutter presentation owners and their direct
tests/goldens. It added no dependency and changed no native, engine, runner,
controller, model, persistence, transport, scheduling, design-system,
browser/Electron, release, signing, or package owner.

### Resulting Flutter composition

| Surface | Current classification | Accepted result |
| --- | --- | --- |
| Mini Guide | Visual parity for Flutter composition | Five shallow broadcast rows retain channel/current/next/progress facts, tuned/focus distinction, paging, tuning, and timeout behavior from compact through widescreen layouts. |
| Player OSD | Visual parity for Flutter composition | The bottom-rising control plane keeps restrained metadata in the lower-left/lower band, secondary actions in the lower-right, a top-right channel bug, and an edge-to-edge absolute-bottom progress line. Transport UI is hidden by default and restored by DVR playback controls; no native/libmpv behavior changes. |
| Rich Now Playing | Visual parity for Flutter composition | The source-informed lower-left shelf width remains bounded while the shared top-right channel bug, poster/text, clear-logo/title fallback, year/genres, concise rating/resolution/dynamic-range/audio badges, synopsis, and conditional cast row have a stronger internal hierarchy. Plex cast facts render bounded actor portraits plus a names line; missing or failed headshots use a neutral person silhouette rather than initials, and absent cast reserves no space. The playback line shows source/runtime facts only when available and prefers native position/duration, falling back to schedule timing when native duration is unavailable. Up Next and secondary actions remain OSD-owned. |
| Profiles and protected PIN | Visual parity for Flutter composition | Smaller remote-first profile cards and quieter idle keypad keys preserve response-backed badges, four-digit submit/retry, focus containment, keyboard/numpad input, and safe errors. |
| Channel Setup | Visual parity with structural failure coverage | One centered inset composition spans libraries, strategies, review, applying, failure, and completion; review emphasizes current-to-final impact while final apply remains atomic, indeterminate, and noncancelable. |

Exactly five 1920x1080 macOS goldens were added:
`mini-guide-1920x1080.png`, `player-osd-1920x1080.png`,
`player-now-playing-1920x1080.png`, `profiles-1920x1080.png`, and
`channel-setup-review-1920x1080.png`. Ten existing 1280x720 goldens changed:
Mini Guide, OSD, Now Playing, Profiles, protected-profile PIN, and Channel
Setup libraries, strategies, review, progress, and completion. The current
inventory is therefore 25 goldens: the historical 13-golden 2026-08-24 set was
expanded to 20 by the 2026-08-25 campaign and to 25 by this campaign. Those
historical counts retain their original date and scope.

### Verification and runtime evidence

Using pinned Flutter 3.47.0 framework revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` and Dart 3.13.0, formatting
checked 59 files with zero changes, analysis was clean, and the focused
`player_view`, `guide_view`, `lineup_app`, `ui_parity`,
`ui_review_regression`, `theme_shell`, and `ui_acceptance_golden` suites passed
162 tests. The full suite passed 486 tests, the macOS release build succeeded
at 50.6 MB, `git diff --check` passed, and the post-VPP-6 worktree was clean.
All 25 golden comparisons passed, and all 15 affected PNGs were individually
inspected at original pixels and accepted.

The macOS synthetic harness built and launched, and Guide/Classic PiP plus the
Player were observed. A bounded follow-up run observed Guide vertical paging,
horizontal navigation, jump-to-now, tuning, the shallow OSD, five-row Mini
Guide, Rich Now Playing shelf, audio and subtitle rails, Settings over and back
to Player, and all five themes. The synthetic black Player canvas is expected
because `HarnessPlayer` provides no video surface. Profiles/PIN and Channel
Setup were not reachable from the harness ready state; the
resize/fullscreen/DPI matrix and timeout-retention scenarios were not completely
rerun. An initial macOS screen-capture failure and Flutter accessibility
pending-tree warnings limited automation; these are tooling observations, not
product or physical assistive-technology failures.

### Physical Windows result

VPP-7 was **Blocked/not run** at exact product HEAD
`6714eed8b25b6305934ac90a1a84b9eb3604cee7`. The local object and pinned
toolchain were verified, but the available host was Darwin arm64 and no
authorized physical Windows 10/11 x64 machine, operator, or transport route was
available. Consequently every physical Windows row remained blocked: there is
no machine/display/scaling/runtime/build/media identity, evidence directory,
or new platform-validation/support claim. Native video layering,
DirectComposition, fullscreen/DPI, physical focus/input, and real-video
translucency remain pending under
[Windows Native Acceptance](windows-native-validation.md).

## 2026-08-27 Channel Studio deterministic acceptance

### Scope and evidence boundary

Channel Studio implementation started from
`c8d782e880f29b0b7b56565096a42b475faa1b1d`, reached Slice 6 baseline
`a99695425b216b59102e1dea893933708bfe0962`, and includes the reviewed current
Slice 7 Studio correction, its direct tests, and six closeout documents. It
changes Flutter/Dart channel ownership policy, persistence seams, management
UI, and deterministic schedule projection. It does not change native C++,
libmpv, DirectComposition, the Flutter engine patch, packaging, or WebViews.

The implemented UI keeps one Channels destination and one number-ordered list.
**Generate lineup** remains the bulk generator; **New channel** opens the
full-page Studio. Create, edit custom, inspect generated, and duplicate-as-
custom modes use explicit textual ownership. Every mode retains Air Check;
compact layouts show now/next while expanded layouts show bounded surrounding
schedule context. Source choice, playback rhythm, unavailable retention,
validation, stale/failure recovery, and save-versus-tune behavior are covered
by focused widget/controller/scheduler tests.

### Visual and deterministic result

The canonical macOS inventory is now 27 goldens. Two new Studio images cover
expanded `1280x720` and compact `800x600` authoring. The accepted Slice 1 and
Slice 3 copy also refreshed the existing Channel Setup review images at
`1280x720` and `1920x1080` plus completion at `1280x720`. All five images were
inspected and contain deterministic synthetic facts only. The complete golden
suite passed 27 of 27 comparisons, and the corrected focused
Studio/parity/review suite passed 97 tests. The Slice 4 and Slice 5 owning
matrices passed 197 and 203 tests respectively. Viewport, 200 percent text
scale, focus, semantics, live
regions, Reduce Motion, large focus, keyboard reorder, bounded large-library
filtering, and stale-safe preview behavior are deterministic evidence.

The sequential closeout gate checked 63 formatted files with zero changes,
reported no analysis issues, passed all 613 repository tests under
`America/New_York`, and built the 51.0 MB macOS release application.

These results establish Flutter composition and interaction contracts on the
macOS test harness. No physical Windows campaign was run, so they do not
establish Windows DPI, keyboard/remote delivery, screen-reader behavior, native
video layering during **Tune in**, media compatibility, packaging, platform
validation, or support.

## 2026-08-30 bounded Desktop UX corrections

This bounded pass starts from exact Desktop baseline
`f57b2dd4a48cb6bb3ba30fc9c40ab10ccca180ae`. It removes the zero-removal
Channel Setup confirmation, the duplicated Channel Studio cancel action, and
the selected-navigation label distortion; omits the explanation-only Audio
Setup stage; presents all five existing themes as one compact labeled palette
chooser; and omits the Guide poster slot only when synchronous source metadata
contains neither a show thumbnail nor poster reference. A referenced poster
retains normal geometry during loading and after byte-load failure, preventing
a fallback flash or post-load layout shift.

The current macOS inventory is 31 goldens. The pass removes the obsolete Audio
Setup image, adds a Channel Setup removal review, adds compact and large theme
chooser images, and adds matched 1920×1080 rich/reference-free Guide images.
Affected images use deterministic synthetic facts and were inspected at their
original pixels. This evidence proves Flutter composition only; physical
Windows input, assistive technology, native video layering, media behavior,
packaging, platform validation, and support remain outside this pass.

Using pinned Flutter 3.47.0 framework revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` and Dart 3.13.0, formatting
checked 65 files with zero changes, analysis reported no issues, the focused
cross-surface gate passed 212 tests with concurrency one, and the complete
canonical `America/New_York` suite passed 654 tests with concurrency one. The
macOS release build succeeded at 51.2 MB. No physical Windows campaign was run.
