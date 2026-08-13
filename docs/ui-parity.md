# Portable UI parity

This document is the source record for Prompt 3B. It describes portable,
non-player Flutter UI parity; it does not claim Windows media validation.

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
| 1280×720 through 3840×2160 | Intentional Desktop adaptation | Widget tests verify the capped 1,120-pixel management workspace, extended navigation, reachability, and absence of layout errors through a 3840×2160 logical viewport. Guide/player retain their specialized full-area owners. Windows runtime DPI behavior remains Windows-only validation. |
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
/Users/tristan/Software/dev/flutter/bin/flutter test test/app/ui_parity_test.dart
```

The focused suite verifies destination order and focus entry, responsive
management pages at 800×600, 1280×720, 1600×900, 1920×1080, 2560×1440 and
3840×2160, destructive confirmation, local editor validation, physical
protected-PIN keys, Settings category scrolling, and all three Channel Setup
stages. At 2560×1440 and 3840×2160 the tests also assert the deliberate
1,120-logical-pixel management workspace, 1,180-pixel onboarding workspace,
1,440-pixel Channel Setup workspace, extended navigation, and Diagnostics
reachability. Flutter lays out in logical pixels; a deterministic 3840×2160 at
DPR 2 case verifies the 1920×1080 logical regime. Actual Windows DPI mapping
and physical readability still require Windows runtime observation. The full
validation commands remain in `docs/DEVELOPMENT.md`.

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
