# Architecture

Lineup Desktop is a native Flutter/Dart application. The historical Electron
implementation is preserved on `electron-ui` at the immutable
`bfaee636748f2a0d442f3690b7ba5262d32ff17c` baseline. `initial-build` is a
later historical Flutter-replatform milestone. Both are reference material,
not runtime, source-compatibility, or migration targets.

```text
Flutter/Dart application
    |
    +-- Plex, channels, scheduling, settings, persistence, diagnostics
    |
    +-- Flutter Guide, OSD, navigation, focus, input, accessibility
    |
    +-- narrow native player boundary
              |
              +-- C++ / libmpv
              +-- Windows native video presentation
              +-- DirectComposition integration
```

## Accepted ownership

The Dart application is a feature-oriented modular monolith with one bootstrap
composition root. Product policy remains in Dart: Plex coordination, channels,
deterministic schedules, settings, persistence, diagnostics, playback
coordination, and every visible or accessible interaction. Dependencies are
explicit constructor arguments. Feature state remains local until a real
cross-feature asynchronous state graph justifies one mature state-management
dependency.

C++ is reserved for behavior that materially needs native ownership: libmpv
lifetime and commands, decoded-frame presentation, Windows platform objects,
DirectComposition, and native media telemetry. Native handles, mpv internals,
and token-bearing URLs do not enter ordinary Flutter UI state.

The `NativePlayer` Dart interface exists because native platform code and test
doubles are a genuine seam. Its Windows contract covers lifecycle, replacement
loads, transport, seeking, volume, track selection, presentation bounds,
fullscreen, playback events, and bounded decoder/output/video metadata.

## Windows presentation and ownership

The production foundation uses one top-level `Lineup Desktop` window. Flutter's
runner-owned view remains the ordinary UI, accessibility, focus, keyboard, and
mouse owner. A disabled, non-activating native child presentation host is
parented to that Flutter view and kept at the bottom of its child order. libmpv
receives that host through its supported `wid` option and owns native D3D11
video presentation inside it. The host is not a top-level or owned popup and
cannot create a second taskbar or Alt+Tab entry.

Flutter renders the Guide, navigation, OSD, dialogs, text, and interactive
panels above video. Opaque Flutter regions cover video; transparent player
regions reveal it. Frames do not cross the Dart boundary and are not copied
through a Flutter texture. The native baseline explicitly requests
`vo=gpu-next`, the D3D11 GPU API/context, and `hwdec=auto`.

Stock Flutter 3.47.0 does not request ANGLE's DirectComposition EGL window
surface mode, so it cannot provide the required transparent composition
reliably. Lineup therefore owns the single-file patch in
`tool/flutter_engine`. It targets framework revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05` and engine revision
`5f77625673248ee5846fbcaf5d3e1a3878386fd7`. The runner opts in before engine
startup; the patched engine records an exact-revision marker only after surface
creation succeeds; and native initialization rejects a missing or mismatched
marker. This makes stock-engine or opaque fallback obvious.

Plezy was studied for Windows composition behavior only; no GPL Plezy
application source is present in Lineup. The engine change was evaluated
separately from the BSD-3-Clause `flutter-plezy` patch series at the pinned
commit recorded in `tool/flutter_engine/NOTICE`.

`WindowsNativePlayer` is the only native owner. It creates and tears down
libmpv, the presentation host, its event thread, observations, bounded event
queue, and fullscreen placement. mpv callbacks never call Dart. They copy a
small whitelist into the queue, post a runner-window message, and the platform
thread invokes the one MethodChannel. A generation rejects stale events across
dispose/recreate. Dart remains the owner of application playback coordination;
Plex authentication, networking, channel policy, settings, Guide behavior, and
navigation do not enter C++.

## Implemented now

- Root Flutter project targeting only macOS and Windows.
- Application bootstrap, a compact shared visual vocabulary, responsive page,
  section, notice, empty-state and confirmation primitives, focus-aware
  Material controls, semantic labels, navigation shell, and explicit startup
  failure surface.
- A persisted five-theme Flutter system using `ThemeData` plus one semantic
  `ThemeExtension`. Ember & Steel is the default; onboarding, management,
  Guide, player, overlays, dialogs, progress and focus consume shared roles
  without theme-specific native code or feature-widget theme branches.
- Production Guide, Channels, Settings, Diagnostics, and shared player routes
  consuming the persisted Channel Builder lineup without fixture-only paths.
- One route-selection authority with a discoverable management shell for
  Channels, Settings and Diagnostics, and an immersive shell for Guide and
  Player. The immersive Lineup menu calls the same route owner; it is not a
  second navigation system.
- The Dart native-player seam and an explicit macOS unsupported development
  backend. It never reports successful playback.
- A Windows C++ libmpv owner, native child presentation, command/property/event
  channel, track projection, decoder/output and quality/HDR observations,
  fullscreen/resize/minimize handling, and clean recreation controls.
- A retained Flutter Guide with lazy fixed-extent rows, shared time geometry,
  distinct focus/selection/tuned/airing/hover treatment, bounded schedule and
  artwork caches, stale-result rejection, library filters, accessible
  visible-cell semantics, responsive PiP allocation, and selection/time/scroll
  restoration across player transitions.
- One Flutter player coordinator and overlay model for contract-valid playback
  projection, the status-sensitive OSD, persistent-on-request rich Now Playing,
  bounded five-row mini Guide, full Guide, channel entry, available
  audio/subtitle tracks, recoverable/terminal errors, sleep timer, fullscreen
  intent, cursor timeout, cancellable epoch-safe auto-hide, and input/focus
  restoration. Rich Now Playing is one mutually exclusive Flutter overlay, not
  a route or second playback owner. It reads the current scheduled program and
  reuses `GuideController`'s bounded artwork futures/cache for poster, backdrop,
  optional clear-logo, and cast-portrait bytes; artwork identity includes the
  current content generation so replaced content cannot retain stale imagery.
  Ordered Plex parts remain one Flutter-owned playback lifetime: the
  coordinator gives every native load its own generation, advances natural
  completion once, and maps only known part boundaries. Native events remain
  the track-state authority.
  Keyboard focus in the active timed OSD or mini Guide suspends dismissal;
  presentation generations reject stale focus callbacks. Player transitions
  use Flutter's effective Reduce Motion setting, and track rails initially
  focus the selected track. Product state does not move into the native player.
- The Player OSD defaults to classic-TV behavior: transport buttons and
  Player-local pause/play/seek/stop/rewind/fast-forward keyboard/media
  shortcuts are suppressed, while channel surfing, number entry,
  Guide/Mini Guide tuning, tracks, sleep, menu, and fullscreen remain owned by
  Flutter. The persisted **DVR playback controls** preference restores the
  transport UI and those shortcuts without changing native/libmpv behavior;
  omitted legacy values migrate to false.
- The OSD keeps channel identity in a top-right channel bug, restrained
  metadata in the lower-left/lower band, secondary actions in the lower-right,
  and an edge-to-edge absolute-bottom progress line. **Prefer official title
  artwork** is enabled by default and reuses Plex clear logos across Guide and
  Player, with text fallback when unavailable.
- A Dart product engine for Plex PIN authentication, Plex Home profiles,
  server discovery/probing, library and media parsing, privileged playback
  descriptors, deterministic channels/schedules, channel suggestions,
  playback policy, settings, redacted diagnostics, and durable state.
- Plex.tv account and Home-profile credentials are used only with Plex.tv.
  Resource discovery returns a separate PMS-issued credential for each server;
  the controller retains it only in private runtime scope and uses it for that
  server's probes, libraries, artwork, and playback. A bounded
  authorization recovery refreshes the same server credential once without
  exposing it through public models, persisted state, URLs, or diagnostics.
  Cast portraits from Plex's exact HTTPS metadata image origin use a separate,
  redirect-disabled, size-bounded request that sends no Plex credentials;
  other foreign artwork references remain rejected.
- Profile and selected-server state remains scoped by Plex profile. The
  application controller serializes whole state mutations through
  snapshot/save/commit or rollback, serializes secure credential writes with
  logout, rejects stale profile/server operations, clears unavailable runtime
  server state without crossing scopes, and retains per-server lineups when a
  saved selection is explicitly cleared. One content generation invalidates
  Guide caches and player work across committed profile, server, and library
  changes. Connection priority is applied before an eight-endpoint probe bound;
  only the selected direct/local/relay type and its actually measured latency
  are retained.
- Upstream-shaped, remote-first onboarding for Plex QR/PIN linking, Home
  profile/PIN selection, secure server recovery, and Channel Setup. Channel
  Setup owns library selection, all eight source
  strategies, priority and cross-library scope, series variants, build mode,
  preview/review/confirmation, and atomic application for up to 1,000
  channels. Actor/director proposals do not receive alternate copies or
  variants. Custom channel editing, Settings, and diagnostics remain separate
  Flutter workflows.
- Channel Setup inventories up to four selected libraries concurrently while
  preserving library and page order. Page size and pagination are bounded; it
  reports page/item progress and item totals when available, rejects stale
  results, and supports active cancellation.
  Empty libraries, unsupported media, transient failures, and cancellation are
  distinct states. Generated, filtered-library, playlist, and mixed channels
  expose their source read-only during editing; metadata-only saves preserve
  source and generated identity.
- State loading treats invalid UTF-8, malformed JSON, or schema-invalid JSON as
  corruption, moves the original bytes aside, and starts empty with a
  dismissible recovery banner. Missing state
  starts empty; transient read or quarantine failures stop startup instead of
  silently replacing data. Diagnostics accept only bounded structured facts
  from a finite allowlist; arbitrary exception and native message text never
  enters diagnostic storage. Existing message redaction remains defense in
  depth.
- Keychain-backed credential ownership on macOS. Unsigned development builds
  use the legacy macOS Keychain compatibility mode; production signing must
  enable and validate the data-protection Keychain. Tokens remain outside
  ordinary application state and durable JSON; selected-server persistence
  stores only profile-scoped server identity.
- Persisted Guide preferences own library-filter visibility, the Now Playing
  context banner, and player-control auto-hide duration. Their existing Guide
  and player coordinators consume updates directly; there is no second
  settings or overlay owner.
- A pinned, repository-owned Flutter Windows DirectComposition patch with the
  adapted BSD notice and an exact runtime compatibility check.
- Flutter format, analysis, tests, focused macOS golden verification and
  application builds, focused Windows widget tests, pinned LGPL libmpv
  application builds, conditional patched-engine builds, packaging rejection
  checks, and portable Windows package uploads in CI.

## Integration and acceptance status

The owner reports that native Player, Classic PiP/Overlay presentation, and
fullscreen work at a surface level on Windows. Exact-commit remote Plex,
representative HDR, broad codec/container/audio/subtitle, transition, and
packaged-runtime acceptance remain deeper evidence work. This evidence boundary
limits support claims, not playback attempts: the Windows libmpv backend accepts
original Plex streams without a codec, container, or HDR allowlist and without
treating native audio passthrough as a decode gate. It lets libmpv/FFmpeg demux,
decode video and supported audio such as TrueHD and DTS-family tracks, convert
audio to the system output (normally PCM), render subtitles, and tone-map as
needed. This application-completeness batch adds no browser codec allowlist,
compulsory server transcode/remux, subtitle burn-in framework, or passthrough
decode gate. Passthrough, server fallback, and explicit subtitle sidecar loading
remain separate capabilities justified only by a concrete product requirement
or demonstrated native gap.

## Dependency decision

One behaviorful `ChangeNotifier` owns the current cross-feature asynchronous
state graph; widgets retain local form and navigation state. A separate state
framework would add forwarding and lifecycle ceremony without improving this
single-owner graph. `http`, `xml`, `path_provider`, `qr_flutter`, `crypto`, and
`flutter_secure_storage` provide maintained transport, Plex XML fallback,
platform application-data paths, Flutter-rendered QR presentation, stable builder
provenance hashes, and Keychain/platform-secure credential storage
respectively. The macOS
legacy-Keychain option is an explicit bridge
for unsigned development, not plaintext storage or the production signing
endpoint. No plaintext credential fallback exists.

The Windows runtime additionally links libmpv dynamically at the native
boundary. The pinned production asset uses mpv's LGPL mode and an LGPLv3
FFmpeg configuration, with exact acquisition and binary checksums enforced by
the preparation script and CMake. `docs/windows-runtime.md` records the source,
configuration, obligations, and package policy.
`flutter_lints` and `flutter_test` are development dependencies under their
SDK/BSD licenses. Re-evaluate packages when a concrete feature can show a
material reliability or ownership advantage.
