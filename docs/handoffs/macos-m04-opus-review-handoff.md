# M-04: Opus 5.5 review after Slider containment

## Follow-up after this packet's review

The returned second Opus report exposed a visible Slider interactivity regression.
It was adjudicated and fixed as **`8105f73c9b5891e880d9fa292f0b26d679238a41`**:
one actual interactivity boolean also keys the local Overlay, remounting the
portal when its semantics group changes. Five new regression cases first fail
the prior product's missing-record condition, then pass; the focused file is now
22/22 and the full local suite is 1,852. Fresh independent review preceded
integration. Both stock unkeyed native flip directions reject; both keyed
comparisons retain usable native values with zero AX errors. A production
Next-channel action alone did not capture the flip and did not reject.

The exact follow-up canonical Release then completed two fresh native processes
for entry/Next-channel and untimed Now Playing menu/window-resize/restoration,
with zero AX/Flutter errors through normal Quit. The untimed mode removes the
old auto-hide confound; no production interactivity flip or hidden widget
identity was directly observed. CI run `39312611152` passed 1,850 Linux tests,
739 selected Windows tests, the stock Windows build and all eight selected
native/reference CTests. The closing report records exact provenance, cleanup
and an unclassified synthetic input/focus observation after Now Playing collapse.

The [closing report](macos-post-audit-fix-report.md#m-04-follow-up-visible-slider-interactivity)
owns current product Release/CI evidence and remaining acceptance. Its correction
of the returned report's broad post-mutation/reparent claims is material: some
reparenting errors are in preflight, and a failing prepass need not have mutated.
M-04 remains open. The earlier packet below retains its original product,
source/log hashes and evidence scope; those are historical identities, not new
observations of `8105f73c`.

## Earlier review packet — product `5c6349d4`

Updated 2026-10-19. Review the integrated containment and remaining M-04 findings
independently. Challenge the source reasoning and evidence, including the earlier
Opus recommendations; reviewer agreement is not authority. Return findings before
implementing anything. **M-04 and overall accessibility acceptance remain open.**

This packet supersedes its pre-containment version. The supplied
[implementation handoff](macos-m04-containment-implementation-handoff.md) remains
unchanged as historical input; its pending Gate A and atomicity wording are
superseded by the approval and calibrated conclusions below.

## Source, authority and reading order

- Repository: <https://github.com/TJZine/LineupDesktop>, branch `platform/macos`.
- Integrated product: **`5c6349d4cf43244da9989fb72f298ac2acb614b0`**,
  `fix(player): contain Slider portal within OSD semantics`.
- Evidence closeout: **`392399c13b8cf2171c685f522a6251280b50c494`**, documentation
  only on top of that product. The controller verified a clean, pushed checkout
  there before updating this packet. Resolve later HEAD/dirty work explicitly;
  do not relabel old runs as observations of new product inputs.
- Before-fix product: `459fd726024a4cf5e40b69ec1cca29ecd2d1dd23`; scratch baseline
  `a51ea124c0f2b9051723a4eb4163cd882f1c74ee` adds documentation only.
- The user explicitly approved **the unlabeled Slider group after OSD controls**.
  Gate A is resolved. Do not request the same approval again or invent a label.
- This assignment is read-only investigation/review. It does not authorize an
  engine patch, application change, new product direction, publication or messages.
  Use the user's `orchestrate-implementation-chats` skill if delegation is needed;
  the controller retains integration, builds, CI and native-app ownership.

Read `AGENTS.md` and `.agents/project.md`, then:

1. [Closing report](macos-post-audit-fix-report.md#m-04-containment-implementation-after-opus-review),
   including fresh Release evidence and the **single final human checklist**.
2. [Investigation](macos-ax-update-investigation.md), especially static origins,
   retained-error recovery, production node 378 and the final Opus follow-up.
3. [Continuation handoff](macos-post-audit-continuation.md), current update first;
   lower sections preserve historical source states.
4. `lib/playback/player_view.dart`: AnimatedSwitcher previous-child wrappers and
   `progressLine` / `Overlay.wrap`; `lib/app/lineup_shell.dart`: menu barrier,
   focus, tooltip visibility and Player semantics exclusion.
5. `test/playback/player_slider_semantics_update_test.dart` and
   `test/support/semantics_update_recorder.dart`.
6. [Reproduction README](../../tool/macos/ax-tooltip-repro/README.md),
   `slider_fade.dart`, `slider_containment.dart`, `slider_retirement.dart`,
   `first-rejection.json` and `slider-first-rejection.json` in that directory.
   Earlier comparison paragraphs retain their original scope; later product
   evidence is in this packet and the closing report.

Pinned tools: Flutter **3.47.7**, Dart **3.13.5**, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`. Observed host: arm64 macOS
**27.0.1 (26A434)**. Inspect these sources, not today's Flutter main. Local SDK:
`/Users/tristan/.cache/lineup-flutter/3.47.7/flutter`; default shell Flutter
previously resolved 3.47.6.

## What changed, and why

Pinned Slider eagerly creates/shows its value-indicator OverlayPortal even for
the continuous, visually indicator-free case. Previously its portal could remain
physically attached to the route overlay while fade/exclusion removed the origin
from effective semantics traversal. A dirty/new empty portal leaf could reach the
common desktop bridge as an unknown, unreachable non-root node and be rejected.

The fix wraps **only the existing SliderTheme/Slider** in
`Overlay.wrap(clipBehavior: Clip.none)` inside the existing finite-height 40-pixel
progress Stack. Portal and origin now share local fade/exclusion/retirement
ancestry. The separate 4-pixel visible indicator, progress Semantics, theme,
callbacks and approved Player geometry remain unchanged. No lifetime state
machine, broad semantics override, tooltip-policy change or engine patch was added.

Containment changes emitted accessibility structure/order: an unlabeled group
contains Slider and its empty local portal leaf, after the OSD controls. The old
structure placed Slider earlier and used a full-window portal leaf. The user
accepted this departure; exact native group role and spoken behavior still need
acceptance. A widget assertion does not prove an AXGroup announcement or native
focus behavior.

The earlier Opus retirement finding was accepted: AnimatedSwitcher's previous
children gain `ExcludeFocus → ExcludeSemantics → TooltipVisibility`, changing
element ancestry and remounting the retiring OSD/Slider under exclusion. This is
a separate hidden-mount trigger from fading an already-mounted Slider. The
retirement wrapper itself was preserved.

The menu refinement was also accepted: exclusion and a Slider value update need
not dirty the empty portal leaf. **Resize while excluded** is discriminating.
The retained harness includes the real ModalBarrier type and shell-equivalent
focus/exclusion wrappers, correcting the earlier scratch probe's omission.

## Verification established so far

### Outgoing updates and interaction — controlled Dart evidence

The recorder intercepts and forwards every argument of the pinned
`SemanticsUpdateBuilder` API. Structural replay covers bridge reparent prepass,
parent-first ordering, recursive destruction, pending-child initialization and
unknown-node validation. Opposing sorted seed orders flag unsupported disagreement;
they do not exhaust C++ unordered-map iteration. There is no event/native-role/
cache/notification/recovery model. Replay stops at the first rejection.

The real PlayerView harness uses forced Dart semantics, fake time and fake
native/media boundaries. The final same-test-source comparison is:

| Evidence | Result and scope |
| --- | --- |
| Before-fix source | **4 pass / 13 expected failures**: eleven first unknown-node transition failures, one pending-child menu-restoration failure, one failure of the approved new group/order contract. |
| Contained source | **17/17 pass**: replay controls, stable visible/value update, hidden entry, retirement/midfade restoration, rapid reversal, menu/resize, menu during entry, retirement with position/resize, route replacement during entry, five other OSD destinations, and interaction/menu isolation. |
| Interaction | Tab reaches Slider; Right and drag seek; hit testing reaches Slider; menu removes focus/semantics and blocks seeking; Slider state survives menu exclusion; hidden pointer input does not seek. Widget evidence only. |
| Existing affected suites | **198 pass**, canonical format and analysis clean. |
| Full local suite | **1,847 pass** on the same product and approved group assertions. A later diagnostic-only assertion reorder was checked by rerunning the final 17-test file plus its format/analysis; the full suite was not repeated for that reorder. |

The original resize baseline initially failed a missing-Slider assertion before
reporting the replay error. Fresh review required moving the health assertion
earlier; final before/after logs are distinct. The earlier **5/-12** pre-Gate-A
baseline is not the final comparison.

The earlier Opus scratch comparison reported identical settled-frame RGBA and
geometry at five size/text-scale configurations, pointer/keyboard checks and
1,830 existing tests passing. These remain **scratch Dart/rendering evidence**,
not a newly repeated integrated visual or native-input acceptance campaign.

Fresh read-only review chat `01a15549-f33f-79e0-a782-03c26f736941` challenged the
replay, negative controls, OSD destinations, interaction/paint/focus and shared
Windows bridge implications. It found no remaining material issues after the
evidence correction and checked final source/log identities before integration.
Independently reassess that conclusion.

### Stock native discriminator and integrated Release

`slider_retirement.dart` starts with healthy native AX and visible Slider 50%.
Default retirement produces first unknown node 13; two messages through Quit
are **not two established independent rejections**. A fresh contained process
retires/restores at 60%, reverses midfade and exposes 70%, with zero AX errors.
Its otherwise stock runner redirects stderr only; it does not change semantics
or input. Source/binary hashes are in the repro README.

The canonical product Release was built via `dart tool/macos/build_app.dart build
--release`, with AOT identity **`1@5c6349d4cf43244da9989fb72f298ac2acb614b0`**.
Four **fresh processes**, each starting with healthy native AX in Guide and no
forced Dart semantics handle, completed normally:

| Sequence | Native observation and limit |
| --- | --- |
| DVR On → Guide → tune | Native Slider appears; CUA traversal places it after OSD controls. |
| Visible OSD → Escape → Return | OSD/Slider disappear, then return. |
| Live menu → actual window zoom → restore | Menu excludes Player while outer window changes 800×632 → 1728×1084; Slider returns afterward and size is restored. OSD auto-hide could run during the menu, so continuous Slider lifetime is unproven. |
| Dismiss → Return/show → freshly observed menu control | Menu works, but observation finished at **965 ms** and click at **989 ms** after show versus the **350 ms** fade. This **does not prove native menu opening during entry**. |

All four logs contain zero AXTree/Flutter error messages and no native shutdown
timeout. Quiet logs/populated trees do **not** directly observe every `Unserialize`
result or establish notification/recovery/spoken acceptance. Inspector bound to
the exact process, but unusable CUA thumbnail geometry prevented target-element
selection; the bare group's native AXRole was not extracted.

The user cleared the new Keychain prompt. Starting channel, DVR Off and window
size were restored; all verification apps/Inspector were closed. Recheck current
processes before further native work.

### Windows/Linux CI

[Run 39300402918](https://github.com/TJZine/LineupDesktop/actions/runs/39300402918)
passed **1,845 Linux tests**, **734 selected Windows Dart tests**, stock Windows
application compilation and all eight selected native/reference CTests:
`track_list_encoder`, `native_playback_state`, `player_core_contract`,
`encodable_value_conversion`, `display_dynamic_range`, `display_guardian`,
`native_player_contract`, `authenticated_reference`.

Verification `865c5c3a71981fe17f9312fdf02ee2eb4c464d20` is the product's
direct child and differs only in `.github/workflows/ci.yml`; the new Slider suite
is explicitly selected on Windows. Live runs were checked and none cancelled.
This does not establish physical Windows AX, playback or presentation behavior.

## Remaining findings and questions for Opus

1. **Containment completeness.** Is there a concrete path where the local portal
   can still outlive/out-traverse its origin? Trace actual Overlay selection,
   traversal grafting, entry/retirement, exclusion/restoration, route changes and
   DVR changes. Assess active gestures, indicator positioning/clipping, focus,
   text scaling and paint order. Separate missing proof from a defect.
2. **Regression fidelity.** Does the recorder forward the pinned API faithfully?
   Does structural replay falsely accept/reject relative to the bridge/AXTree,
   especially ordering, reparenting, pending nodes and destruction? Are negative
   controls discriminating? Two seed samples and fake time are not native proof.
3. **Native evidence gaps.** Precise first-frame menu entry, continuous excluded-
   Slider lifetime during native resize, bare group role, VoiceOver order/
   announcement and notification delivery remain unverified. What smallest
   faithful observation settles each material gap? Native traversal and user
   approval do not settle spoken usefulness.
4. **Retained-error/event-delivery defect — source-established, still open.**
   The pinned common bridge ignores both `Unserialize` return values and checks
   retained `AXTree::error()` instead; success does not clear that string. Later
   valid mutations can skip event delivery and `ClearEvents()`, and a reparent
   prepass can stop early. Check exact flow and distinguish source consequences
   from unobserved native recovery. Correcting this check alone would not restore
   valid updates lost from a rejected batch.
5. **Discarded-batch divergence — calibrated, still open.** This unknown non-root
   failure occurs in `ComputePendingChanges` before the main update mutates
   structure; the bridge discards that main batch, including valid updates.
   Its reparent prepass is a separate earlier update. **Not every AXTree rejection
   is atomic**: other failures can occur after `UpdateNode` starts mutation or
   during pending-child completion. No automatic complete resynchronization has
   been established. Challenge stronger atomicity/recovery claims.
6. **Historical attribution.** Production V2 first error node 378 followed batch
   671: empty full-window portal leaf physically at `0 → 1 → 378`, token 97 with
   no origin, while effective traversal stayed complete/acyclic. Stock Slider
   controls strongly correlate that topology with DVR Slider, but the Release
   trace did not name its widget instance. That was one shared process after
   earlier keyboard work. **Historical node 866 remains unattributed.** Do not
   assign every M-04 failure to Slider or invalidate earlier Tooltip/static/Now
   origin repairs without a concrete counterexample.

Useful pinned source: framework `material/slider.dart`, `widgets/overlay.dart`,
`rendering/proxy_box.dart`, `semantics/semantics.dart`; engine
`shell/platform/common/accessibility_bridge.cc` (`CommitUpdates`,
`CreateRemoveReparentedNodesUpdate`, `GetSubTreeList`, event handling) and
`third_party/accessibility/ax/ax_tree.cc` (`Unserialize`, `ComputePendingChanges`,
`UpdateNode`, retained error). Compare physical and effective traversal graphs.
Optimized-frame LLDB Boolean probes from earlier work were ambiguous and are
**excluded/untrusted**. Repeated retained errors are not independent failures.

## Evidence access and reproducibility

Committed source/fixtures/report and CI are available to repository reviewers.
Raw captures are private and local; remote reviewers must state they were
unavailable and must not invent execution. Main local directory:
`/tmp/lineup-audit/m04-containment-implementation/`.

| Local artifact | Purpose |
| --- | --- |
| `final-diagnostic-evidence.json`, `final-source-sha256.txt` | Final identities and 4/-13 versus 17/0 results. The JSON's `head` is the scratch baseline, not the later product commit. |
| `original-focused-final.log`, `contained-focused-final.log` | Distinct final negative/positive runs; earlier similarly named logs are historical. |
| `existing-affected.log`, `full-tests.log`, format/analysis logs | Portable checks, with the assertion-order reuse limit above. |
| `native-*.log`, per-process result JSONs, `native-summary.json` | Four bounded integrated runs; logs can contain private media information. |
| `release-identity.json`, `release-build.log` | Exact canonical Release provenance. |
| `retirement-*-result.json`, logs and preserved `.app` bundles | Fresh stock retirement default/contained comparison. |
| `ci-identity.json`, `ci-final.json`, `ci.log` | CI product relationship and completed results. |

Older local sources: `/tmp/lineup-audit/opus-m04/` (Opus scratch rendering/model),
`/tmp/lineup-audit/pro-round4/` (initial native containment comparison), and
`/tmp/lineup-audit/pro-round3/` (production trace/stock Slider controls).
These paths may expire and are unavailable to GitHub-only reviewers.

Current source SHA-256:

| File | SHA-256 |
| --- | --- |
| `lib/playback/player_view.dart` | `5bc67c073a1f7c23639c5612db459a451ef802e8084ada6f98c164595203433a` |
| `test/playback/player_slider_semantics_update_test.dart` | `6fc40b67d13fd0f07398a6d99fd438ea80283da68c07c50077be538c7f077a03` |
| `test/support/semantics_update_recorder.dart` | `d1b5b5608f6d324965ae09c46aa2f56b9d28d3913c90bd3161b02c6aa4eaf27f` |

Canonical Release executable SHA-256:
`43fe0b049a0da44b6c1bd2efd35266d18c5e32ade093d07d4b88d8f4175f9496`;
App.framework `c2b65189429b5b9924ffb48cc65a09b781fb0fea4e3ae3d8fd7bb7c88f0835b0`;
106-entry bundle-manifest SHA-256
`681337fe95702d9113cead06a24e554494a020061c35b8be8d666e955dbf01c8`.
Runtime BUILD-INFO and further identities are in the closing report.

If executing locally, use the pinned SDK and record exact inputs:

```sh
export PATH="/Users/tristan/.cache/lineup-flutter/3.47.7/flutter/bin:$PATH"
TZ=America/New_York flutter test test/playback/player_slider_semantics_update_test.dart
```

Reuse valid full-suite/CI evidence for unchanged inputs; this documentation
update does not require another product run. Coordinate exclusive native-app
and build resources with the controller.

## Constraints and requested return

Preserve the approved Player layout, useful hover information and accepted
unlabeled group/order decision. No engine patches, upstream publication, messages
to people, main merge, signing, distribution or release work. Do not retest
accepted HDR/Dolby Vision picture quality. Keep private labels/content, media
paths, URLs, credentials and raw diagnostics out of shared evidence.

Keep physical keyboard, spoken VoiceOver, audio drift and window/lifecycle
acceptance in the existing **single final human checklist** in the closing
report; do not create another user checklist or mark those checks complete.
Any later authorized fix needs a meaningful regression, fresh independent
adversarial review before integration, a conventional commit/progress entry,
appropriate native Release evidence and Windows CI for shared Dart/core changes.
Check live CI first and never cancel an in-progress run.

Return prioritized actionable findings with exact source identity/location,
trigger, mechanism, consequence and evidence. Separate established defects,
evidence gaps and optional ideas. State what you executed, what is source-derived
and what was unavailable. Give an explicit verdict on **accepting the bounded
application mitigation** separately from **closing M-04/accessibility acceptance**,
and recommend the smallest justified next step for each remaining material issue.
