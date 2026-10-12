# Maintainability remediation execution

[Detailed plan and accepted findings](PLAN.md). All nine source packages are implemented, independently reviewed and committed. Available-host integration is accepted. Windows compile/runtime acceptance is pending; optional stored visual baselines have demonstrated pre-existing drift.

## Authority, scope and integration

Controller chat `01a13204-a261-7133-83c5-8084aa2036ef`, local. Original human authorization and callback retrieval references are in PLAN.md. All workers used `gpt-6.1-sol` / `medium`; both independent reviewers used `gpt-6.1-sol` / `high`. The controller adjudicated findings, serialized shared execution and owned Git. Children verified the original human authorization before callbacks. No push, merge, deployment, dependency upgrade, product/UI direction change or unrelated workflow maintenance.

Branch: `codex/desktop-ui-second-pass`. Initial product commit: `e83778169ea6e00217140981213425c3ecae5358`. Final product commit: `69cedc0bd2a72f29e557834a1e511b598910588c`. Planning commit: `f0f618f59cc34698dba7f611a2f74256feab71d2`. Final documentation-only changes do not invalidate product evidence.

Reviewers: R1 `01a13213-f08d-76d0-8258-40c6d7683c15`; R2 `01a13215-f99c-7832-8d48-c377908ec935`. Chats were reused for bounded reviews and corrections instead of repeated whole-repository audits. The initial plan received independent high review; consequential clarifications and accepted implementation refinements remain in PLAN.md.

## Packages and commits

| Package | Worker chat | Review | Commit | Result and distinct proof |
|---|---|---|---|---|
| M01 formatter | `01a13213-b438-7d33-a98a-de7f58d5cc63` | R2 | `66d0d28a` | Git-owned formatter includes tracked/new source and excludes ignored probes; 10 real Git controls passed in 5s, including literal percent/backslash paths |
| M02 diagnostics | `01a13213-c230-7250-a97e-ecb7a561cdcb` | R1 | `0d4357e0` | Safe build@commit and producer/export categories retained; 394 affected tests passed in 1s |
| M03 Plex paging | `01a13213-d2d4-7500-9b4f-206d547b1f4c` | R2 | `769b44fc` | Shared envelope validation with distinct stream policies; four Plex suites203 tests passed in 4s |
| M04 Studio/facets | `01a13213-e0f5-7680-97c7-552e86e62cf8` | R2 | `19416bc9` | One draft/session projection owner and typed facet matching; combined 371 tests passed in 34s; review refreshed after style correction |
| M05 scan ownership | `01a1321f-6a2e-7e80-be97-2d338e2b1b40` | R2 | `a4d9a415` | Row-derived attempt/readiness and retained content lifetimes; controller/setup/onboarding/restore: 283 tests passed in 8s; analyzer clean |
| M06 fixtures/API | `01a1322c-759f-7623-820c-b44e864c3ae3` | R1 core; R2 callers/proof | `69cedc0b` | Read-only committed state, recursive immutable publication, valid one-shot scenarios and finite fixture events; final focused 281 tests passed in 29s, full suite: 1,479 passed in 58s |
| M07 release policy | `01a1321a-e768-7612-ab7f-4e1bb2135379` | R2 | `a74486ab` | Public production launch/release owners with executable fixture-process controls; real PowerShell policy gate exit 0 |
| M08 navigation | `01a1321b-83af-7f71-908a-4699428f9e69` | R1 | `9b0a0f69` | Shared route-key recognition with existing local actions/leave guards; stable 204 tests passed in 20s |
| M09 native contracts | `01a13219-3530-7e93-8cbd-ea4ac5a9b091` | R1 | `ea4dce49` | Typed native command identities and actual production correlation/runner proof wiring; strict portable C++ state compile/executable passed; Windows targets uncompiled/unexecuted |

All twelve accepted findings map to these packages in PLAN.md. No blanket test pruning, generic state/queue framework, persisted schema change, credential seed, incidental source-spelling expansion or screenshot update was introduced.

## Review corrections and acceptance

Every material independent review finding was adjudicated and repaired with the same worker before source acceptance:

- M01: literal-path URI encoding could omit percent/backslash filenames; real temporary Git controls now prove inclusion.
- M02: additional normalized producer codes were missing; composed producer/export/privacy proof covers the repaired vocabulary.
- M07: the initial generic AST checker accepted wrong Git-root/pubspec association and missing exit forwarding while rejecting equivalent named path syntax. Controller reproduced the counterexamples. The accepted replacement uses canonical repository provenance and the full production launch owner, with a narrow wiring guard and executable positive/negative controls.
- M09: seeding correlation state alone missed the actual load producer handoff. Windows contract tests now drive parser → queue → RunCommand with bounded deterministic DLL query outcomes, including successful/query-failure FIFO and replacement/error correlation. High review closed the source gap; Windows execution remains pending.
- M06: queued plans/expected state retained nested caller aliases; first logout/schedule work left seed eligibility open; identity actors could leave old requests current; capture ignored rich scenarios; snapshotting stripped a serialization observer. All five were repaired and closed by the appropriate high reviewer on exact frozen inputs.

M06 freezes queue proposals and expected values at invocation, preserves published transition identity across metadata saves, closes fresh eligibility before asynchronous work, and guards/retire requests before synthetic identity transitions. Its presentation seam cannot seed credentials or reset operation/revision/currentness counters. Existing transaction, rollback, cancellation, child-profile and durable-value assertions remain; restored owner setup uses actual persisted state and initialize rather than actor/token bypasses.

The first M06 runtime candidate failed eight controller cases and one Studio case. Five controller assertions compared borrowed inputs with newly owned snapshots; three profile controls deadlocked in newly added setup before reaching their intended child-operation gate. The Studio case expected borrowed transition identity. Repairs retain complete value/committed-identity and original IO/save/late-result obligations. A subsequent focused run passed 279 and failed only two NEW invalid controls: a mixed child lacked its filtered genre, and an empty unseeded controller correctly produced noContent through the real schedule worker. Test-only corrections retain all mutable aliases and register the specific future failure before synchronous seed rejection. R1 accepted those final two controls; the final focused and full runs passed. The previous claim that the unseeded worker should produce a nonempty schedule is explicitly superseded.

Final M06 33-file aggregate: `57aaafa4b42993d377c5b3b3eef5b29d8d9c9edda5074cb8bba9d619832409a0` (sorted UTF-8 path + NUL + binary file SHA256). All 33 files remained unchanged through formatting, analysis, full-suite and visual execution. Final controller test SHA256: `af4ece6c291820115181f00ccd6956bd0d04ce85118d231642972e12d0de743a`. The product commit records the full accepted file identities.

M08's initial 204-pass/16s run overlapped a brief M05 controller edit and was discarded. Acceptance uses the replacement 204-pass/20s run on acknowledged stable inputs. Failed pre-repair gates are diagnosis evidence, not relabeled passes.

## Available-host final evidence

Pinned Flutter 3.47.6 / Dart 3.13.5, macOS. Tests use `TZ=America/New_York` and `--no-pub`. Initial audit baseline: 1,403 tests passed in 56s; analyzer clean; dot formatting failed seven ignored historical probes while intended tracked source was clean.

| Check | Final observed result | Limit |
|---|---|---|
| `dart tool/format.dart --check` | 99 files, 0 changes, 1.90s | Intended Git source; ignored historical probes excluded |
| `flutter analyze --no-pub` | No issues, 1.9s | Static/compile evidence, including tool and fixture consumers |
| `TZ=America/New_York flutter test --no-pub --reporter expanded` | 1,479 passed, 58s,exit 0 | Portable policy/widget/boundary evidence; includes required macOS Guide alpha |
| Controller + Studio focused suites | 281 passed, 29s,exit 0 | Real controlled IO/save/currentness boundaries, not OS credential/media acceptance |
| Serialization negative control | Injected real `channel.toJson()` in health signature fails expected 0/actual 1; exact restoration then passes | Reversible proof of observer effectiveness; no production observer hook |
| Rich/fallback design captures @1920x1080 | 2 tests passed in 3s; rich cast/artwork/fallback images inspected | Synthetic widget composition, not physical video |
| Three optional visual suites | 6 tests fail stored PNG comparisons; all 13 actual rendered PNGs exactly match original commit output | Pre-existing golden drift, not a passed stored-baseline gate |
| PowerShell release-policy gate | Actual PowerShell 7.6.6 process exit 0 | Platform executables are fixtures; no Windows launch/package acceptance |
| Portable production native state | Strict clang++ C++17 compile and executable exit 0 | Does not compile Windows parser/runner or establish HWND/messenger lifetime |
| `git diff --check` | Passed | Whitespace only |
| Preservation and retired-path checks | Protected 35 baseline files unchanged; other baseline files outside authorized net diff unchanged; retired manual-origin/aggregate override references absent | No numerical usage measurement |

Serialization control source was restored byte-for-byte to SHA256 `a0f20da5f21c6c49b4b8498fbb60d959cafb5803aea005128b65c9ac5c4ce769` before subsequent checks. All 24 historical capture files and existing ignored visual failure outputs were preserved/restored; no PNG baseline updates.

Optional visual diagnosis used an isolated exact `e83778169ea6e00217140981213425c3ecae5358` export, the same pinned SDK, unchanged dependency lock and the same three suites. Initial temp package mapping failed before tests; actual offline dependency resolution repaired that temporary harness without changing the lock. The observed baseline then reproduced all six golden failures. Every one of 13 actual PNG files is byte-for-byte equal between original and final source. Thus this remediation preserves those rendered outputs; refreshing historical golden expectations needs a separate approved visual-baseline task.

PowerShell runtime is temporary, not installed globally: `/tmp/lineup-maintainability-powershell-2026-10-12/runtime/pwsh`. Official 7.6.6 arm64 archive SHA256 verified: `6df833d094ebac1c1a74340d7b3437f4aaf5e03ce640484a1c4359f3ce8b3db1`. Command: `pwsh -NoLogo -NoProfile -File tool/windows/verify-release-policy.ps1`. Expected negative controls include unborn HEAD, Flutter exit 23 and Ninja exit 24; the assertion gate exits0. Existing dirty/source/artifact/trust-anchor protections remain.

Portable native command: `clang++ -std=c++17 -Wall -Wextra -Werror -pedantic windows/runner/native_playback_state_test.cpp -o /tmp/lineup-native-playback-state-test`, then the executable. This exercises the same state owner used in production.

## Remaining acceptance and usage benefit

M09 requires exact pinned Windows production compile/link, new native command and FlutterWindow lifecycle CTests, existing encoder/authenticated-reference CTests and affected physical tune/track/stop/dispose/recreate/window-close scenarios. M07 requires actual Windows launcher/patched release/package rejection acceptance. All are **unexecuted on this Mac**. Follow [Development native test tiers](../../DEVELOPMENT.md#current-test-tiers-and-gaps) and [physical/package acceptance](../../windows-native-validation.md); record exact candidate commit, installed assets, prepared/copied DLL hashes and patched-engine identity. Portable state, fake-platform subprocesses and blank-widget runner fixtures do not establish physical media, HDR, composition, input or package behavior.

Pre-existing user modifications and untracked October 7/October 10 review evidence, design packets, test-slimming records and local configuration remain untouched. The current checkout intentionally retains that original dirt; it is not an incomplete product diff. No source package remains uncommitted.

Expected maintenance/AI usage benefit comes from fewer independent policy authorities, owned scan/draft transitions, stable immutable publication, reusable valid fixture inputs and fewer false formatting or incidental-spelling failures. Numerical token, cost or future task-time savings have not been measured. Behavioral proof was preserved rather than pruned for lower runtime.
