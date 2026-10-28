# objective_c 9.6.2 local build-hook correction

Baseline: complete published objective_c 9.6.2 archive from
https://pub.dev/api/archives/objective_c-9.6.2.tar.gz, SHA-256
`5c80c2ad6e2c0397de5db38c6d653e69616a3397e13aa7633bf39eb668f2041b`.
UPSTREAM.json records all 204 original file hashes. Runtime, generated bindings,
native sources, package version/pubspec and license bytes are unchanged.

LOCAL.patch records the complete delta to published files:

- hook/build.dart accepts an integer macos_target_version (10–99). It applies
  only to macOS, defaults to the incoming hook target, and supplies the same
  flag to compilation and linking. Root pubspec selects 12. Target-specific
  output/object directories prevent sharing artifacts across overridden targets.
  A private schema-2 receipt retains the exact producing configuration and
  hashes of source files, workspace pubspec, compiler and SDKSettings, checked
  before and after compilation, plus the completed raw artifact hash.
  Workspace pubspec, compiler and SDKSettings are hook dependencies. The app
  verifier rejects old receipt schemas and stale cached identities, and requires
  matching raw UUID/text and final bundle evidence. SDKSettings identifies the
  selected SDK; this is not a hash of the entire SDK installation.
- analysis_options.yaml uses the root analysis policy for the owned hook while
  excluding unchanged foreign lib/test/example/benchmark/tool files and the
  upstream monorepo-only pubspec dev paths. Only existing hook logging/exception
  lint rules are disabled in this exact vendor context. Canonical formatting
  likewise includes hook/build.dart and excludes other foreign Dart files.

The source companion includes this complete tree/manifest in the exact Lineup
Git archive. The in-app recipe presents this record, delta, hook and root gate
inputs rather than duplicating generated bindings. Upstream LICENSE applies.

Retire this local delta only when the pinned upstream package/tooling honors
Lineup's approved macOS target through supported configuration, and after renewed
source, final-bundle and target-OS runtime proof. Do not patch Pub/SDK caches,
rewrite Mach-O minimum metadata or replace binaries after Flutter builds.

Existing unchanged-source arm64 availability/ABI compilation evidence is
attributed separately; it is not actual macOS 12 startup or semantic ABI proof.
