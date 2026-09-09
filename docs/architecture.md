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

Stock Flutter 3.47.2 does not request ANGLE's DirectComposition EGL window
surface mode, so it cannot provide the required transparent composition
reliably. Lineup therefore owns the single-file patch in
`tool/flutter_engine`, targeting the exact framework and engine identities in
[Windows build metadata](../tool/windows/build-metadata.psd1). The runner opts
in before engine startup; the patched engine records an exact-revision marker
only after surface creation succeeds; native initialization rejects a missing or mismatched
marker. This makes stock-engine or opaque fallback obvious.

Plezy was studied for Windows composition behavior only; no GPL Plezy
application source is present in Lineup. The engine change was evaluated
separately from the BSD-3-Clause `flutter-plezy` patch series at the pinned
commit recorded in `tool/flutter_engine/NOTICE`.

The C++ `WindowsNativePlayer` is the only native player owner. Its worker
executes queued media commands, reads mpv events, and copies bounded facts into
the event queue. It posts a runner-window message; only the platform thread
invokes the MethodChannel or changes runner-owned Windows objects. Native
lifecycle generations reject events across dispose/recreate. Per-load IDs
correlate media events across replacement loads; track request IDs correlate
native command execution within the active load; separate stop IDs correlate
idle confirmation. None substitutes for the others. Dart remains the owner of
application playback coordination; Plex authentication, networking, channel
policy, settings, Guide behavior, and navigation do not enter C++.

Normal shutdown is asynchronous: stop accepting commands and invalidate the
native generation, let the worker destroy libmpv, then handle its platform
message, join the worker, destroy the presentation host, and complete disposal.
Window close waits for that handshake. The runner destroys the native owner
before the Flutter controller/messenger. Preserve this ordering when changing
close or recreation; the destructor's five-second wait and termination fallback
is emergency cleanup, not the normal path. See
[native player lifetime](../windows/runner/native_player.cpp) and
[runner message handling](../windows/runner/flutter_window.cpp).

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
  the track-state authority. Seeks into a loading part share its readiness and
  apply the latest requested position after it loads, including authorization
  recovery. Playback errors retain a native cleanup obligation even after UI
  intent is retired. Windows stop completion uses a separate request identity
  and confirms libmpv is idle with an empty playlist; failed or timed-out stops
  remain retryable and replacement playback waits for cleanup.
  Keyboard focus in the active timed OSD suspends dismissal; the Mini Guide and
  track panels remain open until explicitly dismissed or an action closes them.
  Presentation generations reject stale focus callbacks. Player transitions
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
  Authenticated media requires HTTPS in both the Dart adapter and native
  boundary. The PMS credential crosses the privileged load seam separately
  from the URL and is applied as a per-load header, never as a global mpv
  credential option. Authenticated mpv loads reject redirects because custom
  headers can otherwise follow them; Dart Plex requests also disable redirects.
  Preserve native header-buffer clearing after command execution and queue
  cleanup. See [Dart load validation](../lib/playback/windows_native_player.dart),
  [native load options](../windows/runner/native_player.cpp), and the
  [physical redirect scenarios](windows-native-validation.md#6-plex-end-to-end-campaign).
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
  results, and supports active cancellation. Playlist discovery checks scan
  currentness between bounded batches. Cancelling or replacing a scan aborts
  its active library and playlist requests, and each Plex request aborts when
  its response deadline expires.
  Empty libraries, unsupported media, transient failures, and cancellation are
  distinct states. Generated, filtered-library, playlist, and mixed channels
  expose their source read-only during editing; metadata-only saves preserve
  source and generated identity.
- State loading treats invalid UTF-8, malformed JSON, or schema-invalid JSON as
  corruption, moves the original bytes aside, and starts empty with a
  dismissible recovery banner. Missing state
  starts empty; transient read or quarantine failures stop startup instead of
  silently replacing data.
- Diagnostic producers supply fixed area/message text and normalized structured
  facts, excluding raw exceptions, native messages, credentials, and media
  descriptors. `Diagnostics.add` filters context keys, string syntax/length,
  and numeric bounds; it does not determine whether an otherwise valid string
  is secret. Its message redaction is defense in depth, not permission to log
  arbitrary text. Diagnostics remain opt-in, clear when disabled, and retain
  at most 250 entries. See [storage filtering](../lib/diagnostics/diagnostics.dart),
  [logger tests](../test/diagnostics/diagnostics_test.dart), and producer tests in
  [the controller suite](../test/app/lineup_controller_test.dart).
- Keychain-backed credential ownership on macOS. Unsigned development builds
  use the legacy macOS Keychain compatibility mode; production signing must
  enable and validate the data-protection Keychain. Tokens remain outside
  ordinary application state and durable JSON; selected-server persistence
  stores only profile-scoped server identity.
- Persisted Guide preferences own the two-, three- or four-hour span, information
  background, the Now Playing context banner, and player-control auto-hide
  duration. The full Guide is PiP-only with permanent search/library controls;
  retired layout, density, past-window and library-visibility keys are validated
  on legacy reads and omitted from canonical writes. Existing Guide and player
  coordinators consume updates directly; there is no second settings or overlay
  owner.
- A pinned, repository-owned Flutter Windows DirectComposition patch with the
  adapted BSD notice and an exact runtime compatibility check.
- Flutter format, analysis, tests, focused macOS golden verification and
  application builds, focused Windows widget tests, pinned LGPL libmpv
  application builds, conditional patched-engine builds, packaging rejection
  checks, and portable Windows package uploads in CI.

## Changing asynchronous and persisted state

Use [LineupController](../lib/app/lineup_controller.dart)'s existing operation
epoch for superseded requests and content generation for committed content
changes. Check currentness before publishing success or failure. Scan
cancellation also aborts active HTTP requests through
[PlexClient](../lib/plex/plex_client.dart); rejecting a stale result alone does
not release its connection. Controller race tests and the
[IO transport tests](../test/plex/plex_io_transport_test.dart) cover these
distinct obligations.

The controller's state-operation queue owns snapshot/save/commit or rollback
across features. `FileAppStore`'s write queue serializes file replacement; it
does not protect controller snapshots. Credential writes and logout cleanup
have their own ordered queue. Preserve these responsibilities when adding a
mutation; see the delayed/failing state and credential tests in
[lineup_controller_test.dart](../test/app/lineup_controller_test.dart).

Library scans stage per-library results outside the committed inventory. Retrying
the same profile/server/selection reuses completed libraries; an explicit ready
subset commit persists selection and schedule migration before publishing it.
Reviewed setup application and reorder compare the complete captured lineup
inside the state-operation queue. Batch deletion compares only its confirmed
targets, so unrelated changes do not invalidate the confirmation. A mismatch
returns a distinct stale result without writing; the UI retains its draft and
refreshes the consequences for renewed confirmation.

[PersistedState](../lib/persistence/app_store.dart) requires an exact structural
field set. Adding a required field can make previously valid state enter the
corruption/quarantine path. For a schema change, choose compatible defaults or
a targeted migration; an intentional reset requires an authorized data-loss
decision. Exercise existing serialized state and failure/recovery behavior in
[app_store_test.dart](../test/persistence/app_store_test.dart). Preserve strict
validation of malformed data and the original bytes on recovery; do not add a
generic migration framework without a current need.

Before the first refinement-schema rewrite, the store retains the original bytes
in a sibling backup. Backup or migration IO failures propagate without classifying
valid legacy state as corrupt. Schedule migration embeds the resolved legacy cycle
and a UTC boundary before publishing the revised algorithm; pre-boundary lookup
uses that frozen cycle, and explicit programming edits retire the transition.
The private backup and embedded media snapshot never belong in diagnostic reports.

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
