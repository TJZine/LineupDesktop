# macOS HDR root cause and channel-switch latency: handoff to Codex

Prepared 2026-10-18 by Claude Opus 5.5 after the investigation requested in
`docs/handoffs/macos-hdr-investigation-opus.md`. Codex owns orchestration
from here: implementation, adversarial review and integration. Repository
rules in `AGENTS.md` and `.agents/project.md` apply. No production source has
been changed. Diagnostics ran from a detached worktree and copied app bundles,
using the accepted runtime unchanged (libmpv SHA-256 `625eb842…adc30f`).

## 1. HDR dimness: root cause established

### Mechanism

MoltenVK configures the video `CAMetalLayer` from the thread that creates the
swapchain. It sets `colorspace`, `wantsExtendedDynamicRangeContent`,
`EDRMetadata`, `pixelFormat` and `drawableSize` there
(`MVKSwapchain.mm` `initCAMetalLayer` lines 520–567 and `setHDRMetadataEXT`
lines 377–382, MoltenVK 1.4.2). With our embedding patch, that thread is
mpv's VO thread, which has no run loop and never commits Core Animation
transactions. Measured: **every file load creates a new VO thread**; each
creates an sRGB swapchain first, then about 30 ms later recreates it as PQ
for HDR content.

The layer's model properties change immediately, so getters report PQ/EDR,
which is why earlier probes looked correct. The window server keeps the old
configuration until a main-thread transaction touches **the video layer
itself**:

- the adapter's `hidden` toggle on occlusion or refocus;
- a resize, as when opening the Guide.

A Flutter-only repaint does **not** publish it; showing the OSD did not
repair the picture. The screen therefore shows the previous load's color
state, which explains every earlier observation:

- **Rapid SDR→HDR stays dim:** the HDR configuration is never published.
- **Guide, refocus or fullscreen repairs it:** a main-thread change to the
  video layer publishes the pending configuration.
- **Same-channel HDR reselect sometimes repairs it:** whether it does depends
  on which layer commits happen in between.

### Objective signal

`NSScreen.maximumExtendedDynamicRangeColorComponentValue`, read **inside the
app**, is the EDR headroom the window server actually grants this process.
It stays 1.00 when the server has not received the EDR request. An external
process always reads 1.00, so the earlier external observer could not see
this.

### Discriminating experiment

The same diagnostic build ran twice with synthetic fixtures (channel 1 is
`sdr-long.mp4`, channel 2 is `hdr10-long.mp4`). The user did the physical
judging in the foreground, in a fixed window.

| | Arm A: `LINEUP_DIAG_CA_FLUSH=off` | Arm B: `LINEUP_DIAG_CA_FLUSH=drawable` |
|---|---|---|
| HDR reference | model PQ/EDR=1 from t+0.1 s, headroom **1.00 for more than 15 s** while active, key and visible. User: **dim** | flush at first acquisition; headroom starts rising after 0.14 s and reaches 16 within about 2 s. User: **bright** |
| `1↵2↵1↵2↵` rapid | final HDR channel: headroom fell 16→1.00 while frontmost. User: **dim** | User: **bright, immediately on every change** |
| Return (OSD only) | no headroom change. User: **dim** | n/a |
| Refocus / app switch | headroom ramps to 16. User: **bright** | n/a |
| Flush thread equals setter thread | n/a | yes for every load (0 mismatches) |

The diagnostic flush works as follows. A `CAMetalLayer` subclass, the
adapter-owned video layer only, records off-main-thread calls to those five
setters. In its `nextDrawable` override, if the recorded thread is the
calling thread, it calls `[CATransaction flush]` before `super`. The setters
run inside libplacebo's swapchain recreation (`start_frame`) or colorspace
hint, both of which precede that frame's acquisition on the same VO thread.

### Correction: owner and options

1. **Recommended: the adapter-owned layer subclass**
   (`macos/Runner/NativePlayer/LineupNativePlayer.mm`, `makeBackingLayer`).
   This is the mechanism already proven above. The port plan §4.3 makes the
   adapter the layer's owner. It needs no runtime rebuild and leaves Windows
   untouched.
   - Production shape: override the setters MoltenVK uses to note the
     dirtying thread when called off the main thread. In `nextDrawable`,
     flush when the current thread matches, then call `super` exactly once.
   - Decide explicitly what happens on a thread mismatch. Flushing on the
     setter thread immediately is the fallback. The diagnostic's `setter`
     mode exists but was not physically tested.
   - Keep it cheap: no logging and no per-frame allocation. Thread IDs come
     from `pthread_threadid_np`, or compare `pthread_self()`.
2. **Alternative: the mpv embedding patch**, flushing on the VO thread in the
   embedded path. The only per-frame hook after configuration is
   `swap_buffers`, which runs *after* `vkQueuePresent`, so the first frame of
   a new configuration could be interpreted with the old one. This requires a
   runtime rebuild and a new lock. It is not tested.
3. Consider reporting upstream: MoltenVK changes `CAMetalLayer` properties on
   arbitrary threads without managing the transaction.

Adjacent behavior to protect:

- MoltenVK's `forceUnpresentedImageCompletion` writes a 1×1 `drawableSize`
  on the old VO thread at teardown. Check that publishing promptly causes no
  black flash between channels.
- Stale-load rejection, shutdown ordering (§4.6), live resize and fullscreen
  must not change. The flush only publishes values MoltenVK already set.

### Verification for the production change

- **Physical, required:** repeat the arm A/B protocol with the production
  build on the EDR display:
  1. HDR reference;
  2. `1↵2↵1↵2↵` rapid;
  3. `1↵2↵` again.

  Each must be judged bright immediately, before refocusing or returning to
  chat.
- **Objective companion:** the in-app headroom, available today through the
  existing `LINEUP_PRESENTATION_LOG=1` poll in
  `LineupNativePlayer.mm` `logPresentationFacts`. HDR loads must reach a
  headroom above 1 within about 1 s while frontmost.
- An independent adversarial review is required before integration. Portable
  tests and compilation do not establish this behavior.

## 2. Channel-switch latency

### Findings

The "3.6 s gap" in the earlier trace was the human's key cadence, not
latency. Stage timing on the user's real local-server **direct-play 4K Plex**
channels, eight tunes per arm, foreground fullscreen, flush fix active:

| Stage (ms) | exact seek (current code) | keyframe seek (diagnostic toggle) |
|---|---|---|
| key → native load call (includes waiting for stop) | 30–100 | 10–135 |
| HTTP open and probe (loadfile → `FILE_LOADED`) | 180–630 (890 cold) | 95–215 (warmer server cache) |
| `FILE_LOADED` → seek issued (Dart round trip) | 24–57 | 1–52 |
| **seek → `PLAYBACK_RESTART`** | **350–1015, median ≈ 860** | **134–303, median ≈ 290** |
| **key → playing, warm median** | **1206 (812–1632)** | **533 (349–617)** |

Synthetic local files give 150–230 ms from load to first frame.

### Cause

[`player_coordinator.dart`](../../lib/playback/player_coordinator.dart)
`_completePartLoad` loads at position 0, waits for readiness, then calls
`player.seek`. That becomes `absolute+exact` in
[`player_core.cpp`](../../native/player_core/player_core.cpp)
(`SeekCommand`). The exact seek decodes from the previous keyframe up to the
schedule position. For 4K HEVC that is the dominant stage.

### Candidates, in order of measured value

1. **Keyframe join for tunes:** measured at about −55 % (≈ −670 ms median).
   - **Product decision for the user:** a keyframe seek lands on the nearest
     keyframe, a few seconds from the exact schedule position. Explicit
     user seeks may still want exact positioning, so separate tune-join
     from user seek.
   - The native seek is in the shared core, so Windows needs CI and later
     physical acceptance.
2. **Start position in the load:** pass the position as mpv's per-file
   `start` option in `loadfile`. This removes the `FILE_LOADED`→seek round
   trip and the read at position 0. It changes the load contract
   (`LoadCommand`, protocol doc, both adapters) and the timing benefit is
   **not yet measured**. Keep the token safety rules: options via node map,
   no URL changes.
3. **Stop → load serialization:** this costs 30–130 ms because Dart awaits
   the native stop before loading. `loadfile replace` might make the explicit
   stop unnecessary. Only pursue it if stale-load and cleanup correctness are
   preserved. Lower value.

The webOS reference feels near-instant. A warm target of about 300–450 ms
seems reachable with options 1 and 2. Measure again after each change, with
the same protocol.

### Unverified UX note

During automation, the first digit typed right after a tune did not start
channel entry; a following Return opened the OSD's Audio panel. This may be
input timing while the OSD had focus. It was not investigated.

## 3. Artifacts (local, not committed; no media identity, URLs or tokens)

`/private/tmp/lineup-ca-flush-apps/`:

- `diagnostic.patch`: the complete diagnostic diff. **Never merge.**
- `armA-frozen.log` and `armA-full.log`: flush off, physical dim.
- `armB-frozen.log` and `armB-full.log`: flush on, physical bright.
- `real-plex-exact-full.log`: Plex timing with the current exact seek.
- `real-plex-keyframes-frozen.log`: Plex timing with keyframe seek.
- `harness/`, `real/` and `real-kf/`: the diagnostic app bundles.

The diagnostic worktree is `/private/tmp/lineup-ca-flush-diagnostic`, a
detached git worktree at `8075c0dc`. Remove it with
`git worktree remove --force /private/tmp/lineup-ca-flush-diagnostic` when it
is no longer needed.

Log format: `<unix seconds> <event>`.

- `sample`: in-app headroom and layer model, every 0.25 s on change and
  every 5 s otherwise.
- `layer-set`: setter calls, with thread.
- `ca-flush`: flushes.
- `first-acquire`: the first drawable acquired after a load or setter.
- `dart …`: coordinator stages.
- `core …` and `mpv …`: native stages.

Earlier evidence remains in `/tmp/lineup-visible-hdr-investigation/`.

## 4. Status of other gates (unchanged)

- Windows CI fix `b0c38b5b` is pushed but not yet verified by CI. Three
  local docs commits on `platform/macos` are unpushed.
- D0 product decisions remain open, along with Licenses UI, signing, legal
  review and monetization.
- No release readiness is claimed.
