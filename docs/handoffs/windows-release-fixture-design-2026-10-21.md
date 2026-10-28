# Windows Release engine-test fixture decision — October 21, 2026

Status: approved by the maintainer on October 21: “Approve canonical recipe and
rebuild.” Implementation and actual Release execution remain pending. [Open obligations](../open-obligations.md)
remains the single unfinished-work register.

## Observed problem

CI run [39548870477](https://github.com/TJZine/LineupDesktop/actions/runs/39548870477)
built the combined engine/application/package at `c767d79d`. Its Debug engine job
passed; controller inspection confirms 242 common and 396 Windows passes, all
twelve required recovery cases passing, no baseline exclusions, and one visible
existing disabled Windows test.
Release common tests passed 240 cases, including all ten bridge recovery cases.
The Release Windows suite started 395 registered cases but reached only 130
starts and 47 failed completions before its 300-second timeout aborted the
process. The new native bridge recovery case failed; the required engine callback
case was not reached. Windows XML and the top-level summary are absent.

The repository worker (gpt-6.1-sol, medium) inspected the pinned Flutter source at
`abaf9c523780a608bd46686fd5e53740a07077f8`. Windows fixture helpers contain dummy
or omitted AOT paths, and some tests force JIT startup. The production engine
loads AOT data before the mocked Run call. Upstream selects Debug for this suite.
An invocation, working-directory or file-copy adjustment alone cannot repair the
missing native properties and mixed mock/runtime assumptions.

No inherently JIT-only assertion was identified in that investigation. It has
not proved that the entire suite can run faithfully in Release. Any incompatible
obligation must remain a failure and return for a decision.

## Recommended: canonical fixture migration

Keep one canonical source authority. Add a reviewed Windows-only test-fixture
patch to the normal recipe, with sequential patch derivation for files already
touched by the AX patch. Migrate manifest, verification, receipts, consumers and
baseline attribution together; do not admit arbitrary patch lists.

The fixture changes would be confined initially to these Flutter Windows files:

- `testing/windows_test_context.h` and `.cc`: use generated, absolute fixture
  paths for actual AOT startup.
- `testing/windows_test_config_builder.cc`: propagate the AOT property that is
  currently omitted.
- `testing/test_keyboard.cc`, `accessibility_bridge_windows_unittests.cc` and
  `flutter_windows_view_unittests.cc`: keep wholly mocked Run paths consistently
  mocked and assert successful setup before using engine state.
- `flutter_windows_engine_unittests.cc`: distinguish wholly mocked startup from
  real VM tests; real tests use the actual compiled runtime and generated AOT
  assets, and failed startup must fail before a wait can hang.

No production algorithm, player, libmpv, product Dart, shared build rule or
fixture Dart edit is included. The existing fixture generator already names
`app_elf_snapshot.so`. The existing Debug-only death-assertion semantics stay
explicit; they do not become Release death evidence.

The same fixture patch must apply to combined and DC-only sources. Only unrelated
failures qualify for exact-name, same-mode baseline attribution. None of the
twelve required recovery cases can be waived, skipped or replaced by Debug or
optimized JIT. Preserve full-suite selection and environment-filter protections.

This changes canonical manifest identity, including the identity recorded on
macOS even though the fixture code is Windows-only. It therefore requires a
fresh isolated verified macOS engine, fresh candidate and affected revalidation.
The existing verified pairs must remain intact under their original identities;
no receipt editing or relabeling is permitted. Check disk before provisioning;
do not delete existing data to obtain space. No build-time estimate is claimed.

The controller recommends this migration over maintaining a second source
verifier. It follows the maintainer's preference for one verified recipe and
accepts the additional build/resource cost explicitly. This is an approved
exception to the original frozen macOS identity. The controller reverified the
existing Release engine before migration; its binary and provenance hashes
remain `8daffe9911b489adc26f021034a893c57c54ad84b946bbacfb422ce8c657b09a`
and `4226268a0fa6d4b2bd41e38229d1ea49254191c7e4620561f85203521d7e606c`.

## Alternative: isolated test-only overlay

Keep the canonical product recipe and current Mac pair unchanged. A separate
isolated Windows test checkout applies the two canonical product patches plus
one allowlisted test-fixture overlay. A distinct test verifier/receipt binds
the canonical production tree, exact overlay derivation, dependencies,
configuration, toolchain, generated assets, test binaries and results. Normal
launch/package validation must reject this test-output kind.

Apply the same overlay to DC-only baseline tests and prove production source
outside the reviewed fixture files is unchanged. This avoids a Mac rebuild,
but adds a second source authority and separate test-source lifecycle/builds.
It is not acceptable to slip the overlay into the existing verifier's allowlist
or describe its test executable as the shipped DLL.

## Verification and stop conditions

First run representative mocked bridge and real AOT callback, headless startup,
platform-message, merged-thread and custom-entrypoint cases in both actual modes.
On disposable output, removing the AOT fixture must fail promptly; restore it
and require green. These focused runs are diagnostic, not final acceptance.

Final acceptance requires both complete common/Windows suites in Debug and
Release, all twelve named recovery cases present and passing without skips,
visible unrelated skips/failures, and same-mode DC-only attribution where needed.
Verify source/configuration/artifacts before and after. Preserve canonical
engine/application/package positive and rejection controls separately.

Python must also retain per-suite exit/XML-completion status and a blocked
top-level summary when a process aborts or XML is missing/malformed. Keep logs;
never synthesize passing XML, waive a crash or infer completion from console
counts. Portable controls must reject wrong source, patch order, fixture,
binary, mode and receipt identities and retain failed execution evidence.

Stop for any required production/shared-build/Dart-fixture change, weakened
assertion, incompatible AOT obligation, unequal baseline harness, required-case
failure or resource failure. Implementation uses the repository worker preset;
an independent reviewer checks the resulting source/identity boundary. The
controller owns integration, builds, commits and hosted dispatch. No new
signing settings, credentials, publication or platform acceptance is authorized
by this proposal.
