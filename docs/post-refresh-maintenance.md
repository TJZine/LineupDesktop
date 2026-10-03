# Post-refresh maintenance

> **Current workflow authority:** This record preserves its product scope,
> completed work, and dated evidence. Its model assignments, sequential-task
> rules, and review directives are historical execution policy. New or resumed
> work follows [AGENTS.md](../AGENTS.md), [the project profile](../.agents/project.md),
> and the shared skills. Parallel work is eligible when ownership and resources
> permit it. This notice does not authorize dependency upgrades or other product
> work, change UI approvals, or establish new platform acceptance.

User authorization: improve Windows launch/package usability, repair the current
non-golden CI failure, reduce goldens to a small useful set, and update dependencies
as far as current compatibility evidence supports. Use sequential fresh Luna/xhigh
implementation tasks in the existing checkout; Astra supplies the decisions,
reviews results, verifies and commits. No worktrees or automatic reviewers.

## Work sequence

1. Small Windows development launcher and clear portable-package instructions.
   Reuse the provisioned patched engine and existing release/package scripts.
   Environment defaults may remember local paths; no new configuration framework.
2. Repair the Settings overflow at800x600/text200 reported by CI, preserving the
   locked1080 appearance. Reduce mandatory goldens to representative Guide,
   Player and Settings coverage, preserving meaningful behavior assertions and
   capture tooling. Astra selects exact retained cases before dispatch.
3. Dependency upgrades after Astra's current upstream/version/compatibility
   assessment. Include Dart dependencies/transitives, Flutter/Dart, CI actions and
   native/toolchain pins in the inventory. Prefer latest stable compatible
   versions; don't bypass SDK constraints or integrity/native-engine contracts.
   Explain any retained pin rather than silently omitting it.

## Starting evidence

Base137b0778c774aea162a206d2dfbd4b41ac3bf923. GitHub PR41 latest run34734716604:
Verify Dart803passed/1failed; theme_shell_test accessible theme check reports an
8.7px horizontal overflow at800x600/text200, reproduced locally at8.8px.
Windows application build/tests and release-policy checks passed. Golden failures
are known; the running patched-engine job is outside this CI-failure diagnosis.

The dependency inventory currently reports secure-storage11.0.0 ->11.1.1 plus
three compatible platform updates. Other reported newer transitives are blocked
by existing package/SDK constraints and require explicit assessment.

## Status

The Windows development launcher and portable-package instructions are complete
in commit 8aa4cf0b. The bounded Settings overflow repair is also complete: the
existing accessible-text regression, full theme shell suite and shared
navigation suite pass, with formatting, analysis and diff checks clean. No
golden or dependency changes were made. The contact sheet and these checks are
portable evidence only; no physical Windows build or launch validation is
implied.

The golden reduction is complete in the current checkout: 30 screenshot
assertions and baselines became 5 representative 1920×1080 snapshots; 23 UI
golden cases were removed, 25 obsolete PNGs were deleted, and the two Guide
opacity cases remain as non-baseline aperture checks. The retained baselines
were refreshed and rerun without `--update-goldens` using the pinned Flutter
SDK, `TZ=America/New_York`, and macOS. The final five renders were reviewed in
one contact sheet. That golden-reduction run did not establish full-suite or
physical Windows validation; the dependency-assessment unit is recorded below.

The current golden CI failure was investigated from the macOS run at the exact
checkout. Its three failing screenshot pairs were equal in size and content,
with sparse scattered text/icon-edge differences: 391 pixels (maximum channel
delta 66/255) in OSD, 1,161 pixels (53/255) in Now Playing, and 1,007 pixels
(42/255) in Appearance, each out of 2,073,600 pixels. The evidence supports
cross-macOS rasterization variance between the hosted and local macOS images;
the specific CoreText/Skia mechanism is inferred, not proven. Pinned Flutter
fonts, locale, timezone, test harness, source, and baseline bytes were checked,
and no baseline was regenerated. The first repair attempt used a bounded
comparator that accepted only equal-sized images where both the changed pixel
fraction was at most 0.1% and the maximum RGBA channel delta was at most
70/255. Its three accepted UI pairs proved that threshold could cover the
observed UI variance, but it was not retained after the next CI run exposed
Guide differences above the pixel-fraction ceiling: the rich Guide differed in
4,101 pixels (0.198%) and reference-free Guide in 2,553 pixels (0.123%), both
with maximum channel delta 57/255. The two alpha-aperture checks remained exact
throughout; no baseline was regenerated.

The current policy is therefore explicit: the same five existing 1920×1080
screenshots are optional local visual-review checks under `tool/visual/`, using
Flutter's default exact comparator, and are not run by default `flutter test`
or required CI. Required macOS visual coverage is the exact alpha/aperture
suite at `test/app/guide_opacity_test.dart`; behavior, accessibility, focus,
and input tests remain in normal CI. The CI macOS job runs that required suite
and then builds the macOS application. Use the optional local commands in
`docs/DEVELOPMENT.md` for intentional screenshot review or baseline updates.

## Dependency and SDK assessment

The SDK refresh uses the stable Flutter 3.47.4 tag, verified at framework
revision `9584c6713b324636289d067944a46fd6b49df14b`, engine revision
`06a2e2a110089dff50fe635cffd2a61e1b24fbcd`, and Dart 3.13.3. The tag matches
the stable branch; the upstream delta from 3.47.2 was reviewed in the
[Flutter 3.47.2 to 3.47.4 comparison](https://github.com/flutter/flutter/compare/3.47.2...3.47.4).
The existing DirectComposition patch still applies contextually to the exact
3.47.4 Windows manager source; its logic is unchanged, while its engine marker
and normalized patched-manager hash were refreshed.

`flutter_secure_storage` moves from `^11.0.0` to `^11.1.1`. The resolver also
updated `flutter_secure_storage_darwin` to 0.4.2, `flutter_secure_storage_linux`
to 3.0.3, and `flutter_secure_storage_platform_interface` to 2.1.0. The
[flutter_secure_storage changelog](https://pub.dev/packages/flutter_secure_storage/changelog)
and the [Darwin](https://pub.dev/packages/flutter_secure_storage_darwin/changelog),
[Linux](https://pub.dev/packages/flutter_secure_storage_linux/changelog), and
[platform-interface](https://pub.dev/packages/flutter_secure_storage_platform_interface/changelog)
changelogs were reviewed; no application migration is needed for this additive
upgrade. Other direct dependencies had no compatible
updates. `qr_flutter` remains at 4.1.0 with `qr` 3.0.2 because `qr` 4.x changes
the renderer-facing correction-level and constructor APIs. SDK-owned
`material_color_utilities` 0.13.0 and `test_api` 0.7.12 remain at the versions
selected by Flutter's constraints.

The verified CI action pins remain unchanged: checkout v7.0.1
(`3d3c42e5aac5ba805825da76410c181273ba90b1`), upload-artifact v7.0.1
(`043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`), and flutter-action v2.23.0
(`1a449444c387b1966244ae4d4f8c696479add0b2`). The native runtime and
`depot_tools` assessment is recorded below. Physical Windows patched-engine
rebuild and runtime validation are still required before making native Windows
support claims.

## Native runtime refresh

The pinned runtime now uses the latest same-vendor standard x86-64 LGPL asset
available on 2026-09-12:
`mpv-dev-lgpl-x86_64-20260912-git-14f2d48cbc.7z`. Its downloaded bytes matched
the release SHA-256
`455965297ba3f5906a63cd2b219442685be45528a1fe806e4b228147881e41cb` before
inspection. The exact [successful LGPL x86-64 build](https://github.com/zhongfly/mpv-winbuild/actions/runs/34692529514)
was run `34692529514`, job `103550228585`; the release metadata also records
the [published asset](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-09-12-14f2d48cbc)
and [build logs artifact](https://github.com/zhongfly/mpv-winbuild/actions/runs/34692529514/artifacts/10297832765).

Component identities are taken from the new DLL, build logs, and the separate
FFmpeg build artifact:

- mpv `v0.41.0-1044-g14f2d48cb`, commit
  `14f2d48cbc7dda61adb4bd181e107a1f3f76e533`, DLL SHA-256
  `b507529d99a4dffdeaec85eceff7661a7e3c6ca4efd09c2014e11a1441b83eaa`;
- FFmpeg `N-126523-g884590dd4`, commit
  `884590dd4aad5fcc7a91fbbb7af8a5da80b61d96`;
- libplacebo `7.371.0`, source commit
  `3330a515d62139259c26239014f286e233bd3a5c`.

The mpv configure log reports `gpl=false`; the FFmpeg configure log reports
`License: LGPL version 3 or later`. The four upstream license texts at these
revisions match the checked-in files byte-for-byte, so their existing SHA-256
anchors remain unchanged. The [mpv source comparison](https://github.com/mpv-player/mpv/compare/7e4cb538a3f30d25920ad8e87ba6571540fb729f...14f2d48cbc7dda61adb4bd181e107a1f3f76e533)
contains the Android `hwdec_aimagereader` fixes; no Windows ABI or playback
benefit is claimed from that source delta.

Static PE inspection found the new DLL is still x86-64 PE32+, retains the same
47 imported DLLs and 206 exported symbols as the old bundle. The selected
standard x86-64 distribution and documented Vulkan-loader prerequisite remain
unchanged; this is not physical CPU or runtime compatibility evidence. The changed DLL
is now independently pinned by `prepare-mpv.ps1`, runner CMake, and the package
gate; no old-provenance DLL is mixed with the new asset.

`depot_tools` remains pinned to `13febbee9ece9e03df923f69d540afc63c6db93e`.
The current upstream utility revision
[`36a8df4ad006eaa0572fb446edb8145fe5403592`](https://chromium.googlesource.com/chromium/tools/depot_tools/+/36a8df4ad006eaa0572fb446edb8145fe5403592)
was reviewed and not adopted: it reverts a recent change because
that change broke `gclient sync`. Keeping the existing pinned utility avoids
additional provisioning churn; Flutter 3.47.4 does not require a newer revision.
CMake, MSVC, and Windows SDK versions remain
machine-discovered toolchain minimums rather than vendored dependency pins.

The portable gate covers release-policy parsing, exact source/license hashes,
and the independent archive/DLL pins. The user must prepare the new runtime in
a fresh directory and rebuild the patched debug/release engines and host before
building or packaging. No Windows compile, launch, playback, HDR, Vulkan-loader,
DirectComposition, or physical acceptance result is established by this
macOS-side refresh.

Verification for the preceding SDK/Dart unit used the separate 3.47.4 SDK cache with
`TZ=America/New_York`: tracked Dart formatting and analysis passed, `flutter pub
get` and `flutter pub outdated --json` resolved the recorded lockfile, and the
full macOS suite passed all 811 tests, including the five retained goldens and
two pixel checks. No golden baseline was regenerated.


## 2026-10-03 dependency refresh and security re-check

This is new evidence on `codex/libmpv-reference-security-report`, starting at
`d02ee445dac8ddd0fe2dc084df62fa4130518329`. The preceding completed plan and its
evidence remain historical. The three pre-existing local documentation edits
were preserved and excluded from the refresh commits. Nothing was pushed, no
PR was created, and no release gate was changed.

| Step | Commit | Result |
| --- | --- | --- |
| Constrained Dart upgrade | `9bb4f380c838844ceb83fefc5abab61bf9d18d9d` | Nine hosted packages refreshed; direct secure-storage/XML lower bounds raised |
| Flutter SDK patch bump | `de6b708e7fd7c5a22c2f04ccb28df3f0a59c91c3` | Flutter 3.47.6 / Dart 3.13.5 with refreshed exact engine marker |
| LGPL libmpv runtime bump | `978b5eb2b8cece501ec13224d1ac209d20e97e4c` | Baseline x86-64 LGPL 2026-10-02 dev asset, all integrity consumers refreshed |
| Nested-reference re-check | Accompanying documentation commit | [Dated addendum](libmpv-authenticated-reference-investigation.md#2026-10-03-addendum-refreshed-windows-runtime); no fix or production option change |

### Dart versions and archive hashes

The following are every changed hosted package version and archive SHA-256
in `pubspec.lock`. `pubspec.yaml` now uses `flutter_secure_storage: ^11.2.0`
and `xml: ^7.1.0`, following the previous direct-bound refresh style.

| Package | Version, old -> new | Archive SHA-256, old -> new |
| --- | --- | --- |
| `code_assets` | `2.0.0` -> `2.1.0` | `cfd4f5f575a49c5f10ca856e9846073f1e6c3ee94912377eea5f6cefc5272941` -> `828110d598123b5ea96c00c9f3c72105bf79f8ee36c20a39b26209ade421ec57` |
| `flutter_secure_storage` | `11.1.1` -> `11.2.0` | `d87713a152ee2f255117bdbbf43da1dea1797e0551e499e0334f0c9dcfafddd2` -> `d4e1fb6b2cb524868929e78dc0282fa000554b22060fb53789dc481c9fc95bb8` |
| `flutter_secure_storage_darwin` | `0.4.2` -> `0.4.3` | `d0b136b1e21fd4081170fc394e64197046ce889e8f63f2370a13e41b832cc044` -> `a031ceac9b070e62ef183cd7f7d1a8798ebde402d5049f0fe6eb3a51bd797a21` |
| `flutter_secure_storage_platform_interface` | `2.1.0` -> `2.1.1` | `4bc033841169d07f690d46d89dbc3f5305b6562820822445384c82e0866e2719` -> `64951127f001f546891c86f414972bf49ef2c4c8a4c92c65f5790cc0c9100045` |
| `jni` | `1.0.3` -> `1.1.0` | `f038e58b4dc2c9037f50e233175086337e0b305e356d28211bf55f21c504cbd3` -> `6b9ca0602fef0230e83149afbe3f9f8227e94f2bbe84a1da4f14d699742f402d` |
| `objective_c` | `9.6.0` -> `9.6.2` | `ad56fd53a78ff6b1472fa59ff2a4e8b8ccabafc586fc263a1dfad0b99b5553e3` -> `5c80c2ad6e2c0397de5db38c6d653e69616a3397e13aa7633bf39eb668f2041b` |
| `petitparser` | `7.0.2` -> `7.1.0` | `91bd59303e9f769f108f8df05e371341b15d59e995e6806aefab827b58336675` -> `2f1564aadb14215e478563b5406cb80729d022158c01dc50c96013c2f7eb4790` |
| `vector_math` | `2.4.2` -> `2.4.3` | `f36f9f3be64c6198714492bb455c11056e33e2f85d9a0b676a48301e44fdcf47` -> `92b9910f66ed1057fd4da7b040ae7c74cafacf885bdc81be496928d5049b032d` |
| `xml` | `7.0.1` -> `7.1.0` | `67f0aff7be013d107995e9b75bf4e7f2c3ef2dfdb2c8e68024bba0a7fd5756a4` -> `0fe8cc98946def31cbcbc8734aa4067031e6f65ea3a78a508060bfed2200bfeb` |

The pub.dev advisory API was scanned for all 63 hosted lock packages after the
upgrade. No locked version was affected. The only returned advisory,
[GHSA-4rgh-jx4f-qfcq](https://github.com/advisories/GHSA-4rgh-jx4f-qfcq),
affects `http` before 0.13.3; locked 1.6.0 is outside its range.
`qr_flutter` remains at latest 4.1.0 (published 2023-05-14), requiring
`qr ^3.0.1`, so `qr` remains 3.0.2. Its age is a maintenance flag;
4.0.0 was not forced. `material_color_utilities` 0.13.0 and `test_api` 0.7.12
remain pinned by Flutter. The Dart language lower bound remains `^3.13.0`;
the existing convention does not tie it to the SDK's Dart patch version.

### Flutter identities and engine integrity

All four `flutter-version` jobs in CI now select 3.47.6. Current development,
architecture, runtime, and engine-contract references were updated; historical
audit/evidence references retain their original identities.

| Pin | Old -> new |
| --- | --- |
| Flutter / Dart | `3.47.4` / `3.13.3` -> `3.47.6` / `3.13.5` |
| Framework revision | `9584c6713b324636289d067944a46fd6b49df14b` -> `5fc346839b5d0eef006ed8404392afb4dfae428d` |
| Engine revision and native/patch identity marker | `06a2e2a110089dff50fe635cffd2a61e1b24fbcd` -> `692136cb6582dbfc5af3fb33c2515a069f2f66d0` |
| Owned patch SHA-256 | `3A6AA524780826F250352425BE146C6D2549FCCB11B87F993F250EFD4DBC1DCB` -> `A9D057E127F32E5A82B635F8B53ACFB00C8827D47AA205FDA086A75411E6522F` |
| Patched manager SHA-256, LF normalized | `3F4EEE4CA2D9F07C3FF15F56A4FC28596B18B8AF91FCA5E255A01351E0DEE4DD` -> `3D3AE9116C0F662D55EE323AE1723EEB35123920E8380379207D29EB485B5C7E` |

The 13-commit framework range changes only `task_runner_window.cc` under the
Windows engine directory, including the Win32 TimerThread fix. The unpatched
EGL manager blob remains `64fb765bf546190fa610a9bdff007fc881c3cc7e`, and the
standard gclient blob remains `a05a39e336335389321b8a6d855b13bd3fc7892c`.
Both were recomputed from the exact new checkout. The original patch applies
contextually without a logic change. The revised patch changes only its
version text and engine identity marker; the resulting manager hash and exact
reverse-application check pass. `depot_tools` remains at its existing pin.

### Runtime identities and acquisition integrity

Versions came from the actual DLL properties. Its `mpv-configuration` confirms
`-Dgpl=false`; the companion LGPL FFmpeg executable reports LGPLv3-or-later.
The standard x86-64 variant was selected, never the v3 variant.

| Pin or source identity | Old -> new |
| --- | --- |
| Release tag | `2026-09-12-14f2d48cbc` -> `2026-10-02-3186d369f9` |
| Asset filename | `mpv-dev-lgpl-x86_64-20260912-git-14f2d48cbc.7z` -> `mpv-dev-lgpl-x86_64-20261002-git-3186d369f9.7z` |
| Asset SHA-256 | `455965297BA3F5906A63CD2B219442685BE45528A1FE806E4B228147881E41CB` -> `322CB0040B97B15F97069F631F665FD63DA331CED92705F757DA13B99380DA5F` |
| DLL SHA-256 | `B507529D99A4DFFDEAEC85ECEFF7661A7E3C6CA4EFD09C2014E11A1441B83EAA` -> `4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51` |
| MpvVersion | `mpv-v0.41.0-1044-g14f2d48cb` -> `mpv-v0.41.0-1092-g3186d369f` |
| mpv source | `14f2d48cbc7dda61adb4bd181e107a1f3f76e533` -> `3186d369f9f090cd1363be0ac46a037824b702c6` |
| FfmpegVersion | `N-126523-g884590dd4` -> `N-127094-gf68e1afc1` |
| FFmpeg source | `884590dd4aad5fcc7a91fbbb7af8a5da80b61d96` -> `f68e1afc1b7cf4275d09f1a9026ff80228cf99a8` |
| LibplaceboVersion | `7.371.0` -> `7.374.0` |
| libplacebo base source | `3330a515d62139259c26239014f286e233bd3a5c` -> `92b5ac6db79f4d680eb656692f7bf51e9606f42a` |
| Builder source | `423ffd555dddc9b7fceae22eb303eebc2dc47574` -> `88bdc4db67bb476a7606921eb2d68b273440d59b` |
| Successful public build / LGPL x86-64 job | `34692529514` / `103550228585` -> `37004200613` / `110828586306` |

The acquisition URL now uses the new tag and filename under
[zhongfly's release download endpoint](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-02-3186d369f9).
Archive and extracted DLL hashes were independently computed; the archive also
matches the release asset's published digest. Independent archive/DLL consumers
in preparation, runner CMake, and package policy all use the new hashes.
The header SHA-256 remains
`1ACF99EE77C8C2A6F1D1993BD81BBC8A91D27FB5924E80171670E6139A4BD353`.
The DLL's libplacebo string includes `v7.360.0-149-g92b5ac6-dirty`, so the table
records its base source revision with the builder recipe rather than claiming
an unmodified checkout. Both DLLs expose the same 206 exports and import the
same 47 DLLs, including `vulkan-1.dll`; no loader gate was relaxed.

Every upstream license text was fetched at the exact new component revision
and matched the checked-in file byte for byte. The license set and anchors
remain unchanged:

| License file | Unchanged SHA-256 |
| --- | --- |
| mpv-LICENSE.LGPL | `72B672113D642CBB8EF5DCC76938DB801983C56E50B1400AB930F1A64D6DC8D9` |
| FFmpeg-COPYING.LGPLv3 | `DA7EABB7BAFDF7D3AE5E9F223AA5BDC1EECE45AC569DC21B3B037520B4464768` |
| FFmpeg-COPYING.GPLv3 | `8CEB4B9EE5ADEDDE47B31E975C1D90C73AD27B6B165A1DCD80C7C545EB65B903` |
| libplacebo-LICENSE | `B3AA400ACA6D2BA1F0BD03BD98D03D1FE7489A3BBB26969D72016360AF8A5C9D` |

The full [48-commit mpv range](https://github.com/mpv-player/mpv/compare/14f2d48cbc7dda61adb4bd181e107a1f3f76e533...3186d369f9f090cd1363be0ac46a037824b702c6)
was reviewed for impact: HLS/DASH manifests now pass through mpv's stream;
edition-title lifetime and sliced-stream bounds are repaired; curl continues
capped range replies with validation; stereo metadata and HDR10+ luminance
handling change; channel-layout/remix handling is substantially revised;
gpu-next defers seek queue reset until a new frame; Vulkan entry points are
resolved through the instance; scaler/LUT initialization is repaired. The
remaining changes are encoding symbol names, optional scripts, documentation,
upstream build/release automation, and tests. This review is not physical
playback, HDR, stereo, surround audio, or passthrough compatibility proof.

### Verification and remaining acceptance

All portable commands selected the exact SDK for the relevant bump. The
Windows OS timezone was `Eastern Standard Time`; `TZ=America/New_York` was
also supplied. Existing tests were run; no test or production behavior was
changed to hide a failure.

| Step / tier | Command | Observed result |
| --- | --- | --- |
| Step 1, dependency resolution | `flutter pub upgrade`; `flutter pub get` after lower-bound edit | Nine upgrades; lock resolved |
| Steps 1 and 2, portable formatting | `dart format --output=none --set-exit-if-changed` on `git ls-files '*.dart'` | 80 files; zero changes |
| Steps 1 and 2, portable analysis | `flutter analyze` | No issues; still applicable to Step 3's unchanged Dart graph |
| Steps 1, 2 and 3, portable tests on Windows | `TZ=America/New_York flutter test --reporter expanded` (PowerShell environment form) | Each: 936 passed / 1 failed; original pre-upgrade lock also reproduces the same failure |
| Step 2, SDK diagnostics | `flutter doctor -v` | Exit 0; Windows/Visual Studio/network ready; Flutter checkout/PATH warnings and unavailable Android/Chrome tooling reported |
| Step 2, Windows CI widget subset | `flutter test test/app/ui_parity_test.dart test/guide/guide_view_test.dart test/playback/player_view_test.dart` | 112 passed |
| Steps 2 and 3, release policy | `pwsh -File ./tool/windows/verify-release-policy.ps1` | Passed |
| Steps 2 and 3, Windows CI compile | `flutter build windows` | Passed against each bump's runtime; stock engine compile/link evidence |
| Step 3, runtime preparation | `pwsh -File ./tool/windows/prepare-mpv.ps1 -Destination <fresh directory>` | Passed end to end; MSVC import library and provenance generated |
| Step 3, native encoder build | `cmake --build ./build/windows/x64 --config Release --target track_list_encoder_test` | Passed |
| Step 3, native CTest | `ctest --test-dir ./build/windows/x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30` | 1/1 passed |
| Step 4, exact DLL experiment | Temporary C++/HTTPS harness, six cases plus same-origin controls on each DLL | [Results and limits](libmpv-authenticated-reference-investigation.md#2026-10-03-addendum-refreshed-windows-runtime) |
| Patched engine and release wrapper | Pinned `gclient sync`, GN debug/release, Ninja, `build-release.ps1` | Release engine (7,189 actions), debug engine (6,941 actions), and wrappers at the exact Step 2 and Step 3 commits passed |
| macOS alpha | `flutter test test/app/guide_opacity_test.dart` | Passed on 2026-10-03 within the full macOS suite at `5509a5a3`, Flutter 3.47.6 |
| Physical Windows | App/media/package scenarios below | Not run; no new supported-runtime claim |

The recorded full-suite failure was `channel_air_check_test.dart`, "Air Check hides
ended retained entries and preserves a future inspection": a scroll/tap misses
the intended row and the selection assertion fails. The complete original-lock
suite fails identically (936/1), while the isolated case passes with both
original and upgraded locks. This pre-existing Windows suite interaction was
reported without broadening the dependency scope. The scroll/tap fragility is
resolved by the fix commit `test(air-check): flush scroll layout before tapping`
(locate with `git show ':/flush scroll layout before tapping'`). On 2026-10-03,
the original case, file, and full suite each passed three Windows runs; the
historical 240-pixel-step failure did not reproduce. A 230-pixel-step fixture
deterministically reproduced a tap using stale layout, including at `575ab62c`
before the slimming changes. Pumping the layout after each visibility jump fixes
that case without changing production behavior or assertions. Windows verification
passed five consecutive file runs, seeds 17, 42, and 20261003, and the full portable
suite (937 passed), plus analysis and changed-file formatting. These runs used
Flutter 3.47.6 and the Windows Eastern timezone. On macOS at `5509a5a3`, the
Air Check file passed three consecutive runs and the full portable suite passed
939 tests with `TZ=America/New_York` on both Flutter 3.47.4 and the pinned
3.47.6; `pubspec.lock` was unchanged by `flutter pub get`, and formatting and
analysis were clean.

The new raw Windows build still has an empty native-assets manifest, so
`dartjni.dll` remains excluded under the existing package policy. The two
macOS-only alpha checks are excluded from this Windows suite; they passed in the
939-test macOS run recorded above.

Fresh SDK dependency synchronization initially hit Git's Windows filename-length
limit in an upstream plugin fixture. The checkout was repaired with
`core.longpaths=true`, and `gclient sync --no-history` completed with the same
per-invocation setting. Engine GN configuration and compilation emitted upstream
unused-argument/import-link warnings; successful exit status is recorded rather
than claiming warning-free builds.

The release wrapper requires a clean source tree. A separate local verification
checkout on the same branch was used to preserve the user's local edits without
weakening that gate. The saved local launcher defaults were refreshed from the old provisioned
engine/runtime to the verified new ones. Existing processes retain their
inherited environment until refreshed. No physical acceptance or packaging
support claim follows
from compilation or a build marker.

For the maintainer, run [Windows native acceptance](windows-native-validation.md)
at the exact final commit and DLL: local SDR smoke (visible video, audible
sound, pause/seek, resize/minimize/maximize, OSD stacking/focus, shutdown); Plex
startup/auth, replacement tune, Guide PiP/Player continuity, tracks and subtitle
rendering; the authenticated HTTPS-to-other-HTTPS and HTTPS-to-HTTP redirect
row; fullscreen/layering and multi-monitor/DPI; SDR-1/2, HDR-1, DV-1 where
available, AUDIO-1/2 (including channel placement and decode-to-PCM), SUB-1/2,
OPEN-1, remote/relay when available; portable-package acceptance, including
loader-present/absent/restored behavior and redirect checks from the package.
The nested-reference harness is not acceptance of the app's authenticated
redirect row.

The libmpv bump leaves the tested nested-reference credential outcomes
unchanged: B still receives the header by default and with either single
switch. Disabling references blocks playback; combining the switches removes
the header from both cross-origin and authenticated same-origin segments.
Manifest/request counts change, but the finding is not fixed. Separate options
research and a maintainer decision still precede a fix. Independent review is
specifically recommended for Steps 3 and 4; none was launched automatically.
