# C. macOS bundled source materials

Branch `followup/macos-bundled-sources` starts at `76419674e`. The tested source commit is `96ce8a41c14d0ea9a5bd5188e35d388b183d3ca9`. [PR #98](https://github.com/TJZine/LineupDesktop/pull/98)

FU5 and FU6
cover the source documents accessible from the macOS Licenses screen.

## FU5. Read the release app

`verify-app` validates the checkout's manifest against the canonical generated
inventory, then compares SHA-256 for that manifest and each distinct document
in the app's Flutter assets against its repository file. The inventory has
33 titles and 32 distinct document paths. The macOS build job runs the check
immediately after building the release app.

The local release build ran with the candidate sources in a worktree at `76419674e` and used pinned Flutter 3.47.7 for arm64 with
`FLUTTER_MACOS_ARM64_ONLY=true`. The prepared runtime matched the lock SHA-256
`7df202602cc5a0276a7ac8762b0b4289e33e2db4a01d8adc352ca438ab9e842c`.

```sh
python3 tool/macos/source_materials.py verify-app \
  "build/macos/Build/Products/Release/Lineup Desktop.app"
```

This command passed on the built app. Flipping byte zero of the bundled
`tool/macos/native_assets.py` made it exit 1 with
`Bundled source bytes differ from the repository: tool/macos/native_assets.py`.
Restoring the original bytes made the same command pass.

The portable fixture additionally exercised a missing member, a manifest that
omits a member, a manifest differing only by a newline, and a checkout and
package carrying the same incomplete manifest. The CLI named the affected
path for the missing member and the byte changes.

## FU6. Check the build inputs independently

The `verify` job now runs `python3 tool/macos/source_materials_test.py`.
Its closure check reads both build recipes. The Dart wrapper invokes
`desktop_accessibility.py` and `native_assets.py` and reads `pubspec.yaml`.
The runtime shell script sources its lock, invokes `collect-notices.py`, and
compiles `runtime-smoke.c` and `runtime-smoke-layer.m`. The check compares
the direct repository inputs and both recipes against `HELPERS`.

In disposable copies of `76419674e`, removing `tool/macos/native_assets.py`
and, separately, `tool/macos/collect-notices.py` from `HELPERS` allowed the
old `assets` and `assets --check` commands to pass after regeneration. The new
check exited 1 in each case, named the missing path, and said
`add it to HELPERS in tool/macos/source_materials.py`. Restoring the original
list passed the same check.

```sh
python3 tool/macos/source_materials_test.py SourceMaterialsTests.test_macos_build_recipe_inputs_are_bundled
python3 tool/macos/source_materials_test.py
python3 tool/macos/source_materials.py assets --flutter-sdk "$FLUTTER_ROOT" --check
python3 tool/macos/collect_notices_test.py
```

All ten source-material tests and seven collector tests passed locally.
The checked-in inventory and Flutter asset declarations passed the generator
check.

## Updated review base

After A merged, C was rebased onto `4706b8205d03081eb7dbb703e8fa941b2a3053a8`. The rebased implementation commit is `cc84bd811aed0ac9f4dddf643734cbbdb325e2f6`. Its tree matches a clean integration of the original C implementation with the new main.

## Hosted verification

At source head `96ce8a41c14d0ea9a5bd5188e35d388b183d3ca9`, Verify Dart ran the source inventory and package-verifier tests and passed. The hosted macOS job built the arm64 release app, ran `verify-app` on that artifact, and passed. [Generator and verifier tests](https://github.com/TJZine/LineupDesktop/actions/runs/45481874144/job/138756867465) · [Packaged app byte check](https://github.com/TJZine/LineupDesktop/actions/runs/45481874144/job/138756868083)
