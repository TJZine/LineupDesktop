# Post-refresh maintenance

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
(`1a449444c387b1966244ae4d4f8c696479add0b2`). Native mpv/FFmpeg/libplacebo
bundle and depot_tools assessment remains pending; those pins were not changed
in this unit. Physical Windows patched-engine rebuild and runtime validation are
still required before making native Windows support claims.

Verification for this unit used the separate 3.47.4 SDK cache with
`TZ=America/New_York`: tracked Dart formatting and analysis passed, `flutter pub
get` and `flutter pub outdated --json` resolved the recorded lockfile, and the
full macOS suite passed all 811 tests, including the five retained goldens and
two pixel checks. No golden baseline was regenerated.
