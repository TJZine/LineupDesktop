# `lineup/native_player` protocol

This document specifies the Dart/native boundary used by `NativePlayer`. The
wire is platform-neutral. The Windows and macOS adapters implement it on the
shared libmpv core in `native/player_core/`, each with its own presentation;
neither copies the other's private types.

The specification was cross-checked against:

- `lib/playback/native_player.dart`
- `lib/playback/method_channel_native_player.dart`
- `lib/playback/unsupported_native_player.dart`
- `native/player_core/player_core.cpp` and `.h` (shared libmpv core)
- `native/player_core/track_list_encoder.cpp`
- `windows/runner/native_player.cpp` and `.h` (Windows adapter)
- `windows/runner/display_dynamic_range.*`
- `macos/Runner/NativePlayer/LineupNativePlayer.mm` (macOS adapter)

## Channel and call shape

The method channel name is `lineup/native_player`. Dart calls native methods
with Flutter's standard method codec. Native sends asynchronous callbacks by
invoking the method `event` on the same channel with a map argument. Unknown
native methods call Flutter's `NotImplemented` result. The Dart method-channel
client does not remap that result: Flutter surfaces it as
`MissingPluginException`, which is a version-skew signal.

Every native command except `initialize` and `dispose` returns
`not_initialized` until initialization has completed. The Dart transport also
rejects commands locally when it has no initialized backend.

## Dart to native methods

The native result is `null` unless a result map is shown.

| Method | Arguments and bounds | Result and errors |
| --- | --- | --- |
| `initialize` | None | `{clientApiVersion: int}`. Errors: `required_engine_unavailable`, `initialize_failed`. Initialization advances the native lifecycle generation, resets display matching revision, and purges queued display events. |
| `dispose` | None | `null` after the worker has finished. `dispose_in_progress` if another disposal is pending. Repeated disposal is successful. |
| `setDisplayMatching` | `revision: int >= 0`, `session: bool`, `desired: "hdr"`, `"sdr"`, or `"unknown"` | `null`; `invalid_argument` for malformed data or a native revision that is not strictly increasing. Dart ignores a revision that is not newer before making the call. |
| `load` | `uri: String`, 1–32,768 bytes; `loadId: int >= 0`; `plexToken: String?`, either null or 1–8,192 printable ASCII bytes from `0x21`–`0x7e`; `startPaused: bool?`; `startSeconds: num?`, omitted or finite and >= 0 (explicit null is invalid) | `null`; `invalid_argument`, `insecure_media_uri`, or `command_queue_full`. An authenticated load requires an HTTPS URI with an authority. |
| `play` | None | `null` or `command_queue_full`. |
| `pause` | None | `null` or `command_queue_full`. |
| `seek` | `seconds: num`, finite and >= 0; `mode: "exact"` or `"keyframes"`, optional, default `"exact"` | `null`, `invalid_argument`, or `command_queue_full`. |
| `stop` | `stopId: int > 0` | `null`, `invalid_argument`, or `command_queue_full`. Completion is asynchronous through `stopResult`. |
| `setVideoRect` | `left`, `top`, `width`, `height`, and `scale` are finite numbers; `width >= 0`, `height >= 0`, `scale > 0` | `null` or `invalid_argument`. The Windows implementation also returns `invalid_argument` if the host window is missing or `SetWindowPos` fails. |
| `setFullscreen` | `fullscreen: bool` | `null`, `invalid_argument`, or `window_error`. |
| `selectTrack` | `type: "video"`, `"audio"`, or `"subtitle"`; `id: int > 0` or null; `loadId: int > 0`; `requestId: int > 0` | `null`, `invalid_argument`, or `command_queue_full`. Completion is asynchronous through `trackResult`. |
| `setSubtitlePresentation` | `scale: num`, finite, 0.25–4.0; `imageRaise: num`, finite, 0–0.25; `lineupDrawsStyled: bool`; all required | `null`, `not_initialized`, or `invalid_argument`; Android may return `native_command_error` for unexpected exceptions. Never `command_queue_full`. |
| `setVolume` | `volume: num`, finite and 0–100 inclusive | `null`, `invalid_argument`, or `command_queue_full`. |

`loadId` is non-negative in the native `load` parser, while Dart-generated
load IDs start at 1. `selectTrack` deliberately has the stricter positive
load-ID rule. Native command admission also has a capacity of 64 queued
commands and a combined URI/header budget of 128 KiB; rejection uses
`command_queue_full`.

### Command error mapping in Dart

For a `PlatformException`, the transport preserves these native command codes:

`required_engine_unavailable`, `initialize_failed`, `dispose_in_progress`,
`not_initialized`, `invalid_argument`, `insecure_media_uri`,
`command_queue_full`, and `window_error`.

Any other `PlatformException` from a command becomes
`PlayerUnavailable(failureCode: "native_command_error")`. The unknown-method
`MissingPluginException` path is intentionally outside that mapping.

The transport synthesizes these additional failure codes while correlating
asynchronous work: `load_timeout`, `stop_timeout`, `stop_failed`,
`wait_timeout`, `native_playback_error`, and `native_error`. The coordinator
may synthesize higher-level policy codes; those are not native wire values.

## Native to Dart events

Events are maps with a required `type` key. The Dart transport drops malformed
events and load-scoped events whose load identity is not current. `display`
and `fullscreen` are player-scoped and parsed before load correlation. A native lifecycle
generation is attached to queued events internally; during draining, events
from an older native generation are dropped before invocation. The generation
is not serialized as an event key. Dart projects its own active load generation
onto `PlayerEvent` for coordinator currentness checks.

### `fullscreen`

`{type: "fullscreen", fullscreen: bool}` reports the actual completed window
state. It has no `loadId` and is independent of playback, tracks, and stop.
Both Windows and macOS emit an initial snapshot after successful native
initialization (including an already-fullscreen window) and after completed
native fullscreen changes, whatever initiated them. Native adapters use the
core's bounded platform-event queue and drain the observation on the platform
thread before replying, so the next serialized Dart toggle calculates its
target from the observed window state. Native lifecycle generations change
on initialization and disposal, not media loads. A failed transition emits no
invented target state.

Dart accepts only a bool payload during the channel owner's initializing or
initialized lifetime. Disposal/failure retires the event handler epoch and
resets its snapshot; late callbacks from a retired lifetime are ignored. The
`NativePlayer.fullscreenChanges` stream is hot/broadcast with no replay;
`fullscreen` retains the latest observation for a later subscriber (false
before initialization). The coordinator reconciles this state and display
matching without issuing another native request. Received observations,
including one equal to the previous value, supersede an in-flight command's
intent and any late success/error. Dart toggles remain serialized; cleanup
retires their existing control epoch and exits fullscreen. A completed command
can commit its target only if no newer observation or cleanup superseded it.
Player-scoped observations remain meaningful across media/scope replacement;
they cannot revive retired playback intent or a disposed coordinator.

On macOS a completed AppKit transition settles waiting requests successfully
with that published state even if the user changed their original target. It
does not queue an automatic reverse transition toward stale intent. Missing
windows, invalid arguments, failure to start, and transition deadlines keep
their bounded error behavior. An already-matching request still succeeds
immediately, including during a pending/active transition.

### `state`

Keys:

- `state`: `idle`, `loading`, `playing`, `ended`, `stopped`, or `error` from
  the native implementation. Dart also understands `paused` as a defensive
  value, but the current native backend represents pause through the `pause`
  property instead.
- `message`: a bounded diagnostic/status string.
- `loadId`: optional for load-scoped events; the initialization-ready `idle`
  event has no `loadId`.
- `paused`: bool snapshot of the actual libmpv pause flag on file-readiness
  `playing` events when the native query succeeds. It overrides the Dart load
  intent cache; pause/resume can coalesce without a property notification. Raw
  `playing` still completes load readiness even when this flag is true.
- `failureCode`: present for an error state.
- `httpStatus`: optional integer, used with `http_error` for 4xx/5xx status.

The stable native status messages are `Native libmpv player ready`, `Loading
media`, `Playing`, `Playback ended`, and `Playback stopped`. Dart preserves
native error messages where appropriate and uses its existing safe status
messages for command, timeout, and local lifecycle failures.

### `property`

Keys:

- `name`: one of the forwarded property names below.
- `value`: the property value, or null when the property is unavailable.
- `loadId`: optional while a media load is active.

The Dart transport silently drops a property event with a non-string `name`.
It drops malformed values for typed telemetry fields without replacing the
last valid fact.

Forwarded properties are:

| Name | Wire value |
| --- | --- |
| `pause` | bool |
| `time-pos`, `duration` | finite mpv doubles; Dart clamps missing, negative, or non-finite values to zero duration |
| `subtitle-cues` | list of at most 8 cues; ephemeral media content, parsed separately from `PlayerEvent` (see Subtitles) |
| `track-list` | list of at most 256 track maps |
| `video-format`, `video-codec`, `current-vo`, `hwdec-current` | bounded strings, at most 4,096 bytes each |
| `video-params` | map with `w`, `h`, `pixelformat`, `hw-pixelformat`, `primaries`, `gamma`, `colormatrix`, and `sig-peak` |
| `video-target-params` | map with `gamma`, `primaries`, and `pixelformat`; each value is null or a lower-cased string using `[a-z0-9._-]`, at most 64 bytes |

Each valid track map contains `id: int > 0`, `type: "video"`, `"audio"`,
or **`"sub"`**, and `selected: bool`. The Dart model exposes the native
`sub` value as `PlayerTrackType.subtitle`; `selectTrack` uses the request wire
value `subtitle`. Optional track keys are `title`, `lang`, `codec`,
`demux-channels` (strings), `demux-channel-count` (positive integer), and
`forced`, `external`, `hearing-impaired`, `visual-impaired`, and `commentary`
(bools). Invalid track entries and invalid optional facts are omitted.

The video-parameter numeric fields `w` and `h` are integers; `sig-peak` is a
number. The other fields are strings or null. The native encoder bounds the
aggregate metadata node to 64 KiB in addition to the per-string bound.

### `stopResult`

Keys are `stopId: int` and `success: bool`. Dart accepts the result only when
`stopId` matches the currently pending stop. A false result completes the stop
with `stop_failed`; a late result cannot complete a later stop or replacement
load.

### `trackResult`

Keys are `loadId: int`, `requestId: int`, and `success: bool`. Dart accepts the
result only when both IDs match the pending track request. A false result is a
`command_error`; an event for a retired load or request is dropped.

### `display`

Keys are:

- `revision: int >= 0`
- `session`: `inactive`, `active`, `suspended`, or `unavailable`
- `observed`: `hdr`, `sdr`, or `unknown`
- `outcome`: `idle`, `pending`, `matched`, or `failed`
- `wrote: bool`
- `owned: bool`
- `reason`: null or `unsupported_api`, `not_hdr_capable`, `ambiguous_target`,
  `state_unknown`, `guardian_unavailable`, `set_rejected`, `not_observed`,
  `external_change`, `restore_failed`, or `target_lost`
- `route`: `hdr_state`, `advanced_color`, or `none`
- `activeColorMode`: `sdr`, `wcg`, `hdr`, or `unknown`, or null when absent

Dart accepts only a fully typed report for the current display revision. Display
reports are not associated with a media load and use a separate broadcast
stream.

## Playback failure codes

The current native failure vocabulary is:

- `http_error` (with an optional 4xx/5xx `httpStatus`)
- `network_error`
- `audio_decode_error`
- `video_decode_error`
- `audio_output_error`
- `video_output_error`
- `source_open_error`
- `container_error`
- `correlation_error`
- `command_error`
- `event_queue_overflow`
- `mpv_error`

Native `command_error` is used when a queued mpv command fails. Native
`correlation_error` is used when bounded load/redirect tracking cannot preserve
an association. `event_queue_overflow` reports an mpv queue overflow. Dart
normalizes an unrecognized state `failureCode` to `native_error` and an error
state without a code to `native_playback_error`.

## Correlation and lifetime rules

### Loads

The Dart transport creates a monotonically increasing `loadId` for each load,
retires the previous load before replacement, and accepts only events whose
`loadId` equals the active ID. A load completes when its matching `playing`
state arrives. A matching error, timeout, explicit stop, or replacement settles
the pending load and retires its active ID. The caller's product generation is
kept in Dart and projected onto `PlayerEvent`; it is not sent as a native
argument.

### Seeks

Dart owns seek intent. Schedule/tune joins and ordinary authorization recovery
joins pass an optional initial position in `load.startSeconds`; the existing
schedule join omits it when elapsed is at most two seconds. The core supplies
string-valued per-file `start` and `hr-seek=no` options in a `loadfile` node map
at index -1. Authenticated header and redirect options share that map, without
modifying URI bytes or weakening reference restrictions. Each coordinator load
records its native initial target explicitly and omits its post-load join seek;
status updates to the resume position cannot reintroduce that seek. Explicit
user seeks select `exact`, including a seek
that overrides a pending join, crosses parts, or immediately recovers that
unfinished operation. Completing a user seek does not make later playback
recovery joins exact. Sequential part loads preserve the current operation's
intent; program rollover resolves the newly scheduled program normally.

Explicit seek commands execute `absolute+exact` or `absolute+keyframes`.
An exact command overrides the per-file `hr-seek=no` setting. In pinned mpv
`3186d369f9f090cd1363be0ac46a037824b702c6`, absolute keyframe seeks use the
backward demux preference, while positive relative seeks use `SEEK_FORWARD`.
The lavf path uses FFmpeg's `AVSEEK_FLAG_BACKWARD`. This is a preference, not a
strict no-overshoot guarantee: cached demux seeking can select the first later
keyframe when no predecessor exists, and lavf retries without the backward flag
if that seek fails. No exact fallback, admission pause, or extra retry is added.
Existing `startPaused` display holds and explicit pause intent are unchanged.

Seek command success means queue acceptance. The native worker emits a passive
`seek landing` diagnostic for an executed, current-load seek command followed
by a `SEEK`/`PLAYBACK_RESTART` pair. An initial `start` load instead opens a
window only after its matching `START_FILE` and `FILE_LOADED`; the subsequent
initial restart can produce one sample. A restart before either matching event
cannot confirm the initial join. Both paths require `seeking=false` and a finite,
non-negative native `time-pos`. Fields are load ID, mode, target, observed
seconds, and signed `observed-target` offset; no URI, token, title, or raw mpv
output is included. Initial joins report `mode=keyframes`.

Samples expire ten seconds after native command execution. Replacement, stop,
matching end/error, command failure, overflow, and stale load identity invalidate
them. An older file's end cannot retire the new load's pending initial sample.
Overlapping seek commands (including an exact user override) or duplicate seek
notifications make samples ambiguous and suppress logging until the next load.
A load/seek without its matching restart produces no landing diagnostic.
Logging never changes playback, waits for completion, pauses, retries, or adds
a seek.

Classified mpv error logs are retained as detail for a later failed `END_FILE`.
Their presence alone does not invalidate a matched restart: backend probing can
fail and then recover with another output. Actual terminal and command errors
still retire observations. A landing diagnostic reports position, not successful
audio output or continued playback.

This is a restart observation, not an exact per-request or first-frame PTS
protocol: mpv supplies no seek request ID, and `time-pos` is sampled when the
worker consumes the restart. It may include playback progress since landing.
Dart keeps commanded resume intent separate from observed UI position and never
treats a commanded target as landing evidence.

### Stops

`stop()` immediately retires the Dart active load and settles pending load and
track waiters, then sends a positive `stopId`. The stop future completes only
after the matching `stopResult`, not when the command is accepted. A failed or
timed-out stop retains cleanup responsibility; a retry receives a new ID.

### Track requests

`selectTrack` uses the current positive `loadId` plus a monotonically increasing
positive `requestId`. Native completion must echo both IDs. Completion means
that the native command ran, not that mpv's observed `track-list` confirms the
requested selection. A replacement load invalidates pending track requests.

### Native generations

Each initialized native worker captures a lifecycle generation. Dispose bumps
the generation before stopping the worker; queued events carry the old
generation and are dropped by the native drain. Initialization also purges
queued display events and resets display revision. Dart independently resets
its report and media state on initialize/dispose.

## Queue capacity and eviction

The native event queue holds 256 events. When it is full, the policy in
`PlayerCore::QueueEvent` in `native/player_core/player_core.cpp` is:

1. Find and evict the oldest queued `property` event, regardless of the type
   of the incoming event.
2. If no queued property exists, drop an incoming `property` event.
3. If no queued property exists and the incoming event is not a property, evict
   the oldest event of any type and admit the incoming event.

This policy protects state, stop, track, and display completions when property
telemetry is under pressure. It is separate from the native command queue's
64-entry/128-KiB admission limit.

## Presentation obligations

Any platform implementation must preserve these obligations:

1. Render real alpha compositing beneath transparent Flutter routes, including
   the approved Guide alpha.
2. Interpret the video rectangle in logical units with a top-left origin.
   Windows multiplies by `scale`; a bottom-left-origin platform must account
   for its view coordinate system.
3. Keep the rectangle across load and stop. Hide video for a zero rectangle or
   while minimized.
4. Keep video passive: it has no hit-testing, focus, or accessibility surface.
5. Complete a nonmatching `setFullscreen` request after the platform transition
   has completed; an already-matching request succeeds immediately. Publish the
   actual `fullscreen` observation, which may supersede the requested target.
6. Enforce the token-safety contract documented on `NativePlayer.load`:
   HTTPS, scoped headers, no unsafe redirects, no logging, and no implicit
   unvalidated nested references.

## Windows-specific diagnostics and portability

The following fields describe Windows mechanisms rather than portable product
policy and may be unavailable on another backend:

- the DirectComposition engine marker checked during `initialize`;
- the native child presentation window (`wid`/host window);
- display `route` (`hdr_state` or `advanced_color`) and `activeColorMode`
  (`sdr`, `wcg`, or `hdr`);
- the Windows-style fullscreen transition and its `window_error` diagnostics;
- libmpv's `current-vo`, `hwdec-current`, and the Windows-specific pixel/output
  facts in telemetry.

A backend without equivalent information should report unavailable/unknown
values truthfully (`DisplayMatchingSessionState.unavailable`, an appropriate
`reason`, `route: none`, `activeColorMode: null` or `unknown`, and null
telemetry facts) rather than fabricating Windows values.

## macOS backend

`macos/Runner/NativePlayer/LineupNativePlayer.mm` implements this protocol on
the shared core, with these platform-specific values:

- `initialize` never returns `required_engine_unavailable`; the stock Flutter
  macOS engine composites a transparent `FlutterView` over the video layer.
- libmpv renders with `vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=macvk`,
  and `target-colorspace-hint=yes` into an adapter-owned `CAMetalLayer` passed
  as `wid` (the runtime's embedding patch). HDR output is EDR on that layer,
  selected by mpv from the content; there is no display mode switch.
  The owned layer publishes MoltenVK's off-main color space, EDR, metadata,
  pixel format, and drawable-size mutations immediately on the setter's
  calling thread. This also covers teardown and threads that never acquire
  another drawable; acquisition on another thread cannot publish that
  transaction. Main-thread mutations retain normal AppKit transactions.
- `setDisplayMatching` validates its arguments and the strictly increasing
  revision exactly as above, returns `null`, and queues a `display` report
  for that revision with `session: unavailable`, `observed: unknown`,
  `outcome: failed`, `wrote: false`, `owned: false`,
  `reason: unsupported_api`, `route: none`, and `activeColorMode: null`. This
  is `DisplayMatchingReport.unavailable(revision: r)`.
- `setVideoRect` places the video in logical points with a top-left origin
  (a flipped host view) and ignores `scale`, because AppKit views are in
  points; the layer's `contentsScale` and `drawableSize` follow the window's
  backing scale. Video is hidden for a zero rectangle and while the window is
  minimized or occluded; the layer keeps a non-empty frame while hidden.
- `setFullscreen` uses the window's native fullscreen. Nonmatching requests
  complete after AppKit reports the transition. It fails with `window_error`
  when AppKit does not start the transition within one second or complete
  the request within five. A request for the window's current state succeeds
  immediately, even when a transition is running or pending. Completed AppKit
  notifications publish the actual player-scoped state and settle waiting
  requests without reversing a user change.
- Closing the window or quitting starts asynchronous native disposal after
  the existing close/Flutter quit approval. The window and video owners stay
  alive while the main run loop handles wakeups. libmpv terminates on its
  worker, then the platform thread joins and removes the layer before allowing
  window/app teardown. Repeated close/quit requests coalesce, and a concurrent
  Dart `dispose` keeps its reply. Runner shutdown rejects subsequent commands
  except `dispose`, including reinitialization. If disposal does not finish
  within five seconds, a fixed diagnostic is logged and the process exits with
  failure without running destructors or removing a live worker's layer.
  Synchronous shutdown is reserved for emergency/destructor cleanup.

## Android backend

`android/app/src/main/kotlin/com/tjzine/lineup/player/` implements the same wire
with Media3 **1.11.1**; it does not use or duplicate the desktop libmpv core.
The Dart composition root selects the existing method-channel transport on
Android. Plex, schedule joins, recovery, persistence and navigation remain Dart
policy. `clientApiVersion: 1` is an Android adapter constant, not an mpv version.
Dart's historical local ready message is unchanged for desktop compatibility.

`NativePlayerController` validates codec values, admits at most 64 commands and
128 KiB of URI/header data, and owns load/stop/request correlation. Commands and
Media3 callbacks run on the application looper. A fresh engine/listener captures
one load and lifecycle generation; replacement retires it before teardown.
Dispose retires its generation and queued credentials before asynchronously
releasing the engine and replying. Decoder/view operations stay on the application
looper; cancellation and TLS pool closure run on an IO worker. Stop/dispose and
successor loads wait for that cleanup, which is coalesced across concurrent
retirement requests. A failed release retains cleanup responsibility for retry. Events use the 256-entry property-first
queue above; essential-event overflow terminates the current load with
`event_queue_overflow`. Retired events are filtered again at delivery.

The engine publishes `loading` once and `playing` only on its first READY,
including a paused READY. Rebuffering, seeking and later READY callbacks do not
emit state changes. Pause is a property. Position and duration are read from
Media3 every 250 ms, including while paused; unavailable duration is null.
Track command completion and observed `onTracksChanged` snapshots remain
separate. Positive track IDs belong to TrackGroup identity/index for that load;
unsupported subtitle entries are omitted. Original text `Format.codecs` maps
Media3's pre-parsed cues to `subrip`/`ass`. There is no wire `default` flag.
Channel layouts, pixel formats, output color and signal peak stay null when
unavailable. Source BT.2020/PQ/HLG facts describe source metadata, not display
appearance; `hwdec-current` is the observed decoder name and `current-vo` is null.

| Media3 observation | Native failure code |
| --- | --- |
| HTTP response failure | `http_error`, with a 4xx/5xx status when available |
| HTTP/network IO, timeout, unsafe redirect | `network_error` |
| Decoder initialization/query/decode/capability failure | `video_decode_error` or `audio_decode_error`, from renderer format |
| Container/manifest parsing | `container_error` |
| MP4 type-observer structural failure (even wrapped in IO) | `container_error` |
| Extractor omitted all declared video/audio, or exposed type has no supported track | `video_decode_error` / `audio_decode_error` |
| File not found, source permission/open failure | `source_open_error` |
| AudioTrack initialization/write/offload failure | `audio_output_error` |
| Video frame processing failure | `video_output_error` |
| Other engine failure | `native_error` (Dart's existing normalization) |

Typed omitted-media and MP4 structural causes take precedence over generic
parser/network categories. Matroska callbacks and a bounded consumed-byte MP4
observer detect extractor omissions; fragmented MP4 checks each new `moov`
against **current** parsed track exposure. Ordinary sample seeks retain validated
facts. Fragmented-extractor seeks restart at box headers: they retain the last
validated declaration while rearming framing observation, so a later `moov`
cannot borrow old audio/video exposure after a nonzero indexed seek. Ordinary
nonfragmented sample seeks retain facts without treating sample bytes as boxes.
Genuine audio-only/video-only and supported alternative tracks remain
valid. Subtitles alone never cause an audio/video unsupported-type failure.

Only `ProgressiveMediaSource` and an HTTP-only OkHttp data source are installed;
there is no manifest, file, nested-reference or external-subtitle resolver.
OkHttp automatic redirects are disabled. Each manual redirect must retain the
original HTTPS scheme, normalized host and effective port, with a bounded hop
count and no userinfo or token query parameter. Credentials are header-only;
stop/dispose drop the header factory and cancel network operations. No event or
command error includes a URI, token or raw engine exception. The synthetic
fixture CA is trusted only by debug builds; profile/release have no fixture CA
or network-security override.

Initial positions use the approved exact Media3 preparation position, avoiding
a later backward re-seek. Explicit `exact` and `keyframes` map to
`SeekParameters.EXACT` and `PREVIOUS_SYNC`. This backend choice does not alter
the coordinator's join/user-seek policy or desktop behavior.

Presentation uses a default-z-order native video `SurfaceView`, native
`SubtitleView`, then Flutter with both transparent background and surface render
mode. The rectangle is logical top-left × scale, with aspect fit including pixel
aspect ratio; zero size hides presentation while retaining media. A zero rectangle
hides the video `SurfaceView` itself (releasing its surface; Media3 reattaches on
show), never only its container: a visible 0x0 SurfaceView skips surface updates
on Android 11/12, so backgrounding would orphan its layer and later loads would
render black. It persists
across loads/stops. Native views have no input or accessibility ownership.
Fullscreen is always observed true, including after a false request; Flutter
owns the approved TV control adaptation. Display matching validates revisions
and reports `unavailable`/`unsupported_api` with route `none`, without changing
OS display settings. Media3 retains its default seamless-only frame-rate
strategy. KEEP_SCREEN_ON follows observed playback and clears on pause,
stop, end, error and disposal.

The U2 probe's spatial/alpha/HDR results support this presentation choice;
**temporal G6 (the ≤1-display-frame transition bound) remains unverified** under
the maintainer's permission to proceed. Probe results are not acceptance of the
production adapter. Physical Fire TV, receiver audio, Dolby Vision, PGS and final
integrated acceptance remain separately recorded target/human obligations.

## Dart/C++ differences recorded at this revision

- Native initialization queues an `idle` event with message `Native libmpv
  player ready` and no `loadId`. Dart's event handler requires a current load
  ID for load-scoped events, so that wire event is dropped; Dart sets the same
  ready status locally after the initialize method returns. This is harmless
  but is a real difference in event consumption.
- Dart understands a `paused` state value defensively, while the current C++
  producer emits pause changes as the `pause` property and does not emit a
  `paused` state event.
- The wire uses track type `sub` in native track snapshots but `subtitle` in
  track-selection requests. Dart deliberately translates between them.
- `DisplayMatchingReport.unavailable` uses null for `activeColorMode` in Dart;
  a native report may use the explicit `unknown` string. Both represent an
  unavailable/unknown diagnostic, but they are not the same serialized value.
- Dart-generated load IDs start at 1 although the native `load` parser also
  accepts 0. The stricter positive rule remains required for `selectTrack`.

## Subtitles

Dart owns persisted style, defaults and plain-text rendering. Native owns decoder
classification: plain text is Lineup-drawn, native ASS is engine-drawn unless
`lineupDrawsStyled` is true, and image subtitles always remain engine-drawn.
`scale` affects engine subtitles; `imageRaise` moves only image subtitles.
Lineup text uses its own concrete appearance in the presentation rectangle.

`setSubtitlePresentation` is player-scoped (no `loadId`). It applies to the
current and later loads until replaced or disposed. Native keeps one pending
latest-value slot, separate from the ordinary command queue. Acceptance before
another command guarantees application before that command executes. Desktop
applies changes within one worker poll. Dispose resets presentation; Dart sends
again before the next load after initialization. Invalid arguments leave the
current presentation unchanged; unknown extra keys are ignored. Rendering is
unobserved: application failures never become playback errors or track results.

The coordinator sends without awaiting immediately before load, and coalesces
committed settings updates while a call is in flight. Rejection clears its sent
value for retry on the next load and records only an allowlisted error code.
Cue updates never emit a general Player snapshot or coordinator notification.
Malformed cues are skipped with a fixed message. Cues clear on replacement load,
stop, terminal state, subtitle-off, stale-load rejection and disposal.

The coordinator owns one `SubtitleAppearanceSource` for its app/controller
scope. Engine presentation, Player text and the Settings preview consume this
same resolved value. The coordinator retains it even without Flutter cues;
additional consumers may `retain()` and release without registering another
channel handler. The source cancels the device subscription when no consumer
requires device style, and disposes its client with the coordinator.

On Android, with `useDeviceStyle` enabled, device `fontScale` supplies the
**same effective scale for every subtitle format**, including engine-drawn ASS
and images, regardless of the OS captions enabled switch. Positive device
scales are clamped to the protocol's 0.25–4.0 range before either painting or
sending. Until the initial asynchronous device read completes, both use the
saved Lineup scale; load never awaits that read. Device changes and a refresh
on application resume update that shared appearance and coalesce through the
existing native command rules. Color-only device changes send no presentation
command. Disabling device style restores the saved Lineup appearance and
scale. Position, Bold and the styled-subtitle toggle remain Lineup's choices;
device-derived values are never persisted. Desktop never invokes the Android
caption channel. Canceled/disposed reads and callbacks cannot publish or send.

**Event: `property` with name `subtitle-cues`:**

- Value: a list of at most 8 cues; an empty list clears. Each cue is
  `{align: int 1–9 (numeric-keypad position; 2 = bottom center), lines: [[segment, …], …]}`
  with at most 8 lines per cue and 32 segments per line. A segment is
  `{text: String, italic?: bool, bold?: bool, underline?: bool}`. Total text
  across the value is at most 4 KiB UTF-8; native truncates at a character
  boundary and drops excess cues, lines or segments rather than failing.
- Load-scoped like the existing property events (carries the current
  `loadId`; Dart drops stale ones). **Replace in place, never evicted:** both
  bounded queues (`PlayerCore::QueueEvent` and Android `PlayerEventQueue.add`)
  enforce the same rule: a new
  `subtitle-cues` replaces any undelivered `subtitle-cues` at its position, and
  the capacity eviction skips it so a pending clear cannot be evicted. At most
  one `subtitle-cues` is ever queued, so the exemption cannot grow the queue.
- Emitted **only while the selected subtitle track is Lineup-drawn**.
  When the selection changes to an engine-drawn track or to none, and on stop,
  end, error and new load, native emits (or Dart synthesizes) an empty list.
- Embedded colors, fonts and positions inside plain-text cues are dropped,
  except alignment: SRT/ASS `{\anN}` tags (mpv) and Media3 cue line/position
  map to `align` (top/middle/bottom × left/center/right). Media3 fractional
  lines (WebVTT) map by thirds; CEA-608's `LINE_TYPE_NUMBER` rows
  (`Cea608Decoder.java:1050`) map positive rows in the top third to top and the
  rest to bottom, and negative rows (counted from the bottom) to bottom. On
  desktop, ffmpeg's WebVTT decoder drops cue settings, so WebVTT positions apply
  on Android only. Italic, bold and underline are kept.
- Cue text is media content: never logged, exported or retained after clearing.

**Separate channel `lineup/device_captions` (Android only).** Not part of
the player protocol, because it is not player-scoped:

- `read` → `{enabled: bool, fontScale: num, foreground: int?, background: int?, window: int?, edgeType: "none"|"outline"|"dropShadow"|"raised"|"depressed"|null, edgeColor: int?, typeface: "standard"|"monoSans"|"serif"|"monoSerif"|"casual"|"cursive"|"smallCaps"|null}`.
  Unset device values are null and Dart uses the Standard value for them.
  ARGB ints may arrive as 32- or 64-bit integers. `enabled` is the system
  captions switch; Lineup uses the device **style** whether or not that switch
  is on (the viewer asked for it explicitly), and the Settings row says so when
  it is off.
- Native calls `changed` with the same map when a `CaptioningChangeListener`
  fires. It registers while Dart has called `listen` and unregisters on
  `cancel` or activity destruction.
- Desktop has no handler; Dart never calls it there (host-gated).

### Desktop subtitle decoding and presentation

Windows and macOS share the libmpv subtitle implementation in
`native/player_core`. A pending `setSubtitlePresentation` value is taken under
the same mutex as the next command batch and applied before that batch. It
uses no command-queue slot or URI/header budget and adds no worker wake
primitive; idle changes are picked up by the existing 50 ms poll. Rejected
subtitle properties are logged with their fixed property name and libmpv error,
without publishing a playback failure; unchanged property values are not retried
on every cue.

At mpv `3186d369`, codec `ass` is native styled ASS. The bitmap codecs are
`hdmv_pgs_subtitle`, `dvd_subtitle`, `dvb_subtitle`, `xsub`, and the default
bitmap configurations of `dvb_teletext` and `arib_caption`. Every other codec,
including lavf `ssa`, is treated as converted text. Recheck this classification
against `sd_ass` and `sd_lavc` when upgrading libmpv.

The core observes the selected codec and `sub-text/ass` privately. Neither raw
property is forwarded or logged. Codec and text notifications may arrive in
either order; cached text is reclassified when the codec arrives. Converted text
(and native ASS when opted in) uses `sub-visibility=no`; an invisible unstyled
libass style is also installed as a track-switch backstop. Native ASS and bitmap
subtitles retain their engine rendering. Scale applies to both; `sub-pos` is
raised only for bitmap tracks and reset to 100 for other tracks, preserving
authored ASS positioning.

Cue conversion retains alignment and italic/bold/underline runs, drops other
overrides, and bounds the input scan/cache to 64 KiB and the output to the common
cue limits. Opted-in native ASS excludes whole events containing positioning,
clipping or positive drawing-mode (`\p` > 0) tags, even if a later `\p0` resets
the mode. A `\p0` reset alone retains dialogue, emphasis and alignment. Cues belong to the active observed load; obsolete observations
are discarded. Load, subtitle selection, stop, end, error and disposal discard
cached media text. Explicit clears accompany previously published text; the
Dart transport also clears at its load/stop/dispose boundaries. Pending cue
updates replace in place and remain exempt from both telemetry and completion
eviction, including empty clears. Cue text is never diagnostic content.

### Android subtitle mechanisms

Android accepts `setSubtitlePresentation` on the application looper, separately
from the 64-command media queue. The adapter retains its latest validated value
for the current and subsequent engines. Disposal clears that value and resets
the persistent SubtitleView's cues, embedded-style flags and default sizes.

Media3 routes the selected text format using its sample MIME (the original MIME
in `Format.codecs` for pre-parsed `application/x-media3-cues`). SSA remains
native unless `lineupDrawsStyled` is true. PGS, VobSub, DVB and every bitmap cue
remain native. Other text is encoded as bounded `subtitle-cues`; native text
painting is suppressed. Track changes clear both outputs and route the latest
cue list again. Presentation changes transform the original cues again, avoiding
cumulative scale. Fractional SSA font sizes scale individually; the fallback
font size compensates for video letterboxing relative to the presentation rect.
Supported start-anchored fractional bitmap rectangles scale about bottom-center,
raise, and clamp inside the frame; unsupported anchors/unset dimensions retain
the decoder's geometry.

The independent Android `lineup/device_captions` channel registers its
CaptioningManager listener only between `listen` and `cancel`, and removes it on
activity cleanup. Reads and `changed` events use nullable fields for unset OS
style values, unsigned 64-bit ARGB colors, and the protocol's seven typeface
keys. Device style remains available while the system captions switch is off.
Subtitle processing exceptions use fixed debug-only messages without content.

For Direct Play SSA, private nonvisual cue metadata retains event classification
through Media3's pre-parsed cue codec. It adds no wire fields. Lineup mode drops
whole sign events (pos/move/org/clip/iclip) and positive drawing-mode events;
p0 dialogue and i/b/u/an remain. A failed decorator track falls back to stock
native drawing even when `lineupDrawsStyled` is true; existing decoded cues also
fall back without reload or a playback-error event. Native drawing receives
stock-equivalent cues with private metadata removed.
