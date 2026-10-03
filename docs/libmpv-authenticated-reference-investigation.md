# Authenticated libmpv references: Windows investigation

**Audience:** Lineup Desktop maintainers continuing security and playback work.
**Status:** Historical investigation evidence followed by the 2026-10-03 mitigation below; implemented and deterministically tested, with physical playback acceptance pending. No severity rating or release acceptance.
**Classification:** **Authenticated nested-reference header propagation confirmed in the pinned native runtime.** Practical reachability through a normal Plex library item remains unproven.

This report separates observed requests from possible attack paths and compatibility predictions. It contains no credential, token-bearing URL, private media identity, full request header, certificate, or retained fixture. The [security policy](../SECURITY.md) gives the private reporting route for any additional sensitive evidence.

The investigation and runtime-recheck sections retain their original evidence
boundaries and describe the configuration at those revisions. The final dated
mitigation section supersedes their statements about the current configuration
and the still-pending maintainer decision.

## Scope and source revisions

| Evidence | Repository revision | Boundary |
| --- | --- | --- |
| Initial exact-runtime, two-origin HTTPS test | `9d30daa9b5fe22eb60c5ebed4fc4db5bd2b5593b` | Temporary C++/libmpv harness; not the Lineup UI |
| Real PMS media samples and further libmpv option checks | `380b6b8cb2ac30af786271b849e7cd78ff0f9425` | Temporary harnesses and a read-only local PMS path; not visual or audible app acceptance |
| Source and documentation review for this report | `380b6b8cb2ac30af786271b849e7cd78ff0f9425` | No production edit or new playback test |

The relevant native load, Dart credential contract, Plex media-part URL construction, player-coordinator call, and runtime provenance files have no changes between the two tested revisions. The earlier macOS mpv 0.41.0 experiment showed the same broad mechanism but is **not** evidence for the pinned Windows build.

The test host was Windows 10 Home 10.0.19045, x64. The prepared DLL was supplied through the documented `LINEUP_MPV_ROOT` toolchain location outside the repository; machine-local absolute paths are omitted here. The DLL SHA-256 was verified before the first test and rechecked for this report:

| Runtime identity | Verified value |
| --- | --- |
| mpv build | `v0.41.0-1044-g14f2d48cb` |
| mpv source commit | `14f2d48cbc7dda61adb4bd181e107a1f3f76e533` |
| `libmpv-2.dll` SHA-256 | `B507529D99A4DFFDEAEC85ECEFF7661A7E3C6CA4EFD09C2014E11A1441B83EAA` |

The [Windows runtime provenance](windows-runtime.md) and [native development workflow](DEVELOPMENT.md#windows-native-player) are the authorities for obtaining that exact DLL. No system mpv or substitute build was used.

## Relevant Lineup behavior

Lineup builds each Plex playback part URL from the selected server, rejects a part URL whose scheme, host, or port differs, and passes the selected part and token through its player coordinator. The [Dart player contract](../lib/playback/native_player.dart) requires HTTPS and an `X-Plex-Token` request header rather than a token-bearing media URL. The [Windows native player](../windows/runner/native_player.cpp) validates the supplied token and HTTPS media URI, sets `tls-verify=yes`, and issues authenticated `loadfile` through `mpv_command_node` with per-file `http-header-fields` and `curl-max-redirects=0`. It does not set `access-references`, so mpv's default is `yes`. See the [Plex client](../lib/plex/plex_client.dart) and [player coordinator](../lib/playback/player_coordinator.dart) for the caller path.

That initial same-origin URL check and zero-redirect setting do not inspect URLs discovered later inside a media response. An HLS segment named by an absolute URL is a new request initiated by the media demuxer, not a 3xx redirect. TLS verification authenticates the contacted HTTPS host; it does not decide whether that host may receive the Plex header.

## Exact-runtime synthetic HTTPS experiment

A temporary C++ console harness used the verified headers, import library, and DLL. It called `mpv_create`, set `config=no`, `terminal=no`, `ytdl=no`, `vo=null`, `ao=null`, `tls-verify=yes`, and a temporary `tls-ca-file`, then called `mpv_initialize` and `loadfile` with `mpv_command_node`. The authenticated option map matched Lineup's header and redirect options. Each run had a bounded wait and clean libmpv termination.

Two HTTPS servers bound only to loopback on different ports. Origin A served `/media.m3u8`, whose HLS manifest named an absolute HTTPS `/segment.ts` URL at origin B. An already installed ffmpeg generated a tiny synthetic MPEG-TS segment, so successful demux/playback could be distinguished from a mere request. A temporary self-signed CA and leaf certificate were supplied only to the harness and servers; TLS verification remained enabled and no certificate was added to a trust store. The synthetic token was explicitly non-secret. Servers retained only origin, requested path, request count, and whether that expected value was seen; no complete headers were captured.

Observations were reset for each case:

| Case | A requests | A synthetic token seen | B requests | B synthetic token seen | Bounded harness outcome |
| --- | ---: | --- | ---: | --- | --- |
| Per-file header, `curl-max-redirects=0`, default references | 2 | Yes | 1 | Yes | File loaded; normal end |
| No-header control, default references | 2 | No | 1 | No | File loaded; normal end |
| Per-file header, `access-references=no` | 1 | Yes | 0 | Not applicable | Load failed: unknown format |

The no-header control proves that this fixture was recognized as HLS and that origin B was reachable. The primary case proves that the exact pinned DLL sent the synthetic `X-Plex-Token` header to a different HTTPS origin. The reference-disabled case prevented that request by preventing this HLS fixture from loading. It is a compatibility characterization, not a safe remediation.

## Further configuration checks on the pinned DLL

A later temporary harness used the same pinned DLL and a synthetic HLS fixture to ask whether existing libmpv switches could retain references but scope the credential. These are request/playback observations, not a proposed production configuration. The no-header control reached the cross-origin segment.

| Temporary setting | Cross-origin referenced segment | Authenticated same-origin referenced segment |
| --- | --- | --- |
| Current options/default references | Received the synthetic token | Played |
| `demuxer-lavf-propagate-opts=no` alone | Still received the token | Not established in this comparison |
| `curl-enabled=no` alone | Still received the token | Not established in this comparison |
| Both options above | Did not receive the token | Lost the token; playback failed |
| `access-references=no` | No segment request | No segment request; playback failed |

No tested switch produced the desired combination: authenticated same-origin nested playback and token-free cross-origin nested playback. The [pinned mpv nested-open implementation](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/demux/demux_lavf.c) can use mpv's curl stream or FFmpeg's own open path, consistent with the one-option failures. This was not an exhaustive audit of every mpv option or every demuxer.

## Read-only checks with real local Plex media

After explicit authorization for in-memory, read-only use of this machine's local Plex credential, three actual media parts were selected from the local PMS. The credential went only to that server. A temporary loopback HTTPS proxy served the media to the pinned libmpv harness, which used a synthetic token; the real credential was never handed to libmpv or a test origin. No media or credential was retained. These checks exercised the real part bytes under two libmpv reference settings, not the Lineup UI or an actual Plex-authenticated libmpv network request.

| Sample container/video codec | Default references | `access-references=no` | Observed tracks / ordinary chapters in both |
| --- | --- | --- | --- |
| MP4 / H.264 | Loaded; position advanced | Loaded; position advanced | 2 / 0 |
| MKV / H.264 | Loaded; position advanced | Loaded; position advanced | 4 / 3 |
| MKV / HEVC | Loaded; position advanced | Loaded; position advanced | 3 / 0 |

These were null-audio/null-video demux and playback-progress observations. They do not prove visible video, audible sound, track selection, seeking quality, or physical Lineup playback. The three ordinary chapters in the sampled MKV are not evidence about Matroska *ordered* chapters that require other files. No reference-bearing item was established as ingestible and playable through the Plex library path.

## What disabling references would change

The [pinned mpv option documentation](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/DOCS/man/options.rst#L390-L406) says `access-references=no` disables ordered chapters, MOV reference files, archive opening, and other reference-dependent features. It also says paired subtitle files can still be opened, and some FFmpeg demuxers may not honor the option. It is therefore both a broad playback restriction and an incomplete security boundary.

| Lineup use | Evidence and limit |
| --- | --- |
| Plex playlists, channel schedules, sequential media parts | Flutter resolves playlists and loads parts individually; this mpv option should not remove those application lists. A failed media load would still leave that item without playable output. |
| Common self-contained MP4/MKV | The three sampled parts progressed in both modes with unchanged track counts; broader compatibility is not proven. |
| Ordinary in-file chapter markers | Three sampled MKV chapter markers remained; ordered external-segment chapters were not tested. |
| HLS and likely other segmented/reference media | Same-origin authenticated HLS failed in the synthetic control. DASH was not tested, so its exact result remains unknown. |
| Ordered chapters, MOV references, archives | mpv documents feature loss; no representative Lineup/Plex acceptance was run. |
| Paired or external subtitles | The option is not a complete block on these opens; Lineup currently has no explicit external sidecar loading capability. |

The [architecture record](architecture.md#integration-and-acceptance-status) keeps format-open original-stream playback as the current native direction. The [Windows native acceptance matrix](windows-native-validation.md) still requires representative media, subtitle, track, and package checks before supported playback claims. A blanket `access-references=no` setting would trade away known capabilities without establishing that all header-bearing secondary requests are contained.

## Feasibility and impact: facts versus inferences

**Observed fact:** when authenticated HTTPS content is interpreted as the tested HLS manifest, the pinned DLL makes a request to the manifest's different HTTPS origin and sends the per-file synthetic header. The protection against authenticated HTTP redirects does not cover that new request.

**Required but unproven Plex path:** a real item must be indexed and exposed by PMS as a playable part whose served bytes contain references that the pinned runtime follows. Lineup currently requests original media parts rather than a Plex transcode playlist. [Plex explains](https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/) that Direct Play sends the original file unchanged, but this investigation did **not** establish whether PMS indexes an HLS manifest as a library item. A MOV reference movie is another candidate because mpv documents MOV references, but no Plex/MOV cross-origin test was run. Ordinary self-contained MP4/MKV samples did not provide such a trigger.

**Potential attacker path, conditional on that missing proof:** someone able to place or replace reference-bearing media served by an otherwise trusted PMS could make the media name an attacker-controlled HTTPS origin. That origin would receive the credential if the same propagation occurs through the PMS item. Merely controlling an unrelated website does not supply the required media reference. A fully malicious PMS already receives the credential on the initial authenticated request, so the nested-reference path adds less to that threat model.

**Possible confidentiality impact:** a receiving origin could record the token. Plex describes `X-Plex-Token` as an authentication value for server requests; practical replay depends on its scope and the attacker's ability to reach the relevant server. This test does not establish account-wide privilege, remote server reachability, frequency in real libraries, or final severity. It does not show that every Plex media item is exploitable.

## Comparison with other open source clients

The following are source comparisons, **not** security verdicts or runtime tests of those applications:

- [Jellyfin MPV Shim at `8cc74621a50cb0384bf610c0374ad5fdbdb211ac`](https://github.com/jellyfin/jellyfin-mpv-shim/blob/8cc74621a50cb0384bf610c0374ad5fdbdb211ac/docs/auth-headers.md) explicitly treats mpv's header option as broad and persistent. Its [player path](https://github.com/jellyfin/jellyfin-mpv-shim/blob/8cc74621a50cb0384bf610c0374ad5fdbdb211ac/jellyfin_mpv_shim/player.py) clears the global header between items, checks the eventual media origin, and declines to install it for known foreign subtitle hosts. It falls back to same-origin URL credentials in some cases. These checks address known external paths; they do not prove arbitrary references hidden in media are scoped.
- [Jellyfin Desktop at `2cb4a4456fd29b5b62d825ef0e5df93ed6913328`](https://github.com/jellyfin/jellyfin-desktop/blob/2cb4a4456fd29b5b62d825ef0e5df93ed6913328/src/player/PlayerComponent.cpp) passes a supplied URL to mpv in the inspected `queueMedia` path and adds a User-Agent option, without adding an analogous auth header there. That one path does not establish its complete credential handling or security posture.

Lineup owns the decision to supply a Plex credential, but a Dart check of the initial URL cannot enforce a policy on URLs found later inside libmpv. The credential policy needs enforcement at the native network request boundary or another transport demonstrated to cover every nested open path. No such implementation was made here.

## Continuation gates

1. **Prove or bound Plex reachability.** With separate authorization to alter an isolated Plex test library, add only synthetic reference-bearing media and determine whether PMS indexes it and serves the original bytes as a playable part. Use the real credential only for requests back to PMS. Do not allow that credential to reach a test origin. If PMS will not serve a suitable fixture, record the practical trigger as unproven rather than treating the runtime test as a demonstrated Plex exploit.
2. **Design origin-scoped credential delivery.** Preserve same-origin authenticated nested requests and allow cross-origin references without the Plex token. Define origin comparison, retries, seeks, redirects, alternate legitimate PMS hostnames, and failure behavior. A cross-origin reference that genuinely requires the same token may need a separate product decision. Do not adopt a broad reference block as the default fix.
3. **Verify compatibility and confidentiality before release.** Use synthetic two-origin and same-origin HLS controls; add representative DASH, ordered-chapter, MOV-reference, archive, and sidecar cases where supported. Recheck real PMS part samples and physical Lineup playback against the exact new DLL hash and commit. Follow the relevant [Windows native acceptance](windows-native-validation.md) scenarios. Independent review is specifically recommended for any credential/header transport change.

No fixture, harness, certificate, proxy, server, media copy, or synthetic credential from the tests was committed or retained. All temporary test processes were stopped and the created temporary directories were removed. The initial test left the pre-existing three documentation edits unchanged. This report and its documentation-index link are the only intended changes in the report commit.


## 2026-10-03 addendum: refreshed Windows runtime

The dependency refresh was rechecked at Lineup commit
`978b5eb2b8cece501ec13224d1ac209d20e97e4c` on Windows x64 using the
baseline x86-64 LGPL dev asset from the
[2026-10-02 release](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-02-3186d369f9).
The original evidence above is unchanged.

| Refreshed runtime identity | Verified value |
| --- | --- |
| mpv build | `v0.41.0-1092-g3186d369f` |
| mpv source commit | `3186d369f9f090cd1363be0ac46a037824b702c6` |
| `libmpv-2.dll` SHA-256 | `4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51` |
| Release archive SHA-256 | `322CB0040B97B15F97069F631F665FD63DA331CED92705F757DA13B99380DA5F` |

A recreated temporary C++ harness used the verified header, generated MSVC
import library, and exact new DLL. It retained the initial experiment's null
outputs, TLS verification, temporary CA, per-file option map, and synthetic
MPEG-TS/HLS fixture. Both HTTPS servers bound only to loopback, on different
ports. No real Plex credential or media was used. Options were checked for
successful acceptance. Each run had a 12-second event deadline and an
18-second process timeout. Playlist handoffs were followed through the final
file outcome rather than treating `MPV_END_FILE_REASON_REDIRECT` as a completed
playback result. Request observations contained only origin, fixture path,
counts, and synthetic-token-seen booleans; full headers were not captured.

| Cross-origin HLS case | A requests | A synthetic token seen | B segment requests | B synthetic token seen | Null-output harness outcome |
| --- | ---: | --- | ---: | --- | --- |
| Per-file header, `curl-max-redirects=0`, default references | 1 | Yes | 1 | **Yes** | Loaded; normal end |
| No-header control | 1 | No | 1 | No | Loaded; normal end |
| `access-references=no` | 1 | Yes | 0 | No | Did not load; error end |
| `demuxer-lavf-propagate-opts=no` | 1 | Yes | 1 | **Yes** | Loaded; normal end |
| `curl-enabled=no` | 1 | Yes | 1 | **Yes** | Loaded; normal end |
| Both preceding switches | 1 | Yes | 1 | No | Loaded; normal end after playlist handoff |

A second fixture pointed the segment back to A and required the synthetic
header on both the manifest and segment. It established the compatibility
control that a token-free cross-origin request alone does not establish:

| Authenticated same-origin HLS case | Segment requests | Segment synthetic token seen | Null-output harness outcome |
| --- | ---: | --- | --- |
| Current options/default references | 1 | Yes | Loaded; normal end |
| No-header control | 0 | No | Manifest rejected; error end |
| `access-references=no` | 0 | No | Did not load; error end |
| `demuxer-lavf-propagate-opts=no` | 1 | Yes | Loaded; normal end |
| `curl-enabled=no` | 1 | Yes | Loaded; normal end |
| Both preceding switches | 1 | No | Segment rejected; error end |

For a direct comparison, the same completed harness and fixtures were rerun
against the original DLL after verifying its recorded SHA-256. All six
credential/playback outcomes in each fixture were the same. Request patterns
changed: the old DLL fetched the cross-origin fixture's manifest twice for
default references and the option-switch cases, while the new DLL fetched it
once. With both switches, the old DLL made three token-free B segment requests
and the new DLL made one. This is consistent with
[the HLS/DASH stream-open change](https://github.com/mpv-player/mpv/commit/13a4bfbc1a184c0576ca69c2de486a972aeb2407),
which removes the duplicate manifest fetch; the request counts are observations
of this fixture, not a general request-count contract.

**The libmpv bump did not fix the nested-reference finding or change the tested
credential-delivery outcomes.** Default references still sent the synthetic
per-file credential to B. Neither single switch scoped it, and the combined
switches also removed the credential needed for authenticated same-origin
playback. No production option, security fix, or fix design was changed.

This is executed Windows DLL/harness evidence, not physical Lineup playback,
HDR, audio output, DirectComposition, fullscreen, input, or package acceptance.
Practical Plex library reachability and the original evidence limits remain
unproven. Separate options research and the maintainer's decision still precede
any remediation. Independent review is specifically recommended for the
runtime/provenance bump and this security re-check. The temporary servers were
stopped, and the harness, fixtures, certificates, keys, and synthetic value
were removed after recording these normalized results.

## 2026-10-03 mitigation: disable reference following

The maintainer selected the hardened configuration. Commit `3d2014e` sets
`access-references=no` and `autoload-files=no` beside `tls-verify=yes` in the
production initialization loop. Either option being rejected uses the existing
initialization error/cleanup path; playback does not continue. Per-file
`http-header-fields` and `curl-max-redirects=0` are unchanged. There is no
`demuxer-lavf-propagate-opts=no` setting: reference-disabled initialization
installs `block_io_open`, so the propagation branch in `nested_io_open` is never
consulted. This is configuration hardening, without an mpv patch or `stream_cb`
transport.

**Unsupported:** nested/reference-dependent playback, including same-server
HLS and DASH, MOV reference movies/external tracks, EDL/CUE/media-file playlists,
Matroska ordered chapters requiring other segments, archives and automatic
external subtitle/audio/cover-art discovery. Flutter-resolved Plex playlists,
channel schedules and individually loaded parts are separate application
features. Ordinary in-file chapters and embedded audio/subtitle tracks do not
require reference following. An ordered-chapter container can fall back to its
main file with references ignored; disabling references does not promise that
every file containing reference metadata is rejected.

### Bounded pinned-source audit

Sources were read at mpv
`3186d369f9f090cd1363be0ac46a037824b702c6` and FFmpeg
`f68e1afc1b7cf4275d09f1a9026ff80228cf99a8`. The boundary is a caller-authorized
Direct Play HTTPS part, content probing, the production defaults and the two
new options. Explicit forced formats, arbitrary client commands and different
runtime configurations are outside it. Optional demuxers are conservatively
audited even where this DLL may not include them.

**Blocked** means the relevant open is refused or not reachable from this
boundary. **Header-free** means an open can bypass mpv's callback but does not
receive the per-file credential. **Open** would mean an uncontained credential
path and would stop this work. No **open** path was found in this bounded audit.
This is not a claim that mpv disables all network activity or enforces HTTPS
same-origin policy on every internal open.

| Path | Status | Pinned-source evidence |
| --- | --- | --- |
| HLS manifests, variants, segments, initialization sections and AES keys | Blocked | The only `nested_network` entries are HLS and DASH in [mpv's format hacks](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_lavf.c#L180). Headers still enter their open dictionary at lines 1453–1457, but lines 1498–1505 install `block_io_open`. [HLS `open_url`](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/hls.c#L742) routes new opens through `s->io_open`. Its potential direct keepalive bypass is disabled for the custom main AVIO at lines 2317–2329; no native HTTP context exists to reuse. Child demuxers install their own rejecting `nested_io_open` at lines 1917 and 1950. |
| DASH manifest refreshes, initialization and media segments | Blocked | [DASH `open_url`](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/dashdec.c#L460) and manifest open at line 1297 use `s->io_open`. Child demuxers reject further opens at lines 1919–1926 and 1991. Receiving the network dictionary does not bypass those callbacks. |
| `AVFMT_NOFILE`: `image2` | Blocked | [FFmpeg probing](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/format.c#L191) excludes NOFILE inputs when probing opened content, with `image2` as the explicit exception. [mpv probing](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_lavf.c#L509) passes `buf_size > 0` and blacklists `image2` at line 218. Even its file opens use `s1->io_open` in [img2dec.c](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/img2dec.c#L405). |
| `AVFMT_NOFILE`: `rtsp`, `rtp`, `sap`, `rdt`, `dvdvideo`; NOFILE device inputs | Blocked | The same FFmpeg probe exclusion applies before the dictionary-injection code. RTSP/RTP/SAP can call `ffurl_open_whitelist` directly, DVD uses native disc IO and RDT is an internal helper, but none is selected by probing an opened HTTPS response. Definitions: [rtspdec.c:1122](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/rtspdec.c#L1122), [rtsp.c:2901](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/rtsp.c#L2901), [sapdec.c:245](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/sapdec.c#L245), [rmdec.c:1187](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/rmdec.c#L1187), [dvdvideodec.c:1861](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/dvdvideodec.c#L1861). No production forced-format/device command is supplied. NOFILE muxers are output paths and are not media-part demuxers. |
| SDP content and RTP/RTCP transport | Header-free | SDP is probeable and [sdp_read_header](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/rtsp.c#L2677) opens RTP directly, bypassing `io_open`. The mpv SDP hack is `is_network`, not `nested_network` or NOFILE; it gets no headers dictionary. [map_to_opts](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/rtsp.c#L134) supplies buffer/packet/local-address settings only, and the transport is RTP/UDP, not an HTTP URL from `a=control`. This configuration is not a general network sandbox. |
| Media-file playlists, including M3U/PLS/reference INI | Blocked | [demux_playlist.c:646](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_playlist.c#L646) rejects opening when references are disabled. `load-unsafe-playlists` defaults false in [stream.c:127–135](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/stream/stream.c#L127); `playlist-inherit-options` defaults to zero (`no`) in [options.c](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/options/options.c#L625), and [loadfile.c:1185](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/player/loadfile.c#L1185) only copies file options for `yes/current`. Network-origin rules allow other network origins, so they are not an HTTPS host/port credential policy. The reference guard is the protection here. |
| EDL and CUE | Blocked | Explicit early guards in [demux_edl.c:637](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_edl.c#L637) and [demux_cue.c:249](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_cue.c#L249) run before subordinate opens. [stream.c:243](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/stream/stream.c#L243) also forbids network content from switching to filesystem/unsafe streams. |
| Ordered chapters and archives | Blocked | [demux_mkv_timeline.c:527](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_mkv_timeline.c#L527) declines the external-segment timeline; [demux_libarchive.c:43](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_libarchive.c#L43) refuses archive demuxing. Ordinary in-file playback/chapters may remain. |
| MOV external data references | Blocked | FFmpeg [mov.c:12592](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/mov.c#L12592) defaults `enable_drefs` to zero. If enabled, `mov_open_dref` still uses `c->fc->io_open` at lines 5462 and 5468, so the mpv block applies. The generated `rmra/rdrf` fixture is rejected in both configurations and is not proof of a pre-change MOV leak. |
| Automatic external subtitle/audio/cover-art files | Blocked | [loadfile.c:1087](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/player/loadfile.c#L1087) returns before discovery with `autoload-files=no`. Config files are disabled, external-file option lists are empty by default, and the production channel exposes no external-file add command. Embedded track selection is separate. |
| FFmpeg concat: absolute URLs and file-supplied options | Blocked | [concatdec.c:128](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/concatdec.c#L128) enforces safe filenames; safe mode defaults on at line 994 and rejects unsafe option directives at line 507. Absolute HTTPS references are refused. |
| FFmpeg concat: safe relative filenames | Header-free | [concatdec.c:345–362](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/concatdec.c#L345) creates a fresh child format context without copying the parent's callbacks or network headers. Only the file's own options are passed; safe mode disallows option directives. This bypass can open a relative resource, but carries no per-file Plex header. |
| Paired VobSub `.idx/.sub` | Header-free | [mpeg.c:813–823](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/mpeg.c#L813) creates a fresh child and calls `avformat_open_input` with NULL options, copying only protocol/format allowlists. mpv [guess_and_set_vobsub_name](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/demux/demux_lavf.c#L579) supplies a paired filename, not credentials. `autoload-files=no` does not control this internal demuxer open. |
| IMF asset maps and MXF resources | Blocked | [imfdec.c:323](https://github.com/FFmpeg/FFmpeg/blob/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8/libavformat/imfdec.c#L323) uses `s->io_open` for asset maps. Child MXF contexts copy `io_open`, `io_close2` and `opaque` at lines 394–396, preserving the mpv block through `avformat_open_input`. |
| Authenticated HTTP redirects and stream-location changes | Blocked | The production per-load redirect limit remains zero. [stream_curl.c:864–879](https://github.com/mpv-player/mpv/blob/3186d369f9f090cd1363be0ac46a037824b702c6/stream/stream_curl.c#L864) applies `CURLOPT_MAXREDIRS` and peer/host verification. The initial HTTPS request cannot redirect to HTTPS or HTTP. Header-free FFmpeg child opens above may follow their own redirects; they still lack the per-file header. |

### Native regression and verification

Commit `36567d6` adds the opt-in Windows CTest described in
[Development](DEVELOPMENT.md#current-test-tiers-and-gaps). It compiles the
production player implementation, initializes it through its existing method
channel, and executes the production authenticated load command. Test-local
forwarders supply a temporary CA and null outputs, with no production export
or duplicate production option list. The prepared and copied DLL both match
SHA-256 `4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51`.
Origin A requires the synthetic token. No system trust store is modified.

The negative comparison rebuilt this same harness with only the two new
options removed, reproducing the pre-change option set at `5509a5a`. It failed
once because B received the synthetic per-file token. After restoring the
production options, the final 22-check CTest passed three consecutive runs
(8.81, 8.91 and 8.58 seconds). Each run regenerated fixtures/certificates,
stopped both servers, terminated native clients and removed all temporary
media, certificates and keys. No raw diagnostics or headers were retained.

| Fixture | Before: B requests / token seen | After: B requests / token seen | Playback/result limit |
| --- | --- | --- | --- |
| Authenticated self-contained MP4 and MKV | 0 / No, each | 0 / No, each | A saw the token; both progressed and completed in both configurations. Synthetic H.264 video with null outputs. |
| HLS, different hostname | 1 / Yes | 0 / No | Before progressed; after rejected. |
| HLS, same hostname/different port | 1 / Yes | 0 / No | Before progressed; after rejected. |
| Authenticated same-origin HLS | 0 / No | 0 / No | Before: A had 2 requests, including an authenticated segment; after: A had 1 manifest request and the load was rejected. |
| HLS master/variant reference | 2 / Yes | 0 / No | Before progressed; after rejected. |
| HLS AES-key/segment references | 3 / Yes | 0 / No | Before reached B with the token; after rejected. This is egress evidence, not a successful encrypted-decoding claim. |
| DASH | 2 / Yes | 0 / No | Before eventually failed but had already leaked; after rejected before any B request. |
| Media-file playlist | 1 / No | 0 / No | Before progressed without inheriting the header; after rejected. |
| EDL | 1 / Yes | 0 / No | Before progressed; after rejected. |
| CUE, generated MOV reference, absolute concat and VobSub index | 0 / No, each | 0 / No, each | Rejected in both. Before CUE also made a secondary A request carrying the token; after it did not. These ancillary fixtures do not prove that every named demuxer recognized them or exercised its internal secondary-open branch. |
| Relative concat and minimal IMF CPL | Not run in negative comparison | 0 / No, each | After rejected with A=1. No child request occurred; bypass classifications above are source evidence, not a dynamic child-open demonstration. |
| SDP with foreign HTTPS `a=control` | Not run in negative comparison | 0 / No | A=1; bounded 2-second observation, then native cleanup. Neither playback nor rejection was established; the RTP/header-free classification comes from source. |
| HTTPS and HTTP redirect targets | 0 / No, each | 0 / No, each | Initial authenticated request refused the redirect in both configurations. |
| Reject either hardening option during initialization | Not run in negative comparison | 0 / No, each | Test-local rejection injection produced initialization failure with A=0. |
| Untrusted CA | Not run in negative comparison | 0 / No | A=0; verified TLS refusal. |

The full Windows portable suite passed **937 tests** on this checkout in the
Windows Eastern timezone. The separately tracked Air Check failure did not
reproduce; no Air Check changes were made here. `flutter analyze`, the existing
encoder CTest, `pwsh -File ./tool/windows/verify-release-policy.ps1`, and
`flutter build windows` all passed. These checks used the pinned Flutter SDK.

**Evidence tier:** implemented and deterministically tested against the pinned
Windows DLL; not physical Lineup/Plex, visible/audible, HDR, DirectComposition,
input/focus, fullscreen or portable-package acceptance. Remaining maintainer
checks at the final acceptance commit: real Plex MP4/MKV H.264/HEVC, including
an HDR remux; start, seek, switch embedded audio/subtitle tracks and change
channels; controlled reference-bearing rejection/containment and recovery.
Representative ordered-chapter and MOV library items were not physically
tested. **Independent review is specifically recommended** because this change
modifies the credential boundary. Nothing was pushed and no CI gate changed.
