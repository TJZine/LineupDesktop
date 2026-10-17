# macOS runtime provenance

Lineup Desktop's macOS player uses a self-built arm64 libmpv runtime. Route C
(see [the port plan](macos-port-plan.md#43-presentation-and-hdr-route)) needs
an mpv patch, so no third-party binary build is used.
`tool/macos/build-mpv.sh` builds every component from pinned upstream sources
listed in `tool/macos/mpv-runtime.lock`. The repository does not commit
third-party binaries.

Every shipped component is a dynamic library with an `@rpath/` install name,
for `Lineup Desktop.app/Contents/Frameworks`. A user can replace any LGPL
library with a compatible modified build. The configuration is LGPL or
permissive only: no GPL component is built into the runtime.

This document is an engineering inventory, not legal advice. **Independent
legal review of the LGPL and App Store position is still required before the
first paid submission** (see "Distribution notes" below).

## Media runtime

| Component | Exact source | License and distribution decision |
| --- | --- | --- |
| libmpv (`libmpv.2.dylib`) | mpv `v0.41.0-1092-g3186d369f`, full commit `3186d369f9f090cd1363be0ac46a037824b702c6` (the commit Windows pins), plus `tool/macos/mpv-patches/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch` (SHA-256 `9d070fc30414a80b1a418c6b15dee8071086298e7d6aed3236babf331f964b15`) | LGPL-2.1-or-later; built with `-Dgpl=false`. Ship the patch, the LGPL text, and the source links. |
| FFmpeg (`libavcodec.63`, `libavformat.63`, `libavutil.61`, `libavfilter.12`, `libswscale.10`, `libswresample.7`) | Release 9.0.2, `https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`, SHA-256 `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e` | LGPL-2.1-or-later. Configured without `gpl`, `version3`, or `nonfree`; every `*_license()` reports `LGPL version 2.1 or later`. |
| libplacebo (`libplacebo.360.dylib`) | Tag `v7.360.1`, commit `cee9b076f2c63104ccfd497fa79c39a867293ec4`, with submodules, from `https://code.videolan.org/videolan/libplacebo.git` | LGPL-2.1-or-later. Vulkan, Dolby Vision reshaping (`dovi`), and lcms enabled. It also contains the header-only fast_float (MIT, Apache-2.0, or BSL-1.0) and statically linked glslang (below). |
| glslang (static, inside libplacebo) | Release 16.6.0, `https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz`, SHA-256 `9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2` | BSD-3-Clause, BSD-2-Clause, MIT, and Apache-2.0. Its license file also contains GPL-3.0 text with the Bison exception, for the historical Bison parser skeleton; the exception permits distribution under any terms. **Flagged for the legal review.** |
| MoltenVK (`libMoltenVK.dylib`) | Tag `v1.4.2`, commit `db66022459ffb663aa2b50f6b018bc2e124f5edf`, from `https://github.com/KhronosGroup/MoltenVK.git`. Its `fetchDependencies` revisions are pinned in the lock file and checked: Vulkan-Headers `e3b1eec0…`, SPIRV-Cross `6c09849f…`, SPIRV-Headers `29981f65…`, SPIRV-Tools `0d6fd73c…`, Vulkan-Tools `8c66b352…`, Volk `77689330…`, cereal `a56bad8b…` | Apache-2.0. SPIRV-Cross (Apache-2.0 or MIT) and cereal (BSD-3-Clause) are compiled into it. libplacebo and mpv link MoltenVK directly; there is no Vulkan loader and no ICD manifest search. |
| Vulkan-Headers | Exact MoltenVK pin above (`e3b1eec08173d6b825cd3ac88c885a63b621504a`); also the `vk.xml` used to generate libplacebo's Vulkan code | Apache-2.0 or MIT; headers only. |
| libcurl (`libcurl.4.dylib`) | Release 8.23.0, `https://curl.se/download/curl-8.23.0.tar.bz2`, SHA-256 `95b22eb32bf6d1fa6e3e9463bdb61cece3efc56d86576a9b3cbd428246a6d854` | curl license (MIT-style). HTTP and HTTPS only. See "TLS decision". |
| OpenSSL (`libssl.3`, `libcrypto.3`) | Release 3.5.9 (LTS), `https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz`, SHA-256 `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` | Apache-2.0. Providers built in (`no-module`), no engines, and no DSO loading, so it never loads code at runtime. |
| dav1d (`libdav1d.7.dylib`) | Release 1.5.4, `https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz`, SHA-256 `686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5` | BSD-2-Clause. AV1 software decode (M1 has no AV1 hardware decoder). |
| libass (`libass.9.dylib`) | Release 0.17.5, `https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz`, SHA-256 `2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc` | ISC. CoreText font provider; no fontconfig. |
| FreeType (`libfreetype.6.dylib`) | Release 2.15.0, `https://download.savannah.gnu.org/releases/freetype/freetype-2.15.0.tar.xz`, SHA-256 `93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5` | Dual FTL or GPL-2.0; **used under the FTL**, which requires a credit in the documentation (the Licenses screen). |
| HarfBuzz (`libharfbuzz.0.dylib`) | Release 14.6.0, `https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz`, SHA-256 `d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586` | MIT ("Old MIT"). Shaping library only. |
| FriBidi (`libfribidi.0.dylib`) | Release 1.0.17, `https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz`, SHA-256 `6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2` | LGPL-2.1-or-later for the library. Only the library is built, not its GPL table-generation tools. |
| Little CMS (`liblcms2.2.dylib`) | Release 2.19.1, `https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz`, SHA-256 `bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8` | MIT. The GPL-3.0 fast-float and threaded plugins are disabled. |

macOS supplies zlib, bzip2, iconv, the Swift runtime (`/usr/lib/swift`),
libc++, and the system frameworks. They are not bundled.

The archive SHA-256 values were cross-checked against Homebrew's independent
pins for the same upstream URLs: they match for all archives except glslang,
which Homebrew does not pin. Git sources are verified by full commit after
checkout.

### Build configuration

Every configure flag is in `tool/macos/mpv-runtime.lock`. The main decisions:

- **mpv** is configured with `-Dauto_features=disabled`, so only listed
  features exist. Enabled features (from the build summary): `avfoundation
  bsd-fstatfs cocoa coreaudio darwin ffmpeg glob glob-posix iconv lcms2 libass
  libcurl libdl libplacebo mac-thread-name macos-10-15-4-features
  macos-11-3-features macos-11-features macos-12-features posix posix-shm swift
  vector videotoolbox-pl vulkan zlib`. Not built: Lua, JavaScript, C plugins
  (no runtime code loading), OpenGL and cocoa-cb, rubberband, vapoursynth,
  libbluray, DVD, CDDA, libarchive, uchardet, zimg, JPEG, SDL, the
  media-player and Touch Bar integrations, and the CLI player.
- **FFmpeg** uses `--disable-autodetect`. Enabled: VideoToolbox, libdav1d,
  zlib, bzlib, pthreads, OpenSSL, and the protocols `file crypto data http
  https httpproxy tcp tls`. libavdevice, the programs, and the RTP/RTSP/SAP/WHIP
  formats (which would pull in `udp`, `rtp`, and `dtls`) are disabled. The
  built-in decoders include HEVC (Main 10), H.264, VP9, AV1 (native for
  hwaccel, libdav1d for software), AAC, AC-3/E-AC-3, TrueHD/MLP, DTS, FLAC,
  Opus, and MP3, plus ASS, SubRip, WebVTT, PGS, DVB, and DVD subtitles. The
  demuxers include Matroska, MOV/MP4, MPEG-TS, and HLS. DASH needs libxml2 and
  is not built.
- **libplacebo** links glslang statically and has no libdovi. FFmpeg parses
  the Dolby Vision RPU and libplacebo applies the reshaping.
- **Deployment target** macOS 12.0 for every library (`LC_BUILD_VERSION minos
  12.0`). No dependency required a newer target. mpv's Swift code is compiled
  with `-target arm64-apple-macos12.0`; Swift overlays newer than macOS 12
  (for example `libswiftSpatial`) are weak-linked by the toolchain.
- **Architectures:** arm64 only (`LINEUP_RUNTIME_ARCHS` in the lock file). The
  script's per-architecture variables, OpenSSL/FFmpeg targets, and cross
  flags already accept `x86_64`. A universal runtime would build each
  architecture into its own `dist/ARCH` and merge them with `lipo`. That merge
  step is not written yet.

## TLS decision

**Decision:** libcurl 8.23.0 with OpenSSL 3.5.9 for the TLS protocol and
**Apple SecTrust** (`--with-apple-sectrust`) for certificate verification. No
CA bundle or CA path is compiled in.

Why:

- In this mpv version, mpv's own libcurl stream handles `http` and `https`
  (the `curl-max-redirects` and `http-header-fields` behavior the Windows
  player relies on). It is enabled by default with libavformat ≥ 62.15.101;
  FFmpeg 9.0.2 is libavformat 63. mpv sets `CURLSSLOPT_NATIVE_CA` and maps
  `tls-verify` to `CURLOPT_SSL_VERIFYPEER` and `CURLOPT_SSL_VERIFYHOST`.
- curl removed its Secure Transport backend. Its `CURLSSLOPT_NATIVE_CA`
  documentation lists OpenSSL's native CA support for Windows only. Since
  curl 8.17.0, `--with-apple-sectrust` verifies through Apple's SecTrust
  service with an OpenSSL-compatible backend or GnuTLS (curl `docs/INSTALL`,
  "Selecting TLS Trust Anchors Defaults", and `docs/SSLCERTS`). That makes the
  macOS system trust store, including user and MDM trust settings, the trust
  source. curl's configure summary for this build reports `CA native: Apple
  SecTrust`, `CA cert bundle: no`, `CA cert path: no`, and `Protocols: http
  https`.
- OpenSSL (Apache-2.0) was chosen over GnuTLS, which would add LGPL/GPL-dual
  nettle and GMP. OpenSSL's `OPENSSLDIR` points to a directory that does not
  exist (`/var/empty/lineup-openssl`), so no system or third-party
  `openssl.cnf` or CA directory is read.
- Passing mpv's `tls-ca-file` (`CURLOPT_CAINFO`) replaces SecTrust with that
  file, per curl's documentation. Lineup does not set it.

**FFmpeg's own TLS.** In this runtime, mpv opens nested HTTP(S) requests (HLS
playlists, segments, keys) through libcurl: `nested_io_open` tries
`mp_curl_avio_open` first. FFmpeg still needs its `http` and `https` protocols
registered, because its HLS demuxer checks each segment URL's protocol by name
(`avio_find_protocol_name`) and rejects unknown ones before calling mpv's open.
A first build with `--disable-network` would have broken Plex HLS transcoding.
FFmpeg's `tls` therefore uses the same OpenSSL. Certificate verification is on
by default in FFmpeg 9 and there are no trust anchors, so any HTTPS connection
FFmpeg makes itself **fails closed**. That covers the header-free fallback
opens in [the authenticated-reference audit](libmpv-authenticated-reference-investigation.md)
and `curl-enabled=no`. The verification below shows this.

## Verification evidence (2026-10-17, M1 Pro, macOS 27.0.1, Xcode 27.0)

**Clean build.** `tool/macos/build-mpv.sh --clean` completed every stage from
an empty output directory in 486 s wall time, ending with `verify (arm64):
passed`.

**Link closure** (`otool -L` on all 18 dylibs, enforced by the `verify`
stage). Every non-system dependency is `@rpath/<name>` and present in
`dist/arm64/lib`. Every other path is under `/usr/lib` or
`/System/Library`. No load command references `/opt/homebrew`, `/usr/local`,
or the build directory. Every install name is `@rpath/<file>`. The only
`LC_RPATH` entries are `@loader_path` and `/usr/lib/swift` (libmpv only).
Every library has `minos 12.0`.

**License checks:**

- FFmpeg `config.h`: `FFMPEG_LICENSE "LGPL version 2.1 or later"`,
  `CONFIG_GPL 0`, `CONFIG_VERSION3 0`, `CONFIG_NONFREE 0`.
- At runtime, `avutil_license()`, `avcodec_license()`, `avformat_license()`,
  `avfilter_license()`, `swscale_license()`, and `swresample_license()` all
  return `LGPL version 2.1 or later`.
- mpv: `HAVE_GPL 0`. No excluded feature is defined.

**Smoke test** (`tool/macos/runtime-smoke.c`, loading the runtime through
`@rpath`). The `--layer` rows render with the production route C output:
`vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=macvk`, and
`target-colorspace-hint=yes` into an off-screen host `CAMetalLayer` passed
through `--wid`.

| Content | Mode | Result |
| --- | --- | --- |
| HDR10 HEVC 10-bit (synthetic ramp) | `vo=null`, `hwdec=videotoolbox` | `hwdec-current: no`, `gamma: pq`. `vo=null` has no hardware-frame interop, so mpv falls back to software. |
| HDR10 HEVC 10-bit (synthetic ramp) | `--layer`, `hwdec=videotoolbox` | `hwdec-current: videotoolbox`, `hw-pixelformat: p010`, `colormatrix: bt.2020-ncl`, `primaries: bt.2020`, `gamma: pq`, `current-vo: gpu-next`, `current-gpu-context: macvk` |
| HDR10 4K60 HEVC 10-bit | `--layer`, `hwdec=videotoolbox` | `hwdec-current: videotoolbox`, `p010`, `pq` |
| HLG | `--layer`, `hwdec=videotoolbox` | `hwdec-current: videotoolbox`, `p010`, `gamma: hlg` |
| SDR H.264 | `--layer`, `hwdec=videotoolbox` | `hwdec-current: videotoolbox`, `nv12`, `bt.709` / `bt.1886` |
| Dolby Vision profile 5 (Dolby test pattern) | `--layer`, `hwdec=videotoolbox` | `hwdec-current: videotoolbox`, `colormatrix: dolbyvision`, `gamma: pq` |
| Dolby Vision profile 5 | `vo=null`, `hwdec=videotoolbox-copy` | `hwdec-current: videotoolbox-copy`, `colormatrix: dolbyvision` |
| Dolby Vision profile 5 | `vo=null`, `hwdec=no` | `colormatrix: dolbyvision` |
| Public HTTPS MP4, valid certificate | `tls-verify=yes` | Loaded through curl; H.264 decoded |
| Public HLS over HTTPS (master, variants, `.ts` segments) | `tls-verify=yes` | Loaded. All 16 opens in the log go through `[curl]`, with no FFmpeg-native HTTP or TLS. |
| `expired`, `self-signed`, `wrong.host`, and `untrusted-root.badssl.com` | `tls-verify=yes` | All rejected: `curl: error: SSL peer certificate or SSH remote key was not OK`, `TLS certificate verification failed` |
| `expired.badssl.com` (control) | `tls-verify=no` | No TLS error; fails later as `unrecognized file format` (HTML). The rejection above comes from verification. |
| Valid HTTPS MP4 through FFmpeg's own TLS | `tls-verify=yes`, `curl-enabled=no` | Fails closed: `tls: error:0A000086:SSL routines::certificate verify failed` |

These are headless runtime checks. They do not establish visible HDR, EDR, or
Dolby Vision picture quality (S1 covered those through the real app), App
Sandbox or hardened-runtime loading, or behavior on macOS 12–26.

Smoke test usage, after a build (paths in `build/macos-runtime/`):

```sh
tool/macos/build-mpv.sh verify     # builds work/arm64/runtime-smoke
build/macos-runtime/work/arm64/runtime-smoke --layer -o hwdec=videotoolbox \
  -p hwdec-current -p video-params/colormatrix -p video-params/gamma \
  --expect load <media>
build/macos-runtime/work/arm64/runtime-smoke -o tls-verify=yes \
  --expect reject https://self-signed.badssl.com/
```

## How to rebuild

Prerequisites: Xcode with the macOS SDK, plus `meson`, `ninja`, `pkg-config`,
`cmake`, `python3`, and `git` on `PATH`. Homebrew build tools are fine: the
script clears the compiler, linker, and pkg-config search environment, uses
only `build/macos-runtime/prefix/ARCH` through `PKG_CONFIG_LIBDIR`, and
ignores `/opt/homebrew` and `/usr/local` in CMake. The `verify` stage rejects
any dylib that references a path outside the runtime and the OS.

```sh
tool/macos/build-mpv.sh --clean        # from scratch, about 8 minutes on M1 Pro
tool/macos/build-mpv.sh                # incremental: unchanged stages are skipped
tool/macos/build-mpv.sh mpv dist verify  # rebuild selected stages
```

Stages run in dependency order: `fetch`, `moltenvk`, `glslang`, `openssl`,
`curl`, `lcms2`, `dav1d`, `freetype`, `fribidi`, `harfbuzz`, `libass`,
`ffmpeg`, `libplacebo`, `mpv`, `dist`, `verify`. A stage is skipped when its
stamp (the pin entry, flags, SDK, and target) is unchanged. Once a stage
rebuilds, every later stage in that run rebuilds too. The output is
`build/macos-runtime/dist/arm64/`:

- `lib/`: the 18 dylibs
- `include/mpv/`: the client headers
- `licenses/`: one directory per component
- `patches/`: the mpv patch series
- `BUILD-INFO.txt`: the pin-file hash, the source list, the SDK, and each
  dylib's SHA-256

The dylib bytes are not bit-reproducible across machines or checkout paths:
they embed build paths in debug and Swift AST records, and they carry ad-hoc
signatures. The provenance identity is the source pins plus the lock file.
Release signing replaces the ad-hoc signatures.

To change a component, edit its entry in `tool/macos/mpv-runtime.lock`,
rebuild with `--clean`, re-run the verification above, and update this
document in the same commit.

## What the app must ship

- All 18 dylibs from `dist/arm64/lib` in `Contents/Frameworks`. Each must be
  signed with the team identity; the executable needs an
  `@executable_path/../Frameworks` rpath. Provisioning and signing are R1 work.
- In the Licenses screen (§4.8): every text under `dist/arm64/licenses`
  (mpv, FFmpeg, libplacebo, glslang, fast_float, MoltenVK, SPIRV-Cross, cereal,
  Vulkan-Headers, OpenSSL, curl, Little CMS, dav1d, FreeType with the FTL
  credit, FriBidi, HarfBuzz, libass).
- An LGPL notice for mpv, FFmpeg, libplacebo, and FriBidi. It links the exact
  sources above, the mpv patch, `tool/macos/build-mpv.sh`, and the lock file,
  and states that users may replace those libraries and how.
- The published mpv patch,
  `tool/macos/mpv-patches/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch`.
- Before public distribution, mirror the exact source archives and Git
  snapshots to a project-controlled release, as for Windows.

## Distribution notes (for the legal review)

- LGPL-2.1 components (mpv, FFmpeg, libplacebo, FriBidi) are separate dynamic
  libraries. On the App Store a user cannot swap a library inside the signed
  bundle in place, but can re-sign a modified copy and run it locally. This is
  the model other LGPL FFmpeg- and libmpv-based Mac App Store apps use. The
  review should confirm that it satisfies LGPL-2.1 §6 for a paid app.
- glslang's license file includes GPL-3.0 text with the Bison exception (see
  the component table).
- libmpv (LGPL-2.1) links libcurl, which links OpenSSL (Apache-2.0), and FFmpeg
  links OpenSSL directly. Apache-2.0 and LGPL-2.1 compatibility, for
  separately linked libraries, is a review item. Unlike FFmpeg's GPL
  configuration, its LGPL configuration accepts OpenSSL 3 without
  `--enable-version3`.
- FreeType is used under the FTL, not the GPL.

## Remaining work and risks

- **Authenticated-reference parity:** `http-header-fields` and
  `curl-max-redirects=0` use the same mpv source as Windows, but
  `authenticated_reference_test` has not been ported to macOS (plan §4.4).
- **Sandbox and hardened runtime:** not yet tested with a signed, sandboxed
  build (R1). The runtime has no plugins, scripting, or `dlopen`-based code
  loading. The OpenSSL config path does not exist, which matters inside the
  sandbox.
- **macOS 12–26:** all libraries target 12.0, but only macOS 27 was tested.
- **CI:** the plan calls for building in CI; the script is CI-ready, but no
  workflow was added.
- **x86_64 / universal:** not built (plan P3).
- **MoltenVK logging:** MoltenVK writes an `[mvk-info]` banner and
  `[mvk-warn] … primitive restart` lines to stderr. The adapter should set
  `MVK_CONFIG_LOG_LEVEL` (for example to errors only), or the runtime should
  be built with a lower default.
- **Patch upkeep:** the embedding patch applies to `3186d369f` only, and each
  mpv bump needs it rebased.

## Source and license locations

- mpv: <https://github.com/mpv-player/mpv/tree/3186d369f9f090cd1363be0ac46a037824b702c6>
- FFmpeg 9.0.2: <https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz>
- libplacebo: <https://code.videolan.org/videolan/libplacebo/-/tree/cee9b076f2c63104ccfd497fa79c39a867293ec4>
- glslang 16.6.0: <https://github.com/KhronosGroup/glslang/tree/16.6.0>
- MoltenVK 1.4.2: <https://github.com/KhronosGroup/MoltenVK/tree/db66022459ffb663aa2b50f6b018bc2e124f5edf>
- curl 8.23.0: <https://curl.se/download/curl-8.23.0.tar.bz2>; Apple SecTrust: <https://curl.se/docs/sslcerts.html>, <https://curl.se/docs/install.html>
- OpenSSL 3.5.9: <https://github.com/openssl/openssl/releases/tag/openssl-3.5.9>
- dav1d 1.5.4: <https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/>
- libass 0.17.5: <https://github.com/libass/libass/releases/tag/0.17.5>
- FreeType 2.15.0: <https://download.savannah.gnu.org/releases/freetype/>
- HarfBuzz 14.6.0: <https://github.com/harfbuzz/harfbuzz/releases/tag/14.6.0>
- FriBidi 1.0.17: <https://github.com/fribidi/fribidi/releases/tag/v1.0.17>
- Little CMS 2.19.1: <https://github.com/mm2/Little-CMS/releases/tag/lcms2.19.1>
