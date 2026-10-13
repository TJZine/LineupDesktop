# Lineup Desktop Test Inventory and Slimming Process Review

Prepared October 2, 2026 for the maintainer and Claude Opus. Source snapshot:
`575ab62cdb4818517478987697df025aa516d1be` on
`dev/testing-user-visible-standards`.

This is a read-only review of tests and their production flows, plus a proposal
for Opus to critique. No tests were deleted or rewritten, no production code or
test infrastructure changed, and no test suite or mutation was executed. The
only repository additions from this review are this report and its inventory
attachments. There is no deletion approval or measured savings estimate here.

The main recommendation is to slim by observable behavior and demonstrated
redundancy, using the strongest feasible proof in this desktop stack. Existing
real-widget, filesystem, transport, isolate, and native-contract tests are
valuable owners. A mandatory new executable E2E harness would be a separate
engineering project, not a prerequisite for adjudicating the clearest overlaps.
Conversely, the absence of a harness does not establish that desktop E2E is
infeasible.

## Standards and evidence boundaries

Read `AGENTS.md`, `.agents/skills/flutter-test-design/SKILL.md`, relevant sections
of `docs/DEVELOPMENT.md` and `docs/architecture.md`, and
`docs/windows-native-validation.md`. The maintainer's global
`test-suite-slimming` skill supplies the full process; its Python commands and
coverage-context assumptions must be adapted rather than copied into Dart.

The maintainer specifically approved these repository adaptations:

- Prefer real-app E2E when feasible. For desktop behavior impractical to
  automate, use the strongest real-widget/public-contract owner and state the
  remaining physical acceptance.
- Avoid low-value tests regardless of E2E feasibility. Apply the four-question
  gate, one owner per behavior, the flow rule, isolated-test categories, and
  mutation-proven distinct cases.
- Keep the always-loaded `AGENTS.md` Testing body to six single-line rules,
  ending with the instruction to load the canonical skill.
- Do not enforce coverage percentages. No floor was found in this repository.

In this report, **observed** means found in source/configuration; **candidate**
means a source-supported hypothesis requiring adjudication; **unknown** means
not established by this review. A test containing an internal assertion can
still protect a valuable behavior. Candidate assertion cleanup and whole-test
deletion are different decisions.

## Inventory and reproducibility

[inventory.json](inventory.json) records every suite's physical lines, ordinary
and widget registration sites, assertion sites, platform annotations, support
files, source-file denominator, and snapshot SHA.
[test-declarations.tsv](test-declarations.tsv) records every discovered Dart
`test`/`testWidgets` call with its file, line, kind, and unexpanded name expression.

The inventory used tracked files ending in `_test.dart` or `_test.cpp`. Counts
come from static call-site searches, not Dart AST analysis or runtime collection.
Loops and name interpolation can create several executed cases from one site;
some loops occur inside one test. Assertion sites include shared helpers and
are not counts of assertions executed. This is a complete mechanical inventory
under that file/call-site definition, not the global skill's completed ledger
of every collected node and assertion classification.

| Metric | Observed value |
| --- | ---: |
| Test files | 46: 42 under `test/`, 3 under `tool/visual/`, 1 native C++ |
| Ordinary Dart `test` registration sites | 530 |
| Dart `testWidgets` registration sites | 344 |
| Total Dart registration sites | 874 |
| Static `expect`/`expectLater`/`assert` sites | 3,920, including 39 C++ assertions |
| Test-suite physical lines | 43,544 |
| Shared support/development-harness files and lines | 3 files, 445 lines |
| Test plus support lines | 43,989 |
| Application source files and lines | 50 files, 37,819 lines |
| Test/support to application-source line ratio | 1.163:1 |

Lines include comments and blanks. Source means `lib/*.dart` recursively plus
Windows runner C++/headers and macOS runner Swift, excluding the native test.
Assets, bundled libraries, engine patch, PowerShell build scripts, generated
platform scaffolding outside those runner paths, and documentation are excluded.
The ratio describes maintenance surface; it is not a deletion target.

Five suites account for 23,920 lines, about 55% of suite lines:
`lineup_controller_test`, `channel_studio_view_test`, `player_view_test`,
`player_coordinator_test`, and `plex_transport_test`. This concentration suggests
where ownership mapping and fixture simplification could matter most, but does
not imply that their failure cases are redundant.

### Every test suite

| Suite | Lines | `test` sites | `testWidgets` sites | Assertion sites | Host |
| --- | ---: | ---: | ---: | ---: | --- |
| `test/app/channel_air_check_test.dart` | 1,234 | 0 | 24 | 126 | portable Flutter |
| `test/app/channel_studio_view_test.dart` | 4,903 | 1 | 66 | 426 | portable Flutter |
| `test/app/channels_view_test.dart` | 317 | 0 | 5 | 26 | portable Flutter |
| `test/app/desktop_diagnostics_test.dart` | 142 | 0 | 3 | 18 | portable Flutter |
| `test/app/desktop_native_audit_test.dart` | 253 | 0 | 3 | 19 | portable Flutter |
| `test/app/desktop_navigation_test.dart` | 204 | 0 | 6 | 27 | portable Flutter |
| `test/app/desktop_onboarding_test.dart` | 383 | 0 | 9 | 30 | portable Flutter |
| `test/app/desktop_settings_test.dart` | 174 | 0 | 2 | 21 | portable Flutter |
| `test/app/desktop_setup_test.dart` | 1,015 | 0 | 15 | 108 | portable Flutter |
| `test/app/form_error_test.dart` | 32 | 1 | 0 | 7 | portable Flutter |
| `test/app/guide_opacity_test.dart` | 182 | 0 | 2 | 2 | macOS only |
| `test/app/lineup_app_test.dart` | 1,712 | 0 | 39 | 154 | portable Flutter |
| `test/app/lineup_controller_test.dart` | 5,386 | 92 | 0 | 575 | portable Flutter |
| `test/app/product_spine_test.dart` | 511 | 1 | 0 | 44 | portable Flutter |
| `test/app/theme_shell_test.dart` | 344 | 0 | 12 | 52 | portable Flutter |
| `test/app/ui_fixture_encapsulation_test.dart` | 20 | 1 | 0 | 3 | portable Flutter |
| `test/app/ui_parity_test.dart` | 180 | 0 | 4 | 21 | portable Flutter |
| `test/app/ui_review_regression_test.dart` | 1,137 | 0 | 18 | 71 | portable Flutter |
| `test/channels/channel_builder_test.dart` | 1,204 | 31 | 0 | 101 | portable Flutter |
| `test/channels/content_resolver_test.dart` | 884 | 28 | 0 | 74 | portable Flutter |
| `test/channels/schedule_worker_test.dart` | 246 | 5 | 0 | 13 | portable Flutter |
| `test/channels/scheduler_test.dart` | 497 | 13 | 0 | 51 | portable Flutter |
| `test/diagnostics/diagnostics_test.dart` | 215 | 8 | 0 | 43 | portable Flutter |
| `test/guide/focused_ticker_test.dart` | 153 | 0 | 6 | 15 | portable Flutter |
| `test/guide/guide_controller_test.dart` | 1,636 | 46 | 0 | 149 | portable Flutter |
| `test/guide/guide_view_test.dart` | 1,854 | 2 | 25 | 170 | portable Flutter |
| `test/persistence/app_store_test.dart` | 883 | 21 | 0 | 101 | portable Flutter |
| `test/playback/native_video_surface_test.dart` | 111 | 0 | 1 | 3 | portable Flutter |
| `test/playback/player_coordinator_test.dart` | 4,613 | 89 | 15 | 385 | portable Flutter |
| `test/playback/player_track_label_test.dart` | 423 | 20 | 0 | 56 | portable Flutter |
| `test/playback/player_view_test.dart` | 4,741 | 0 | 80 | 479 | portable Flutter |
| `test/playback/unsupported_native_player_test.dart` | 19 | 1 | 0 | 4 | portable Flutter |
| `test/playback/windows_native_player_encapsulation_test.dart` | 71 | 1 | 0 | 3 | portable Flutter |
| `test/playback/windows_native_player_test.dart` | 1,594 | 34 | 1 | 132 | portable Flutter |
| `test/plex/plex_io_transport_test.dart` | 69 | 1 | 0 | 1 | portable Flutter |
| `test/plex/plex_parser_test.dart` | 447 | 13 | 0 | 64 | portable Flutter |
| `test/plex/plex_transport_test.dart` | 4,277 | 105 | 1 | 245 | portable Flutter |
| `test/settings/lineup_settings_test.dart` | 93 | 6 | 0 | 12 | portable Flutter |
| `test/support/ui_fixture_test.dart` | 37 | 2 | 0 | 2 | portable Flutter |
| `test/ui/app_theme_test.dart` | 134 | 6 | 0 | 30 | portable Flutter |
| `test/ui/clear_logo_image_test.dart` | 75 | 0 | 1 | 4 | portable Flutter |
| `test/ui_harness_test.dart` | 50 | 2 | 0 | 3 | portable Flutter |
| `tool/visual/guide_sparse_golden_test.dart` | 159 | 0 | 2 | 6 | macOS only |
| `tool/visual/player_track_label_visual_test.dart` | 307 | 0 | 1 | 1 | macOS only |
| `tool/visual/ui_acceptance_golden_test.dart` | 302 | 0 | 3 | 4 | macOS only |
| `windows/runner/track_list_encoder_test.cpp` | 321 | 0 | 0 | 39 | Windows CTest |

The support files are `test/support/ui_fixture.dart` (174 lines),
`test/support/golden_test_support.dart` (56), and
`test_driver/ui_harness.dart` (215). The harness is a runnable synthetic
development composition root, not an automated E2E driver.

## What actually runs and what it proves

The pinned toolchain is Flutter 3.47.4 at
`9584c6713b324636289d067944a46fd6b49df14b`, with Dart 3.13.3. The locally resolved
SDK matches that Flutter revision. This review inspected the pinned
`flutter test --help`; it exposes name filters, JSON file reporting, local line
and branch coverage, explicit timeout, and random ordering. It exposes no
collection-only/list-tests option in the inspected help. No SDK/dependency
installation or update was performed.

| Tier | Existing execution | Evidence and limitations |
| --- | --- | --- |
| Portable Dart/widget owners | `TZ=America/New_York flutter test` | Real Dart owners and Flutter test widgets; many controller/native/HTTP substitutes. Linux CI runs this after format/analyze. Not executable/native playback proof. |
| Cross-owner portable spine | `TZ=America/New_York flutter test test/app/product_spine_test.dart` | Real controller, `FileAppStore`, Guide, worker, coordinator; fake Plex/credentials/native player. No real app launch, Channel Builder journey, or rendered UI. |
| Real transport connection close | `TZ=America/New_York flutter test test/plex/plex_io_transport_test.dart` | Loopback socket observes peer disconnect before client teardown; two modes from one declaration. Distinct from fake status/cancellation evidence. |
| Required Guide pixel alpha | `TZ=America/New_York flutter test test/app/guide_opacity_test.dart` on macOS | Two cases on real Flutter renders; opaque Guide and PiP-aperture alpha. macOS CI executes them; no moving native video. |
| Optional design snapshots | Explicit `tool/visual/ui_acceptance_golden_test.dart` and `guide_sparse_golden_test.dart` on macOS | Five representative exact snapshots; outside default test tree and required CI. Pinned Roboto aliases are not Windows font validation. |
| Track-label design evidence | Explicit `tool/visual/player_track_label_visual_test.dart` on macOS | One registration paints eight combinations: two viewports, bright/dark synthetic video, audio/subtitles. Uses existing evidence-path baselines; not part of the five representative snapshots or required CI. |
| Windows Dart/UI CI | `ui_parity_test`, `guide_view_test`, `player_view_test` | Focused Windows widget subset; CI does not run every portable suite on Windows. OS timezone matters for localized assertions. |
| Native encoder | Explicit CMake target followed by CTest | Real C++ encoder, fabricated `mpv_node` inputs, no live mpv. Target is `EXCLUDE_FROM_ALL`; current CI does not build/run it. |
| Package/release policy | `pwsh -File ./tool/windows/verify-release-policy.ps1`; conditional patched-engine/package CI checks | Script policy, artifact/provenance rejection and packaging. These checks are outside the Dart/C++ registration/line inventory. They do not launch the packaged app. |
| Actual media/presentation | Existing physical Windows acceptance procedure | Exact-commit playback, layering, HDR, fullscreen, DPI, focus/input, tracks/audio and packaged runtime. No automated checked-artifact real-app harness currently exists. |

`flutter analyze` includes `test/`, `test_driver/`, and `tool/visual/`; the
analyzer excludes generated/native platform trees, not Dart tests. Typed
interfaces and real models predominate. Some raw JSON casts and dynamic platform
arguments remain; inclusion in analysis is not proof that every fake is strict
or that every cast has been justified. No analyzer run was performed here.

There is no coverage gate in the workflow/configuration and no test pinning one.
Flutter coverage remains available locally. Native assertion execution in
Release is deliberately enabled in `track_list_encoder_test.cpp:3`.

## Existing owners to protect

| Behavior | Strong existing proof | Why broader-looking tests do not automatically replace it |
| --- | --- | --- |
| Backup, migration, corruption and failed-write preservation | `test/persistence/app_store_test.dart:10`, `:36`, `:65`, `:718`, `:767`, `:791` | Uses real bytes/files and distinguishes transient I/O from corruption. A memory-store/widget test cannot prove original-byte preservation. |
| Controller transactions and credential/scope ordering | `test/app/lineup_controller_test.dart:3875`, `:4052`, `:4079`, `:4276` | Store writes, controller snapshots and credential writes are separate queues. Similar epochs/status outcomes do not make the races interchangeable. |
| Active HTTP abort and fatal sibling cancellation | `test/plex/plex_io_transport_test.dart:10`; `plex_transport_test.dart:2095`, `:2222`, `:3700`; controller `:2711` | Stale-result rejection, cancellation status, native cleanup and actual socket release are distinct outcomes. |
| Exact schedule boundary and legacy continuity | `test/channels/scheduler_test.dart:35`, `:238`, `:288`, `:453` | Independent time/media outputs protect shared arithmetic; cross-owner comparisons using the same scheduler cannot detect common defects. |
| External parser and security/trust boundaries | `test/plex/plex_parser_test.dart:117`, `:293`, `:390`; transport `:171`, `:787`, artwork group `:810` | External data and credential/host validation remain per-branch edges. Own-data malformed-branch consolidation does not apply wholesale. |
| Guide demand, capacity release, cache invalidation | `test/guide/guide_controller_test.dart:409`, `:437`, `:463`, `:828`, `:876`; view `:259` | Queue admission, active load timeout, stale completion, tune priority and visible bounded work are different failure mechanisms. |
| Worker transport/lifetime | `test/channels/schedule_worker_test.dart` | Real isolate send/exit/restart and transition roundtrip; replacing it with synchronous scheduling misses boundary failures. |
| Native load/track/stop identities and confirmed idle | `test/playback/windows_native_player_test.dart:502`, `:571`, `:897`, `:1058`, `:1105`, `:1197`, `:1283`, `:1570`; coordinator `:21`, `:114` | Command acceptance is not readiness or idle. Mocked native events do not prove C++/mpv cleanup, but are meaningful Dart contract proof. |
| C++ metadata projection | `windows/runner/track_list_encoder_test.cpp:63`, `:154`, `:216` | Real encoder catches producer faults that a fake MethodChannel cannot; decoded metadata reaches track labels/selection. Native mpv input is external data. |
| Settings UI persistence/reload | `test/app/theme_shell_test.dart:16` | UI selection, inherited save, stored state and rebuilt app are stronger than a copied enum/default constant. |
| Keyboard focus and semantics | `test/app/desktop_navigation_test.dart:10`, `:175`; channels `:229`; player view `:1970`, `:2509` | Real key/semantics interaction and actionability protect accessibility. Framework field assertions alone are weaker; physical Windows input/AT still needs platform evidence. |
| Guide alpha and native surface bounds | `test/app/guide_opacity_test.dart:33`, `:42`; `test/playback/native_video_surface_test.dart:7` | Actual pixels and logical-to-physical geometry matter to native aperture behavior. Neither establishes actual composition or moving video. |
| Diagnostic export privacy | `test/diagnostics/diagnostics_test.dart:132`, `:187`; `test/app/desktop_diagnostics_test.dart:50` | Harmless-looking secret sentinels, report content and clipboard outcome are user-visible security/output contracts. |

## Candidate ledger for Opus

These are prioritized hypotheses, not an exhaustive classification of every
assertion. Each proposed mutation is unexecuted. Preserve distinct cases until
the old test and proposed retained owner have been compared against the same
fault. Source-line references apply to the snapshot above.

### Small pilot candidates

1. **Native snapshot duplicate.**
   `test/playback/windows_native_player_encapsulation_test.dart:12` checks that
   one track list rejects `clear`. `windows_native_player_test.dart:208` already
   checks current/event/old snapshot immutability and old facts across replacement.
   Both route through `List.unmodifiable` in
   `lib/playback/windows_native_player.dart:518`. Proposed mutant: return a
   mutable decoded list. This is the clearest bounded whole-test duplicate
   candidate, but it has not been proven by execution.

2. **Menu overlap across historical suite boundaries.**
   `test/app/ui_parity_test.dart:11` overlaps menu containment/focus restoration
   in `desktop_navigation_test.dart:10`. Proposed owner: navigation, retaining
   any unique route/accessibility cases. Mutants: allow Tab to escape or omit
   focus restoration; confirm text-scale variants remain protected.

3. **Mislocated Guide tests.**
   `test/guide/guide_controller_test.dart:30` constructs no Guide and checks a
   1,000-channel controller plan. Controller plan owners at
   `lineup_controller_test.dart:1073`, `:1141`, `:1166` and the disk-backed
   spine at `product_spine_test.dart:168` offer stronger destinations. Mutants:
   truncate applied plans; choose the wrong fallback channel. The spine does
   not cover the small replacement fallback, so cardinality alone is insufficient.
   Guide `:634` also checks controller worker creation/reuse, overlapping
   controller `:3609`; distinguish observable bounded resources/cache identity
   from a construction-count assertion before deciding its fate.

4. **Source grep and synthetic helper proof.**
   `test/app/ui_fixture_encapsulation_test.dart:6` scans production source for
   two strings; a comment can fail it and a renamed fixture path can evade it.
   It checks no shipped route/artifact. Two `ui_fixture_test.dart` tests and two
   `ui_harness_test.dart` tests exercise substitute stream/lifetime behavior.
   They might protect trustworthy consumers; do not call them proven junk.
   Mutate broadcast to single subscription or remove disposal/supersession
   guards, then inspect whether retained widget/harness consumers already fail.
   The runnable development harness is a real consumer outside `lib`, so its
   helper is not automatically unused production code.

5. **Local builder truncation overlap.**
   `test/channels/channel_builder_test.dart:710` and `:802` both exercise series
   expansion overflow; the latter also distinguishes exact completion. Proposed
   owner: one exact/overflow case matrix. Mutants: use `>=` instead of `>` or
   apply the cap before expansion. Preserve exhaustion at `:834` separately.

### Larger clusters needing a behavior map

6. **Program-owned state malformed-branch repetition.**
   `test/persistence/app_store_test.dart:485–598` has five schema tests with
   multiple invalid branches; `:608–715` has ten quarantine/restart cases.
   Settings `:75` and content-resolver serialization cases at `:708`, `:744`,
   `:761` add related refusal matrices. Classify by refused decode/write,
   quarantine, unavailable startup, original-byte preservation and restart,
   not one test for each malformed field. Preserve artwork/security checks,
   cache identity, migration compatibility, real I/O failure distinctions and
   user-edited/imported input. Opus must decide the ingress boundary: a file
   normally written by the app can also be deliberately edited or imported.
   R2 must not erase a documented user-input/schema contract by assumption.

7. **Track-label common outputs duplicated below actual widgets.**
   `player_track_label_test.dart:50–137`, `:205`, `:379` overlaps audio/subtitle
   output and semantics in `player_view_test.dart:1900`, `:1972`, `:2314`.
   Move ordinary shared outputs to one owner only after comparable mutants fail
   both. Keep unique aliases, contradictory channel layout/count, unknown
   codec/language, peer discrimination and title deduplication when they kill
   faults the widget owner does not. Pure formatter output is user-visible,
   so pure tests are not low value by definition.

8. **Theme/settings/PIN proof dispersed among UI suites.**
   Theme dropdown cases in `theme_shell_test.dart:71`, `:104`,
   `desktop_settings_test.dart:20`, save busy/failure cases in
   `ui_review_regression_test.dart:605` versus theme `:175`, and PIN focus in
   review `:643` versus onboarding/app input owners deserve mapping. Palette,
   persistence, focus rollback, keyboard digits and semantics-button activation
   are distinct outcomes. Separate those before consolidating suite history.

9. **Generated recipe preservation and builder/controller overlap.**
   `ui_review_regression_test.dart:417` overlaps Studio `:179`;
   `channel_builder_test.dart:955` overlaps controller `:1106`, `:1166`.
   Candidate mutations: overwrite a generated source on metadata save, clear
   `builderKey`, lose seed/block size, drop custom channels during replace, or
   alter append/merge ordering. Do not collapse source/mode cases without a
   mutation that demonstrates their equivalence. `same(existing)` assertions
   in builder `:596`, `:876`, `:1129` need an observable identity/cache consequence.

10. **Prefetch/generation assertions that need stronger consequences.**
    Guide `:904` pins an eight-ID start sequence, but also guards preserving
    explicit/focused demand while pruning old viewport work. Guide `:876` owns
    tune priority. Preserve bounded tune readiness and newest visible output;
    consider dropping incidental order only after starvation/stale-demand
    mutants are caught. Coordinator `:1632` checks generation monotonicity with
    a skipped tune; `:1564` is a stronger stale-event/status owner. Consolidate
    only if the skipped-dispatch sequence still rejects old media events.

### Weak proof to repair or narrow, not blindly delete

11. **Production-derived expected values.**
    The spine computes `expectedProgram` with real `programAt` and schedule
    loading at `product_spine_test.dart:82`, then compares Guide/player outputs.
    Guide geometry at `guide_view_test.dart:577` uses production policy to
    calculate expected width. Serializer roundtrips in settings `:13` and
    content resolver `:622`, `:683`, `:761` share the serializer/parser family.
    These can detect wiring/transport inconsistency but miss a common arithmetic
    or symmetric field-loss defect. Prefer independent fixture literals for the
    output contract. Do not automatically delete worker-vs-synchronous schedule
    equality (`schedule_worker_test.dart:120`): it legitimately proves isolate
    transport fidelity, while separate scheduler owners prove arithmetic.

12. **Positive-only filters and wrong-command false negatives.**
    Content resolver `:130` supplies only matching fixtures for several filter
    rows and checks length two; removing an actor/studio/director predicate can
    leave those rows passing. A nonmatching control is needed at the owner if no
    existing owner catches the mutant. Player-view aliases at `:112` check four
    transport commands in total; a wrong command can preserve that total.
    Recording actual command/target at the existing native boundary would prove
    more. These are specific gaps, not evidence to discard the whole behavior.

13. **Permissive HTTP mocks.**
    The PIN owner in `test/plex/plex_transport_test.dart:146` checks identity and
    token absence, but its mock accepts every verb/path; mutating `createPin`
    (`lib/plex/plex_client.dart:59`) from POST `/api/v2/pins` can still satisfy
    this test. Tighten the existing transport owner to reject unexpected requests
    before treating it as full request proof. Similar broad fallback handlers
    recur. `UiFixture`'s HTTP boundary already rejects unexpected traffic.
    Request bytes and paging offsets at this real boundary are observable
    contracts, not private fake call shape.

14. **Copied inventory and property assertions.**
    `test/ui/app_theme_test.dart:7`, `:17`, `:107` pins labels, palette constants
    and equality details; contrast at `:38` protects real accessibility output.
    Settings `:8` copies the Guide-hour options. Player view `:3352` mixes useful
    metadata/design proof with exact font/shelf/image/request details. Classify
    assertion by assertion against approved UI contracts; do not delete protected
    alpha, focus, semantics, readable geometry or an actual visible theme choice.
    Framework-consumed equality/overrides are not unused just because `rg` finds
    no explicit direct production call.

15. **Private spine event order and simulated track selection.**
    Spine `:221` checks private event-log order. Stage/persisted outcomes can
    provide stronger proof. Its selected-track assertion at `:136` sees the
    fake's recorded request (`:469`), not native confirmation. Keep request
    dispatch and token-free URL/PMS-token routing; use coordinator track-result
    and actual PlayerView semantics owners for confirmed selection.

## Test-only production seams and hygiene

Observed caller evidence warrants a later, separately authorized seam audit:

- `lib/app/channel_air_check.dart:101–102`: `activeRequestCount` and
  `pendingRequestCount` callers were found only in `channel_air_check_test`.
  The tests also check latest visible programs/errors. Remove introspection
  dependence only while preserving supersession and bounded-work behavior.
- `lib/playback/player_track_label.dart:21`: `PlayerTrackDisplay.secondaryText`
  is used by `player_track_label_test.dart:387`; production PlayerView joins
  `secondaryFacts` itself. Other similarly named references are theme fields.
  This is a concrete test-only convenience-symbol candidate.
- `FileAppStore(clock:)` at `lib/persistence/app_store.dart:154` is supplied by
  tests; production `create()` supplies the default. Clock substitution is also
  an allowed heavy boundary. Opus should resolve this policy tension rather
  than deleting valuable quarantine/collision outcomes automatically.

Do not infer that all injection interfaces are illegitimate. `NativePlayer` is
a real platform seam. Widget framework hooks, platform callbacks, exported
native consumers and interface dispatch require caller analysis beyond text
search. Existing optional test seams need a bounded audit, not speculative
replacement abstractions.

Hygiene findings are future repair candidates, not deletion evidence:

- Controller/spine polling helpers have five-second bounds, but coordinator
  MethodChannel loops at `player_coordinator_test.dart:52`, `:72` have no local
  deadline. Several setup/player/app handshakes await completers without an
  explicit per-wait timeout. The runner's enclosing deadline remains a safety
  net; it is not the new standard's explicit bound on every wait.
- Default `pumpAndSettle()` is bounded by Flutter, but its default may be too
  generous for a failed handshake; repeating timers can never settle. Prefer
  controlled completers/fake-clock pumps and explicit bounds at actual waits.
  Not every `await` needs ceremonial `.timeout` wrapping.
- Wall-clock PIN waits and fixed image-decoding delays are candidates for
  existing controlled/condition-aware techniques; do not add production hooks
  merely to replace a few sleeps.
- Some direct-widget fixtures dispose only after the last assertion. Register
  teardown before assertions when owning timers, streams, workers or static
  channel state. Player-view `_Fixture.dispose` at `:4377` does not close the
  fake native stream; inspect ownership before adding redundant cleanup.
- The native CTest registration has no `TIMEOUT` property. Current documented
  invocation supplies `--timeout 30`. CI's job timeout is not a subprocess
  completion contract.
- Typed fakes are common; raw `as Map` casts in content-resolver JSON setup and
  `MethodCall.arguments` dynamic access deserve local improvement if touched.
  Do not turn this into a typing-framework migration.

## E2E feasibility for this stack

The existing spine is useful cross-owner integration, and `UiFixture` renders
production `LineupBootstrap`. Neither launches the production entry point with
real native playback. Setup/Studio fake-controller overrides sometimes implement
the very apply/save operation being asserted (`desktop_setup_test.dart:959`,
`channel_studio_view_test.dart:4568`, `:4673`), so a broad-looking widget journey
can be weaker than a focused real-controller/filesystem owner.

The smallest credible portable improvement would reuse real owners, generated
channel fixtures, strict HTTP fixtures and real temporary persistence where
possible, plus production widget input for UI claims. Do not widen the spine
into a giant snapshot of every internal field. Strengthen it only for a specific
currently missing user-visible owner, and avoid new flags/injection parameters.
This is a proposed direction, not a harness design approved for implementation.

Windows E2E is expensive, not proven impossible. The production entry point
already accepts `--media=` (`lib/main.dart:31`), and the launcher exposes
`-MediaPath`; generated local media could support a future executable smoke
without a new test-only flag. This review did not demonstrate launch, isolation,
driver/control, checked frame/track output, bounded shutdown, or artifacts.
The command alone is not an automated test.

Actual Lineup playback requires the pinned DirectComposition engine patch,
prepared libmpv, Windows tooling and suitable runtime hardware. Stock-engine CI
builds compile/link the app but do not establish a usable player; initialization
rejects missing patch provenance. macOS intentionally reports unsupported media.
Plex credentials, private media, display/HDR judgments and physical input add
constraints that are absent from a typical headless CLI E2E recipe.

Ask Opus to choose separately among: portable real-owner/widget integration,
gated Windows executable/local-media smoke, and operator-run physical acceptance.
Physical video layering, HDR, monitor/DPI/fullscreen, physical input/AT and
audible/rendered track correspondence retain exact-commit evidence requirements,
even if a smoke harness is later built. No Docker/browser dependency is justified
by the current application architecture.

## Proposed repo-specific slimming process

1. **Agree the evidence tiers and boundaries.** Opus should critique this report
   and identify the smallest pilot. Do not begin a harness project or bulk
   deletion as a side effect of accepting the testing standard. Resolve the
   program-owned/user-edited state boundary and existing clock-seam tension.

2. **Record an executable baseline.** In a dedicated source-clean branch or
   checkout, use the pinned SDK and existing dependencies. Run format/analyze
   and the portable suite with JSON file reporting and explicit test timeout.
   Capture expanded names/counts, skipped platform cases, failures and durations.
   A second baseline run is useful for a suspected nondeterministic cluster,
   not a ritual for every unchanged test. Add required macOS alpha when available;
   run native CTest explicitly on Windows. Do not infer platform passes from
   one host or make local visual baseline updates part of pruning.

3. **Create a behavior ledger for the pilot.** Map each expanded test/case and
   assertion to an output, current owner, source branch/failure, fake boundary
   and keep category. Record what the owner actually executes. Use `owner`,
   `edge`, `failure`, `contract`, `network`, `security`, `platform`, E2E/runtime
   proof and unresolved decisions; cite field/contract evidence. Do not use
   suite names, line count, coverage percentage or number of assertions as value.

4. **Pilot bounded, plausible duplication.** Start with native snapshot
   immutability, menu overlap or builder truncation. These do not need a new
   harness. Compare old candidate and proposed retained owner against each
   relevant minimal mutant, individually. Distinct mutants keep distinct cases.
   Then assess the source-grep/helper cases separately. This can reveal whether
   the process is useful before mapping all 43k test lines in detail.

5. **Serialize source mutations and edits.** Parallel read-only inventory can
   use bounded lanes; mutation/test runs sharing a checkout must be serial.
   Establish a staged-safe clean source baseline, restore only the deliberate
   mutation, and verify restoration. A compiler/linker/suite-load error or runner
   crash is not a killed behavior mutant. A hang mutant needs a bounded
   completion/peer-close assertion, not a long CI job timeout.

6. **Use stack-native coverage as a diagnostic.** Flutter's local
   `--coverage`/`--branch-coverage` emits LCOV; it is not the Python skill's
   per-test `coverage.py` contexts. When attribution matters, run an exact
   expanded name with a separate coverage path. Compare before/after source
   line/branch records; lost production paths need an explained dead-seam
   removal, same-block mutation whose owner failed, or adjudicated own-data
   consolidation. Otherwise keep the uncertain test. Flutter coverage does not
   measure the C++ encoder/native engine, so native mutations require its own
   explicit compile/run proof. Add no percentage gate or mutation dependency.

7. **Delete only proven redundancy, then consolidate.** Keep a case-mapping
   table from original expanded names to retained row/assertion. Distinguish
   whole-test removal, assertion trimming, oracle repair, fixture simplification
   and production-seam removal. Preserve carriers of media/time/identity/token/
   filename/warning/cache values. Fix weak proof at the existing real boundary
   rather than writing another test of the same behavior.

8. **Expand by outcome, not by largest file.** Next assess own-state refusal/
   recovery matrices and common track outputs, then dispersed settings/PIN/recipe
   owners. Treat controller transaction, multipart, transport and native
   identity races as a later protected fault matrix. Reduce duplicate setup
   before collapsing materially different races. External paging/metadata,
   security and actual resource-release cases retain discriminating edges.

9. **Verify and close each slice.** Run focused retained owners, format/analyze,
   relevant full portable checks and changed visual/native tiers. Record the
   removed cases, retained owner, mutant outcomes, coverage limits and unresolved
   physical evidence. Small coherent commits make restoration/review practical.
   Do not push, publish, alter UI direction or change release gates without
   separate authorization. The native CTest CI omission and real-app feasibility
   work deserve separately scoped decisions rather than being hidden in pruning.

Suggested baseline commands, to run in the later approved process, not results
observed by this review:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
mkdir -p build/test-slimming
TZ=America/New_York flutter test --timeout=60s --file-reporter=json:build/test-slimming/baseline.json
TZ=America/New_York flutter test --branch-coverage --coverage-path=build/test-slimming/before.lcov
```

Use JSON-expanded names for targeted mutation runs. `--plain-name` is substring
matching, so use a properly escaped, anchored `--name` expression when one exact
case is required; confirm the number/names actually executed. Choose an explicit
timeout appropriate to the cluster rather than disabling timeouts.

On macOS, run the required alpha owner and explicit optional visual suites only
when relevant. On Windows, after the documented project/runtime configuration:

```powershell
cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test
ctest --test-dir .\build\windows\x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30
```

The native encoder needs the configured Windows project and Flutter wrapper/mpv
headers, but not a live media instance or an executed patched player. Actual
media acceptance needs the full patched runtime and physical evidence procedure.

## Questions and prompt for Claude Opus

The requested next step is independent feedback on the process and classification,
not implementation. A suitable forwarding prompt follows:

> Read this report, its two inventory attachments, `AGENTS.md` and the canonical
> Flutter Test Design skill. Give a read-only critique of the proposed
> LineupDesktop slimming process. Check source for the highest-risk or weakest
> claims; distinguish observed facts from unproven candidate deletions. Do not
> delete tests, edit production code/rules, add dependencies, build a harness,
> update golden baselines or commit during this feedback pass.
>
> Recommend the smallest first pilot, its strongest retained owners, concrete
> discriminating mutants, stop conditions and verification commands. Explain
> which tests should remain isolated in this Flutter/native-media stack and
> whether any real-app E2E work is needed before the pilot. Address:
> (1) own-state versus user-authored/imported schema edges; (2) clock injection
> versus test-only production seams; (3) real-widget tests that fake the controller
> operation under test; (4) aggregate Flutter LCOV versus per-case attribution;
> (5) native producer/consumer and physical Windows evidence; (6) the encoder
> CTest CI gap. Challenge production-derived oracles without discarding useful
> wiring/transport equivalence proof. Give a short proposed sequence for the
> first two or three slices, estimated effort/risk, and uncertainties that need
> baseline execution. Do not set a percentage/count/line-deletion target.

Specifically requested decisions:

- Is the native snapshot/menu/builder pilot preferable to beginning with the
  larger own-state/schema cluster, and why?
- Which pure scheduler/formatter/parser owners are the strongest practical
  proof, even when a widget can display their output?
- Can the existing real-owner spine be strengthened without faking the
  operation under test or introducing test-only production code?
- What minimal gated native smoke could be credible using existing `--media=`
  input, and which outcomes must remain physical acceptance?
- Should the source-grep/helper tests be removed, retained as narrow support
  integrity exceptions, or replaced by stronger existing consumer proof?
- Which candidate seams are truly unnecessary versus real external-boundary
  injection? Do not infer dead code from missing direct text callers alone.
- What evidence is sufficient for a safe deletion when native coverage or
  per-test coverage contexts are unavailable?

Independent Opus review is specifically recommended before any deletion. This
report intentionally leaves baseline pass counts, dynamic case counts, timings,
flakiness, actual mutation kills, local coverage losses and exact-commit physical
runtime validation unknown.
