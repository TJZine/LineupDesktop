# Windows runtime provenance

Lineup Desktop uses a pinned x86-64 libmpv build for Windows. The application
links to libmpv dynamically, and users may replace `libmpv-2.dll` with a
compatible modified build. The repository does not commit third-party
binaries; `tool/windows/prepare-mpv.ps1` downloads and verifies them.

## Media runtime

| Component | Exact source/build | License and distribution decision |
| --- | --- | --- |
| libmpv | mpv `v0.41.0-1044-g14f2d48cb`, full commit `14f2d48cbc7dda61adb4bd181e107a1f3f76e533`; configured with `-Dgpl=false`; DLL SHA-256 `B507529D99A4DFFDEAEC85ECEFF7661A7E3C6CA4EFD09C2014E11A1441B83EAA` | LGPL-2.1-or-later; selected for dynamic bundling with license, source/build links, and replacement permitted. |
| FFmpeg | `N-126523-g884590dd4`, full commit `884590dd4aad5fcc7a91fbbb7af8a5da80b61d96`; successful LGPL x86-64 build reports `License: LGPL version 3 or later` | LGPLv3; statically combined into the replaceable libmpv DLL. Package the LGPLv3 and GPLv3 texts plus the exact source/build recipe. |
| libplacebo | Embedded build version `7.371.0`; full source commit `3330a515d62139259c26239014f286e233bd3a5c` | LGPL-2.1-or-later; statically combined into the replaceable libmpv DLL. Package its license and exact source/build link. |
| Windows build | zhongfly/mpv-winbuild commit `423ffd555dddc9b7fceae22eb303eebc2dc47574`, successful run `34692529514`, LGPL x86-64 job `103550228585` | Reproducible public build recipe. Its LGPL patch disables x264, x265, Rubber Band, DVD navigation, and other incompatible components while retaining decode, D3D11, gpu-next, hardware decode, HDR/tone mapping, and subtitles. |
| Release asset | `mpv-dev-lgpl-x86_64-20260912-git-14f2d48cbc.7z` | SHA-256 `455965297BA3F5906A63CD2B219442685BE45528A1FE806E4B228147881E41CB`; pinned acquisition. |

The release asset is monolithic. Its maintained build recipe includes the
remaining permissive/LGPL codec, subtitle, color, archive, font, crypto, and
platform dependencies. The package notice must link the exact public build run
and corresponding sources and preserve their notices. Independent legal review
is recommended before distribution beyond private alpha because this document
is an engineering inventory, not legal advice.

The verified archive currently remains hosted by the third-party builder.
Before public distribution, mirror those exact bytes in an immutable
project-controlled release, confirm the recorded archive SHA-256 is unchanged,
and update `tool/windows/prepare-mpv.ps1` to use that release. Do not substitute
a rebuilt archive under the existing provenance identity.

## Other native runtime components

| Component | Provenance | Package policy |
| --- | --- | --- |
| Flutter Windows engine | Flutter 3.47.4 framework `9584c6713b324636289d067944a46fd6b49df14b`, engine `06a2e2a110089dff50fe635cffd2a61e1b24fbcd`, plus the repository-owned DirectComposition patch | BSD-3-Clause and upstream third-party notices. Include Flutter's generated `NOTICES.Z` and `tool/flutter_engine/NOTICE`. |
| flutter_secure_storage_windows | Version 4.2.2 from the locked Dart dependency graph | BSD-3-Clause; its notice is generated into Flutter `NOTICES.Z`. |
| Microsoft Visual C++ runtime | Retail x64 VC143 runtime matching the build toolset | Microsoft redistributable code. A portable package uses unmodified app-local retail DLLs from `VC/Redist`; never include debug/nonredistributable files. |
| Khronos Vulkan loader | `vulkan-1.dll` supplied by the installed GPU driver or Vulkan Runtime | System prerequisite. The selected libmpv DLL imports the loader even though Lineup selects D3D11. The portable package records this requirement instead of copying a machine-specific display-driver file. |
| Universal C Runtime and Windows SDK | Windows 10/11 system components | Do not bundle for the supported Windows baseline. |

`tool/windows/build-release.ps1` creates the packaging-eligible Windows build.
It accepts only a clean Git source tree, validates the exact patched Flutter
source, refreshes and selects the configured `host_release` engine, and writes
an artifact-bound marker
containing the source and engine identities plus hashes for every build input
copied into the package. `tool/windows/package.ps1` requires that marker,
rechecks it against the clean current commit and pinned metadata, and rejects
stale identities or modified build artifacts before creating output.
`BUILD-INFO.txt` and `BUILD-PROVENANCE.json` preserve that verified identity in
the portable package.

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

- mpv source and LGPL text: <https://github.com/mpv-player/mpv/tree/14f2d48cbc7dda61adb4bd181e107a1f3f76e533>
- FFmpeg source, LGPLv3 text, and GPLv3 text: <https://github.com/FFmpeg/FFmpeg/tree/884590dd4aad5fcc7a91fbbb7af8a5da80b61d96>
- libplacebo source and LGPL text: <https://github.com/haasn/libplacebo/tree/3330a515d62139259c26239014f286e233bd3a5c>
- exact builder and LGPL patch: <https://github.com/zhongfly/mpv-winbuild/tree/423ffd555dddc9b7fceae22eb303eebc2dc47574>
- exact successful build: <https://github.com/zhongfly/mpv-winbuild/actions/runs/34692529514>
- Microsoft VC runtime redistribution terms: <https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution>
