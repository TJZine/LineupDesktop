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
legal review of the LGPL, patent, trademark, and App Store position is still
required before the first paid submission** (see "Distribution notes" below).

## Media runtime

| Component | Exact source | License and distribution decision |
| --- | --- | --- |
| libmpv (`libmpv.2.dylib`) | mpv `v0.41.0-1092-g3186d369f`, full commit `3186d369f9f090cd1363be0ac46a037824b702c6` (the commit Windows pins), plus `tool/macos/mpv-patches/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch` (SHA-256 `9d070fc30414a80b1a418c6b15dee8071086298e7d6aed3236babf331f964b15`) | LGPL-2.1-or-later; built with `-Dgpl=false`. Ship the patch, the LGPL text, and the source links. |
| FFmpeg (`libavcodec.63`, `libavformat.63`, `libavutil.61`, `libavfilter.12`, `libswscale.10`, `libswresample.7`) | Release 9.0.2, `https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`, SHA-256 `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e` | LGPL-2.1-or-later. Configured without `gpl`, `version3`, or `nonfree`; every `*_license()` reports `LGPL version 2.1 or later`. Contains the IJG-derived DCT files (`jfdctfst.c`, `jfdctint_template.c`, `jrevdct.c`): ship the IJG notice and the credit "This software is based in part on the work of the Independent JPEG Group". FFmpeg 9.0.2 (and master) also has a few files with GPL-2.0+ headers that its LGPL configuration still builds. They are excluded, so no GPL file is compiled; `collect-notices.py` fails the build if one is:<br>• `libavfilter/perlin.c` and `qp_table.c/.h`: the `perlin` video source and the `codecview` debug filter are disabled (neither is used in playback).<br>• `libavcodec/aarch64/ac3dsp_init_aarch64.c` and `ac3dsp_neon.S`: not built, by `tool/macos/ffmpeg-patches/0001-…`. The AC-3 DSP falls back to C, and AC-3/E-AC-3 decode is unchanged.<br>• `libavutil/aarch64/crc.S`: not built, by `tool/macos/ffmpeg-patches/0002-…` with `--disable-arm-crc --disable-pmull --disable-eor3`. libavutil uses C CRC. |
| libplacebo (`libplacebo.360.dylib`) | Tag `v7.360.1`, commit `cee9b076f2c63104ccfd497fa79c39a867293ec4`, with submodules, from `https://code.videolan.org/videolan/libplacebo.git` | LGPL-2.1-or-later. Vulkan, Dolby Vision reshaping (`dovi`), and lcms enabled. It also contains the header-only fast_float (MIT, Apache-2.0, or BSL-1.0) and statically linked glslang (below). |
| glslang (static, inside libplacebo) | Release 16.6.0, `https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz`, SHA-256 `9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2` | BSD-3-Clause, BSD-2-Clause, MIT, and Apache-2.0. Its license file also contains GPL-3.0 text with the Bison exception, for the historical Bison parser skeleton; the exception permits distribution under any terms. **Flagged for the legal review.** |
| MoltenVK (`libMoltenVK.dylib`) | Tag `v1.4.2`, commit `db66022459ffb663aa2b50f6b018bc2e124f5edf`, from `https://github.com/KhronosGroup/MoltenVK.git`. Its `fetchDependencies` revisions are pinned in the lock file and checked: Vulkan-Headers `e3b1eec0…`, SPIRV-Cross `6c09849f…`, SPIRV-Headers `29981f65…`, SPIRV-Tools `0d6fd73c…`, Vulkan-Tools `8c66b352…`, Volk `77689330…`, cereal `a56bad8b…` | Apache-2.0. Compiled into it: SPIRV-Cross (Apache-2.0 or MIT), SPIRV-Tools (Apache-2.0; its disassembler and utilities), the SPIRV-Headers grammar tables (Khronos MIT-style), and cereal (BSD-3-Clause). Vulkan-Tools and Volk are fetched but not linked. libplacebo and mpv link MoltenVK directly; there is no Vulkan loader and no ICD manifest search. |
| Vulkan-Headers | Exact MoltenVK pin above (`e3b1eec08173d6b825cd3ac88c885a63b621504a`); also the `vk.xml` used to generate libplacebo's Vulkan code | Apache-2.0 or MIT; headers only. |
| libcurl (`libcurl.4.dylib`) | Release 8.23.0, `https://curl.se/download/curl-8.23.0.tar.bz2`, SHA-256 `95b22eb32bf6d1fa6e3e9463bdb61cece3efc56d86576a9b3cbd428246a6d854` | curl license (MIT-style). Its `curlx/inet_ntop.c` and `curlx/inet_pton.c` are ISC (Internet Software Consortium), and those notices ship too. HTTP and HTTPS only. See "TLS decision". |
| OpenSSL (`libssl.3`, `libcrypto.3`) | Release 3.5.9 (LTS), `https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz`, SHA-256 `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` | Apache-2.0. Providers built in (`no-module`), no engines, and no DSO loading, so it never loads code at runtime. |
| dav1d (`libdav1d.7.dylib`) | Release 1.5.4, `https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/dav1d-1.5.4.tar.xz`, SHA-256 `686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5` | BSD-2-Clause. AV1 software decode (M1 has no AV1 hardware decoder). |
| libass (`libass.9.dylib`) | Release 0.17.5, `https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz`, SHA-256 `2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc` | ISC. CoreText font provider; no fontconfig. |
| FreeType (`libfreetype.6.dylib`) | Release 2.15.0, `https://download.savannah.gnu.org/releases/freetype/freetype-2.15.0.tar.xz`, SHA-256 `93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5` | Dual FTL or GPL-2.0; **used under the FTL**, which requires a credit in the documentation (the Licenses screen). Its BDF and PCF drivers and `src/base/fthash.c` carry their own MIT-style notices (Computing Research Labs/New Mexico State University, Francesco Zappa Nardelli), and those ship too. The default module set is kept: `fthash.c` is part of FreeType's base library and needs its notice anyway, and dropping the BDF/PCF drivers would need a FreeType source change (`modules.cfg`). |
| HarfBuzz (`libharfbuzz.0.dylib`) | Release 14.6.0, `https://github.com/harfbuzz/harfbuzz/releases/download/14.6.0/harfbuzz-14.6.0.tar.xz`, SHA-256 `d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586` | MIT ("Old MIT"). Shaping library only. Its Universal Shaping Engine tables derive from Microsoft data under `src/ms-use/COPYING` (MIT), which ships too. |
| FriBidi (`libfribidi.0.dylib`) | Release 1.0.17, `https://github.com/fribidi/fribidi/releases/download/v1.0.17/fribidi-1.0.17.tar.xz`, SHA-256 `6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2` | LGPL-2.1-or-later for the library. Only the library is built, not its GPL table-generation tools. |
| Little CMS (`liblcms2.2.dylib`) | Release 2.19.1, `https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz`, SHA-256 `bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8` | MIT. The GPL-3.0 fast-float and threaded plugins are disabled. |

macOS supplies zlib, bzip2, iconv, the Swift runtime (`/usr/lib/swift`),
libc++, and the system frameworks. They are not bundled.

**Independent checksum cross-check.** Homebrew pins the identical upstream
artifact for FFmpeg, glslang, libass, FreeType, HarfBuzz, FriBidi, OpenSSL,
Little CMS, and curl (`.tar.bz2`), and every one of those SHA-256 values
matches. For dav1d, Homebrew pins a different artifact (the GitLab-generated
`.tar.bz2` archive), so it is no cross-check. The lock file's dav1d `.tar.xz`
hash matches the `.sha256` file VideoLAN publishes beside the release. Git
sources (mpv, libplacebo, MoltenVK, and MoltenVK's dependencies) are verified
by full commit after checkout.

### Static-linkage license audit

For each shipped dylib, this table lists the third-party code compiled into it
and the shipped license file that covers it. The evidence is the symbols in the
shipped dylib (`nm`). FFmpeg's libraries are stripped of local symbols, so they
were checked against the unstripped build-tree libraries. The count after each
item is the number of matching symbols.

| Dylib | Code compiled in (symbol evidence) | Shipped license files (`dist/arm64/licenses/…`) |
| --- | --- | --- |
| libmpv | mpv, including its Swift code (1878 `$s5swift` symbols) and `ta` (42) | `mpv/LICENSE.LGPL`, `mpv/Copyright`, and the generated `mpv/NOTICES.txt` for files under other terms (below) |
| libavcodec, libavformat, libavutil, libavfilter, libswscale, libswresample | FFmpeg. libavcodec includes the IJG DCT code (8: `ff_j_rev_dct*`, `ff_fdct_ifast*`, `ff_jpeg_fdct_islow*`). No GPL filters are present: 0 `ff_vf_{hqdn3d,boxblur,delogo,eq,pp7,spp,uspp}` | `ffmpeg/LICENSE.md`, `ffmpeg/COPYING.LGPLv2.1`, `ffmpeg/IJG-NOTICE.txt` (IJG notice plus the required credit) |
| libplacebo | libplacebo; glslang (2144 `glslang::`, 352 `spv::` builder); fast_float (23); the generated Vulkan code from `vk.xml`. No xxhash (0) | `libplacebo/LICENSE`, `glslang/LICENSE.txt`, `fast_float/LICENSE-{MIT,APACHE,BOOST}`, `vulkan-headers/*` |
| libMoltenVK | MoltenVK; SPIRV-Cross (5404 `MVK_spirv_cross::`); SPIRV-Tools (337 `spvtools::`); SPIRV-Headers grammar (57 `spvOpcode*`/operand-table symbols); cereal (80 `cereal::`). No Volk (0) | `moltenvk/LICENSE`, `spirv-cross/*`, `spirv-tools/LICENSE`, `spirv-headers/LICENSE`, `cereal/LICENSE`, `vulkan-headers/*` |
| libcurl | curl; ISC `curlx_inet_ntop`/`curlx_inet_pton` (2) | `curl/COPYING`, `curl/inet_ntop-ISC.txt`, `curl/inet_pton-ISC.txt` |
| libssl, libcrypto | OpenSSL only (Apache-2.0 for the whole tree) | `openssl/LICENSE.txt` |
| libfreetype | FreeType; BDF driver (26 `_bdf_`), PCF driver (33 `_pcf_`), `fthash` (11 `ft_hash_`) | `freetype/LICENSE.TXT`, `freetype/FTL.TXT`, `freetype/BDF-README`, `freetype/PCF-README`, `freetype/fthash-NOTICE.txt` |
| libharfbuzz | HarfBuzz, including the USE shaper tables (114 `use` symbols) | `harfbuzz/COPYING`, `harfbuzz/ms-use-COPYING` |
| libass, libdav1d, libfribidi, liblcms2 | Own code only (exported symbols are all `ass_`, `dav1d_`, `fribidi_`, or `cms`) | `libass/COPYING`, `dav1d/COPYING`, `fribidi/COPYING`, `lcms2/LICENSE` |

That table covers whole third-party libraries. Individual files inside a
component can carry their own terms too, so the per-file notices are generated.

### Generated per-file notices

The `dist` stage runs `tool/macos/collect-notices.py` for every component:

1. It takes the files that actually went into the build: sources and the
   headers they included. These come from ninja's dependency log and build
   graph for meson and CMake, from make dependency files (`*.d`, automake
   `.deps/*.Plo`, and Xcode intermediates), and from archive members for
   MoltenVK's prebuilt SPIRV-Cross and SPIRV-Tools static libraries.
2. It extracts each file's leading license comment.
3. It keeps the headers with permissive terms that require the notice to
   accompany binaries (BSD, MIT, ISC, Apache, zlib, Boost, IJG). For
   permissive components, files carrying the project's own standard header
   are skipped; their license file already covers them.
4. It writes the de-duplicated texts, each with the files that carry it, to
   `licenses/COMPONENT/NOTICES.txt`, next to the curated license files above.

The tool also fails the build if any compiled file has a GPL-only header. The
glslang Bison skeleton, which has the Bison exception, is allowed.

**The notices are generated from the compiled sources. Per-file completeness
remains a legal-review item**: notices placed outside a file's leading
comments, or in generated files, are not detected.

| Component | Compiled files scanned | Files with notice-bearing headers | Distinct notices emitted |
| --- | ---: | ---: | ---: |
| mpv | 413 | 17 | 8 |
| ffmpeg | 3090 | 59 | 49 |
| libplacebo | 130 | 5 | 4 |
| glslang | 102 | 98 | 75 |
| moltenvk (incl. SPIRV-Cross, SPIRV-Tools, cereal) | 425 | 282 | 119 |
| openssl | 1556 | 0 | 0 |
| curl | 460 | 2 | 2 |
| lcms2 | 29 | 0 | 0 |
| dav1d | 127 | 1 | 1 |
| freetype | 416 | 17 | 17 |
| fribidi | 59 | 0 | 0 |
| harfbuzz | 399 | 1 | 1 |
| libass | 58 | 2 | 2 |

"Compiled files" includes the headers each source included, as long as they
are in the component's own tree.

The generated notices include, for example:

- **mpv:** `audio/filter/af_scaletempo2_internals.h`, from Chromium (BSD-3);
  `video/out/filter_kernels.c/.h`, from Glumpy (BSD); `osdep/timer-darwin.c`
  (MIT); and the ISC files `ta/*`, `misc/thread_pool.c`,
  `misc/thread_tools.c`, and `player/client.c`.
- **libplacebo:** `src/filters.c` (Glumpy BSD) and `src/shaders/film_grain_av1.c`.
- **FFmpeg:**
  - audio: `ilbcdec.c` (WebRTC), `speexdec.c` (Xiph), `af_arnndn.c`
    (RNNoise), `af_hdcd.c`, and `dsd.c`;
  - video and JPEG 2000: `vvc/itx_1d.c`, `j2kenc.c`, `jpeg2000htdec.c`, and
    `vf_gblur.c`;
  - formats and utilities: the Ogg demuxers, `libavutil/uuid.c`, and
    `avsscanf.c` (musl);
  - the IJG files.
- **libass:** `ass_strtod.c` (UC Regents/Sun).
- **HarfBuzz:** `hb-ucd.cc` (ucdn).
- **curl:** the ISC `inet_ntop`/`inet_pton`.

No compiled file has a GPL-only header. FFmpeg's GPL-headered files are no
longer built (see the component table).

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
  media-player and Touch Bar integrations, and the CLI player. No shipped
  dylib imports `dlopen`; `verify` enforces this.
- **FFmpeg** uses `--disable-autodetect`. Enabled: VideoToolbox, libdav1d,
  zlib, bzlib, pthreads, OpenSSL, and exactly the protocols `crypto data file
  http httpproxy https tcp tls` (`verify` checks this set). libavdevice, the
  programs, and the RTP/RTSP/SAP/WHIP formats (which would pull in `udp`,
  `rtp`, and `dtls`) are disabled. The built-in decoders include HEVC (Main
  10), H.264, VP9, AV1 (native for hwaccel, libdav1d for software), AAC,
  AC-3/E-AC-3, TrueHD/MLP, DTS, FLAC, Opus, and MP3, plus ASS, SubRip, WebVTT,
  PGS, DVB, and DVD subtitles. The demuxers include Matroska, MOV/MP4,
  MPEG-TS, and HLS. DASH needs libxml2 and is not built.
- **libplacebo** links glslang statically and has no libdovi. FFmpeg parses
  the Dolby Vision RPU and libplacebo applies the reshaping.
- **Deployment target** macOS 12.0 for every library (`LC_BUILD_VERSION minos
  12.0`). No dependency required a newer target. mpv's Swift code is compiled
  with `-target arm64-apple-macos12.0`; Swift overlays newer than macOS 12
  (for example `libswiftSpatial`) are weak-linked by the toolchain.
- **Architectures:** arm64 only (`LINEUP_RUNTIME_ARCHS` in the lock file).
  x86_64 is not ready, and has not been tried:
  - The script selects OpenSSL/FFmpeg targets and autotools `--host` for it,
    but meson builds get the architecture only through `CFLAGS`, with no meson
    cross file.
  - dav1d's and FFmpeg's x86 assembly needs `nasm`, which is not a
    prerequisite yet.
  - MoltenVK is already universal and is thinned per architecture.
  - A universal runtime would build each architecture into its own
    `dist/ARCH` and merge them with `lipo`; that step is not written.

### Path-neutral builds

No shipped file contains a path from the build machine. `verify` fails if any
file under `dist/` contains the output directory, the repository path, or
`/Users/`. How the build achieves this:

- **Neutral prefix.** Every component is configured with the prefix
  `/var/empty/lineup-runtime`, which does not exist (`/var/empty` is empty and
  root-owned). It is installed with `DESTDIR` and relocated into
  `prefix/ARCH`. Compiled-in defaults therefore name only that prefix: OpenSSL's
  `OPENSSLDIR`, `ENGINESDIR`, and `MODULESDIR`, mpv's config directory (unused
  with `config=no`), and FFmpeg's and mpv's recorded configure lines.
- **Compiler wrappers.** The compilers are wrappers (`lineup-cc`,
  `lineup-c++`) that add `-ffile-prefix-map=<output dir>=/lineup-build` and
  supply the include and library search paths through `CPATH` and
  `LIBRARY_PATH`. No path appears in a recorded command line, such as
  OpenSSL's compiler string or `avcodec_configuration()`, which reads
  `--prefix=/var/empty/lineup-runtime … --cc=lineup-cc …`.
- **xcodebuild.** MoltenVK and its dependencies get the same mapping through
  `XCODE_XCCONFIG_FILE`.
- **Swift.** mpv's Swift flags (`-target …`, plus `-Xcc` with the mapping, for
  C code the Swift compiler imports from the bridging header) come from a meson
  native file, so they stay out of libmpv's `Configuration:` line.
- **Strip.** `dist` strips debugging symbol-table entries (`strip -S`), which
  removes Swift's AST path.

**Byte identity across directories.** Two `--clean` builds from different
directories were compared: `build/macos-runtime` in the worktree, and a
scratch directory outside the repository. 16 of the 18 dylibs are
byte-identical, and the licenses and headers are identical.

| Status | Dylibs |
| --- | --- |
| Byte-identical | libMoltenVK, libass, the 6 FFmpeg libraries, libcrypto, libssl, libcurl, libdav1d, libfreetype, libfribidi, liblcms2, libplacebo |
| Different | libharfbuzz, libmpv |

libharfbuzz and libmpv differ from directory to directory but are stable within
one directory: two builds in `build/macos-runtime` gave the same UUID. Their
section sizes, symbols, strings, and instruction sequence (mnemonics) are
identical. What differs is placement: their whole `__TEXT` content is shifted
(16 bytes for libharfbuzz), so addresses, PC-relative offsets, LC_UUID, and
the signature hashes differ. The cause is the link-time rpath that meson adds
for the `prefix/ARCH/lib` dependencies, `-Wl,-rpath,<prefix>/lib`. Its
length depends on the build directory, and it changes the size of the load
commands. `dist` deletes that rpath, but the layout is already fixed. Making
these two identical would need meson to stop adding the build rpath; that
was not pursued.

Signing replaces the ad-hoc signatures in any case. The provenance identity
remains the source pins plus the lock file.

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
  source.
  - curl's configure summary for this build reports `CA native: Apple
    SecTrust`, `CA cert bundle: no`, `CA cert path: no`, and `Protocols: http
    https`.
  - `verify` asserts `USE_APPLE_SECTRUST 1` and the absence of
    `CURL_CA_BUNDLE`, `CURL_CA_PATH`, and `CURL_CA_FALLBACK`.
- OpenSSL (Apache-2.0) was chosen over GnuTLS, which would add LGPL/GPL-dual
  nettle and GMP. Its `OPENSSLDIR` is `/var/empty/lineup-runtime/ssl`, so no
  system or third-party `openssl.cnf` or CA directory is read. `verify` asserts
  `OPENSSL_NO_DSO` and `OPENSSL_NO_ENGINE`.
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
an empty output directory, ending with `verify (arm64): passed`. A second
`--clean` build in a scratch directory also passed (see "Byte identity").

**`verify` invariants**, enforced by the `verify` stage on every build:

- Link closure: every non-system dependency is `@rpath/<name>` and present in
  `dist/arm64/lib`; everything else is under `/usr/lib` or `/System/Library`.
- Each install name is `@rpath/<file>`.
- No library is present under two names. An earlier relocation bug shipped
  `libavutil.61.dylib` and `libavutil.61.1.102.dylib` together. That split
  FFmpeg's log callback, and this check catches it.
- No load command references a machine path. No shipped file contains the
  output directory, the repository path, `$HOME`, `/Users/`, `/private/tmp`,
  or `/var/folders` (or `/private/var/folders`).
- No dylib imports `dlopen`.
- The minimum macOS version is 12.0.
- FFmpeg: `FFMPEG_LICENSE "LGPL version 2.1 or later"`, `CONFIG_GPL`,
  `CONFIG_VERSION3`, and `CONFIG_NONFREE` are 0, and the protocol set is exact.
- mpv: `HAVE_GPL 0`, with no excluded features.
- OpenSSL: `OPENSSL_NO_DSO` and `OPENSSL_NO_ENGINE`.
- curl: SecTrust, and no CA bundle, path, or fallback.
- At runtime, every FFmpeg `*_license()` returns `LGPL version 2.1 or later`,
  and only `dist/arm64/lib` libraries load.
- The shipped libavcodec's recorded configure line (`avcodec_configuration()`)
  contains `--disable-gpl --disable-version3 --disable-nonfree
  --disable-autodetect --disable-protocols` and the exact protocol list. It
  does not enable gpl, version3, or nonfree.
- `collect-notices.py` finds no compiled file with a GPL-only header.

The FFmpeg, mpv, OpenSSL, and curl configuration checks read the build-tree
headers (`config.h`, `config_components.h`, `configuration.h`,
`curl_config.h`) that the shipped binaries were compiled from. The
`avcodec_configuration()` check reads the shipped binary itself.

Each of these checks was shown to fail on a deliberately broken copy of a
build: one run per broken invariant, then a restored run that passes.

**Smoke test** (`tool/macos/runtime-smoke.c`, loading the runtime through
`@rpath`). "Route C" rows use `--layer`, which renders with the production
output into an off-screen host `CAMetalLayer` passed through `--wid`:
`vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=macvk`, and
`target-colorspace-hint=yes`. They use `hwdec=videotoolbox` and assert, with
`-e`, `current-vo=gpu-next`, `current-gpu-context=macvk`, and
`hwdec-current=videotoolbox`, in addition to the row's own assertions. Every
row below passed.

| Content | Asserted (`-e`) and observed |
| --- | --- |
| HDR10 HEVC 10-bit (synthetic), route C | `video-params/colormatrix=bt.2020-ncl`, `gamma=pq`; `hw-pixelformat` p010 |
| HDR10 4K60 HEVC 10-bit (synthetic), route C | `gamma=pq` |
| HLG (synthetic), route C | `gamma=hlg` |
| SDR H.264 (synthetic), route C | `colormatrix=bt.709`, `gamma=bt.1886`; nv12 |
| Dolby Vision profile 5 (Dolby test pattern), route C | `colormatrix=dolbyvision`, `gamma=pq` |
| Dolby Vision profile 8.1 (local UHD Blu-ray-sourced clip), route C | `colormatrix=dolbyvision`, `gamma=pq` |
| PGS subtitles + DTS (same clip, `sid=1`), route C | `current-tracks/sub/codec=hdmv_pgs_subtitle`, `audio/codec=dts`; sub decoder "HDMV Presentation Graphic Stream subtitles" |
| PGS + DTS-HD MA, AVC (local Blu-ray remux, first PGS track), route C | `video/codec=h264`, `sub/codec=hdmv_pgs_subtitle`, `audio/codec=dts`; audio decoder "DCA (DTS Coherent Acoustics)", `s32p`. No subtitle event was due at the seek point, so this row shows track selection, not a decoded PGS frame; the previous row covers decode. |
| AC-3, E-AC-3, FLAC (synthetic MKV; AC-3 runs on FFmpeg's C DSP and FLAC on its C CRC after the GPL-file exclusions) | `audio/codec=ac3`, `eac3`, `flac`, `samplerate=48000`; decoders "ATSC A/52A (AC-3)", "ATSC A/52B (AC-3, E-AC-3)", "FLAC (Free Lossless Audio Codec)" |
| AV1 10-bit + TrueHD + ASS (synthetic MKV made with Homebrew ffmpeg, test media only), `--layer` | `video/codec=av1`, `audio/codec=truehd`, `sub/codec=ass`, `sub-text=<the ASS line>`, `pixelformat=yuv420p10`; decoders "dav1d AV1 decoder by VideoLAN" and "TrueHD" (`s32`) |

**HTTPS checks:**

| Target | Options and expectation | Result |
| --- | --- | --- |
| Public HTTPS MP4, valid certificate | `tls-verify=yes`, load; `-e video-codec=H.264 …` | PASS |
| Public HLS over HTTPS (master, variants, `.ts` segments) | `tls-verify=yes`, load; `-e file-format=hls` | PASS. Every open in the log goes through `[curl]`. |
| `expired`, `self-signed`, `wrong.host`, `untrusted-root.badssl.com` | `tls-verify=yes`, reject | PASS: `SSL peer certificate or SSH remote key was not OK`, `TLS certificate verification failed` |
| `tls-v1-0.badssl.com:1010` (negative control) | `tls-verify=yes`, reject | **FAIL, as intended.** curl reports `SSL connect error`, a protocol failure that is not a certificate rejection. `--expect reject` now matches only certificate-verification errors. |
| `expired.badssl.com` (control) | `tls-verify=no`, reject | FAIL, as intended: no TLS error; the HTML fails as `unrecognized file format`. |
| Valid HTTPS MP4 through FFmpeg's own TLS | `tls-verify=yes`, `curl-enabled=no`, reject | PASS: `ffmpeg: tls: error:0A000086:SSL routines::certificate verify failed` (fails closed) |
| Same, control | `tls-verify=no`, `curl-enabled=no`, load | PASS. Verification alone causes the failure above. |

These are headless runtime checks. They do not establish visible HDR, EDR, or
Dolby Vision picture quality (S1 covered those through the real app), App
Sandbox or hardened-runtime loading, or behavior on macOS 12–26.

Smoke test usage, after a build (paths in `build/macos-runtime/`):

```sh
tool/macos/build-mpv.sh verify     # builds work/arm64/runtime-smoke
build/macos-runtime/work/arm64/runtime-smoke --layer -o hwdec=videotoolbox \
  -e current-vo=gpu-next -e current-gpu-context=macvk \
  -e hwdec-current=videotoolbox -e video-params/colormatrix=dolbyvision \
  -p video-params/gamma --expect load <media>
build/macos-runtime/work/arm64/runtime-smoke -o tls-verify=yes \
  --expect reject https://self-signed.badssl.com/
```

## How to rebuild

Prerequisites: Xcode with the macOS SDK, plus `meson`, `ninja`, `pkg-config`,
`cmake`, `python3`, and `git` on `PATH`. Homebrew build tools are fine: the
script clears the compiler, linker, and pkg-config search environment. It uses
only `build/macos-runtime/prefix/ARCH`, through `PKG_CONFIG_LIBDIR` and the
compiler wrappers, and ignores `/opt/homebrew` and `/usr/local` in CMake. meson
runs with `--wrap-mode=nodownload`.

```sh
tool/macos/build-mpv.sh --clean        # from scratch, about 8–9 minutes on M1 Pro
tool/macos/build-mpv.sh                # incremental: unchanged stages are skipped
tool/macos/build-mpv.sh mpv dist verify  # rebuild selected stages
```

Stages run in dependency order: `fetch`, `moltenvk`, `glslang`, `openssl`,
`curl`, `lcms2`, `dav1d`, `freetype`, `fribidi`, `harfbuzz`, `libass`,
`ffmpeg`, `libplacebo`, `mpv`, `dist`, `verify`.

A stage is skipped when its stamp is unchanged. The stamp covers:

- the pin entry and flags;
- the stage's build function and the shared build helpers;
- the toolchain: clang, swiftc, Xcode, SDK, meson, ninja, cmake, and
  pkg-config versions;
- for MoltenVK, its dependency revisions;
- for mpv, the patches.

Once a stage rebuilds, every later stage in that run rebuilds too. The mpv
checkout's marker records both `MPV_COMMIT` and the patch hash. Bumping the
commit without `--clean` re-fetches and re-patches mpv.

The output is `build/macos-runtime/dist/arm64/`:

- `lib/`: the 18 dylibs
- `include/mpv/`: the client headers
- `licenses/`: one directory per component, with the curated license files,
  the generated `NOTICES.txt`, and `NOTICES-SUMMARY.txt` (the coverage
  numbers)
- `patches/mpv/` and `patches/ffmpeg/`: the patch series
- `BUILD-INFO.txt`: the pin-file hash, the source list with licenses, the SDK,
  and each dylib's SHA-256

To change a component, edit its entry in `tool/macos/mpv-runtime.lock`,
rebuild with `--clean`, re-run the verification above, and update this
document in the same commit.

## What the app must ship

- All 18 dylibs from `dist/arm64/lib` in `Contents/Frameworks`. Each must be
  signed with the team identity; the executable needs an
  `@executable_path/../Frameworks` rpath. The `mpv_runtime.sh embed` build
  phase copies the current set and records its basenames in the private
  `Contents/Resources/.lineup-mpv-runtime-manifest`, removing only previously
  managed files and the current components' old numeric aliases. Signed files
  are staged before publication; `Contents/Resources/.lineup-mpv-runtime-pending`
  records ownership across a partial install so a retry can remove superseded
  names without advancing the completed manifest. A legacy manifest in
  `Contents/Frameworks`
  is validated and migrated to `Contents/Resources` only after safe publication,
  so bookkeeping is not treated as code by app signing. Current-name symlinks
  are replaced without following them, while real directories reject the
  install. It preserves unrelated bundle contents.
  Ad hoc signing uses `--timestamp=none`; a non-ad-hoc identity requests
  Apple's secure `--timestamp`, while `CODE_SIGNING_ALLOWED=NO` skips signing.
  Real identity, sandbox, and package acceptance remain separate release
  checks.
- The embed phase also installs the complete selected runtime's `licenses/`
  and `patches/` trees and `BUILD-INFO.txt` into the dedicated
  `Contents/Resources/LineupNativeRuntime/` subtree. Hierarchy and text bytes
  are preserved, including curated licenses, generated `NOTICES.txt` files,
  and `NOTICES-SUMMARY.txt`; directories are `0755`, files `0644`, and dylibs
  remain only in Frameworks. Missing/empty
  required prepared-runtime resource files fail the build. Source trees and
  destinations reject symlinks/special files; bundle paths cannot traverse or
  redirect through an app-directory symlink. This is packaging validation, not
  a second GPL audit or a legal completeness assessment.
  Resources are copied and compared in a private stage before publication.
  The owned directory is replaced as a whole, removing obsolete notices and
  preserving unrelated Resources/Frameworks. A failed replacement restores the
  previous complete tree; if rollback is unavailable, the reserved backup is
  retained for the next retry. Interrupted stages/backups are recovered or
  removed before completing a later embed. This resource transaction preserves
  the existing dylib ownership/pending-manifest recovery behavior.
  `BUILD-INFO.txt` describes the raw prepared runtime: exact source links,
  lock/patch identities and pre-signing library hashes. Those hashes are
  **not** the post-signing app/package hashes; signing changes dylib bytes.
  A later signed artifact requires its own package identity.
- Settings → Support → Open Licenses provides the approved in-app offline
  index, component/file lists and selectable reader. It consumes the installed
  bundle's resource tree through a confined read-only native adapter, alongside
  Flutter's generated license registry, explicit font OFLs and macOS engine
  notices. Every text under `licenses/` is enumerated, including curated license
  files and each component's generated `NOTICES.txt`:
  - mpv; FFmpeg with the IJG notice; libplacebo; glslang; fast_float;
  - MoltenVK, SPIRV-Cross, SPIRV-Tools, SPIRV-Headers, cereal, and
    Vulkan-Headers;
  - OpenSSL; curl with its ISC notices; Little CMS; dav1d;
  - FreeType with the FTL credit and its BDF/PCF/fthash notices; FriBidi;
    HarfBuzz with ms-use; libass.
- Two credits in the accompanying documentation:
  - "This software is based in part on the work of the Independent JPEG
    Group" (FFmpeg's IJG files, in `ffmpeg/IJG-NOTICE.txt`).
  - The FreeType Project credit required by the FTL.
- Sources and rebuilding in the Licenses reader includes the
  [credits and modified-copy rebuilding notice](licenses-and-rebuilding.md),
  exact source inventory, build/helper/lock texts and macOS engine patch inputs.
  The native tree supplies the selected runtime's build information and patches.
  Final-candidate resource/source comparisons and matching companion assembly
  remain required; the UI and raw resources do not close R-03 by themselves.
- The patches are bundled as raw resources above; public source/patch release
  obligations remain separate:
  - `tool/macos/mpv-patches/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch`
  - `tool/macos/ffmpeg-patches/0001-aarch64-do-not-build-GPL-licensed-AC-3-DSP-code.patch`
  - `tool/macos/ffmpeg-patches/0002-aarch64-do-not-build-GPL-licensed-CRC-assembly.patch`
- Before public distribution, mirror the exact source archives and Git
  snapshots to a project-controlled release, as for Windows.

### Offline source-companion preparation

[Source-material tooling](../tool/macos/source_materials.py) uses local verified
archives and Git snapshots; it never fetches, builds or signs. Its small committed
`assets/licenses/` snapshot contains exact source pins (including resolved nested
runtime dependencies), recipe/helper texts and the macOS engine patches. Regenerate
it after changing an included input, with the pinned SDK and prepared runtime
sources available:

```sh
python3 tool/macos/source_materials.py assets --flutter-sdk "$FLUTTER_ROOT"
python3 tool/macos/source_materials.py assets --flutter-sdk "$FLUTTER_ROOT" --check
python3 tool/macos/source_materials_test.py
```

The controller prepares the large source companion **after** the final clean-tree
candidate and repaired-engine identity settle. `prepare` requires an explicit
capacity budget and a new output directory. It re-verifies the selected engine,
requires both the successful-build receipt and the completed
`.engine-provenance.json` envelope from the wrapper's final embedded-engine
comparison. It binds the selected engine, build-receipt digest, current app
artifact map, app identity and actual raw/embedded engine hashes without repeating
signing normalization. It validates every ZIP entry's path/root/type (including
directories), compares its entire file/symlink set, modes and bytes to the app,
and compares all installed runtime notice/patch bytes and build information to
the selected runtime. The ZIP must contain only the app with its root name and preserve UNIX
modes/symlinks (for example, use `zip -r -y` from its parent); receipts stay beside
the unpacked app. Source archives, Lineup/Flutter baseline Git snapshots, evaluated
Flutter Git dependencies, runtime Git/submodule snapshots, patches and helper
closure are delivered together. Sources remain unmodified; patches are provided
separately for rebuilding the selected source. DEPS retains build-tool/CIPD inputs;
this is not an offline mirror of SDKs or proprietary build tools.

```sh
python3 tool/macos/source_materials.py prepare \
  --runtime-root build/macos-runtime \
  --flutter-root "$LINEUP_ENGINE_ROOT" --engine-output "$LINEUP_ENGINE_OUTPUT" \
  --app "$LINEUP_CANDIDATE_APP" --candidate "$LINEUP_CANDIDATE_ZIP" \
  --output "$LINEUP_SOURCE_OUTPUT" --max-gib 24
python3 tool/macos/source_materials.py verify --output "$LINEUP_SOURCE_OUTPUT"
```

Choose the capacity budget deliberately; this example is not a measured space
requirement. The output's `manifest.json` records hashes for the candidate, both
build sidecars, runtime, engine and every source/recipe without exporting local
paths. Verification checks every filesystem entry with non-following metadata;
symlinks and special files are rejected, while real empty directories are allowed.
The output is a companion directory of separately hashed source archives, not a single archive
and not an automatically published release. Missing inputs, mismatches or an
insufficient budget fail without publishing a partial output. Actual preparation
against the final candidate and delivery remain controller-owned gates. This
tooling does not replace independent legal review or authorize sending builds.

## Distribution notes (for the legal review)

This is an engineering list of review items, not legal advice.

- **LGPL relinking.** LGPL-2.1 components (mpv, FFmpeg, libplacebo, FriBidi)
  are separate dynamic libraries. On the App Store a user cannot swap a
  library inside the signed bundle in place, but can re-sign a modified copy
  and run it locally. This is the model other LGPL FFmpeg- and libmpv-based
  Mac App Store apps use. The review should confirm that it satisfies
  LGPL-2.1 §6 for a paid app.
- **glslang.** Its license file includes GPL-3.0 text with the Bison exception
  (see the component table).
- **OpenSSL with LGPL code.** libmpv links libcurl, which links OpenSSL
  (Apache-2.0), and FFmpeg links OpenSSL directly. FFmpeg's `LICENSE.md`
  states that, to the best of its developers' knowledge, OpenSSL is compatible
  with the LGPL (though not with the GPL). Its LGPL configuration accepts
  OpenSSL 3 without `--enable-version3`. mpv is LGPL-2.1-or-later. Confirm.
- **FreeType** is used under the FTL, not the GPL.
- **Patents and trademarks.** A paid app shipping software decoders for HEVC,
  AC-3/E-AC-3, TrueHD, and DTS (and AAC, H.264, and AV1), and applying Dolby
  Vision reshaping, may raise codec patent-pool and Dolby/DTS licensing or
  trademark questions. They are separate from copyright licensing:
  - VideoToolbox handles HEVC and H.264 hardware decode, but FFmpeg's software
    decoders are also present and are the fallback.
  - The app should not use "Dolby Vision", "Dolby Audio", or "DTS" marks
    without a license.

### Signed-sandbox checks still pending (R1)

- SecTrust verification (`trustd`) works from inside the App Sandbox with the
  `network.client` entitlement.
- No sandbox denials for the compiled-in paths: the OpenSSL config,
  engines, and modules directories under `/var/empty/lineup-runtime`, and
  mpv's config directory. They are never meant to exist, and access to them
  should fail quietly.
- MoltenVK writes no files (for example a pipeline cache) outside the
  container.
- The runtime loads under the hardened runtime with library validation, signed
  with the team identity.

## Remaining work and risks

- **Authenticated references:** the standalone production-adapter checker is
  integrated; its [26-case headless proof](DEVELOPMENT.md#macos-authenticated-reference-proof)
  covers the selected real runtime with synthetic loopback TLS/HTTP and token
  audit. This does not establish signed-sandbox, physical or real-Plex behavior.
- **Sandbox and hardened runtime:** see the pending checks above.
- **Older macOS support:** all libraries target 12.0. Current candidate `8c98fb80`
  passed default playback on macOS 27.0.1. Approved macOS 12.6 and 13.0 VMs passed
  cold native notices, PMS scans and saved-session checks, but default playback
  aborted in guest Metal/MoltenVK initialization and intermittent glyph corruption
  remained. A process-only Metal-argument-buffer diagnostic reached video on 13.0;
  it does not establish default support or physical-hardware failure. The tested
  support commitment remains unresolved in [V-06](open-obligations.md).
- **Hosted CI acceptance:** `.github/workflows/ci.yml` now provisions/builds
  the pinned runtime and requires portable/native, embed/signing and
  authenticated-reference checks. The separate core-contract job is also
  integrated. Later attributed hosted macOS native/runtime/auth passes are
  recorded in [the final L2 handoff](handoffs/macos-l2-controller-status-handoff.md#final-controller-addendum--october-18-2026).
  They do not establish a new hosted run for the October 20 opt-in repaired engine
  or signed-distribution acceptance. See [current gaps](open-obligations.md).
- **x86_64 / universal:** not built (plan P3); see "Architectures" for what is
  missing.
- **Byte identity:** libharfbuzz and libmpv still differ between build
  directories (see "Path-neutral builds").
- **Patch upkeep:** the embedding patch applies to `3186d369f` only, and each
  mpv bump needs it rebased.

## Source and license locations

- mpv: <https://github.com/mpv-player/mpv/tree/3186d369f9f090cd1363be0ac46a037824b702c6>
- FFmpeg 9.0.2: <https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz>
- libplacebo: <https://code.videolan.org/videolan/libplacebo/-/tree/cee9b076f2c63104ccfd497fa79c39a867293ec4>
- glslang 16.6.0: <https://github.com/KhronosGroup/glslang/tree/16.6.0>
- MoltenVK 1.4.2: <https://github.com/KhronosGroup/MoltenVK/tree/db66022459ffb663aa2b50f6b018bc2e124f5edf>
- SPIRV-Tools (MoltenVK pin): <https://github.com/KhronosGroup/SPIRV-Tools/tree/0d6fd73ca73830ccab5fa1f00ed5ed40124e2c55>
- SPIRV-Headers (MoltenVK pin): <https://github.com/KhronosGroup/SPIRV-Headers/tree/29981f65241605e08b0ede4cfeb999fe3b723c6a>
- SPIRV-Cross (MoltenVK pin): <https://github.com/KhronosGroup/SPIRV-Cross/tree/6c09849fe88c48eaed08413aa022aaa136a3a057>
- cereal (MoltenVK pin): <https://github.com/USCiLab/cereal/tree/a56bad8bbb770ee266e930c95d37fff2a5be7fea>
- curl 8.23.0: <https://curl.se/download/curl-8.23.0.tar.bz2>; Apple SecTrust: <https://curl.se/docs/sslcerts.html>, <https://curl.se/docs/install.html>
- OpenSSL 3.5.9: <https://github.com/openssl/openssl/releases/tag/openssl-3.5.9>
- dav1d 1.5.4: <https://downloads.videolan.org/pub/videolan/dav1d/1.5.4/>
- libass 0.17.5: <https://github.com/libass/libass/releases/tag/0.17.5>
- FreeType 2.15.0: <https://download.savannah.gnu.org/releases/freetype/>
- HarfBuzz 14.6.0: <https://github.com/harfbuzz/harfbuzz/releases/tag/14.6.0>
- FriBidi 1.0.17: <https://github.com/fribidi/fribidi/releases/tag/v1.0.17>
- Little CMS 2.19.1: <https://github.com/mm2/Little-CMS/releases/tag/lcms2.19.1>
