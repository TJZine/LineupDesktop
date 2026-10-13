Unit E review is complete and read-only. The strongest finding is a current native verification regression. A second finding concerns incomplete junction containment in build/package paths.

Target: `codex/desktop-ui-second-pass`, HEAD `4fb7758034f4f47290fae13a4ea8275860ba1284`. Pre-existing changes were preserved. No files, probes, tests, builds, dependencies, or Git state were changed. No current passing verification result is claimed.

### Findings

**E04 — Natural EOF no longer completes the authenticated-reference harness**

**Keep: confirmed defect; S2 Medium; high confidence.** Static evidence confirms the producer/consumer mismatch. Actual pinned Windows CTest execution remains outstanding.

The reachable path is:

1. The Python runner generates one-second MP4 media and remuxes it to MKV at [authenticated-reference-test.py:126](/Users/tristan/Software/LineupDesktop/tool/windows/authenticated-reference-test.py:126).
2. The native harness compiles the production implementation directly at [authenticated_reference_test.cpp:43](/Users/tristan/Software/LineupDesktop/windows/runner/authenticated_reference_test.cpp:43). It overrides only the test CA and audio/video presentation.
3. Production initialization sets `idle=yes` and `keep-open=no` at [native_player.cpp:595](/Users/tristan/Software/LineupDesktop/windows/runner/native_player.cpp:595).
4. Natural EOF now produces `state=ended` at [native_player.cpp:1174](/Users/tristan/Software/LineupDesktop/windows/runner/native_player.cpp:1174).
5. The harness recognizes only `stopped` and `error` as terminal at [authenticated_reference_test.cpp:75](/Users/tristan/Software/LineupDesktop/windows/runner/authenticated_reference_test.cpp:75).
6. Its message loop therefore waits until the 12-second deadline, sets `timed_out`, and returns failure at [authenticated_reference_test.cpp:170](/Users/tristan/Software/LineupDesktop/windows/runner/authenticated_reference_test.cpp:170).
7. Python requires successful exit, progress, and absence of rejection for the positive controls at [authenticated-reference-test.py:201](/Users/tristan/Software/LineupDesktop/tool/windows/authenticated-reference-test.py:201).

I checked the proposed later-`stopped` counterexample. The harness sends only initialize/load, not Stop. Production’s idle confirmation runs only when a stop request is pending, and emits a `stopResult`, not `state=stopped`, at [native_player.cpp:1038](/Users/tristan/Software/LineupDesktop/windows/runner/native_player.cpp:1038). Other unhandled mpv events fall through. Destruction occurs after the timeout flag is computed and cannot rescue the result.

**History/root cause:** `db30c286` correctly distinguished natural EOF from stopped loads and added Dart adapter coverage, but did not update this native consumer. The actual diff was inspected. Earlier fixes remain useful: `d6fff072` requires no later rejection, and `29062716` retains rejection monotonically across stopped events. The current bounded messenger contract covers stopped/error/progress-error-stop, but omits ended.

**Impact:** successful playback can fail the opt-in containment suite, obstructing trustworthy security regression evidence. This does not demonstrate a product playback failure, and the target is excluded from default builds and CI.

**Correction direction:** teach the harness the current natural-completion contract and add Release-active ended/error-ending sequences. Preserve monotonic rejection and the positive control’s progress/no-rejection requirements; do not finish merely on progress or force Stop to manufacture success.

**Required proof:** rebuild the actual target and run the pinned Windows CTest repeatedly, with MP4/MKV success, negative containment, rejected-option, and untrusted-CA controls retained.

---

**E01 — Package containment misses a junction above `build/package`**

**Keep for controller adjudication: confirmed incomplete static guard; S2 Medium.** High confidence in the omitted ancestor check; exact Windows package manifestation is unexecuted.

[package.ps1:30](/Users/tristan/Software/LineupDesktop/tool/windows/package.ps1:30) qualifies the destination and checks its textual prefix below repository `build/package`. It then calls the shared reparse walker with that directory as its boundary at [package.ps1:223](/Users/tristan/Software/LineupDesktop/tool/windows/package.ps1:223).

The walker returns as soon as it reaches the boundary at [build-inputs.ps1:82](/Users/tristan/Software/LineupDesktop/tool/windows/build-inputs.ps1:82). It never checks the repository’s `build` ancestor. If ignored `build` is a junction and its `package` descendants are ordinary directories, output creation/copy/archive operations can resolve outside the intended checkout tree. Junctions reference other directories through reparse points. [Microsoft junction documentation](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions).

The sibling build guard checks the Release directory and descendants at [build-inputs.ps1:56](/Users/tristan/Software/LineupDesktop/tool/windows/build-inputs.ps1:56), also omitting ancestors. The release wrapper removes an existing marker and invokes Flutter before that inspection at [build-release.ps1:142](/Users/tristan/Software/LineupDesktop/tool/windows/build-release.ps1:142).

**Counterpoints:** direct package-root/descendant links, Release-root/descendant links, and tracked Git symlinks are rejected. Existing destinations cannot be silently overwritten. Source, engine, runtime, and artifact hashes remain protective. I found no demonstrated provenance bypass, remote exploit, or corruption of existing package files.

**History/root cause:** actual diffs for `565bf0bd` and `ca56080a` show deliberate linked-input rejection, but the chosen inspection roots leave the above-root sibling uncovered. Current CI probes junctions inside Release/data and inside build/package at [ci.yml:251](/Users/tristan/Software/LineupDesktop/.github/workflows/ci.yml:251), not the ignored build ancestor.

**Correction direction:** enforce the intended link policy across all path components below the repository boundary before build/package writes begin. Explicitly document any intentionally supported linked-root exception.

**Minimum Windows probe:** use an isolated clean disposable checkout and operation-owned target directory. Compare ordinary build, a junction inside packageRoot, and a junction at build. Exercise the real walker, then real packaging with valid prepared artifacts, checking rejection before external output changes. Do not alter the current checkout’s existing build tree. A Python imitation would not establish PowerShell/Windows acceptance.

---

**E02 — Release-policy checks depend on implementation spelling**

**Optional: subjective maintainability concern; S3 Low; high confidence.**

[verify-release-policy.ps1:37](/Users/tristan/Software/LineupDesktop/tool/windows/verify-release-policy.ps1:37) requires literal launcher source fragments; [verify-release-policy.ps1:192](/Users/tristan/Software/LineupDesktop/tool/windows/verify-release-policy.ps1:192) requires specific assignment and invocation shapes. Behavior-preserving helper extraction, renaming, or equivalent argument construction can fail these checks, while matching text does not prove invocation behavior.

Mitigations are substantial: the script executes real path/argument helpers and pubspec negative cases; the conditional Windows job tests packaging. Retain parsing, integrity anchors, and behavioral rejection coverage. Replace spelling constraints when this tooling next changes rather than removing the gate wholesale. Park this if it falls below the review’s materiality threshold.

**E03 — Small documentation drift; informational, not promoted**

- [docs/README.md:111](/Users/tristan/Software/LineupDesktop/docs/README.md:111) describes both freshness scenarios as deferred, while the linked investigation explicitly resolves canonical-shuffle scenario A.
- [DEVELOPMENT.md:180](/Users/tristan/Software/LineupDesktop/docs/DEVELOPMENT.md:180) describes two optional suites/five representative snapshots but does not distinguish the additional dated track-label golden suite.
- [architecture.md:285](/Users/tristan/Software/LineupDesktop/docs/architecture.md:285) aggregates macOS golden verification “in CI”; CI runs the required alpha suite, while optional screenshot goldens are separate. Detailed Development guidance states the distinction correctly.

These can accompany current-document reconciliation. They are not new product regressions.

### Coverage and calibration

Read instructions and skills: AGENTS.md, CLAUDE.md, `.agents/project.md`, supplied census/input identity, Prompt 1, shared review-code, repo-production-review, build/release, tests/CI, docs/DX, maintainability, operations, and evidence-calibration rubrics. No nested delegation occurred.

The wide scan covered tracked Windows/engine tools, CMake/manifests, macOS setup, dependency manifests/lockfile, vendor metadata/licenses, CI, tests/harnesses/visual suites, current authorities, relevant plans, and historical reviews. Searches covered provenance, links, dirty state, environment/arguments, diagnostics identity, skips, golden evidence, source-grep tests, and absent authority documents.

Deep inspection included every production PowerShell owner; the entire CI workflow; engine patch/notice; Windows CMake and runner manifest; package allowlist/CRT requirements; libmpv metadata; macOS entitlements/deployment/signing settings; CLI startup wiring; both native test harnesses; product-spine/driver boundaries; alpha/font/golden support; DST prerequisites; and representative persistence negative/recovery tests. All 212 documentation files and every permanent test were not read line-by-line.

| Dimension | Result within assigned scope |
| --- | --- |
| Architecture/ownership | Shared build-input enumeration and Flutter/native division are coherent. No new material ownership finding. |
| Correctness/failure modes | E01 path boundary and E04 terminal-state mismatch survive calibration. Other inspected build failures generally fail closed. |
| Maintainability | Purposeful scripts and shared artifact enumeration; optional E02 spelling coupling. |
| AI/debt patterns | No promoted placeholder, fake-success, speculative-framework, or size-based finding. |
| Tests/CI | E04 breaks opt-in positive controls; E01 lacks ancestor controls. Synthetic/default/native tiers are otherwise substantially qualified. |
| Security/privacy | Array invocation, integrity anchors, credential-safe test output and rejection controls inspected. E01 is bounded filesystem containment; no remote exploit claim. |
| Build/release/supply chain | Pins, runtime/header/license hashes, source/engine/artifact identity, CRT and Vulkan requirements inspected. Existing release gates remain unclosed. |
| Operations/configuration | Launcher parameter precedence, setup failures, environment/location restoration and diagnostic defines traced. No additional promoted issue. |
| Performance/reliability | Download retries, subprocess/native waits, server cleanup and CI deadlines inspected; no measured performance claim or new demonstrated unbounded cost. |
| Docs/DX | Current operational guidance predominantly matches source; E03 is limited drift. |

**C12 historical lessons retained:** actual diffs for `d816b53b` established source/engine/artifact-bound package identity; `565bf0bd` rejected linked inputs; `ca56080a` moved tracked-symlink rejection before build; `070ab1d6` embedded diagnostic identity. Sibling searches covered provisioning, apply, launcher, CMake, marker writer/consumer, CI, notices and diagnostic defines. E01 is the newly identified ancestor sibling.

**C13 historical lessons retained:** actual diffs for `d6fff072`, `29062716`, `766ed05f`, and `9d30daa9` were inspected. Progress-plus-rejection and overwritten-error defects are corrected; malformed-state/model/settings and exact-byte quarantine/reload contracts remain represented; fixture-source grep and fake-support self-tests were deliberately removed. E04 is a new protocol-consumer regression introduced by the later EOF distinction.

The October 7 report was treated as frozen historical evidence, including its October 8 resolution annotations. I did not repeat corrected product findings. Scheduled continuation is implemented; transcoding and automatic fullscreen HDR remain planned. No planned feature was promoted into a newly discovered regression.

### Assigned journeys and documentation claims

| Journey | Trace and remaining limit |
| --- | --- |
| J09 diagnostic identity | Release wrapper derives strict pubspec name and numeric build@SHA, passes both defines, and Diagnostics reads them at [diagnostics_view.dart:76](/Users/tristan/Software/LineupDesktop/lib/app/diagnostics_view.dart:76). Development defaults truthfully show Unavailable. Actual packaged identity/clipboard/runtime observation remains Windows acceptance. |
| J11 local-media/platform entry | Launcher validates optional media → preserves one argument → pinned Flutter → Windows runner forwards arguments → Dart `--media=` → shell → coordinator load. Missing/blank paths fail early; local-load errors have a bounded recovery surface. Actual argument transfer, image/audio, hardware, DPI, input and lifecycle were not executed. macOS playback remains explicitly unsupported. |
| J12 build/release | Pinned preparation → exact contextual engine patch → launcher refresh → clean release build → artifact marker → package revalidation/copy/licenses/CRT/requirements/manifest/archive. E01 affects containment. Complete launch outside checkout and on clean Windows remains unverified. |

Documentation-to-owner disposition:

- README platform/package limits → Windows scripts/native build owners: correctly pre-release.
- Development test tiers → CMake/harnesses: accurately opt-in and absent from CI; E04 changes current harness usability.
- Development timezone guidance → Guide DST prerequisite: accurately distinguishes skip/portable evidence from canonical Windows behavior.
- Development launcher/provision/package commands → PowerShell owners: substantially aligned, with E01.
- Runtime provenance → preparation/CMake/package metadata: integrity controls present; mirror/transitive notices/legal completion explicitly pending.
- User-guide installation requirements → packaged CRT/Vulkan/complete-folder requirements: aligned.
- Collaborative/platform acceptance → actual native producers and exact-package scenarios: human/physical evidence remains required.
- Continuation/freshness/transcode/HDR plans → current status: implemented/resolved versus planned distinctions retained; index drift noted in E03.
- Historical review evidence → named frozen source: not relabeled as current verification.

No current tracked DECISIONS.md, TODO.md, CHANGELOG.md, current-cli-contract.md or current-architecture.md was found. Available CHANGELOG history is upstream provenance; actual current equivalents are architecture, Development, main and launcher contracts.

### Deferred verification

PowerShell is absent from the parent’s PATH. There is no faithful installed replacement for executing its parser/helper policy. Do not call source matching or a Python simulation policy acceptance.

On an existing PowerShell 7.4+ host:

```powershell
pwsh -File ./tool/windows/verify-release-policy.ps1
```

Windows prerequisites are the exact pinned Flutter/runtime identities, Git, PowerShell 7.4+, MSVC/Desktop C++/Windows SDK and 7-Zip. Patched-engine work additionally requires Python, pinned depot_tools, ATL, SDK `10.0.22621.0`, Debugging Tools, configured GN/Ninja outputs, and the Vulkan loader prerequisite.

```powershell
cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test
ctest --test-dir .\build\windows\x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30

cmake --build .\build\windows\x64 --config Release --target authenticated_reference_test
ctest --test-dir .\build\windows\x64 -C Release -R '^authenticated_reference$' --repeat until-fail:3 --verbose --timeout 180
```

The reference test also requires FFmpeg with libx264/DASH and OpenSSL. E04 must be addressed under separate implementation authorization before a passing result is expected.

Then verify launcher omission/blank/missing/spaced media paths, caller-directory/environment restoration, and actual SDR output. From a clean isolated candidate, run the release wrapper and package script with a unique destination; verify manifest/hash/build identity and launch outside the checkout and on clean Windows. Perform E01’s real junction controls there.

Native CTests still do not establish composition, fullscreen, input, HDR, hardware decode or complete package behavior. Loader-absent and system-setting scenarios require their appropriate disposable-environment authorization.

Excluded or unverified: full application/UI policy assigned elsewhere; detailed native lifecycle beyond these seams; actual DLL imports/binaries; private stores/logs; dependency vulnerability or legal completeness audits; fresh GitHub run metadata; opaque assets/generated output except release metadata; exhaustive historical links; all Windows/live/physical execution. Docker was excluded.

Automatic approval review rejected the terminal callback, stating that trusted authorization to message the parent was not established. The parent subsequently instructed direct retrieval instead; no callback was retried.
