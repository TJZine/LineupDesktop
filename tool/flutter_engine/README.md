# Lineup Windows Flutter engine patch

Lineup requires Flutter's ANGLE surface to use a premultiplied-alpha
DirectComposition swapchain so native mpv video can remain beneath Flutter in
the same application window. Stock Flutter 3.47.4 does not request that
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

The unchanged patch logic was contextually checked against Flutter 3.47.4
framework `9584c6713b324636289d067944a46fd6b49df14b` and engine
`06a2e2a110089dff50fe635cffd2a61e1b24fbcd`; only the identity marker and
metadata were refreshed.
