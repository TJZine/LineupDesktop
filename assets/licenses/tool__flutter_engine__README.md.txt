# Lineup Flutter engine patches

The Windows composition patch remains the runnable Windows player's required
baseline. The separate opt-in desktop accessibility candidate reconciles
retained Flutter semantics with AXTree and stages rejected commits without
replacing surviving native accessible objects. Stock SDK builds do not contain
that repair. macOS is still a development platform; engine tests and bundle
verification do not establish spoken or physical acceptance.

## Desktop accessibility candidate

`0002-desktop-accessibility.patch` applies to the exact framework revision in
`tool/flutter_version.json` and engine revision in Windows build metadata.
`desktop-accessibility.json` records baseline blobs, patched source hashes and
ordered patch hashes. Windows selects DirectComposition followed by accessibility;
macOS selects accessibility and the separate optional Apple-linker build patch.
`0003-macos-apple-linker.patch` adds a default-off host-linker option because the
pinned LLVM linker cannot parse the inspected Xcode 27 SDK's TAPI architecture.
It leaves the default and iOS linker commands unchanged.
Selecting `--apple-linker` also disables LTO: the inspected Apple linker cannot
consume the pinned LLVM compiler's bitcode. Ordinary compiler optimization is
retained; no performance comparison is claimed. GN arguments record this choice.

Provision an isolated pinned Flutter checkout with the metadata-pinned
depot_tools and `gclient sync --no-history`. Use the pinned
`engine/scripts/standard.gclient`; the verifier permits only boolean dependency
download/use_rbe overrides, with no source pin or custom dependency overrides.
macOS requires full Xcode and its Metal Toolchain (`xcodebuild -downloadComponent
MetalToolchain`; check `xcrun -sdk macosx metal --version`). Keep the stock SDK and
its binary cache separate. Before resolving an app's dependencies in a fresh
isolated SDK, run `/path/to/isolated/flutter/bin/flutter precache --macos` without
local-engine flags. Flutter's SDK package resolver requires cached `sky_engine`
and `flutter_gpu` even when a local engine is selected later. This prepares only
the isolated SDK cache; the wrapper still requires and verifies the explicit
patched engine output. The patch changes no public `dart:ui` API. Canonical
patches, pins and manifest must match their committed Lineup inputs.

From the Lineup repository, with the placeholders replaced by absolute paths:

```sh
python3 tool/flutter_engine/desktop_accessibility.py apply \
  --flutter-root /path/to/isolated/flutter --platform macos
python3 tool/flutter_engine/desktop_accessibility.py build \
  --flutter-root /path/to/isolated/flutter --platform macos \
  --architecture arm64 --mode release --apple-linker --jobs 2 \
  --ninja /path/to/actual/ninja --gclient /path/to/pinned/depot_tools/gclient
dart tool/macos/build_app.dart build --release \
  --accessibility-engine-root=/path/to/isolated/flutter \
  --accessibility-engine=lineup_ax_release_arm64
```

The engine build requires a fresh `out/lineup_ax_<mode>_<architecture>` directory,
selects the app's framework and required host tools explicitly, and binds the
evaluated Git dependency graph, clean dependency checkouts, compiler/linker/Metal
tools, GN/Ninja configuration and consumed artifacts to its provenance. Annotated
Git tag pins are resolved to commits before comparison. Supply an actual Ninja
executable; context-dependent script shims are rejected. Separate native test
targets are `common_cpp_unittests`, `flutter_desktop_darwin_unittests` on macOS,
and `flutter_windows_unittests` on Windows. Run the relevant bridge/delegate tests
in both required runtime modes; configuring tests does not execute them.

The macOS wrapper verifies the selected engine before a clean, committed-source
build. Its verified flow accepts one explicit mode and inline Dart defines, uses
the default `lib/main.dart` entrypoint, and rejects informational/nonbuilding
options. A successful build produces a receipt binding its recipe and the entire
bundle, including compiled Dart and assets. Post-build verification compares
engine executable contents after a fixed ad-hoc sign/remove cycle normalizes
signature allocation on disposable copies only; original artifacts stay intact.
Local receipts describe the wrapper's execution; they are not hostile-local
attestation. Sidecars beside the app contain private build details and stay out
of Git. An actual loaded-engine observation is still required after launch.

Windows engine checks use `--platform windows --architecture x64`, omit
`--apple-linker`, and select `lineup_ax_debug_x64` or `lineup_ax_release_x64`.
The Windows apply wrapper delegates to Python's combined apply command. Launch
and release verify the explicit candidate instead of refreshing it with Ninja;
changed engine inputs require a fresh multi-hour recipe build. Release verifies
before/after Flutter, compares the bundled DLL, and emits schema-2 receipts with
canonical inputs, ordered patches, provenance/DLL digests and application hashes.
Packaging rejects schema 1 and validates the sanitized receipt among hashed data
artifacts without retaining private engine checkout paths or raw provenance.

After building each mode, run the complete Windows suites and attribution gate:

```powershell
python tool/flutter_engine/desktop_accessibility.py windows-tests `
  --flutter-root C:\path\to\flutter --platform windows --architecture x64 --mode debug `
  --ninja C:\path\to\actual\ninja.exe --jobs 2 --results C:\private\fresh-debug-results
```

Repeat for Release with a fresh result directory. This builds/runs both full suites,
checks all twelve named recovery cases, and attributes unrelated failures using
same-mode DC-only baseline output. It restores combined source after attribution
and reverifies the candidate; failures without completed attribution block CI.
Results include XML/logs and a sanitized summary with observed duration and
explicit baseline exclusions. These mechanisms and the separate CI mode jobs
still need executed Windows proof; portable fixtures cannot establish it.

To refresh metadata after a reviewed patch changes, run `finalize --flutter-root
/path/to/pinned/flutter`, inspect the derived hashes, and commit canonical inputs
before verification. `finalize` reads pinned Git blobs and does not modify the SDK.
Rollback selects the preserved previous application/engine pair explicitly;
never overwrite stock caches or relabel an older native observation.

## Windows DirectComposition baseline

Lineup requires Flutter's ANGLE surface to use a premultiplied-alpha
DirectComposition swapchain so native mpv video can remain beneath Flutter in
the same application window. Stock Flutter 3.47.7 does not request that
surface mode.

The owned patch targets only the framework and engine revisions recorded in
[Windows build metadata](../windows/build-metadata.psd1). It sets a process marker
only after the DirectComposition EGL surface succeeds. The native player refuses to
initialize without the exact marker, preventing silent opaque fallback.

[apply.ps1](apply.ps1) invokes the single Python combined apply authority with a
checked process exit. That authority requires committed canonical pins, manifest
and patches, derives exact patched source from pinned Git blobs, and atomically
applies DirectComposition followed by AX. Windows excludes the Apple-linker patch.
Untracked Flutter source is rejected while expected clean gclient dependencies
and build outputs are verified through their separate identities.

Use [Development's provisioning and build commands](../../docs/DEVELOPMENT.md#patched-engine-provisioning)
for prerequisites, gclient setup, combined application and explicit engine selection.
Do not copy artifacts over the stock SDK cache.

See [CI evidence](../../docs/DEVELOPMENT.md#ci-evidence) for routine compile checks
and the conditional patched-engine/package job. Runtime marker and
DirectComposition presentation still require an executed Windows acceptance
check.

See [NOTICE](NOTICE) before redistributing a patched engine binary.

The patch was adapted from the BSD-3-Clause `flutter-plezy` Windows patch at
commit `e721699fd4857afcd5a3414dccc55edc24c6680f`:
https://github.com/edde746/flutter-plezy/tree/e721699fd4857afcd5a3414dccc55edc24c6680f

The unchanged patch logic was contextually checked against Flutter 3.47.7
framework `abaf9c523780a608bd46686fd5e53740a07077f8` and engine
`deb287481e3ce9468f3434937ced4240a70539ca`. The identity marker retains that
engine revision; integrity metadata covers the comment-pruned patch and source.
