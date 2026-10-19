# M-04: Opus 5.5 review after the Slider interactivity fix

Updated 2026-10-19. Independently review the integrated mitigation, completed
verification and remaining findings. Challenge earlier Opus/controller conclusions
against current source and actual evidence. Return findings before implementing
anything. **M-04 and overall accessibility acceptance remain open.**

This replaces the accumulated earlier review packet. Historical evidence retains
its original source/build identity in the linked report and investigation.

## Source, scope and settled decisions

- Repository: <https://github.com/TJZine/LineupDesktop>, branch `platform/macos`;
  local checkout `/Users/tristan/Software/LineupDesktop`.
- Current product: **`8105f73c9b5891e880d9fa292f0b26d679238a41`**,
  `fix(player): renew Slider portal when interactivity changes`.
- Final evidence closeout: **`fb358c735f89fa312959ce804c9f7bfa44dbcd1d`**. Later
  commits through that revision are documentation only. The controller checked a
  clean, pushed checkout there before this packet update. Resolve any newer HEAD
  or dirty files explicitly; do not relabel older runs as new product evidence.
- Original containment: `5c6349d4cf43244da9989fb72f298ac2acb614b0`.
  Its review-packet revision `7a4964503055566b1357b0b005edcc24ba62ef8f` changes
  documentation only and is the interactivity negative-control baseline.
- Before containment: `459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`.
- The user approved the **unlabeled enabled-Slider group after OSD controls**.
  Gate A is resolved. Preserve approved Player visuals and useful hover information;
  do not request that approval again or invent a group label.
- This is a read-only review/investigation assignment, not authorization to patch
  the application/engine or change product direction. If delegation is needed,
  use the user's `orchestrate-implementation-chats` skill. The controller owns
  integration, builds, CI and native-app resources. Review this packet's current
  work rather than restarting unrelated completed audit fixes.

Read `AGENTS.md`, `.agents/project.md`, then:

1. [Closing report: interactivity follow-up](macos-post-audit-fix-report.md#m-04-follow-up-visible-slider-interactivity),
   its original containment section, and the **single final human checklist**.
2. [Investigation](macos-ax-update-investigation.md), especially the two final
   Opus follow-ups, static origins, retained-error recovery and production node 378.
3. [Continuation handoff](macos-post-audit-continuation.md), current update first;
   lower sections preserve historical states.
4. `lib/playback/player_view.dart`: `_Osd` interactivity/progress overlay and
   AnimatedSwitcher previous-child wrappers; `lib/app/lineup_shell.dart`: menu
   barrier/focus/exclusion; `lib/playback/player_key_resolver.dart` and
   `player_coordinator.dart`: key routing, duration/status updates and Now Playing.
5. `test/playback/player_slider_semantics_update_test.dart` and
   `test/support/semantics_update_recorder.dart`.
6. [Repro README](../../tool/macos/ax-tooltip-repro/README.md), especially
   `slider_interactivity.dart`, plus the original `slider_fade.dart`,
   `slider_containment.dart`, `slider_retirement.dart` and sanitized rejection
   fixtures. Earlier comparison paragraphs describe their original evidence.

The supplied [containment implementation handoff](macos-m04-containment-implementation-handoff.md)
is historical input. Its pending Gate A, pre-implementation status and broad
atomicity wording are superseded; it is not a current instruction to repeat work.

Pinned tools: Flutter **3.47.7**, Dart **3.13.5**, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`. Host: arm64 macOS
**27.0.1 (26A434)**. Inspect that pinned source, not today's Flutter main. Local
SDK: `/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`; default shell Flutter
previously resolved 3.47.6.

## Implemented behavior and mechanism

Original containment puts only SliderTheme/Slider inside
`Overlay.wrap(clipBehavior: Clip.none)` in the existing 40-pixel progress Stack.
The portal and its semantics origin share fade, exclusion and retirement ancestry.
The separate 4-pixel visible indicator, progress Semantics, callbacks/theme and
AnimatedSwitcher retirement wrapper are preserved. The user accepted the emitted
unlabeled group and order change; native role/announcement acceptance is separate.

The second Opus review found an additional regression in that contained shape:
when a visible Slider changes enabled state, its semantics group can change ID.
Slider is resent under the new group, but its empty grafted portal leaf is not.
The pinned bridge asserts that moved children have pending records. In Release,
its successful removal prepass can destroy the leaf; the main update then
references an uninitialized child and rejects with `Nodes left pending`.

The integrated follow-up derives **one** condition:

```dart
final sliderInteractive = controller.duration > Duration.zero && !unsupported;
```

That condition drives both `Overlay.wrap(key: ValueKey(sliderInteractive), …)`
and Slider's actual `onChanged` availability. A flip remounts Slider and portal
together so the replacement subtree emits its data. Same-interactivity value/max
changes and menu exclusion retain Slider State. A disable intentionally ends the
old Slider's gesture/focus lifetime; tests cover disabled noninteraction and
reenabled usability. No separate lifetime state machine, broad semantics override,
new group label, tooltip-policy change or engine patch was introduced.

The older retirement finding also remains relevant: AnimatedSwitcher's previous
child gains `ExcludeFocus → ExcludeSemantics → TooltipVisibility`, remounting the
retiring OSD under exclusion. This differs from fading a stable mounted Slider.
The wrapper was deliberately preserved; containment carries that behavior forward.

## Final verification evidence

### Controlled Dart semantics and interaction

The recorder forwards every argument of the pinned SemanticsUpdateBuilder API.
Replay models the common bridge's removal prepass, parent-first ordering,
recursive destruction, pending-child initialization and unknown-node checks.
It samples two opposing sorted seed orders and flags unsupported disagreement;
this does not exhaust native unordered-map orders. It does not model native roles,
events, caches, notifications or recovery, and stops at the first rejection.
Its missing-record guard rejects earlier than native Release mutation/completion.

The real PlayerView harness uses forced Dart semantics, fake time and fake media/
native boundaries, plus shell-equivalent ModalBarrier/focus/exclusion structure.

| Evidence | Final result and limit |
| --- | --- |
| Interactivity before-fix control, identical final test source | **17 pass / 5 fail** on `5c6349d4`/`7a496450`; all five new cases first reject the absent reparented-child record. |
| Integrated focused file | **22/22 pass**: original transition/group/interaction cases plus duration disappearing, independently disabled initial mount then duration arriving, unsupported/restoration, unchanged-interactivity state retention, and active-drag cancellation. |
| Added behavior assertions | Healthy initial state in each direction; disable drops focus and blocks tap/continued-drag seeking; reenabled Tab/Right can seek; enabled group/order retained; ordinary value/max and menu changes preserve State. |
| Existing PlayerView file | **123/123 pass**. |
| Full local suite | **1,852 pass** on the final source. |
| Canonical checks | Format **159 files / 0 changed**; analysis clean. |

One Opus scratch disabled-to-enabled probe had already failed during its preparatory
disable. The retained tests correct that: each direction begins independently
healthy. On historical `459fd726`, the five added cases have no replay rejection:
**2 pass / 3 fail only at the later approved group assertion**. Do not claim five
complete passes there. The original containment **4 pass / 13 fail** negative
control belongs to the earlier 17-test harness; it was not a run of the new file.

Fresh independent reviewer chat `01a155a7-84ee-7641-b56d-fceb695328e3` checked the
patch, before/after evidence, focus/gesture consequences and stock discriminator
before integration, with no remaining material issue. Later scoped review checked
final CI/native evidence calibration. It did not repeat native actions itself.
Reviewer agreement is not acceptance authority; independently challenge the result.

### Fresh stock native controls — actual flip reproduction

`slider_interactivity.dart` contains stock widgets only, with no Lineup imports,
forced semantics, custom semantics nodes, tracing or native-runner modification.
Its default is the **unkeyed local overlay**, not the older route-overlay shape.
`REPRO_KEYED_OVERLAY=true` selects the follow-up; `REPRO_INITIALLY_DISABLED=true`
starts the opposite direction independently. Every Release process began with
healthy native AX and visible Slider 50%, then ended by normal Quit:

| Variant | Native observation |
| --- | --- |
| Unkeyed, initially enabled | Disable → first `Nodes left pending by the update: 12`; one AX error message. Quit immediately after rejection. |
| Unkeyed, initially disabled | Enable → same first pending-node error; one AX error message. Quit immediately after rejection. |
| Keyed, initially enabled | Disable → Change value exposes 60% → Enable → Change value exposes 70%; zero AX/Flutter errors. |
| Keyed, initially disabled | Enable → Change value exposes 60%; zero AX/Flutter errors. |

The unchanged stock runners were launched directly with shell stdout/stderr
capture. All four share the pinned stock engine and the same nonfatal sandbox-
extension launch warning. Exact variant/binary hashes are in the repro README.
These establish bounded native rejection/healthy controls, not production widget
identity, notifications, spoken output or recovery after rejection.

### Exact product Release and bounded native application checks

Canonical wrapper: `dart tool/macos/build_app.dart build --release`.
Version/build: `0.1.0` / `1`; AOT identity:
**`1@8105f73c9b5891e880d9fa292f0b26d679238a41`**.

| Identity | SHA-256 |
| --- | --- |
| Native executable | `b8a5f25b95b650d8714119b66efc38e0d4980f6476c1ee34b6b8b0a873b8ea6d` |
| App.framework | `fd606f666077872ed44aaf350c77a3fcfca1e8927f891cd0e72f13634902acf8` |
| 106-entry bundle manifest | `14da8ccdc19c274c11d38d351ebf38e41ba6415b71b76d9aee842bf56a65fbb6` |
| Runtime BUILD-INFO | `b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899` |

Manifest encoding: compact JSON mapping relative paths to hashes, sorted keys,
UTF-8, no trailing newline. All 106 bundle file hashes were rechecked unchanged
at closeout. Documentation commits did not rebuild or change these product inputs.

The user cleared the binary's Keychain prompt. Two fresh processes established
healthy native AX in Guide without a forced Dart handle and ended normally:

| Final-product sequence | Observation and limit |
| --- | --- |
| Entry/Next channel | DVR On → Guide → tune exposes native Slider → actual OSD Next channel → native Slider after tuning. **No interactivity flip directly observed.** |
| Untimed Now Playing/menu/resize | Tune starting channel → I opens Now Playing, with Close collapse control and Slider → live menu excludes Slider → actual zoom changes outer window 800×632 → 1728×1084 while menu stays open → Escape restores Slider/Now Playing Close → zoom returns 800×632. |

Both logs contain zero AX/Flutter errors, no exception and no native shutdown
timeout. `showNowPlaying()` uses `timed: false`, removing the earlier auto-hide
confound for this resize check. This does not directly prove hidden Slider State
identity or the exact timed-OSD entry/lifetime cases. The pre-fix product's actual
Next-channel control also logged zero errors without an observed flip; neither
production run is the failing flip control or a disproof of the stock finding.

DVR Off, starting channel and original size were restored; no verification app,
Inspector or SecurityAgent remained at final inspection. Recheck current processes
before new native work. The cleanup input observation below is not a passed
keyboard check, despite successful pointer-based cleanup and normal Quit.

### Windows/Linux CI — completed

[Run 39312611152](https://github.com/TJZine/LineupDesktop/actions/runs/39312611152)
passed **1,850 Linux tests**, **739 selected Windows Dart tests**, the stock
Windows application build and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract`, `authenticated_reference`.

Verification **`6e7112e20583e65afb81023dd8e9bbf14793354a`** is the product's direct
child and differs only in `.github/workflows/ci.yml`. The updated Slider file is
explicitly selected on Windows. The completed head, parent relationship, exact
diff and raw logs were checked. Live runs were checked before dispatch; none was
cancelled. These checks do not establish physical Windows AX/media/presentation.

## Returned third review — adjudicated

Opus reviewed this packet at `871c7a3c` and accepted bounded product `8105f73c`
without establishing another defect. The controller corroborated its 11 ported
and 18 environment/combined scratch probes: 29 completed, with reported replay
errors null, all nine environment State identities retained and all nine combined
exception reports null. These are exploratory Dart/fake-time observations; they
do not add native acceptance or change the retained/full-suite counts above.

Its focus appendix did not reproduce the exact real-shell Now Playing sequence
because that fixture lacked a current program. Root-scope fallback is a possible
mechanism only when no replacement focus is pending, not an established cause.
Command-comma uses the native application-menu path, but comparing it with Escape
alone does not conclusively classify focus versus delivery. Capture the actual
focus and same-key event path if the observation recurs. Do not implement a
speculative focus workaround. The [closing report](macos-post-audit-fix-report.md#third-opus-follow-up--no-new-application-defect)
records dispositions, guards, probe provenance and unchanged native/human limits.
The questions below remain evidence questions, not newly accepted defects.

## Remaining open findings and focused questions

1. **Mitigation completeness and proof quality.** Does the key track exactly the
   actual interactivity boundary, with safe focus/gesture disposal and reenable
   behavior? Is any relevant path still capable of separating a grafted child
   from its origin or omitting data during parent replacement? Challenge the
   recorder/replay against pinned source, especially prepass/order/destruction.
   Identify a concrete defect separately from missing evidence or an optional idea.
2. **Unclassified input/focus observation.** After the final Now Playing → menu/
   resize → restore → collapse sequence, synthetic Escape/Return/F2 did not expose
   controls. Native AX showed the video-only Player; clicking its native container
   restored OSD, and live menu/Settings worked. There were no AX/Flutter errors.
   `resolvePlayerKey` maps Escape on none to Guide, Enter on none to OSD, and F2 to
   Guide. The sparse tree describes absent overlay controls; it does not explain
   ineffective delivered keys. Player's key handler is outside the descendant
   keyed Slider overlay. Neither input delivery/focus nor a regression caused by
   this fix was established. What smallest observation would distinguish physical
   application failure from synthetic-event/focus behavior? Keep this context in
   the existing physical checklist rather than prescribe an unproven workaround.
3. **Native accessibility acceptance.** Exact bare group AXRole, spoken group
   announcement/order/usefulness and notification delivery remain unverified.
   The user approved emitted structure/order; that does not prove spoken quality.
   Native traversal after controls was observed on `5c6349d4`, with its original
   identity. Exact native first-entry menu timing remains unproved: the earlier
   attempted click completed at 989 ms versus a 350 ms fade. Untimed Now Playing
   resolves the auto-hide confound for its bounded resize sequence, not every
   timed-OSD lifetime case. Recommend only observations needed for a material claim.
4. **Retained-error/event delivery — source-established, no engine repair.**
   The pinned common bridge ignores both `Unserialize` return values and checks
   retained `AXTree::error()`; successful updates do not clear it. Later mutations
   can skip event delivery and `ClearEvents()`. A retained error after a removal
   prepass can return before consuming/clearing pending updates. Calibrate claims
   to the surviving bridge/tree instance; no native recovery or complete reset
   mechanism was established. Fixing the check alone would not restore lost data.
5. **Rejected batches and divergence — calibrated.** Unknown non-root failures
   here occur in `ComputePendingChanges` before that main update mutates structure;
   the bridge still discards its valid updates. A successful removal prepass is
   a separate earlier mutation and can already have destroyed moved subtrees.
   A failing prepass need not have mutated. **Not every rejection is atomic, and
   not every "reparented" error is post-mutation:** `ComputePendingChangesToNode`
   can reject "not marked for destruction, would be reparented" before UpdateNode.
   `Nodes left pending` completion failure occurs after node updates. Replay's
   early missing-record check proves invalidity, not exact native mutation timing.
   No complete automatic resynchronization or notification recovery is established.
6. **Historical attribution remains limited.** V2 production first error node
   378 followed batch 671: an empty full-window leaf physically at `0 → 1 → 378`,
   token 97 without an origin, while effective traversal was complete/acyclic.
   This strongly source-correlates with entering DVR Slider; the Release trace
   did not name a widget instance. It was one shared process after keyboard work.
   **Node 866 remains unattributed.** Do not assign all M-04 failures to Slider or
   invalidate earlier Tooltip/static/Now-origin repairs without a counterexample.

Pinned source starting points: framework `material/slider.dart`,
`widgets/overlay.dart`, `rendering/proxy_box.dart`, `semantics/semantics.dart`;
engine `shell/platform/common/accessibility_bridge.cc` (`CommitUpdates`,
`CreateRemoveReparentedNodesUpdate`, `GetSubTreeList`, event handling) and
`third_party/accessibility/ax/ax_tree.cc` (`Unserialize`, pending computation,
`UpdateNode`, completion validation and retained error). Distinguish physical
attachment from effective traversal. Earlier optimized-frame LLDB Boolean probes
were ambiguous and are **excluded/untrusted**. Repeated retained errors are not
independent rejections; quiet logs/populated values are not notification recovery.

## Evidence access and reproducibility

Main private directory: `/tmp/lineup-audit/m04-interactivity-followup/`.
Remote reviewers cannot assume access. State unavailable artifacts explicitly and
do not invent execution. Committed source/fixtures and CI remain independently
accessible; raw production logs may contain private media information.

| Local artifact | Contents |
| --- | --- |
| `worker/summary.json`, `worker/before.log`, `worker/after.log`, `worker/retained-test.dart` | Final identical-test-source 17/-5 versus 22/0 evidence, commands/hashes/limits. |
| `worker/before459-added-cases.log` | Historical 2 pass / 3 later group-only failures, without replay rejection. |
| `full-tests.log`, `format.log`, `analyze.log`, worker PlayerView log | Final local checks. |
| `stock-native-summary.json`, `interactivity-*.app`, `interactivity-*-native.log` | Four stock native variants, exact hashes, observations and preserved bundles. |
| `native-baseline-next-channel-result.json` and log | Pre-fix production control, without an observed flip. |
| `native-final-summary.json`, `native-final-*.log` | Two final product processes, size transitions, cleanup observation and log hashes. |
| `release-identity.json`, `release-bundle-manifest.json`, `release-build.log` | Exact product provenance. |
| `ci-identity.json`, `ci-final.json`, `ci-log-checks.json`, `ci.log` | Completed CI results and product relationship. |

Older local directories: `/tmp/lineup-audit/opus-m04-round2/` (incoming scratch
probes), `m04-containment-implementation/` (first containment evidence),
`opus-m04/`, `pro-round4/` and `pro-round3/` under the same audit root. Attribute
each to its own source and limits. Temporary paths may expire.

Current source SHA-256:

| File | SHA-256 |
| --- | --- |
| `lib/playback/player_view.dart` | `90889b45e98335aaaff5027fa20ebd657a95a9d97000899cd8ce9ba112d3122b` |
| `test/playback/player_slider_semantics_update_test.dart` | `0112b233bc4d5a3da18e73a86dd770165694d4159d4d43526e2bbf4914fb2aae` |
| `test/support/semantics_update_recorder.dart` | `d1b5b5608f6d324965ae09c46aa2f56b9d28d3913c90bd3161b02c6aa4eaf27f` |
| `tool/macos/ax-tooltip-repro/slider_interactivity.dart` | `2f5e497e6598d4e37dcc6c73ce9846e8d48da42575f1638cbb81ccf610f433cb` |

For a focused local rerun, record exact inputs and use the pinned SDK:

```sh
export PATH="/Users/tristan/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH"
TZ=America/New_York flutter test test/playback/player_slider_semantics_update_test.dart
```

Reuse valid full-suite/CI evidence for unchanged inputs; this prose update does
not require another product run. Coordinate exclusive app/build resources before
executing native work, and restart after any rejection.

## Constraints and requested return

No engine patches, upstream publication/messages, main merge, release/signing or
distribution. Do not retest accepted HDR/Dolby Vision picture quality. Keep media
labels/content, private media paths, URLs, credentials and raw diagnostics out of
shared evidence. Do not remove useful hover behavior or change the approved
Player layout/group direction without a new consequential decision.

Physical keyboard, spoken VoiceOver, audio drift and window/lifecycle acceptance
remain in the **single final human checklist** in the closing report. Do not
create another user checklist or mark those checks complete. Any later authorized
fix needs a discriminating regression, fresh independent adversarial review before
integration, a conventional commit/progress entry, relevant native Release checks
and Windows CI for shared Dart/core changes. Check live CI first; never cancel
an in-progress run.

Return prioritized actionable findings with exact source identity/location,
trigger, mechanism, consequence and evidence. Separate established defects,
evidence gaps and optional ideas; state what you executed, inferred from source,
or could not access. Give separate verdicts on **the bounded application
mitigation** and **closing M-04/overall accessibility acceptance**, and recommend
the smallest justified next step for each remaining material issue. An empty
new-defect list is valid; it does not automatically close unverified acceptance.
