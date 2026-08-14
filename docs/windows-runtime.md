# Windows runtime provenance

Lineup Desktop uses a pinned x86-64 libmpv build for Windows. The application
links to libmpv dynamically, and users may replace `libmpv-2.dll` with a
compatible modified build. The repository does not commit third-party
binaries; `tool/windows/prepare-mpv.ps1` downloads and verifies them.

## Media runtime

| Component | Exact source/build | License and distribution decision |
| --- | --- | --- |
| libmpv | mpv `v0.41.0-923-g7b8915bc1`, full commit `7b8915bc1d04c7e1b61184e00c7fbfaab1911e75`; configured with `-Dgpl=false`; DLL SHA-256 `353D527E569F69D822A9D679B28D2E975C6B22A82AB9924D533110E1C21C8508` | LGPL-2.1-or-later; selected for dynamic bundling with license, source/build links, and replacement permitted. |
| FFmpeg | `N-126123-g8b4fad11a`, full commit `8b4fad11acfc958dfde29fb0799d3ca1818bbbf7`; builder removes `--enable-gpl` and GPL dependencies and retains `--enable-version3` | LGPLv3; statically combined into the replaceable libmpv DLL. Package the LGPLv3 text and exact source/build recipe. |
| libplacebo | `v7.371.0` (`v7.360.0-111-g22ee762-dirty`), full commit `22ee762e8e0890fc54068beb670310f0edce7263` | LGPL-2.1-or-later; statically combined into the replaceable libmpv DLL. Package its license and exact source/build link. |
| Windows build | zhongfly/mpv-winbuild commit `a237017af09e72a689882afdf0adf6108c33c0fd`, successful run `31738744791`, LGPL x86-64 job `94576668176` | Reproducible public build recipe. Its LGPL patch disables x264, x265, Rubber Band, DVD navigation, and other incompatible components while retaining decode, D3D11, gpu-next, hardware decode, HDR/tone mapping, and subtitles. |
| Release asset | `mpv-dev-lgpl-x86_64-20260813-git-7b8915bc1d.7z` | SHA-256 `13723530C3A719577A27EA19E0127175CE6A047071F8D988ADC1B0DD400B3D18`; pinned acquisition. |

The release asset is monolithic. Its maintained build recipe includes the
remaining permissive/LGPL codec, subtitle, color, archive, font, crypto, and
platform dependencies. The package notice must link the exact public build run
and corresponding sources and preserve their notices. Independent legal review
is recommended before distribution beyond private alpha because this document
is an engineering inventory, not legal advice.

## Other native runtime components

| Component | Provenance | Package policy |
| --- | --- | --- |
| Flutter Windows engine | Flutter 3.47.0 framework `4cf24164269a5ebf0c16a028a00727d0e77bbb05`, engine `5f77625673248ee5846fbcaf5d3e1a3878386fd7`, plus the repository-owned DirectComposition patch | BSD-3-Clause and upstream third-party notices. Include Flutter's generated `NOTICES.Z` and `tool/flutter_engine/NOTICE`. |
| flutter_secure_storage_windows | Version 4.2.2 from the locked Dart dependency graph | BSD-3-Clause; its notice is generated into Flutter `NOTICES.Z`. |
| Microsoft Visual C++ runtime | Retail x64 VC143 runtime matching the build toolset | Microsoft redistributable code. A portable package uses unmodified app-local retail DLLs from `VC/Redist`; never include debug/nonredistributable files. |
| Khronos Vulkan loader | `vulkan-1.dll` supplied by the installed GPU driver or Vulkan Runtime | System prerequisite. The selected libmpv DLL imports the loader even though Lineup selects D3D11. The portable package records this requirement instead of copying a machine-specific display-driver file. |
| Universal C Runtime and Windows SDK | Windows 10/11 system components | Do not bundle for the supported Windows baseline. |

`dartjni.dll` can appear in Flutter's raw Windows build because an Android
transitive package advertises a Windows FFI asset. Lineup does not register or
load it on Windows, and the native asset manifest is empty, so the portable
package excludes it.

## Source and license locations

- mpv source and LGPL text: <https://github.com/mpv-player/mpv/tree/7b8915bc1d04c7e1b61184e00c7fbfaab1911e75>
- FFmpeg source and LGPLv3 text: <https://github.com/FFmpeg/FFmpeg/tree/8b4fad11acfc958dfde29fb0799d3ca1818bbbf7>
- libplacebo source and LGPL text: <https://github.com/haasn/libplacebo/tree/22ee762e8e0890fc54068beb670310f0edce7263>
- exact builder and LGPL patch: <https://github.com/zhongfly/mpv-winbuild/tree/a237017af09e72a689882afdf0adf6108c33c0fd>
- exact successful build: <https://github.com/zhongfly/mpv-winbuild/actions/runs/31738744791>
- Microsoft VC runtime redistribution terms: <https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution>
