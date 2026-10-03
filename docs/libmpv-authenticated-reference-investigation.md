# Authenticated libmpv references: Windows investigation

**Audience:** Lineup Desktop maintainers continuing security and playback work.
**Status:** Investigation evidence from 2026-10-02; no remediation, severity rating, or release acceptance.
**Classification:** **Authenticated nested-reference header propagation confirmed in the pinned native runtime.** Practical reachability through a normal Plex library item remains unproven.

This report separates observed requests from possible attack paths and compatibility predictions. It contains no credential, token-bearing URL, private media identity, full request header, certificate, or retained fixture. The [security policy](../SECURITY.md) gives the private reporting route for any additional sensitive evidence.

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
