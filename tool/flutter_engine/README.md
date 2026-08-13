# Lineup Windows Flutter engine patch

Lineup requires Flutter's ANGLE surface to use a premultiplied-alpha
DirectComposition swapchain so native mpv video can remain beneath Flutter in
the same application window. Stock Flutter 3.47.0 does not request that
surface mode.

The owned patch targets only Flutter `3.47.0`, framework revision
`4cf24164269a5ebf0c16a028a00727d0e77bbb05`, and engine revision
`5f77625673248ee5846fbcaf5d3e1a3878386fd7`. It also sets a process marker only
after the DirectComposition EGL surface succeeds. The native player refuses to
initialize without the exact marker, preventing silent opaque fallback.

Apply from the root of an exact Flutter checkout:

```powershell
C:\path\to\LineupDesktop\tool\flutter_engine\apply.ps1 -FlutterRoot C:\path\to\flutter
```

The script verifies the framework revision, pinned engine artifact revision,
and exact committed Windows EGL manager blob before a normal, contextual `git
apply --check`. The exact hashes and surrounding source context reject
unsupported sources.

Fetch and build the engine using Flutter's official engine setup instructions.
On Windows this requires Visual Studio C++ with ATL, the engine-pinned Windows
SDK 10.0.22621.0, and Debugging Tools for Windows. Before the first
`gclient sync`, copy the pinned checkout's `engine/scripts/standard.gclient` to
`.gclient` at the checkout root. Use the resulting
`host_debug` build for `flutter run` and `host_release` for release builds,
always passing `--local-engine`, the matching `--local-engine-host`, and
`--local-engine-src-path`. Do not copy artifacts over the stock SDK cache.

CI proves the patch applies to the exact framework and engine source revisions,
builds `host_release`, and compiles the Windows application against that local
engine. Runtime marker and DirectComposition presentation still require an
executed Windows acceptance check.

See `docs/DEVELOPMENT.md` for the exact Windows commands and required local
libmpv layout. See `NOTICE` before redistributing a patched engine binary.

The patch was adapted from the BSD-3-Clause `flutter-plezy` Windows patch at
commit `e721699fd4857afcd5a3414dccc55edc24c6680f`:
https://github.com/edde746/flutter-plezy/tree/e721699fd4857afcd5a3414dccc55edc24c6680f
