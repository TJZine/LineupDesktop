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
its binary cache separate. Canonical patches, pins and manifest must match their
committed Lineup inputs.

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

Windows engine checks use `--platform windows --architecture x64` and omit
`--apple-linker`. The existing Windows launcher/release/package checks retain
their DirectComposition-only source contract and reject an additional AX patch;
this candidate tooling does not claim repaired Windows app/package integration.
Windows engine execution and affected runtime acceptance require a Windows host.

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

[apply.ps1](apply.ps1) requires committed metadata and patch inputs, verifies the
patch's SHA-256, rejects staged or unstaged tracked changes in the Flutter checkout,
and verifies the framework revision, pinned engine artifact revision, and exact
committed Windows EGL manager blob before a normal, contextual `git apply
--check`. Expected untracked gclient dependencies and build outputs are not
treated as source modifications.

Use [Development's provisioning and build commands](../../docs/DEVELOPMENT.md#patched-engine-provisioning)
for prerequisites, gclient setup, patch application, and local-engine selection.
The release wrapper refreshes `host_release` and binds source/engine identities
to the resulting artifacts. Do not copy artifacts over the stock SDK cache.

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
