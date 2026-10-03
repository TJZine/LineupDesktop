# Lineup Desktop project profile

This is the repository-specific reference for the shared `develop-code`,
`design-code`, `review-code`, and `verify-code` skills. Read the sections
relevant to the task. It does not prescribe a model, a fixed agent roster, or a
sequence of review gates.

Recheck the referenced commands, owners, and active branch for the current
task. The paths below are starting points, not permanent restrictions on an
authorized redesign.

## Current planning and verification status

The [Plex transcoding plan](../docs/plex-transcoding-implementation-plan.md)
records product decisions settled on October 3, 2026 and bounded P0
observations. Production implementation remains pending: P1 starts after P0b
stream-selection and true-remote evidence. Settings design agreement, protected
Player proposals, and confirmation of the Remote default before P4 remain
required. Consult the plan for current decisions and acceptance gates rather
than treating its recorded headless observations as integrated Lineup support
or physical acceptance. Workflow maintenance does not implement the plan,
approve UI changes, or authorize P1. Recorded source/runtime identities and
limits remain intact. A historical independent-review recommendation is
evidence of that assessment, not a permanent ban on future focused review.

The authenticated-reference positive controls now require both playback
progress and absence of a later rejection. Earlier passes of weaker assertions
do not establish that stronger claim. Preserve the current production
reference restrictions, the corrected existing checker, and the applicable
physical Windows acceptance requirements. This instruction migration itself
does not claim a fresh native CTest or current package result.

## Product and domain

Lineup Desktop is a Flutter/Dart desktop application with a Windows C++/libmpv
media boundary. The macOS application is a development surface with explicitly
unsupported native playback. Electron history is provenance material, not an
application compatibility target.

Preserve the distinction between a product requirement and its current
implementation. In particular:

- Scheduled/current channel, selected library/server/profile, and active media
  load are different identities.
- Requested track selection, completed native command execution, and confirmed
  observed track selection are different states.
- An operation becoming obsolete, a content generation changing, and a native
  load/session retiring are different events. Preserve their semantics; an
  improved implementation need not retain the same counter or helper names.
- A successful save, a committed in-memory state, and successful credential
  cleanup are different obligations.

Read [current ownership](../docs/architecture.md#accepted-ownership) and
[async/persistence contracts](../docs/architecture.md#changing-asynchronous-and-persisted-state)
when those decisions matter. Use [the user guide](../docs/user-guide.md) for
intended user behavior and [the documentation index](../docs/README.md) for
unfamiliar areas.

## Architecture and current owners

| Concern | Starting points | Obligation to preserve |
| --- | --- | --- |
| Application policy, mutations, profile/server state | `lib/app/lineup_controller.dart` | Stale work cannot publish over current state; saves, rollback, and credential actions retain their ordering guarantees |
| Channel resolution and scheduling | `lib/channels/content_resolver.dart`, `scheduler.dart`, `schedule_worker.dart` | One authoritative deterministic schedule policy; measured expensive work stays off the interaction path where needed |
| Persisted state | `lib/persistence/app_store.dart` | Old valid data remains valid or has an explicit migration; recovery preserves original bytes; failed persistence must not masquerade as a commit |
| Plex boundary | `lib/plex/plex_client.dart`, `plex_models.dart` | Validate external values; cancel obsolete IO where possible; preserve authentication and redaction |
| Playback policy and state | `lib/playback/player_coordinator.dart`, `native_player.dart` | Dart owns product decisions; command acceptance is not observed playback or track confirmation |
| Dart/native transport | `lib/playback/windows_native_player.dart` | Typed bounded payloads, correct lifetime/load/stop correlation, late-event rejection, explicit cleanup |
| Windows media/presentation | `windows/runner/native_player.*`, `flutter_window.*` | Native owner manages libmpv and platform objects; platform-thread and worker-thread responsibilities remain coherent |
| Flutter surface and interaction | `lib/playback/native_video_surface.dart`, `player_view.dart`, affected `lib/app/` views | Flutter owns focus, semantics, input, overlays, and accessible interaction |

These are existing responsibility boundaries. A design proposal should explain
which maintenance burden disappears and how the same obligations are retained.
Do not freeze the exact queues, class decomposition, file count, or constructor
shape merely to match this table. A broad framework, event bus, dependency
layer, or parallel policy implementation needs a demonstrated current benefit.

The native media interface exists for a real platform boundary. A one-
implementation count does not invalidate that boundary. Keep documentation
that explains lifetime, thread, security, or timing contracts that types and
code cannot communicate adequately.

## UI changes

Use [the approved interface system](../.interface-design/system.md) and the
affected approved design record. Existing Player OSD and Now Playing layout
restrictions are product-design decisions. Workflow consolidation does not
supersede them.

For a requested departure, identify its effect and provide matched real-Flutter
before/after evidence at the relevant sizes. Distinguish visual approval,
widget/semantics verification, adaptive behavior, and physical Windows
acceptance. A golden update does not approve a new design.

Historical UI campaign handoffs may explain an approval or an old observation.
Do not import their model selection, worker allocation, dispatch ledger, or
review-group schedule into a new task.

## Verification selection

The shared `verify-code` skill owns the general test-selection method. Use the
least expensive trustworthy observation that addresses the changed risk.
Reuse existing suites when they cover it. A missing E2E driver is not a reason
to invent one during every task, and one behavior may need distinct evidence
at different boundaries. Do not remove existing protection without mapping the
obligation to retained evidence.

| Changed area | Existing evidence starting points | Limit |
| --- | --- | --- |
| Schedules/resolution | `test/channels/scheduler_test.dart`, `content_resolver_test.dart`, `schedule_worker_test.dart` | Deterministic contracts; inspect relevant inputs and clock assumptions |
| Mutations/currentness/credentials | `test/app/lineup_controller_test.dart`, `test/persistence/app_store_test.dart`, `test/plex/plex_io_transport_test.dart` | Controlled failures, late results, saved state, cancellation and transport; OS-specific behavior still needs platform evidence |
| Playback/native messaging | `test/playback/player_coordinator_test.dart`, `windows_native_player_test.dart`, `native_video_surface_test.dart` | Dart contracts and observed widget state, not real media output |
| Interaction/accessibility | Affected widget tests; `test/support/ui_fixture.dart` | Focus, semantics, layout; physical Windows input/assistive technology remain separate when claimed |
| Guide alpha | `test/app/guide_opacity_test.dart` on macOS | Required exact alpha behavior for the relevant Guide surface |
| Visual comparisons | `tool/visual/`, `test/support/golden_test_support.dart` | Optional explicit visual suites; inspect their host restrictions |
| Native encoding | `windows/runner/track_list_encoder_test.cpp` | Real encoder contract; opt-in CTest, not app or presentation proof |
| Authenticated references | `windows/runner/authenticated_reference_test.cpp`, `tool/windows/authenticated-reference-test.py` | Production initialization/load path against the prepared DLL with synthetic HTTPS; no physical Plex or presentation claim |
| Windows runtime/package | [Physical acceptance](../docs/windows-native-validation.md) | Record exact candidate, build/runtime identities, platform, display, scenario and result |

At the inspected revision, `test_driver/ui_harness.dart` is synthetic and
`test/app/product_spine_test.dart` uses fake Plex/native boundaries. CI does
not launch a real application E2E campaign. Neither native CTest is in the
default build or CI. Report their absence from a run accurately.

### Commands and prerequisites

Use the exact toolchain and native identities in
[Development](../docs/DEVELOPMENT.md#portable-commands) and
[Windows build metadata](../tool/windows/build-metadata.psd1). Do not copy
version pins into this profile. Run commands from the repository root.

Portable commands, selected according to the changed area:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

Use `dart format <changed-paths>` to format an edit and select affected test
files while iterating. Run the applicable full acceptance checks once before
completion when required. Reuse results until changed code, fixtures,
dependencies, build settings, or relevant environment invalidate them.

On macOS/Linux, the named timezone is used by localized schedule expectations.
On Windows, `TZ` alone does not change Dart's effective Windows timezone.
Record the actual OS timezone; do not silently change a user's system setting.
Use the documented Windows setup when canonical Eastern schedule expectations
are required.

Documentation-only work: `git diff --check`, affected links/examples, and
source/evidence claims. It does not require another product test run.

Native commands have additional prerequisites; consult
[the task verification map](../docs/DEVELOPMENT.md#verification-by-task) first:

- `flutter build windows` with the pinned SDK and prepared libmpv is a stock-
  engine compile/link check. It does not produce a usable native player.
- `pwsh -File .\tool\windows\run.ps1` is the repository development launcher
  after patched-engine and libmpv provisioning. It checks relevant identities
  and selects the intended engine.
- `pwsh -File ./tool/windows/verify-release-policy.ps1` checks package policy
  on a supported PowerShell host; it does not execute the Windows package.
- Native encoder and authenticated-reference CTest build/run commands are in
  [current test tiers](../docs/DEVELOPMENT.md#current-test-tiers-and-gaps).
  Select these for relevant changes rather than running them for every edit.
- Release builds use `tool/windows/build-release.ps1` and
  `tool/windows/package.ps1` with the documented clean-checkout, prepared
  runtime, and patched-engine inputs. Packaging is only within task scope.

### Native evidence and reuse

Physical Windows proof remains necessary for claims about native playback,
HDR, composition, fullscreen, input integration, and runnable packages.
Source, widget tests, synthetic media harnesses, screenshots, and compilation
establish different facts.

Record which commit/build was actually tested. A later code or runtime change
invalidates the affected result until rechecked. A prose-only later commit
does not create new physical evidence or erase the earlier observation:
carry it forward as explicitly attributed evidence only after establishing
that the relevant product/build inputs are unchanged. Do not relabel the old
run as a new candidate run. The release package still obeys its exact-artifact
provenance checks.

## Review emphasis and tools

Prioritize currentness/cancellation, atomic mutation and recovery,
credential isolation, native lifetime and thread ownership, track confirmation,
accessible focus, native presentation, and package provenance according to
the changed area. One reviewer can apply both requirements and standards
lenses; add a separate specialist only for a concrete uncovered risk.

Codanna is optional assistance for native owner/caller questions. The inspected
configuration does not supply Dart parsing, so use direct reads and `rg` for
Dart, and confirm important native results in source. A missing local Codanna
server does not block ordinary work.

Reuse bot findings as input to the same adjudication process. A bot assertion
or reviewer consensus is not evidence by itself. Trace the trigger, contract,
path, consequence, and proposed correction.

## Workflow maintenance

`AGENTS.md` owns entry and authority rules. This profile owns project-specific
routing. Existing architecture, development, design, and acceptance documents
own their technical details; shared skills own reusable process.

During explicitly requested workflow maintenance, use meaningful repeated
corrections to improve the responsible location or mechanism and remove
superseded instructions. Do not create a new
skill for a rule that belongs in this profile or a new permanent ledger for a
small task.
