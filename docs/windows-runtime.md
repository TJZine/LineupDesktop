# Windows runtime provenance

Lineup Desktop uses a pinned x86-64 libmpv build for Windows. The application
links to libmpv dynamically, and users may replace `libmpv-2.dll` with a
compatible modified build. The repository does not commit third-party
binaries; `tool/windows/prepare-mpv.ps1` downloads and verifies them.

## Media runtime

| Component | Exact source/build | License and distribution decision |
| --- | --- | --- |
| libmpv | mpv `v0.41.0-1092-g3186d369f`, full commit `3186d369f9f090cd1363be0ac46a037824b702c6`; configured with `-Dgpl=false`; DLL SHA-256 `4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51` | LGPL-2.1-or-later; selected for dynamic bundling with license, source/build links, and replacement permitted. |
| FFmpeg | `N-127094-gf68e1afc1`, full commit `f68e1afc1b7cf4275d09f1a9026ff80228cf99a8`; companion LGPL x86-64 FFmpeg executable reports LGPL version 3 or later | LGPLv3; statically combined into the replaceable libmpv DLL. Package the LGPLv3 and GPLv3 texts plus the exact source/build recipe. |
| libplacebo | Embedded build version `7.374.0` (`v7.360.0-149-g92b5ac6-dirty`); base source commit `92b5ac6db79f4d680eb656692f7bf51e9606f42a` | LGPL-2.1-or-later; statically combined into the replaceable libmpv DLL. Package its license and exact source/build link. |
| Windows build | zhongfly/mpv-winbuild commit `88bdc4db67bb476a7606921eb2d68b273440d59b`, successful run `37004200613`, LGPL x86-64 job `110828586306` | Reproducible public build recipe. Its LGPL patch disables x264, x265, Rubber Band, DVD navigation, and other incompatible components while retaining decode, D3D11, gpu-next, hardware decode, HDR/tone mapping, and subtitles. |
| Release asset | `mpv-dev-lgpl-x86_64-20261002-git-3186d369f9.7z` | SHA-256 `322CB0040B97B15F97069F631F665FD63DA331CED92705F757DA13B99380DA5F`; pinned acquisition. |

The verified archive is mirrored in the project-controlled
[`runtime-mpv-20261002-3186d369f9` release](https://github.com/TJZine/LineupDesktop/releases/tag/runtime-mpv-20261002-3186d369f9).
The upstream builder retains releases for only 30 days. After its October 2
release expired, the exact archive was recovered from
[build artifact `11226476657`](https://github.com/zhongfly/mpv-winbuild/actions/runs/37004200613/artifacts/11226476657).
Its archive, header and DLL SHA-256 values match the existing pins;
`tool/windows/prepare-mpv.ps1` downloads the mirror and retains those checks.
Keep the mirror immutable and preserve these exact bytes; do not substitute
a rebuilt archive under the existing provenance identity.

## Static runtime notice inventory

This software is based in part on the work of the Independent JPEG Group.
Portions of this software are copyright © 1996–2026 The FreeType Project
(https://freetype.org). All rights reserved.

The LGPL x86-64 [job 110828586306](https://github.com/zhongfly/mpv-winbuild/actions/runs/37004200613/job/110828586306)
checked out [mpv-winbuild-cmake at `05a60b3cfd04e3e3b89918f4a27f3dde2935dff2`](https://github.com/shinchiro/mpv-winbuild-cmake/tree/05a60b3cfd04e3e3b89918f4a27f3dde2935dff2)
and applied the [LGPL build patch](https://github.com/zhongfly/mpv-winbuild/blob/88bdc4db67bb476a7606921eb2d68b273440d59b/compile-lgpl-libmpv.patch).
The [`64-lgpl_logs` artifact](https://github.com/zhongfly/mpv-winbuild/actions/runs/37004200613/artifacts/11226606392)
contains the mpv and FFmpeg configuration reports and dependency build logs.
The inventory uses those logs, the patched recipe, and version strings and
imports from the pinned PE DLL. FFmpeg was configured static and mpv used
`--prefer-static`. The PE import table identifies Windows libraries and the
external Vulkan loader. The archived logs do not include a final linker map or
a complete source revision manifest. Static archive selection can omit
individual objects, and a build dependency alone does not prove inclusion.

The package carries the four mpv, FFmpeg and libplacebo texts identified above
and the additional source notices below in `licenses/`. A source link points
to the observed commit when available, or to the upstream release matching the
version reported by the build. A reported version alone does not establish
the exact checkout of a floating branch. License descriptions summarize the
listed upstream texts. The package preserves the texts with LF line endings
and verifies each file against `third_party/libmpv/notice-hashes.psd1`. Prepare
libmpv again when this manifest changes.

| Component | Build identity or reported version | Upstream terms | Source for notice | Packaged files |
| --- | --- | --- | --- | --- |
| Brotli | 1.2.0 | MIT | [Upstream source](https://github.com/google/brotli/tree/v1.2.0) | `Brotli-LICENSE` |
| c-ares | 1.34.5 | MIT | [Upstream source](https://github.com/c-ares/c-ares/tree/v1.34.5) | `c-ares-LICENSE.md` |
| dav1d | 1.5.4-30-g7f12cf2 | BSD-2-Clause | [Upstream source](https://code.videolan.org/videolan/dav1d/-/tree/7f12cf2) | `dav1d-COPYING` |
| fontconfig | 2.18.3 | MIT-style | [Upstream source](https://gitlab.freedesktop.org/fontconfig/fontconfig/-/tree/2.18.3) | `fontconfig-COPYING` |
| FreeType | 2.14.3 (aff94e1) | FTL or GPL-2.0-or-later, plus source-specific terms | [Upstream source](https://github.com/freetype/freetype/tree/aff94e1) | `FreeType-FTL.TXT`, `FreeType-GPLv2.TXT`, `FreeType-LICENSE.TXT`, `FreeType-src-bdf-README`, `FreeType-src-pcf-README` |
| FriBidi | 1.0.17 | LGPL-2.1-or-later | [Upstream source](https://github.com/fribidi/fribidi/tree/v1.0.17) | `FriBidi-COPYING` |
| HarfBuzz | 14.5.1 (f20f4c20) | Old MIT and source-specific terms | [Upstream source](https://github.com/harfbuzz/harfbuzz/tree/f20f4c20) | `HarfBuzz-COPYING` |
| Highway | 1.4.0 (741eaa5) | Apache-2.0 or BSD-3-Clause | [Upstream source](https://github.com/google/highway/tree/741eaa5) | `Highway-LICENSE` |
| libaom | 3.15.1-59-ge80624b5 | BSD-2-Clause and patent grant | [Upstream source](https://aomedia.googlesource.com/aom/+/e80624b5) | `libaom-LICENSE`, `libaom-PATENTS` |
| libarchive | 3.9.0 (d294297) | BSD-2-Clause and source-specific terms | [Upstream source](https://github.com/libarchive/libarchive/tree/d294297) | `libarchive-COPYING` |
| libass | 0.17.5-11-gf61db56 | ISC | [Upstream source](https://github.com/libass/libass/tree/f61db567e6593df3470e91594bcd4ad2d0473aff) | `libass-COPYING` |
| libbluray | 1.5.1 | LGPL-2.1-or-later | [Upstream source](https://code.videolan.org/videolan/libbluray/-/tree/1.5.1) | `libbluray-COPYING` |
| libbs2b | 3.1.0 | MIT | [Upstream source](https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz) | `libbs2b-COPYING` |
| libiconv | 1.18 | LGPL-2.1-or-later (library) | [Upstream source](https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.18.tar.gz) | `libiconv-COPYING.LIB.txt` |
| libjpeg-turbo | 3.2.1 | IJG, BSD-3-Clause and Zlib | [Upstream source](https://github.com/libjpeg-turbo/libjpeg-turbo/tree/3.2.1) | `libjpeg-turbo-LICENSE.md`, `libjpeg-turbo-README.ijg` |
| libjxl | 5f92f52 | BSD-3-Clause and patent grant | [Upstream source](https://github.com/libjxl/libjxl/tree/5f92f52) | `libjxl-LICENSE`, `libjxl-PATENTS` |
| libopenmpt | 0.7.12+release.autotools | BSD-3-Clause and BSL-1.0 | [Upstream source](https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-0.7.12+release.autotools.tar.gz) | `libopenmpt-LICENSE`, `libopenmpt-LICENSE.BSL-1.0.txt`, `libopenmpt-LICENSE.BSD-3-Clause.txt` |
| libpsl | 0.23.1 (aa3a80e) | MIT | [Upstream source](https://github.com/rockdaboot/libpsl/tree/aa3a80e18f25caf3916636c8668dcc0fff7c016d) | `libpsl-LICENSE` |
| libsixel | 1.8.7 (af12e5b) | MIT | [Upstream source](https://github.com/saitoha/libsixel/tree/af12e5bc6f3f69ad83479da85ddb371420da9b17) | `libsixel-LICENSE` |
| libssh | 0.12.0 | LGPL-2.1-or-later | [Upstream source](https://gitlab.com/libssh/libssh-mirror/-/tree/libssh-0.12.0) | `libssh-COPYING` |
| libudfread | 1.2.0 | LGPL-2.1-or-later | [Upstream source](https://code.videolan.org/videolan/libudfread/-/tree/1.2.0) | `libudfread-COPYING` |
| libunibreak | 8.0 | Zlib | [Upstream source](https://github.com/adah1972/libunibreak/tree/libunibreak_8_0) | `libunibreak-LICENCE` |
| libvpx | 1.17.0-65-g0a6f769e | BSD-3-Clause and patent grant | [Upstream source](https://chromium.googlesource.com/webm/libvpx/+/0a6f769e) | `libvpx-LICENSE`, `libvpx-PATENTS` |
| libwebp | 91505ed | BSD-3-Clause and patent grant | [Upstream source](https://chromium.googlesource.com/webm/libwebp/+/91505ed) | `libwebp-COPYING`, `libwebp-PATENTS` |
| Little-CMS | 2.19 (9f9b520) | MIT | [Upstream source](https://github.com/mm2/Little-CMS/tree/9f9b520) | `Little-CMS-LICENSE` |
| LLVM | 23.1.2 (03b58ead, compiler and C++ runtimes) | Apache-2.0 WITH LLVM-exception | [Upstream source](https://github.com/llvm/llvm-project/tree/03b58ead1a5d7caae4ab76ec69d66cfa896da372) | `LLVM-llvm-LICENSE.TXT`, `LLVM-compiler-rt-LICENSE.TXT`, `LLVM-libcxx-LICENSE.TXT`, `LLVM-libcxxabi-LICENSE.TXT`, `LLVM-libunwind-LICENSE.TXT` |
| Ogg | 1.3.6 | BSD-3-Clause | [Upstream source](https://github.com/xiph/ogg/tree/v1.3.6) | `Ogg-COPYING` |
| OpenSSL | 4.1.0-dev (d8bf6cdd) | Apache-2.0 | [Upstream source](https://github.com/openssl/openssl/tree/d8bf6cdd4849925c30e4f1911c7acb49cb34b702) | `OpenSSL-LICENSE.txt` |
| Opus | 1.6.1-68-g503d81b | BSD-3-Clause and patent grants | [Upstream source](https://github.com/xiph/opus/tree/503d81b) | `Opus-COPYING` |
| Rust standard library | 420ed2a0 | MIT or Apache-2.0 and third-party notices | [Upstream source](https://github.com/rust-lang/rust/tree/420ed2a0c3d7225b1744266fd884d431b4d8cfe0) | `Rust-standard-library-LICENSE-APACHE`, `Rust-standard-library-LICENSE-MIT`, `Rust-standard-library-COPYRIGHT` |
| SDL | 2.33.0 (4c2d9014) | Zlib | [Upstream source](https://github.com/libsdl-org/SDL/tree/4c2d9014) | `SDL-LICENSE.txt` |
| Shaderc | 2026.5.0 (ba3e587) | Apache-2.0 | [Upstream source](https://github.com/google/shaderc/tree/ba3e587) | `Shaderc-LICENSE` |
| Speex | 1.2.1 | BSD-3-Clause | [Upstream source](https://github.com/xiph/speex/tree/Speex-1.2.1) | `Speex-COPYING` |
| SPIRV-Tools | 4f3a92d | Apache-2.0 | [Upstream source](https://github.com/KhronosGroup/SPIRV-Tools/tree/4f3a92d) | `SPIRV-Tools-LICENSE` |
| subrandr | 1.4.0 | MPL-2.0 | [Upstream source](https://github.com/afishhh/subrandr/tree/v1.4.0) | `subrandr-LICENSE` |
| SVT-AV1 | 4.2.0-174-gd235cfc | BSD-3-Clause-Clear and patent grant | [Upstream source](https://gitlab.com/AOMediaCodec/SVT-AV1/-/tree/d235cfc) | `SVT-AV1-LICENSE.md`, `SVT-AV1-PATENTS.md` |
| uchardet | 0.0.8 | MPL-1.1 or GPL-2.0-or-later or LGPL-2.1-or-later | [Upstream source](https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz) | `uchardet-COPYING` |
| Vorbis | 1.3.7 | BSD-3-Clause | [Upstream source](https://github.com/xiph/vorbis/tree/v1.3.7) | `Vorbis-COPYING` |
| xxHash | 0.8.4 | BSD-2-Clause (library) | [Upstream source](https://github.com/Cyan4973/xxHash/tree/v0.8.4) | `xxHash-LICENSE` |
| XZ | 5.8.2 (3d078b52) | 0BSD (liblzma core) and source-specific terms | [Upstream source](https://github.com/tukaani-project/xz/tree/3d078b52adbff566ccfc51067dfbf742ecf3ef86) | `XZ-COPYING`, `XZ-COPYING.0BSD`, `XZ-COPYING.LGPLv2.1`, `XZ-COPYING.GPLv2`, `XZ-COPYING.GPLv3` |
| zlib-ng | 2.3.90 (8b61b4e, zlib API 1.3.1) | Zlib | [Upstream source](https://github.com/zlib-ng/zlib-ng/tree/8b61b4e) | `zlib-ng-LICENSE.md` |

### Rust libraries identified in the DLL

The DLL records the crate versions below in embedded source paths from
subrandr and the Rust standard library. These records establish a subset of the
Rust closure. The inventory does not infer the rest from a Cargo manifest.

| Component | Build identity or reported version | Upstream terms | Source for notice | Packaged files |
| --- | --- | --- | --- | --- |
| addr2line | 0.27.1 | Apache-2.0 OR MIT | [Crate source](https://crates.io/crates/addr2line/0.27.1) | `addr2line-0.27.1-LICENSE-APACHE`, `addr2line-0.27.1-LICENSE-MIT` |
| gimli | 0.34.0 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/gimli/0.34.0) | `gimli-0.34.0-LICENSE-APACHE`, `gimli-0.34.0-LICENSE-MIT` |
| hashbrown | 0.15.2 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/hashbrown/0.15.2) | `hashbrown-0.15.2-LICENSE-APACHE`, `hashbrown-0.15.2-LICENSE-MIT` |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/hashbrown/0.17.1) | `hashbrown-0.17.1-LICENSE-APACHE`, `hashbrown-0.17.1-LICENSE-MIT` |
| icu_locale | 2.0.0 | Unicode-3.0 | [Crate source](https://crates.io/crates/icu_locale/2.0.0) | `icu_locale-2.0.0-LICENSE` |
| icu_locale_core | 2.0.0 | Unicode-3.0 | [Crate source](https://crates.io/crates/icu_locale_core/2.0.0) | `icu_locale_core-2.0.0-LICENSE` |
| icu_segmenter | 2.0.0 | Unicode-3.0 | [Crate source](https://crates.io/crates/icu_segmenter/2.0.0) | `icu_segmenter-2.0.0-LICENSE` |
| litemap | 0.8.0 | Unicode-3.0 | [Crate source](https://crates.io/crates/litemap/0.8.0) | `litemap-0.8.0-LICENSE` |
| once_cell | 1.21.3 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/once_cell/1.21.3) | `once_cell-1.21.3-LICENSE-APACHE`, `once_cell-1.21.3-LICENSE-MIT` |
| quick-xml | 0.36.2 | MIT | [Crate source](https://crates.io/crates/quick-xml/0.36.2) | `quick-xml-0.36.2-LICENSE-MIT.md` |
| rustc-demangle | 0.1.28 | MIT/Apache-2.0 | [Crate source](https://crates.io/crates/rustc-demangle/0.1.28) | `rustc-demangle-0.1.28-LICENSE-APACHE`, `rustc-demangle-0.1.28-LICENSE-MIT` |
| unicode-bidi | 0.3.18 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/unicode-bidi/0.3.18) | `unicode-bidi-0.3.18-COPYRIGHT`, `unicode-bidi-0.3.18-LICENSE-APACHE`, `unicode-bidi-0.3.18-LICENSE-MIT` |
| windows | 0.61.1 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/windows/0.61.1) | `windows-0.61.1-license-apache-2.0`, `windows-0.61.1-license-mit` |
| windows-core | 0.61.0 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/windows-core/0.61.0) | `windows-core-0.61.0-license-apache-2.0`, `windows-core-0.61.0-license-mit` |
| windows-strings | 0.4.0 | MIT OR Apache-2.0 | [Crate source](https://crates.io/crates/windows-strings/0.4.0) | `windows-strings-0.4.0-license-apache-2.0`, `windows-strings-0.4.0-license-mit` |
| zerotrie | 0.2.2 | Unicode-3.0 | [Crate source](https://crates.io/crates/zerotrie/0.2.2) | `zerotrie-0.2.2-LICENSE` |
| zerovec | 0.11.2 | Unicode-3.0 | [Crate source](https://crates.io/crates/zerovec/0.11.2) | `zerovec-0.11.2-LICENSE` |

### Header and import interfaces

These build inputs have separate roles. The Vulkan import library resolves to
the system loader. The VapourSynth recipe installs headers and pkg-config
metadata for the optional runtime interface. The Windows package carries their
upstream texts below.

| Component | Build identity or reported version | Upstream terms | Source for notice | Packaged files |
| --- | --- | --- | --- | --- |
| VapourSynth | R72 (e462044) | LGPL-2.1-or-later (library) | [Upstream source](https://github.com/vapoursynth/vapoursynth/tree/e46204429041e95a881b61eedddd46c08f9a307c) | `VapourSynth-COPYING.LESSER` |
| Vulkan-Headers | 1.4.365 (c468508) | Apache-2.0 or MIT | [Upstream source](https://github.com/KhronosGroup/Vulkan-Headers/tree/c468508) | `Vulkan-Headers-LICENSE.md`, `Vulkan-Headers-Apache-2.0.txt`, `Vulkan-Headers-MIT.txt` |
| Vulkan-Loader | 1.4.365 (f866657, import library) | Apache-2.0 | [Upstream source](https://github.com/KhronosGroup/Vulkan-Loader/tree/f866657) | `Vulkan-Loader-LICENSE.txt` |

### Unresolved coverage

The following candidates were identified by the pinned recipe, dependency
configuration, or DLL strings. Their exact source or applicable notice could
not be established from the available evidence. Their notices are still open.

| Area | Components and evidence |
| --- | --- |
| FFmpeg and mpv | BZip2 (1.1.0), LAME, libaribcaption, libmodplug, libmysofa, libpng (1.6.60.git), libsoxr, libva (2.25.0.1, API 1.25.0), libvpl/Media SDK (oneVPL API 2.17), libxml2 (2.16.0), LuaJIT (2.1.1789906930), MuJS (1.3.8-23-gad03d60), OpenAL Soft and its fmt dependency (11.2.0), uavs3d (1.2.1798), and zimg (3.0.6) with graphengine. |
| Network and archive | curl (8.23.0-DEV), nghttp2 (1.70.90), nghttp3 (1.18.90), ngtcp2 (1.25.90), Zstandard (1.6.0), and embedded libpsl suffix data. |
| Shaders and bundled headers | SPIRV-Cross (0.68.0, build log suffix `99eae2a`), glslang and SPIRV-Headers used by Shaderc, glad and fast_float used by libplacebo, and the ANGLE, AMF and NVIDIA codec headers. |
| Compiler and other source notices | MinGW-w64 (headers reported as 15.0), remaining Rust crates, fontconfig's libintl fallback, and source-file or embedded data notices beyond the listed upstream texts. |

Flutter's generated notices have a separate dependency graph. Inspection of
[Lineup package artifact 13559480345](https://github.com/TJZine/LineupDesktop/actions/runs/42328608159/artifacts/13559480345)
(source `43382a529b4e4ed196b96cd71721f1b642671a3c`) confirmed the pinned DLL and
the original four libmpv-family files. Its
`data/flutter_assets/NOTICES.Z` (SHA-256
`b5606b982ec4eff917c02c556a87d49a4891cf1737b570415d7bc70eb1ccc439`)
contains package headers for `flutter_secure_storage_windows` and overlapping
engine dependencies such as FreeType, HarfBuzz and zlib. It has no package
header for libass, mpv, FFmpeg or libplacebo. Shared names do not establish
matching versions or coverage of the monolithic DLL.

Independent legal review is recommended before distribution beyond private
alpha. This inventory records engineering evidence and delivery coverage.

## Other native runtime components

| Component | Provenance | Package policy |
| --- | --- | --- |
| Flutter Windows engine | Flutter 3.47.7 framework `abaf9c523780a608bd46686fd5e53740a07077f8`, engine `deb287481e3ce9468f3434937ced4240a70539ca`, plus the repository-owned DirectComposition, desktop AX and native test-fixture patches | BSD-3-Clause and upstream third-party notices. Include Flutter's generated `NOTICES.Z` and `tool/flutter_engine/NOTICE`. |
| flutter_secure_storage_windows | Version 4.2.2 from the locked Dart dependency graph | BSD-3-Clause; its notice is generated into Flutter `NOTICES.Z`. |
| Microsoft Visual C++ runtime | Supported VS2022 17.14 / 14.44 retail x64 VC143 runtime, at least the build toolset version | Microsoft redistributable code. A portable package uses unmodified app-local retail DLLs from `VC/Redist`; never include debug/nonredistributable files. |
| Khronos Vulkan loader | `vulkan-1.dll` supplied by the installed GPU driver or Vulkan Runtime | System prerequisite. The selected libmpv DLL imports the loader even though Lineup selects D3D11. The portable package records this requirement instead of copying a machine-specific display-driver file. |
| Universal C Runtime and Windows SDK | Windows 10/11 system components | Do not bundle for the supported Windows baseline. |

`tool/windows/build-release.ps1` creates the packaging-eligible Windows build.
It accepts only a clean Git source tree, validates the exact patched Flutter
source and selects the freshly provisioned, verified `lineup_ax_release_x64`
engine without an incremental refresh. It writes a schema-2 artifact-bound marker
containing canonical pin/manifest hashes, all three ordered Windows patch identities, engine
provenance/DLL digests and hashes for every build input
copied into the package. `tool/windows/package.ps1` requires that marker,
rechecks it against the clean current commit and pinned metadata, and rejects
stale identities or modified build artifacts before creating output.
`BUILD-INFO.txt` and `BUILD-PROVENANCE.json` preserve that verified identity in
the portable package.

## Windows boundary and CRT checks

The release entrypoint installs `debugPrint` suppression before Flutter binding
or plugin initialization. Framework and unhandled Dart errors emit only fixed
`Lineup: framework_error` / `Lineup: unhandled_error` categories; development
error output and redacted structured diagnostics retain their existing behavior.
This application-level control does not claim to intercept every possible native
or vendor logging API.

Windows browser linking uses the window-owned `lineup/platform` channel. Only
argument-free `openPlexLink` is accepted; native code opens the fixed
`https://plex.tv/link` URL with `ShellExecuteW`, returning true only for a result
greater than 32. The channel detaches before the engine is destroyed. There is
no executable-name/PATH fallback. See Microsoft's
[ShellExecute contract](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shellexecutew).

Packaging reads CMake's recorded x64 compiler path, selects that Visual Studio
installation's `Microsoft.VCRedistVersion.default.txt`, and requires the supported
VS2022 17.14 / 14.44 VC143 servicing family at least as new as the toolset. It
does not choose the highest directory from another installation. A different
compiler/runtime generation requires an explicit support-policy update. Microsoft
requires a [redistributable at least as new as the build tools](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
Each of the three app-local CRT DLLs must have a valid Microsoft Corporation
[Authenticode signature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature):
Windows must report status `Valid`, and the signer certificate's subject and
issuer must each carry exactly one Organization (O) attribute equal to
`Microsoft Corporation`. Trust comes from Windows validation; identity comes from
the X.500 organisation attributes, not the certificate's common name, because
Microsoft signs VC redist DLLs under more than one certificate name (for example
Microsoft Windows Software Compatibility Publisher). Missing, untrusted,
unverifiable or wrong-organisation signatures stop packaging, as do names with
multi-valued relative distinguished names.
The copied bytes are checked against the source SHA-256 and reverified, and
`BUILD-INFO.txt` records toolset/redist selection plus each DLL's version, hash,
signer organisation and signer common name.
Existing source, engine, libmpv, package-content and license checks remain required.

`pwsh -File ./tool/windows/verify-release-policy.ps1` includes portable CRT
selection and rejection fixtures. These use controlled signature objects and do
not establish Windows trust validation. Compile/run `runner_lifecycle_test` on
Windows for the native method's fixed URL, argument rejection, success/failure
boundary and channel retirement, alongside the focused Dart launcher/logging tests.

Before accepting the exact release candidate on disposable Windows targets:

- Capture release stdout/stderr and debugger output with ordinary Windows capture
  facilities. First demonstrate that the capture sees a harmless positive-control
  line through the same output path; an empty capture without that control proves
  nothing. In a disposable instrumented build, inject non-secret canaries before
  binding initialization and in framework/unhandled errors. Confirm raw canaries
  are absent and the two fixed categories are present. Never corrupt real stored
  credentials; remove instrumentation and identify both tested build digests.
- Open the actual browser through onboarding, then exercise a controlled browser
  association failure and confirm the generic error. Place harmless sentinel
  executables named `rundll32.exe` in a disposable working directory/PATH and
  confirm they never execute. Preserve the user's real browser settings.
- Run the exact package on a supported clean host without a separately installed
  VC runtime, checking startup and playback. Record CRT versions/hashes and
  candidate ZIP identity. This is distinct from signature fixtures and compilation.

These physical checks remain pending until their observations are recorded.

## CI-only Vulkan loader

`tool/windows/prepare-ci-vulkan.ps1` stages the official LunarG non-installer
[components ZIP](https://sdk.lunarg.com/sdk/download/1.4.335.0/windows/VulkanRT-X64-1.4.335.0-Components.zip),
version `1.4.335.0`, under a new directory in the Windows job's `RUNNER_TEMP`.
The [official download inventory](https://vulkan.lunarg.com/sdk/files.json)
publishes archive SHA-256
`4F856DA356FFB1C16FBFC792CAE70F6E6873680E6B62BC132B9D7131CBC97FE2`.
The helper extracts only the AMD64 `vulkan-1.dll` (SHA-256
`5C42CA8EA4BC43EE17FFE8FCDAFBA36E377C2AF29722CB09F400C24D9D80FB73`)
and the included MIT/Apache-2.0 license text. The loader exports all Vulkan
functions imported by the pinned libmpv and imports Windows system libraries.

CI adds this directory to its process `PATH` around the required native player
contract CTest and restores `PATH` even on failure. It installs no runtime,
changes no system settings, and copies nothing into the application or package.
This is a CI prerequisite; the system-loader requirement and physical release
acceptance below still apply.

## Vulkan-loader release gate

The selected libmpv DLL imports `vulkan-1.dll` even when Lineup selects D3D11
output. The portable package records this as a system prerequisite and does
not copy a machine-specific display-driver DLL.

The following acceptance evidence is still required before a packaged Windows
release is declared supported:

- [ ] On the supported Windows baseline, the packaged application launches and
      plays the acceptance media with a current GPU driver or Vulkan Runtime
      that supplies `vulkan-1.dll`.
- [ ] In an isolated disposable Windows environment with the loader absent, the
      observed process/startup failure is recorded, including the actionable
      user-facing guidance that is actually possible before process startup.
- [ ] The packaged application is re-tested after restoring the loader; no
      loader DLL is copied from a test machine into the package.

No loader-present or loader-absent runtime result is claimed by this document
until those Windows observations are recorded.

`dartjni.dll` can appear in Flutter's raw Windows build because an Android
transitive package advertises a Windows FFI asset. Lineup does not register or
load it on Windows, and the native asset manifest is empty, so the portable
package excludes it.

## Source and license locations

- mpv source and LGPL text: <https://github.com/mpv-player/mpv/tree/3186d369f9f090cd1363be0ac46a037824b702c6>
- FFmpeg source, LGPLv3 text, and GPLv3 text: <https://github.com/FFmpeg/FFmpeg/tree/f68e1afc1b7cf4275d09f1a9026ff80228cf99a8>
- libplacebo source and LGPL text: <https://github.com/haasn/libplacebo/tree/92b5ac6db79f4d680eb656692f7bf51e9606f42a>
- exact builder and LGPL patch: <https://github.com/zhongfly/mpv-winbuild/tree/88bdc4db67bb476a7606921eb2d68b273440d59b>
- exact successful build: <https://github.com/zhongfly/mpv-winbuild/actions/runs/37004200613>
- Microsoft VC runtime redistribution terms: <https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution>

## Disposable credential backend smoke

The shared [storage smoke entrypoint](../test/persistence/android_credential_smoke.dart)
checks native save/read/restore, exact-profile-key deletion, account/other-profile
isolation, saved state and installation identity across restarts. Use a fresh
Windows VM or disposable Windows user with no Lineup credentials or saved data.
The smoke refuses existing account/state data and clears its synthetic credentials
at the end. Its guard does not make an existing signed-in installation suitable.

With the pinned Flutter and existing Windows build/runtime prerequisites from
[Development](DEVELOPMENT.md), build and run the smoke in that disposable account.
Close its window after observing each expected status so the next launch starts
a new process.

```powershell
flutter build windows --debug --target test/persistence/android_credential_smoke.dart
$smokeCandidate = (Resolve-Path -LiteralPath './build/windows/x64/runner/Debug/lineup_desktop.exe').Path
Get-FileHash -Algorithm SHA256 -LiteralPath $smokeCandidate
Start-Process -FilePath $smokeCandidate -ArgumentList 'write' -Wait
# Observe U1_STORAGE_WRITE_PASS, then close the window.
Start-Process -FilePath $smokeCandidate -ArgumentList 'verify-and-delete' -Wait
# Observe U1_STORAGE_RESTART_EXACT_DELETE_PASS, then close the window.
Start-Process -FilePath $smokeCandidate -ArgumentList 'verify-and-clear' -Wait
# Observe U1_STORAGE_RESTART_UPGRADE_DELETE_PASS, then close the window.
```

Record the source/candidate digest, Windows version, plugin/backend version and
each observed status. `U1_STORAGE_FAIL` is a failed check. Preserve a normal
application build separately and rebuild `lib/main.dart` after the smoke. Dart
method-channel mocks establish payloads and error propagation. Actual backend
save/read/delete/restart acceptance requires this disposable Windows run and the
corresponding [Android smoke](android-runtime.md#storage-and-backup).

## Subtitle presentation

The shared core classifies subtitles against the pinned mpv decoder paths (see
[desktop subtitle protocol](native-player-protocol.md#desktop-subtitle-decoding-and-presentation)).
Flutter draws converted text, including lavf `ssa`; libmpv draws native `ass`
unless the viewer opts into Lineup styling, and always draws bitmap subtitles.
Primary text suppression uses `sub-visibility=no`, with an invisible unstyled
libass style as a backstop. Native ASS retains author styling and positioning.
Size scales engine subtitles; Position affects images only. Large bitmap scales
can extend beyond the frame because mpv does not clamp their geometry.

Portable fake-libmpv tests establish parsing, ordering, bounds, nonfatal property
failures and lifecycle behavior. macOS pinned-runtime suppression captures do
not establish Windows rendering, HDR text brightness or physical playback.
Those remain Windows CI and physical acceptance obligations for the integrated
candidate.
