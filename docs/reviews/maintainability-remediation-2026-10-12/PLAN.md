# Maintainability remediation plan

Date: October 12, 2026. Status: implementation authorized; package acceptance is recorded in EXECUTION.md.

## Scope and authority

The user requested a detailed plan and implementation of the accepted audit findings, prioritizing maintainability and reduced AI usage, preserving current behavior and meaningful tests, using separate GPT-6.1-Sol medium workers and GPT-6.1-Sol high reviewers, and creating proper commits. No push, merge, deployment, dependency upgrade, new UI direction, or unrelated workflow overhaul is authorized.

Controller: Codex chat `01a13204-a261-7133-83c5-8084aa2036ef`, host `local`. Human authorization: turn `01a1320e-af52-7d31-8801-8a40ae68a431`, user message `01a1320e-af79-7af2-acbd-ffa242e61fbf`. Children verify that original human message through `read_thread` before terminal callbacks; a copied quotation is only a retrieval pointer. Finish locally if callback authorization cannot be established or automatic approval rejects it; do not repeat rejected callbacks. The controller can retrieve reports.

Repository: `/Users/tristan/Software/LineupDesktop`; project `local-8c633241263023433fa4ceaef19f114e`; branch `codex/desktop-ui-second-pass`; product baseline `e83778169ea6e00217140981213425c3ecae5358`. The tracking ref is eight commits ahead at discovery; this assignment uses the current checkout, with no pull or branch change. The prior audit is in the controller chat and bounded audit chats A/B/C/D; its accepted evidence is summarized below.

Preserve pre-existing modified October 7 REPORT/REMEDIATION documents, untracked October 10 review evidence, design packet, test-slimming records, `.claude/launch.json`, `docs/comprehensive-review-prompt.md`, and Python cache. The controller recorded all existing tracked/untracked file hashes at `/tmp/lineup-maintainability-remediation-2026-10-12-baseline.json`; this is temporary preservation evidence, not a permanent repo policy.

Read AGENTS.md, relevant .agents/project.md, and shared develop-code/review-code/verify-code guidance. Architecture and async/persistence authorities, approved interface system, and Windows runtime/physical-acceptance documents retain their contracts. Historical prompts and rosters are provenance only. The actual worker/reviewer TOMLs currently resolve to the user's requested models and efforts.

## Accepted findings

| ID | Finding | Classification | Evidence at baseline | Package |
|---|---|---|---|---|
| F01 | Formatter includes ignored historical probes | Confirmed defect, S3, high confidence | DEVELOPMENT:145/project profile:174 use dot; 167 files scanned, seven ignored build probes fail; all 90 tracked Dart files pass | M01 |
| F02 | Release build identity disappears from copied diagnostics | Confirmed defect, S3, high | build-release.ps1:109 produces build@commit; diagnostics.dart:246 rejects @ | M02 |
| F03 | Normalized safe failure categories disappear from export | Confirmed defect, S3, high | controller:656 emits five normalized auth categories; diagnostics.dart:330 omits them and native command_error | M02 |
| F04 | Scan attempt/retained readiness state is scattered | Maintenance concern, S3, high | controller:185-210, :940-982, :2599 maintain overlapping fields/capture/restore/reset | M05 |
| F05 | Studio draft interpretation has three projections | Maintenance concern, S3, high | Studio:364 dirty schema, :2956 source interpretation, :3178 save, :3203 preview | M04 |
| F06 | Plex page envelope rules have three authorities | Maintenance concern, S3, high | Plex client:427 ordinary items, :881 metadata, :1947 playlist validator; duplicate count parsers | M03 |
| F07 | Studio duplicates facet matching and unused untyped support | Maintenance concern, S3, high | Studio:2341 Map<Object,Object>/string switch/sort; resolver:44 typed facet switch | M04 |
| F08 | Fixture-created state influences production API/behavior | Maintenance concern, S3, high | controller:147 public committed fields; :173 test/older-caller origin fallback; independent fixture cascades | M06 |
| F09 | Release gates freeze incidental source spelling | Maintenance concern, S3, high | verify-release-policy.ps1:37-66 and :192-216 assert names and exact call shapes | M07 |
| F10 | Native command integer slot conflates load/stop/track identity | Maintenance concern, S3, high | native_player.h:66 command; cpp:914 load, :968 stop, :981 track | M09 |
| F11 | Route shortcut recognition is duplicated | Maintenance concern, S3, high | shell:390 maps route keys; Player:188 repeats bypass list | M08 |
| F12 | Native correlation/normal shutdown lacks direct regression proof | Inferred risk, S2, medium regression confidence | native event maps/FIFO/queues/shutdown vs Dart tests' prelabelled events and single-load reference harness | M09 |

All findings are accepted for remediation. No generic file splitting, blanket test pruning, dependency framework migration, or historical corrected defect is included. Numerical token/cost savings are unknown.

## Design and integration decisions

Preserve Flutter/Dart application and interaction ownership, native mechanism ownership, modular-monolith composition, explicit dependencies, one scheduler policy, persisted formats, credential isolation/redaction, and separate operation/content/native/track/stop identities. Maintain approved layouts and input behavior; no screenshot baseline changes are planned.

Choose narrow shared domain rules over an app-wide state framework. Extract an owner only when callers or transitions actually become simpler; moving unchanged field juggling to a new file is insufficient. Keep distinct preview/edit/commit states, source occurrence semantics, fatal/recoverable errors, and data-vs-credential commit obligations.

All children run locally in this checkout. The controller alone owns Git staging/commits and acceptance. Concurrent writers have disjoint owned paths. No child executes Flutter, Dart analysis/tests/format, PowerShell builds/checks, native builds/tests, or app instances unless it receives an explicit exclusive resource lease. The controller serializes shared execution, identifies stable changed inputs, and runs focused checks; source reads/review can overlap unrelated writes. A package owner stops editing when reporting ready for review. Corrections return to the same worker.

Independent high reviewers assess both correctness and reduction of the specific maintenance burden. The controller validates findings, including conflicting advice, and accepts the exact reviewed diff. A reviewer is not a second implementation owner. Reuse review chats for related packages with bounded fresh inputs; no fixed panel or duplicate full audits.

## Package overview

| Package | Goal | Dependencies and conflicts | Primary verification |
|---|---|---|---|
| M01 | Reliable formatter input ownership | Independent; finishes before M07 CI/policy edits | Real Git input/enforcement controls; tracked and new source included, ignored probes excluded |
| M02 | Diagnostic identity/category contract | Independent; finishes before M05/M06 controller work | Report and producer/export regressions, privacy negative controls |
| M03 | One Plex page-envelope rule | Independent | Four existing Plex suites including real IO and bounded/fatal cancellation |
| M04 | Studio draft owner and shared typed facets | Independent; finishes before M06 broad fixture migration | Studio/resolver/Air Check/schedule behavior, preview-save agreement |
| M05 | Cohesive scan attempt/readiness owner | M02; source controller exclusive; precedes M06 | Controller scan/restore/commit/failure cases and affected setup/widget callers |
| M06 | Valid fixture scenarios and read-only committed state | M02/M04/M05/M08; requires stable affected test inputs | All affected fixtures plus full suite, transaction/generation/isolation proof |
| M07 | Behavioral release-input policy | M01; independent of Dart owners | PowerShell policy positive/negative controls; preserve pinned/package protections |
| M08 | Navigation owns shortcut recognition | Independent; finishes before M06 widget migration | Actual-key navigation, Player local actions and draft leave guards |
| M09 | Explicit native command identities and direct lifecycle proof | Native paths exclusive; independent of Dart packages | Portable actual-owner tests where possible; Windows compile/CTest and physical acceptance tracked separately |

Start bounded M01/M02/M03/M04 in parallel. As slots and stable ownership permit, dispatch M05/M07/M08/M09; prioritize review/acceptance of completed work. M06 follows its actual shared-state dependencies. Do not equate package numbering with a serial pipeline.

## M01 — Formatter input contract

Goal: remove false local failures without omitting intended new source. Own `tool/format.dart` (or an equally small existing stdlib tooling owner), its meaningful enforcement tests, canonical formatting recipes in DEVELOPMENT/profile/CI, and affected contributor links. Do not alter historical probes or unrelated global workflow instructions.

Decision: obtain tracked plus non-ignored untracked Dart inputs from Git using argument-array subprocess calls and NUL-delimited paths; de-duplicate, account for deleted files, invoke the selected Dart executable without shell interpolation. Use a stdlib Dart entry point so ordinary Dart work gains no Python/PowerShell dependency. `--check` must use output-none/set-exit semantics; explicit formatting is separate. Preserve lib/test/tool/test_driver coverage and newly added source. Do not silently pass when Git or Dart execution fails or no intended inputs can be established.

Verify a real temporary Git repository: clean source passes; intended malformed/incorrectly formatted source fails; new untracked source is included; ignored malformed historical output is excluded; spaced paths and process exit propagation work. Reuse useful infrastructure; avoid implementation-shape assertions. Update one recipe owner and links consistently. Reviewer checks portability and changed input trust boundaries.

Expected behavior change: false failures from ignored output disappear; actual source formatting failures still fail. Rollback is a scoped revert of runner/recipes; no product data change.

## M02 — Diagnostic export contract

Own diagnostic report/sanitizer and existing diagnostic tests; necessary narrow producer-category changes in controller/coordinator/adapter are allowed, but no scan/state/playback refactor. Coordinate any additional producer path with the controller before another writer owns it.

Give release build identity a dedicated bounded grammar supporting the actual numeric-build@40-character-commit shape. Preserve existing safe development labels/numeric builds, unknown fallback, arbitrary-string rejection, and all other report redaction. Do not broadly admit @ into every diagnostic fact.

Make normalized producer categories and export eligibility explicit in one small safe vocabulary/mapping. Cover all current normalized auth outcomes, native command_error, and other currently emitted fixed categories encountered in the owned trace. Keep producer domain semantics in the appropriate owner; unknown upstream/native/user strings remain excluded. Do not replace semantic allowlists with syntax-only trust or a scanner that freezes source spelling.

Verify actual wrapper-shaped identity, oversized/malformed/sensitive negative inputs, allowed/unknown categories, and composed producer-to-export behavior using existing fixtures. Preserve event/report ordering, recording-off clearing, bounds, snapshots and media vocabularies. Focused suites: diagnostics, desktop diagnostics, relevant controller/Player cases. Rollback is scoped code/tests; no persisted schema change.

## M03 — Plex page-envelope authority

Own Plex client and a narrow page-envelope helper if useful, plus relevant Plex tests. Preserve public API, JSON/XML parity, transport cancellation/authorization/redaction and all error codes/messages.

Centralize only common container/count/offset/stable-total/size/empty-before-total/over-total checks. Make domain error category and oversized-complete metadata policy explicit. Retain identity/occurrence validation, progress, fatal versus per-source recovery, bounded pages/entries/member aggregation, shared concurrency and raw-consumed accounting in their actual stream owners. Absent count differs from malformed count. Playlist repetitions differ from library duplicate IDs.

Migrate all three authorities and both count parsers in one change, removing superseded common code. Verify all existing parser/transport/library-scan/IO suites, especially malformed envelopes, oversized terminal metadata, occurrence identities/repetition, stable totals, missing metadata, source replacement, real peer-disconnection and sibling cancellation. Deduplicate tests only if retained proof clearly subsumes them; no pruning target. Rollback as one scoped commit; no data migration.

## M04 — Studio draft interpretation and typed matching

Own Studio view, a local draft/session owner, content resolver/shared typed facet helper, and Studio/resolver/Air Check tests. No controller state changes or UI design changes.

Decision: a cohesive Studio draft value/session owns effective programming, canonical dirty identity and Channel projection; widget State retains text/focus/picker/rendering and controller remains persistence owner. Share effective block size/include-specials/source order/retained schedule rules between dirty/preview/save. Keep invalid raw number/name edits distinguishable, preview safe placeholders, strict save validation, source-choice/manual occurrence identity, candidate vs committed anchors/seeds, generated/duplicate preservation and legacy schedule transition. One common projection must not hide preview/save distinctions or mutate schedule identity on render. Migrate rebase/reload/success/baseline transitions and delete redundant rule copies.

Share one typed facet matcher between domain and Studio. Domain retains saved-source validation/order/deduplication; browser retains search/type/inventory/order decisions. Remove unused string/sort compatibility support after confirming current callers. Preserve OR within a facet, AND across facets, canonical people, decade rules, watched filtering, manual/playlist inventory and missing retained selections.

Verify existing Studio and resolver suites, Air Check, relevant scheduling/controller cases. Trace change/revert dirty state, preview vs saved programming, generated/duplicate transitions, unavailable inventory, stale Air Check, pending picker, migration, conflict/rebase and delayed/failed save. Preserve exact approved rendering/input; new pure owner tests only for a distinct obligation. Rollback scope includes all migrated callers/rules; no persisted schema change.

## M05 — Scan attempt and retained readiness

Own controller scan implementation and a cohesive scan owner/snapshot, controller scan tests and narrow affected setup/onboarding tests. M02 must be stable first; no fixture-wide API conversion in this package.

Decision: represent active scan attempt and retained usable readiness explicitly, with one owner for per-library facts/results and playlist/collection discovery facts, previous readiness capture/restore, attempt cancellation and derived aggregate projections. Controller retains authorization/mutation/content currentness, queues, persistence commit and runtime publication. Attempt obsolescence cannot invalidate usable committed inventory; retained readiness cannot prove source disappearance after an unverified refresh. Keep completed subset commit, explicit failed-row retry, selected ID/scope relationship, playlist catalog unavailable vs per-playlist failure, and collection discovery vs contents failure separate.

Replace manual parallel field lists with a coherent snapshot/transition API; derive aggregate counts where possible. Remove retired copies/restore closure mechanics, not just relocate them. Separate picker/restore bookkeeping from scan reset where semantics permit, migrating every reset caller. Prepare a field/transition inventory in the terminal report and reconcile it with retained tests.

Verify controller scan/restore/source-gone/cancellation/partial-ready/persistence cases, setup/onboarding callers, and cancellation transport controls. Explicitly test late completion across scope changes, failed refresh retaining readiness but not absence proof, retry selection, save failure and commit ordering. Run broad controller/widget evidence on a stable package. Rollback complete owner/callers atomically; no data or credential migration.

## M06 — Valid fixtures and committed-state API

Own production controller committed/session-state API and all necessary existing fixture/test consumers, plus test support. Start after M04/M05/M08 and any overlapping writer stop; no concurrent affected source/test mutations.

Decision: production committed account/profile/server/connection/content/channels/settings state becomes read-only to consumers with explicit command APIs for real transitions. Introduce one controlled typed fixture-seed/scenario seam rather than scattered direct assignments. Prefer existing fake store/client/credentials plus real commands where their boundary is the assertion; cheap widget fixtures may seed a valid committed scenario. Seed installation must establish the same relevant channel revision, inventory identity, content generation, picker origin and selected-scope relationships. Keep credential stores/auth tokens isolated; no unsafe public dynamic setter or generic state-management layer.

The worker must map every direct assignment and distinguish initial scenario setup from a real transition under test. Migrate all affected consumers, preserve explicit invalid-state/late-result/failure controls, and remove the production fallback documented solely for manually configured fixtures/retired callers after verifying no real consumer remains. Do not replace real IO/filesystem/isolate/credential tests with mock-only scenarios. Do not force every visual fixture through account linking.

Verify affected widget/controller/Guide/playback suites and the full portable suite on final stable inputs. Add only necessary seed-contract controls comparing generation/revision/origin/scope to the real operation path. Review checks that getters are not backed by mutable externally exposed collections and that repeated seeding cannot silently bypass active lifetime/cancellation. Rollback production API and all migrated callers together. This is the highest Dart integration-risk package; source-only review is insufficient.

## M07 — Release policy observes contracts

Own Windows run/build-release/build-inputs/verify-release-policy helpers, focused policy fixtures and DEVELOPMENT release recipe if needed. M01 must finish first. No package format, trust-anchor, runtime/engine revision, license, signing, or external CI settings changes.

Expose/reuse small side-effect-free release/launch input contracts for argument generation, version/build identity and path resolution. Have policy checks execute those contracts with known-good and deliberate bad inputs, preserving safe array invocation and failure propagation. Retire incidental variable-name/quote/call-shape requirements only where their meaningful obligation is covered. Preserve exact revision/hash trust anchors, parser validation, no shell interpolation, independent runtime integrity pins, tracked symlink/reparse/dirty-source/stale-marker/artifact/license tamper rejection and stock-engine vs patched-engine distinction.

An equivalent local variable/helper rename should not require policy changes, but a real unsafe argument/identity/path must still fail. No tests that merely assert changed source spelling. Reuse current PowerShell checks and rejection fixtures. Obtain a usable PowerShell 7.4+ runtime locally if safely available without system-wide changes; if absent, finish implementation/source review and record exact unexecuted checks rather than substitute a textual simulator. Windows package/launch tests remain separate. Rollback helper and policy callers together; no package publication.

## M08 — Navigation shortcut recognition

Own a small navigation key resolver, Shell/Player callers and relevant navigation/Player/Guide tests. No persisted route or layout changes, no global command bus.

One navigation-owned resolver recognizes current Ctrl+1..5/G/P/comma routes; Shell uses its result and Player uses the same recognition to allow propagation. Keep current modifier/repeat/typing/control behavior and _select leave guard. Preserve local unmodified channel digits/G/P and transport, focus, menu and editor routing. Review actual propagation rather than direct callback equivalence.

Verify actual route chords from Player/Guide/Studio, unmodified local actions, focused text/control cases, unsaved-draft leave behavior and existing navigation tests. Physical remote input remains a separate gate if claimed. Rollback resolver and both callers together.

## M09 — Native commands and direct transition proof

Own native_player.cpp/h, a narrowly extracted actual native state owner if justified, focused native contract/lifecycle tests and CMake wiring; necessary runner integration and Windows acceptance recipe updates only. No media policy/UI migration, libmpv/engine/options/provenance upgrade, transport payload change, or weakened authentication hardening.

Use operation-specific named payloads/construction for load, stop and track, eliminating integer-slot remapping. Preserve distinct native generation/load/stop/track request/track selection identities, move-only zeroed credential lifetime, bounded queue sizes/bytes, worker/platform responsibilities and existing codec semantics. A small representation is sufficient; no queue framework.

Tests must drive actual production correlation/queue/lifecycle code, not a parallel model that labels events correctly by construction. A narrow production state component can be extracted when that makes real transitions portable/testable; the native owner must use that same code, without duplicated state. Alternatively extend existing native harness with a bounded test seam. Keep Windows HWND/mpv mechanism ownership intact.

Required proof obligations: replacement loads with stale START/END/property/error events; pending-load FIFO and playlist/redirect IDs; stop command acceptance vs observed idle completion and retry; track result correlation across retirement; stale-generation drain; event pressure with critical acknowledgments; normal asynchronous dispose/recreate and window-close completion before messenger/window retirement. Include positive and negative sequences. Preserve encoder and authenticated-reference controls.

Compile/run any portable actual-owner tests on this host; native Windows sources still require exact-toolchain build and CTest. Record executable target and commands for Windows, exact source/runtime identities, and affected physical tune/track/window/close scenarios. Mac-host portability tests do not establish Windows media or normal platform shutdown. Do not mark that gate passed without observation. Rollback production owner and tests/wiring atomically; no binary distribution.

## Verification and review gates

Baseline audit at e837781: pinned Flutter 3.47.6/Dart 3.13.5; analyzer clean (2.1s); New York portable suite 1,403 passed (56s); 90 tracked Dart files format clean; dot formatting fails seven ignored historical probes. Reuse that baseline for unchanged contracts. New commits containing only planning prose do not create new product evidence.

Controller checks each stable package: owned diff and preservation, focused behavioral proof, changed-file formatting, and high independent review. Repair failures caused by changes; same worker handles focused corrections. Reviewers report direct evidence, real caller effects, regressions, residual duplicated policy/invalid states and remaining verification gaps. Require maintained or improved caller/locality cost rather than simply fewer files or lines.

Final stable integration: canonical M01 formatter check; pinned Flutter analyze; `TZ=America/New_York flutter test --no-pub` including macOS Guide alpha; `git diff --check`; authorized-file preservation and retired-path searches; PowerShell policy where available; portable native tests; exact remaining Windows build/CTest/physical checks. Run full suite once after stable combined inputs, then repeat only affected checks for subsequent repairs or invalidated evidence. No coverage percentage or test count target. Do not erase an existing boundary's proof to reduce runtime.

Each accepted package receives a focused conventional commit staged by explicit owned paths. Separate planning/docs commit first; don't accidentally stage pre-existing dirt. Dependent package changes commit after prerequisites and stable review/checks. A native package can have code/portable proof committed with explicitly pending Windows acceptance; this does not imply runtime completion or support. No force reset, amend of user history, push or merge. A rollback is a scoped revert of a complete package and affected dependent commits, preserving user work.

## Execution record and usage evaluation

EXECUTION.md owns dispatch IDs/models/efforts, exact reviewed source/diff identities, checks/results/limits, accepted commits and remaining work. It is a compact current-state record; avoid duplicating all child histories or creating a second testing policy. Workers return a file list, meaningful change/obligation map, proof already run or pending, and terminal completion/blocker callback. The controller does not keep idle polling turns alive.

Evaluate usage benefit qualitatively by removed independent policy copies, reduced transition field lists, valid reusable fixtures and fewer false/shape-sensitive gates. No numerical savings claim without observed task token/time/cost data. Keep current documentation entry/authority routing; no automatic cache/index/agent roster expansion.

## Parking lot

No accepted finding is deferred from implementation. Windows-specific execution and physical acceptance require a suitable Windows host and prepared pinned runtime; these are explicit evidence limits, not substituted by portable tests. Existing transcoding/HDR/product plans and earlier deferred review packages remain outside this task.
