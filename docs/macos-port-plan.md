# macOS playback port plan

Status: proposed, 2026-10-17. Planning only; nothing here is implemented.
Base: `main` at `022b05aa`, whose tree is identical to `cleanup` at `b00478bc`.

This plan builds on the existing authorities and proposes ways to resolve
them. It does not replace them:

- [Code-quality plan §9](code-quality-implementation-plan.md#9-macos-strategy-and-deferred-port-backlog):
  repository strategy, the open macOS decisions, and presentation obligations.
- [Native-player protocol](native-player-protocol.md): the wire contract
  every backend must meet.
- [macOS media backlog](open-obligations.md#macos-media-backlog): obligation
  status.
- [Architecture](architecture.md): ownership. Flutter owns interaction;
  native code owns media and platform mechanisms.

Until the product decision in §3 is accepted, the project profile's statement
still applies: macOS is a development surface with explicitly unsupported
playback.

## 1. Goal and scope

Ship Lineup Desktop on the Mac App Store with libmpv playback, including HDR,
at feature parity with Windows except where macOS has no equivalent mechanism.
The app is free to download, and a paid unlock gives the full feature set. The
app stays one repository and one Flutter application, with macOS as a second
platform implementation.

In scope:

- a macOS native player that implements `lineup/native_player`;
- video presentation under Flutter with the approved Guide alpha;
- **HDR output in the first release, including Dolby Vision profiles 5 and
  8.** This is a core product requirement (§4.3, §4.5);
- a pinned, LGPL, dynamically linked libmpv runtime, built by us with one
  small mpv patch, acceptable for App Store distribution;
- a shared C++ mpv core used by both Windows and macOS;
- macOS fullscreen, window lifecycle, keyboard, menu, and copy;
- App Store packaging, sandbox, signing, CI, and runtime provenance;
- the entitlement model and purchase integration for the free and paid
  tiers (§4.9), designed as its own product workstream.

Out of scope:

- Windows-style HDR mode switching, which has no public macOS API (§4.5);
- any Player OSD or layout change beyond platform wording. Upsell and
  purchase UI goes through design approval in the monetization workstream;
- iOS.

## 2. Current state

The refactor already made the Dart seam platform-neutral:

| Area | State on `main` |
| --- | --- |
| Dart player contract | `NativePlayer` (`lib/playback/native_player.dart`) is platform-neutral. |
| Dart transport | `MethodChannelNativePlayer` speaks the documented protocol. Only one message names Windows: the `required_engine_unavailable` text. |
| Selection | `createPlatformNativePlayer` (`native_player_factory.dart`) returns `UnsupportedNativePlayer` on macOS. |
| Presentation seam | `NativeVideoSurface` sends a logical, top-left `PlayerVideoRect` plus a scale. It needs no change. |
| Display matching | Dart policy (`display_matching.dart`) already handles `DisplayMatchingSessionState.unavailable`. |
| Shortcuts | `commandModifier` (`lib/app/navigation_shortcuts.dart`) is the single seam; it uses Ctrl everywhere. |
| macOS runner | Stock Flutter template, App Sandbox, network client entitlement, macOS 12.0 deployment target, no CocoaPods. |
| macOS CI | Builds the app and runs one Guide alpha test. |
| Licensing | Repository is public under Apache-2.0. |

Windows native code, split by what macOS needs:

| Windows code | Lines (non-test) | macOS relevance |
| --- | --- | --- |
| `native_player.cpp`/`.h`: queues, event loop, load/stop/track correlation, token handling, error classification | ~1,590 | About 60% is platform-neutral mpv logic that should be shared (§4.2). The rest is Win32 hosting and the Flutter Windows codec. |
| `native_playback_state.h` | 171 | Already portable: no Win32 or Flutter includes. |
| `track_list_encoder.*` | 161 | Portable logic, but it emits `flutter::EncodableValue`; it needs a neutral value type. |
| `display_dynamic_range`, `display_guardian`, `display_recovery` | ~1,380 | Windows HDR mode switching. Not ported (§4.5). |
| `flutter_window`, `win32_window`, `main`, `utils` | ~620 | Windows runner. macOS has its own equivalents. |
| DirectComposition engine patch | 62-line patch | Windows only. macOS should need no engine patch (§4.3). |

## 3. Decisions

### Resolved (2026-10-17)

| Decision | Resolution |
| --- | --- |
| Repository strategy | One repository and one Flutter app (CQ plan §9.1). Work branches from `main` and lands by squash merge. |
| Media engine | libmpv. AVFoundation alone lacks MKV, ASS subtitles, and several Plex direct-play codecs, and it would have to synthesize mpv's state vocabulary. |
| HDR | Required in the first macOS release, including Dolby Vision profiles 5 and 8. Not negotiable. |
| Presentation and HDR route | Route C: `gpu-next` on MoltenVK, embedded in our view through one LGPL mpv patch (§4.3). Spike S1 verified HDR10, HLG, and Dolby Vision profiles 5 and 8.1. Route A is ruled out because its renderer cannot render Dolby Vision profile 5. Route B (Flutter texture) is ruled out because it cannot output HDR. |
| Distribution | Mac App Store, free to download with a paid full-feature tier. The free tier limits the number of channels. |

### Product decisions still needed (recommendation first)

| # | Decision | Recommendation | Why |
| --- | --- | --- | --- |
| P1 | Is macOS a supported playback platform? | Yes, once spike S1 passes. | This reverses the profile's "development surface" statement. It needs an explicit yes and then the doc updates in §9. |
| P3 | Minimum macOS and architectures | Keep the current 12.0 target unless the libmpv runtime chosen in S2 needs newer. Build universal (arm64 + x86_64) if that runtime provides both slices; otherwise arm64 only. | Lets the runtime's real requirement drive the minimum. |
| P5 | Command modifier | Use ⌘ on macOS for command chords, and wire `Settings… ⌘,` to Settings. | This is platform convention, and `commandModifier` is already the single seam. |
| P6 | Fullscreen | Support the green button, the View menu, and ⌃⌘F as well as the Player button, all in one native fullscreen state. | Users expect the system controls. This needs the protocol extension in §4.6. |
| P7 | Bundle ID | Keep `com.tjzine.lineupDesktop`. | A new ID starts with empty data and an empty Keychain. |
| M1 | Purchase model | One app: a free download plus a one-time, non-consumable in-app purchase ("Lineup Pro") that unlocks everything. | Apple prefers in-app purchase unlocks to separate "Lite" apps. One app keeps one review, one listing, and one data store, and lets users upgrade without losing anything. |
| M2 | Free-tier limit | A fixed channel count (for example 3). Existing channels beyond the limit stay saved but cannot be watched or edited until upgrade. | Never deletes user data on a downgrade or a restore from another device. |
| M3 | Source visibility | Decide before the paid release: keep the repository public (the paid tier is a convenience anyone could rebuild) or make future development private. | Apache-2.0 code that is already published stays available under Apache-2.0. As the copyright holder you can license future versions differently. Get legal advice. |
| M4 | Windows monetization | Defer. The entitlement model (§4.9) works on either platform. | Not needed for the macOS launch. |

P5 and P6 change platform behavior, not the approved Player layout. Any visual
change beyond wording, including upsell and purchase UI, goes through the
normal design approval.

### Engineering decisions the spikes settle

| # | Decision | Resolved by |
| --- | --- | --- |
| E1 | Whether route C meets the HDR matrix, or C2 is needed | Spike S1 (§4.3) |
| E2 | Self-build recipe and base (§4.4) | Spike S2 |

## 4. Architecture

### 4.1 Ownership on macOS

The ownership is the same as on Windows, with macOS mechanisms:

- **Dart** owns playback policy, load and generation identity, OSD, focus,
  semantics, input, and the entitlement policy (§4.9).
- **Shared C++ mpv core** owns the mpv handle, the command queue and worker,
  event translation, load/stop/track correlation, token handling, and bounds.
  It is platform-neutral.
- **macOS adapter (Objective-C++)** owns the Flutter method channel and codec,
  video presentation (the `CAMetalLayer` view that mpv renders into), window and fullscreen integration, and application
  termination ordering.
- **macOS runner (Swift)** owns the window, the menu, transparency setup, and
  the StoreKit bridge.

Objective-C++ (`.mm`) is the adapter language because it calls the C++ core
and Flutter's Objective-C macOS API directly. Swift–C++ interop would add a
bridging layer without removing any work. The Swift runner files and the
StoreKit bridge stay Swift, because StoreKit 2 is Swift-only.

### 4.2 Shared mpv core

**Burden it removes:** the hard-won correlation and safety logic would
otherwise be written twice, in two languages. That logic covers:

- playlist-ID load correlation;
- stop observation through `idle-active` and `playlist-count`;
- the 256-event eviction policy;
- the 64-command and 128 KiB admission limits;
- HTTP status parsing;
- the token header lifetime and wipe;
- the redirect ban with authenticated headers.

Duplicating it would let the two backends drift on exactly the obligations
the protocol says must not drift.

**Boundary:** the core speaks a neutral value tree and a small host interface.
Each platform adapter converts values to its own Flutter codec and supplies
presentation. A sketch:

```cpp
namespace lineup::player {

// Neutral replacement for flutter::EncodableValue inside the core.
using Value = std::variant<std::monostate, bool, int64_t, double, std::string,
                           ValueList, ValueMap>;

class CoreHost {  // implemented by each platform adapter
 public:
  // Thread-safe. Asks the platform thread to call Core::DrainEvents soon.
  virtual void RequestDrain() = 0;
  // Called on the worker after mpv_terminate_destroy completes.
  virtual void WorkerFinished() = 0;
};

struct OutputConfig {  // platform presentation choice, applied before init
  std::vector<std::pair<std::string, std::string>> options;  // e.g. vo, gpu-api
  std::optional<int64_t> window_id;  // Windows: child HWND; macOS: CAMetalLayer
};

class Core {
 public:
  Core(MpvOperations ops, CoreHost& host);
  CommandResult Initialize(const OutputConfig& output);
  // Validates and queues load/play/pause/seek/stop/selectTrack/setVolume.
  CommandResult Handle(std::string_view method, const ValueMap& args);
  std::vector<Value> DrainEvents();  // platform thread only
  void BeginDispose();
  bool DisposeReady() const;
};

}  // namespace lineup::player
```

The final shape is decided during implementation of K1. The obligations are
fixed:

- validation and bounds stay exactly as the protocol documents them;
- generation-based dropping stays;
- the token lives only in the header buffer and is wiped after the command
  runs;
- the core never logs URIs or tokens.

**Stays per platform:**

- Windows: the `wid` host window, `SetVideoRect`, borderless fullscreen,
  `WM_*` close sequencing, the DirectComposition marker, and display
  matching.
- macOS: the `CAMetalLayer` view, the rect conversion, native fullscreen,
  `applicationShouldTerminate` sequencing, and a display report that always
  says `unavailable`.

**Location:** `native/player_core/`, which both runners build from:

- Windows adds it in `windows/runner/CMakeLists.txt`.
- macOS adds the sources to the Runner target through a folder reference,
  plus a header search path for the pinned libmpv headers.

The existing Windows contract tests use the `MpvOperations` injection. They
move with the core and run on both platforms (§6).

**Migration:** extract the core from `WindowsNativePlayer` with no behavior
change first, while the Windows tests stay green. Then build the macOS
adapter on it. The extraction touches Windows code, so the Windows playback
checks join the user's batched physical acceptance pass. K1 does not depend on
the presentation decision and can start immediately.

### 4.3 Presentation and HDR route

**Requirement:** HDR10, HLG, and Dolby Vision profiles 5 and 8 render with
correct colors and HDR output in the first release.

**Constraints in upstream mpv:**

- mpv cannot draw into an app-owned view on macOS. `--wid` is documented for
  X11, Win32, and Android only. mpv's macOS Vulkan context (`macvk`) and its
  cocoa-cb path create their own window.
- `--target-colorspace-hint`, mpv's HDR output switch, requires `gpu-next` and
  is supported only on Wayland, D3D11, and winvk contexts. It does not support
  `macvk`.
- The libmpv render API offers only OpenGL, D3D11, and software backends, and
  it renders with the classic `gpu` renderer, not `gpu-next`.
- **The classic `gpu` renderer cannot render Dolby Vision profile 5.** On
  texture setup (`video/out/gpu/video.c`) it calls
  `mp_image_params_restore_dovi_mapping`, which discards the Dolby Vision
  representation and falls back to the stream's original color signaling.
  That fallback is harmless for profile 8, which has an HDR10-compatible base
  layer. Profile 5 has no compatible base layer, so it renders with the known
  green and purple tint. `gpu-next` applies the Dolby Vision reshaping through
  libplacebo; that is what Windows uses today.

**What "Dolby Vision support" means on a desktop:** mpv converts Dolby Vision
into correctly colored HDR (PQ) output. Neither the Windows app nor a Mac sends
a Dolby Vision signal to the display:

- A Dolby Vision TV shows its HDR10 mode, not its Dolby Vision badge.
- The picture's colors and brightness are correct.

This is the same behavior the Windows build has today.

Apple TV can send a real Dolby Vision signal because tvOS has a Dolby Vision
output path. As far as Apple documents, macOS does not offer one for external
displays. It plays Dolby Vision as HDR or EDR output, so no route on a Mac
(including C2) produces a Dolby Vision signal.

**Product rule (2026-10-17):** profiles 5 and 8 must render with correct colors
and HDR output. A Dolby Vision signal to the TV is preferred wherever a
platform allows it, but HDR10 output is accepted where it does not.

**Routes considered:**

| | A. Render API, app-owned EDR layer | C. `gpu-next` embedded in our view (chosen; verified in S1) | C2. AVFoundation output (Apple renders Dolby Vision) |
| --- | --- | --- | --- |
| Mechanism | mpv renders through OpenGL into a 16-bit float target. We present it in our own layer with EDR enabled. This is the pattern of mpv's own cocoa-cb backend. | We patch mpv's `macvk` context so it accepts an app-provided `CAMetalLayer` through `--wid`, and so `target-colorspace-hint` sets the MoltenVK swapchain HDR color space. | mpv decodes; frames go to an `AVSampleBufferDisplayLayer` with their Dolby Vision metadata, and macOS renders them. Plezy ships this in a GPL fork. |
| Dolby Vision profile 5 | **No:** the renderer discards the Dolby Vision mapping | Yes, through libplacebo, the same as Windows | Yes, Apple-native |
| HDR10 / HLG | Yes (cocoa-cb pattern) | Yes, if MoltenVK's HDR color spaces behave (verified in S1) | Yes |
| Renderer | Classic `gpu` | `gpu-next`, the same as Windows: one tone-mapping and color pipeline on both platforms | Apple's renderer; mpv's renderer and shaders are unused |
| Subtitles | mpv renders them | mpv renders them | Need a separate path, because mpv's overlay would not be in the AVFoundation frames |
| Upstream | Unmodified | One focused embedding patch (S1), which we try to upstream | A new video output plus FFmpeg metadata-forwarding patches |
| Effort and risk | Lowest, but fails the requirement | Medium | Highest |

**Decision:** route C. Route A is ruled out by the Dolby Vision profile 5
requirement. Route C2 is kept only as a contingency, if MoltenVK cannot
present HDR correctly.

Route C also brings two benefits:

- One renderer on both platforms, so Windows and macOS share tone mapping,
  Dolby Vision handling, and color behavior. That simplifies support and
  diagnostics.
- No dependency on Apple's deprecated OpenGL.

Upstream mpv already uses `gpu-next` on MoltenVK as its default on macOS, but
only inside mpv's own window. The patch adds embedding rather than a new
renderer.

**The mpv patch (LGPL, published, upstreamed if accepted):**

- **Embedding:** when `--wid` is set on macOS, the `macvk` context renders into
  the provided `CAMetalLayer` and creates no window, view, title bar, or app
  integration of its own. The host sets the layer's `drawableSize`, and mpv
  observes it once per frame to resize. This mirrors what `--wid` does on Win32
  and X11.
  - Spike version: `tool/macos/mpv-patches/0001-…patch` on the
    `spike/macos-route-c` branch, about 80 lines in
    `video/out/vulkan/context_mac.m`.

A second patch for HDR signaling was planned but proved unnecessary (see
"Spike S1 results" below).

**Spike S1 results (2026-10-17, M1 Pro, built-in Liquid Retina XDR):**

Setup:

- mpv `3186d369f` (the commit Windows pins) plus the embedding patch, built
  with `-Dgpl=false`.
- MoltenVK 1.4.2 and libplacebo 7.360 from Homebrew. These are spike
  dependencies; the shipped runtime comes from S2.
- The real Lineup Guide and Player, run through `test_driver/ui_harness.dart`,
  with the video rect forwarded to the runner.

| Matrix row | Result |
| --- | --- |
| Embedding under a transparent `FlutterView` | Pass. Video shows exactly through the Guide picture-in-picture aperture and fills the Player route. The rect follows window and fullscreen changes. |
| HDR10 | Pass. With `target-colorspace-hint=yes`, libplacebo picks `A2R10G10B10 + HDR10_ST2084` on MoltenVK. MoltenVK then sets the layer's color space to `ITUR_2100_PQ`, turns on `wantsExtendedDynamicRangeContent`, and passes the HDR metadata as `CAEDRMetadata`. Display headroom is 16×. **The user confirmed visibly brighter highlights than UI white.** |
| HLG | Pass. Converted to PQ output with EDR. |
| Dolby Vision profile 8.1 (4K UHD BD source) | Pass. With VideoToolbox decode, mpv reports `colormatrix=dolbyvision`, so the Dolby Vision metadata survives hardware decoding and reshaping applies. Output is PQ with EDR. |
| Dolby Vision profile 5 (Dolby test patterns, `dvhe.05`, compatibility ID 0) | Pass. Reshaping is applied with VideoToolbox decode. The BT.2020 color bars render with correct hues and neutral gray (no IPT tint), in the full Player and in fullscreen. |
| HDR ↔ SDR switching (4 changes in one session) | Pass. EDR turns off for SDR (BT.709 layer color space, 203-nit white) and back on for HDR every time. |
| 4K60 10-bit HEVC HDR10, full-screen render size | Pass. Drops happen only around startup and the fullscreen transition, none in steady state. About 15–17% CPU. |
| Fullscreen (green button and View menu) | Pass at the presentation level. Dart synchronization (§4.6) is not part of the spike. |
| Exact Guide alpha pixel comparison, live-resize misalignment, mixed-scale dual displays, OSD over HDR | Not yet measured. Only one display was available. These carry into M2 and A1. |

**Consequences for this plan:**

- Only the embedding patch is needed. HDR output, EDR, and HDR metadata work
  through the existing `target-colorspace-hint` path because MoltenVK
  implements `VK_EXT_swapchain_colorspace` and `VK_EXT_hdr_metadata`.
- The production adapter sets `target-colorspace-hint=yes`.
- The spike did not need a target peak from the display's EDR headroom. macOS
  tone-maps PQ above the current headroom itself. Whether a `preferred_csp`
  for `macvk` (reporting headroom to `gpu-next`) improves on that is an
  optional quality refinement for M2, not a requirement.
- Route C2 is no longer needed as a contingency for HDR.

**Spike S1 (decides the remaining unknowns in C):**

1. Build mpv with the patches, as a prototype that need not yet be clean. (Done: only the embedding patch was needed.)
2. Embed it below a transparent `FlutterView`.
3. Run the matrix below.

If MoltenVK cannot present HDR correctly, record why and evaluate C2 against
the same matrix before committing.

**Spike S1 test matrix**, on the Mac's built-in display and, if available, an
external HDR monitor or Dolby Vision TV:

| Content | Pass criterion |
| --- | --- |
| SDR BT.709 | Colors match the SDR reference. EDR stays off, so the system holds no extra headroom. |
| HDR10 (PQ, BT.2020) | Highlights use EDR headroom. No clipping or washed-out blacks. Correct tone mapping on non-EDR displays. |
| HLG | Correct HLG rendering with EDR. |
| Dolby Vision profile 5 | Correct colors (no green or purple tint), with HDR output. |
| Dolby Vision profile 8.1 | Reshaping applied, with HDR output. |
| Dolby Vision with VideoToolbox hardware decode | Dolby Vision metadata survives hardware decoding (reshaping still applies). If it does not, record the decode path that preserves it and its CPU cost. |
| HDR → SDR → HDR channel switch | EDR toggles with the content. No stale color space and no flash. |
| Guide, OSD, and dialogs over HDR video | Flutter UI stays at SDR white and matches the Guide alpha reference. |
| 4K60 HDR, 10-bit HEVC | No sustained dropped frames. Flutter frame pacing is unaffected. |
| Live resize and fullscreen transitions | No tearing and no persistent misalignment of the video rect. |
| 1× and 2× displays, moving the window between them | Correct scale and EDR state on each display. |

Record numbers, screenshots, and color-pick values in a spike report. HDR
color judgments on an EDR display need a physical observation; screenshots
alone do not capture EDR.

**Presentation details the implementation must honor:**

1. The runner sets both `NSWindow.backgroundColor` and
   `FlutterViewController.backgroundColor` to clear. Flutter's macOS
   embedder documents both as required. The video view, which hosts the
   `CAMetalLayer` passed to mpv, is a sibling below the Flutter view in the
   window's content view.
2. The video view is passive: no hit-testing (`hitTest:` returns nil), no
   first responder, and hidden from accessibility (protocol obligation 4).
3. The rect conversion uses the logical top-left `PlayerVideoRect`, in
   points. AppKit views are bottom-left unless flipped; use a flipped
   container, and set `contentsScale` from the window's backing scale.
   Ignore the rect's `scale` because AppKit already works in points. Hide
   the layer on a zero rect, while minimized, or when the window is occluded.
4. The layer belongs to the adapter. mpv renders into it but never resizes,
   reparents, or removes it. Size changes go to mpv through the patched
   context's resize path.
5. HDR state is driven by mpv. The patched context sets the swapchain color
   space and EDR from the content. The adapter only reports facts (content
   transfer, primaries, EDR engaged, headroom) to diagnostics.
6. Disposal order: stop playback, then terminate mpv (which releases the
   swapchain), then remove the layer. The application terminates only after
   that order completes (§4.6).

### 4.4 libmpv runtime and licensing

Policy (the same as the Windows decision in [windows-runtime.md](windows-runtime.md),
tightened for the App Store):

- an LGPL-only configuration, built with `-Dgpl=false`;
- **no GPL component anywhere in the shipped app.** GPL terms are widely
  regarded as incompatible with App Store distribution;
- dynamically linked as a framework inside
  `Lineup Desktop.app/Contents/Frameworks`;
- pinned by exact source and build identity;
- verified by SHA-256 when acquired;
- source and build links, any of our patches, and the license texts are
  published and shipped in an in-app Licenses screen;
- mirrored to a project-controlled release before public distribution.

On the App Store, users cannot swap a framework in a signed bundle in place.
On macOS, though, a user can re-sign a modified copy and run it locally.
Several LGPL FFmpeg- and libmpv-based apps ship on the Mac App Store this way:
dynamic frameworks, published sources, and a relinking notice. **Get a legal
review of the LGPL and App Store position before the first paid submission.**
This plan is an engineering inventory, not legal advice.

**Spike S2 (decides E2):** route C needs our mpv patches, so we build
libmpv ourselves. It is built in CI from pinned mpv, FFmpeg, libplacebo,
MoltenVK, and dependency sources, plus our patch series.

Existing LGPL Apple build recipes are starting points, not shipped artifacts.
Reusing their scripts needs a license check of the scripts themselves:

- **MPVKit**, LGPL-v3 variant: macOS frameworks of libmpv and FFmpeg. Its
  non-`-GPL` artifacts are LGPL.
- **media-kit `libmpv-darwin-build`**, default playback variant. Its
  repository metadata reports conflicting licenses, so verify it directly.

S1 can start on a quick local build, and S2 makes it reproducible.

Pass criteria for the runtime:

- an LGPL-only configuration that is verifiable from its build recipe;
- dynamic linkage;
- arm64 and, if P3 requires it, x86_64 slices;
- `macvk` with MoltenVK and our embedding patch; `gpu-next` with libplacebo's
  Dolby Vision support;
- VideoToolbox hardware decode, including 10-bit HEVC;
- `tls-verify=yes` works against `plex.direct` HTTPS using system trust (the
  build's TLS backend decides this);
- `http-header-fields` and `curl-max-redirects=0` behave as on Windows; port
  `authenticated_reference_test` to prove it;
- it loads under the App Sandbox and hardened runtime when signed with our
  team identity;
- no runtime code loading or downloading. Scripting (Lua/JS) and `ytdl` are
  not built. App Review forbids downloading executable code, and this also
  reduces the attack surface.

Record the chosen identity in a new `docs/macos-runtime.md` that mirrors
`windows-runtime.md`. Keep the patch series in `tool/macos/mpv-patches/`. Add
`tool/macos/build-mpv.sh` to build the runtime, and a provisioning step that
verifies and stages the pinned artifact for app builds.

### 4.5 HDR on macOS

Windows display matching switches the monitor's HDR mode. macOS has no public
API for that. Instead, a layer opts into extended dynamic range (EDR), and the
system supplies headroom:

- on Apple XDR and EDR-capable built-in displays;
- on external HDR displays when the user has turned on High Dynamic Range in
  System Settings.

So HDR on macOS is an output-path feature, owned by the presentation layer
(§4.3), not a display-mode feature:

- The macOS adapter always reports
  `DisplayMatchingReport.unavailable(reason: unsupportedApi)`, with
  `route: none` and `activeColorMode: null`. The existing Dart policy already
  treats this as a no-op session. `setDisplayMatching` validates its arguments
  and returns success, exactly as the protocol requires.
- Settings hides "Match display HDR" on macOS, because the player reports
  display matching as unavailable. The setting stays persisted unchanged.
- HDR output is always on for HDR content, in the first release. It has no
  setting because the system already adapts to the display.
- Diagnostics shows the content's transfer function and primaries, whether
  EDR is engaged, and the current EDR headroom
  (`NSScreen.maximumExtendedDynamicRangeColorComponentValue`). It does not
  show Windows display-mode facts.

### 4.6 Fullscreen and window lifecycle

**Fullscreen:**

- The macOS adapter implements `setFullscreen` with `toggleFullScreen:` and
  completes the call only after `windowDidEnterFullScreen` or
  `windowDidExitFullScreen` fires (protocol obligation 5).
- The green button, the View menu, and ⌃⌘F change fullscreen without Dart
  asking. **Protocol extension:** native emits a player-scoped event,
  `{type: "fullscreen", fullscreen: bool}`, after every completed transition,
  whatever started it.

  Like `display`, the event carries no `loadId`. `MethodChannelNativePlayer`
  exposes it as a stream, and `PlayerCoordinator` reconciles its
  `_fullscreen` state from it, so the Player button icon stays truthful.
- Windows emits the same event after its own transitions, which keeps one
  model. Record this in `native-player-protocol.md`.
- Dart-initiated toggles still serialize through the coordinator's existing
  fullscreen epoch. A user-initiated change during a pending Dart request
  settles that request with the observed state rather than failing.

**Termination:**

- On Windows, `WM_CLOSE` waits for native disposal and display restoration.
- On macOS, `applicationShouldTerminate:` returns `.terminateLater` while the
  player is active. It replies once the disposal order in §4.3 completes, or
  after a bounded timeout that is logged without the media URI.
- Closing the last window follows the same path, because
  `applicationShouldTerminateAfterLastWindowClosed` already returns `true`.

**Sleep, occlusion, and minimize:** pause rendering, but not playback, while
the window is occluded or the display sleeps. Playback policy stays in Dart.

### 4.7 Dart changes for the port

All of these are small. Each one goes behind an existing seam, or behind a
capability the player reports, rather than scattered `Platform.isMacOS`
checks:

| Change | Where |
| --- | --- |
| Select `MethodChannelNativePlayer` on macOS | `native_player_factory.dart` |
| Platform-neutral `required_engine_unavailable` text | `method_channel_native_player.dart` |
| `fullscreen` event stream and coordinator reconciliation (§4.6) | `native_player.dart`, `method_channel_native_player.dart`, `player_coordinator.dart` |
| Hide "Match display HDR" when display matching is unavailable | `lineup_shell.dart` settings |
| Neutral "Display" diagnostics row and text, plus macOS HDR facts (§4.5) | `diagnostics_view.dart`, `diagnostics.dart`, `lineup_shell.dart` |
| ⌘ command modifier on macOS (P5) | `navigation_shortcuts.dart` `commandModifier` |
| `Settings… ⌘,` to Settings | macOS menu (`MainMenu.xib`) plus a small runner channel or `PlatformMenuBar` |
| Plex link opening | `plex_link_launcher.dart`. `Process.run('open')` is not appropriate in a sandboxed App Store app; open the link through `NSWorkspace` instead. |

Existing Dart tests cover the transport and coordinator contracts. Add tests
only for new behavior: the fullscreen event, the capability-driven settings
row, and the modifier.

### 4.8 App Store distribution, sandbox, and credentials

- **Channel:** Mac App Store, with TestFlight for Mac for beta builds. A
  Developer ID–signed, notarized build is optional, for direct testing
  outside TestFlight.
- **Sandbox:** App Sandbox is mandatory on the App Store, and the app already
  runs sandboxed.
  - Keep the `network.client` entitlement.
  - Add `files.user-selected.read-only` only if local media opening is
    offered through a picker.
  - The `--media=` command-line argument stays a development affordance.
- **Signing:** an Apple Distribution certificate and App Store provisioning
  profile. Each embedded framework (libmpv, FFmpeg, MoltenVK if C) is signed
  with the same team identity.
- **Keychain:** signed builds use the data-protection Keychain with a
  `keychain-access-groups` entitlement, as `architecture.md` already
  anticipates. Development builds keep the legacy mode. Development tokens do
  not carry over; App Store users start fresh anyway.
- **App Review:**
  - The reviewer needs a working Plex account and a server with sample media.
    Prepare a demo account and server and include them in the review notes.
  - Check Plex's terms for third-party clients and its trademark guidance for
    the App Store name, icon, and description before submission. Paid
    third-party Plex clients exist, but confirm the current terms.
  - Use only public APIs. Route C does: Metal through MoltenVK, and AppKit.
- **Licenses screen:** an in-app list of third-party licenses and the
  LGPL source and relinking notice (§4.4).

### 4.9 Monetization (separate workstream)

The port does not depend on this, but its architecture should be agreed now so
the port does not paint it into a corner. It needs its own design and approval
pass, especially for the upsell UI.

**Ownership:**

- **Dart** owns the entitlement policy. That means a domain value such as
  `Entitlement { tier: free | pro, source, verifiedAt }` and every decision
  derived from it (channel limit, locked features). This keeps one policy for
  both platforms and keeps it testable in portable Dart tests.
- **Store adapters** report verified purchase state and perform purchases and
  restores:
  - macOS: StoreKit 2 in the Swift runner, behind a small method channel.
    StoreKit 2 verifies transactions on device with signed JWS, so no server
    is needed for a one-time unlock.
  - Windows: deferred (M4). The same Dart interface can later sit on the
    Microsoft Store or a license key.

**Free-tier channel limit (M2):**

- The limit is enforced when channels are created or enabled in
  `LineupController`, not by deleting data.
- Over-limit channels remain persisted, with a visible locked state.
- Upgrading unlocks them immediately. A refund or revocation locks them again
  without deleting anything.
- Persisted data needs no migration, because entitlement is not stored in the
  app's data file; StoreKit's current entitlements are the authority.

**Pricing and tax:** App Store Connect pricing, the Small Business Program (15%
commission under $1M per year), and the Paid Apps agreement with banking and
tax forms. All of these are your account actions.

**Source visibility (M3):** if the repository stays public, the Pro gate is
visible and easy to remove in a self-build. That is normal for open-source
apps sold on the App Store, where buyers pay for convenience and support. If
that is not acceptable, move future development private before Pro ships.

## 5. Work packages

These are not strict sequential phases. The dependencies below are the only
ordering constraints, and independent packages can run in parallel.

| ID | Package | Depends on | Output |
| --- | --- | --- | --- |
| D0 | Product decisions P1, P3, P5–P7, M1–M3 | — | Answers recorded in this plan |
| L0 | Legal review: LGPL on the App Store, Plex terms and trademark, source visibility | M3 | Written go/no-go before the first paid submission |
| S1 | Route C prototype: patched mpv embedded under Flutter, full HDR and Dolby Vision matrix (§4.3) | — (uses a local build) | **Done 2026-10-17**: results in §4.3; E1 decided for C |
| S2 | Reproducible self-built runtime with the patch series (§4.4) | S1 patch drafted (done) | Build script, runtime identity, `macos-runtime.md` |
| K1 | Extract the shared mpv core; Windows uses it with no behavior change | — (starts immediately) | `native/player_core/`, Windows tests green, a Windows acceptance item added to the batched pass |
| K2 | Run the core contract tests on macOS (CMake + CTest, or an XCTest target) | K1 | Native tests in macOS CI |
| M1 | macOS adapter: channel, codec, core wiring, display report `unavailable` | K1, S2 | Playback with audio, track and stop correlation |
| M2 | macOS presentation and HDR (route chosen by S1) | S1, M1 | Video under Flutter with the Guide alpha and HDR output |
| M3 | Fullscreen protocol event and termination ordering (§4.6) | M1, D0 (P6) | Protocol doc updated; Windows and macOS both emit it |
| U1 | Port Dart changes (§4.7) | D0 (P5), M3 for fullscreen | Factory switch, copy, capability-driven settings, ⌘ |
| R1 | Runtime provisioning, App Store signing, `macos-runtime.md`, Licenses screen | S2, D0 (P3) | Reproducible signed build uploadable to App Store Connect |
| C1 | CI: full portable suite on macOS, native core tests, runtime provisioning, a conditional signed-archive job | K2, R1 | Green macOS jobs |
| B1 | Monetization design: entitlement model, channel-limit behavior, upsell UI for approval | D0 (M1, M2) | Approved design |
| B2 | Entitlement implementation: Dart policy, StoreKit 2 bridge, restore, tests | B1 | Free and Pro tiers working in TestFlight |
| A1 | macOS acceptance pass (§6), then TestFlight beta | M2, M3, U1, R1, B2 | Recorded acceptance results |
| AS | App Store submission | A1, L0 | Live listing |

Suggested critical path:

1. Run S1, K1, and D0 in parallel. S1 needs neither the shared core nor
   the final runtime. S2 follows now that the S1 patch has settled.
2. M1, then M2.
3. M3 and U1, alongside B1 and B2.
4. R1 and C1.
5. A1, TestFlight, then AS.

## 6. Verification map

Choose evidence by claim. Static and portable checks do not prove physical
macOS presentation, HDR, or packaging.

| Claim | Evidence | Limit |
| --- | --- | --- |
| The core preserves protocol semantics on both platforms | The existing Windows contract and state tests, moved with the core and run in Windows and macOS CI | Fake mpv operations: proves correlation logic, not real media |
| Token safety (HTTPS only, header only, no redirects, no logging) | `authenticated_reference_test` ported to macOS against the chosen libmpv, plus a log scan | Needs the real libmpv build |
| Dart transport, coordinator, and entitlement policy | Existing `test/playback/*` tests plus new tests for the fullscreen event, capability row, and entitlement decisions | Dart only |
| StoreKit purchase, restore, and revocation | StoreKit Testing in Xcode (local configuration), then the TestFlight sandbox | Sandbox purchases, not production |
| HDR output (the full S1 matrix) | S1 observations, then the same matrix in A1 on a signed build | Physical EDR display; screenshots do not capture EDR |
| Guide alpha over video | The S1 pixel test, then the A1 observation | Physical Mac |
| Rect, scale, and multi-display behavior | A1 at 1× and 2×, plus mixed-scale dual displays | Physical Mac |
| Fullscreen from all four sources | A1: Player button, green button, View menu, ⌃⌘F | Physical Mac |
| Termination during playback | A1: ⌘Q and window close while playing; no hang and no crash log | Physical Mac |
| Sandbox and packaging | The TestFlight build installs and runs; Keychain, network, and link opening work under the sandbox | Physical Mac |
| Windows unchanged after K1 | Windows CI plus items in the user's batched Windows acceptance pass | Physical Windows |

The development machine is a Mac, so S1, S2, and much of A1 can be observed
during implementation. HDR color judgments and the final acceptance pass are
still the user's.

## 7. Risks

| Risk | Effect | Mitigation |
| --- | --- | --- |
| MoltenVK HDR color spaces or EDR misbehave | HDR fails on route C | S1 tests this first. The contingency is C2 (AVFoundation output). |
| Dolby Vision metadata is lost with VideoToolbox hardware decode | Profile 5 is wrong, or needs costly software decode | S1 matrix row. FFmpeg parses the metadata in its HEVC decoder ahead of the hardware decode; verify, and measure the software fallback. |
| A transparent `FlutterView` does not composite exactly over a native layer (Impeller, color space) | Presentation is blocked | S1 tests this early. Fall back to engine-side investigation. |
| mpv patch maintenance | Upgrade friction | Keep the one patch small and well-tested; offer it upstream, since `--wid` on macOS is a long-standing gap. |
| App Review rejects for LGPL, Plex trademark, or a missing demo account | Launch delay | L0 before submission; prepare the demo server and account; follow brand guidance. |
| Public repository undermines the paid tier | Lost revenue | M3 decision before Pro ships. |
| No suitable LGPL macOS build exists | Licensing or provenance gap | Self-build in CI (S2 option 3). |
| Core extraction regresses Windows | Windows playback bugs | Behavior-preserving extraction under the existing contract tests, plus batched Windows acceptance. |
| Video lags the rect during animated resize or transition | Visible misalignment | Measure in S1. Snap the layer inside a `CATransaction` with actions disabled. Hide video during the fullscreen animation if needed. |

## 8. Size

| Area | Size | Notes |
| --- | --- | --- |
| Port Dart changes (U1) | Small: about 200–400 changed lines plus focused tests | Mostly behind existing seams |
| Shared core extraction (K1) | Medium: about 1,000 lines moved and reshaped | The Windows adapter shrinks. The risk is regression, not volume. |
| macOS adapter and presentation (M1–M3) | Medium: about 900–1,300 new lines of Objective-C++ | mpv owns rendering and HDR; the adapter owns the layer, lifecycle, and fullscreen |
| mpv patch and self-built runtime (S1, S2) | Medium: one small mpv patch, a full dependency build, and patch upkeep across mpv updates | The largest new engineering cost, and the price of Dolby Vision profile 5 |
| Runtime, signing, CI, App Store packaging (S2, R1, C1) | Medium | Scripts and provenance more than app code |
| Monetization (B1, B2) | Medium: entitlement policy, StoreKit bridge, locked states, upsell UI | Needs design approval first |
| S1 prototype | Medium | Settles the HDR and transparency unknowns before the main build |

## 9. Documentation updates when this lands

- `.agents/project.md`, `README.md`, `docs/README.md`,
  `docs/architecture.md`, and `docs/DEVELOPMENT.md`: replace "macOS is a
  development surface" once P1 is accepted. Add the macOS presentation, HDR,
  and ownership section next to the Windows one.
- `docs/native-player-protocol.md`:
  - add the `fullscreen` event;
  - generalize the `setVideoRect` and `required_engine_unavailable` notes;
  - record the macOS display report values.
- `docs/open-obligations.md`: move the macOS backlog rows to their results.
- New `docs/macos-runtime.md` (from S2 and R1).
- `docs/user-guide.md`: macOS HDR behavior, the free and Pro tiers, and
  restoring purchases.

## Sources

- mpv manual and source:
  - [`--wid` and `--target-colorspace-hint`](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)
  - [`render.h`](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h)
  - [`vo_libmpv.c`](https://github.com/mpv-player/mpv/blob/master/video/out/vo_libmpv.c)
  - [cocoa-cb EDR handling](https://github.com/mpv-player/mpv/blob/master/video/out/cocoa_cb_common.swift)
  - [classic `gpu` renderer discarding the Dolby Vision mapping](https://github.com/mpv-player/mpv/blob/master/video/out/gpu/video.c)
    (`mp_image_params_restore_dovi_mapping`, defined in [`mp_image.c`](https://github.com/mpv-player/mpv/blob/master/video/mp_image.c))
  - [mac common](https://github.com/mpv-player/mpv/blob/master/video/out/mac/common.swift)
- [Flutter macOS embedder `FlutterViewController.h`](https://api.flutter.dev/macos-embedder/_flutter_view_controller_8h_source.html)
  (transparent background requirements)
- [MPVKit](https://github.com/mpvkit/MPVKit) and
  [media-kit libmpv-darwin-build](https://github.com/media-kit/libmpv-darwin-build)
  (candidate runtimes)
- [Shipping an LGPL libmpv player on the Mac App Store](https://dev.to/yamayu-dev/shipping-a-libmpv-based-video-player-on-the-mac-app-store-1f2l)
  (one developer's account, not legal guidance)
- Plezy ([app](https://github.com/edde746/plezy),
  [mpv-build](https://github.com/edde746/mpv-build)), studied for approach
  only; GPL-3.0, so no source or build is reused
- [IINA HDR discussion](https://github.com/iina/iina/issues/3772)
