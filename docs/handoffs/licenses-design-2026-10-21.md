# R-03: in-app Licenses design for approval

October 21, 2026. **Design approved; implementation evidence appended below.**
The maintainer approved “the proposed themed reader” in parent turn
`01a15cdb-f7b6-71f0-a7dd-7a3254b98f2b`, user item
`01a15cdb-f7e3-7af0-ad4d-18b85eda34b4`. The approved implementation must land
before the beta candidate. R-03 delivery remains open until final-candidate and
source-delivery comparison; this record does not establish legal sufficiency or
beta acceptance. The proposal below is retained as the approved design input.

## Scope, source and decision

Prepared by R-03 child `01a15cbb-c981-78f2-b79d-cdf711560da5`, local, for
controller `01a15cb9-3a80-7b31-997b-5f5a9d306aa8`. Inspected branch:
`platform/macos`; integration base and HEAD at initial inspection:
`dd2b0146a1d7d8e2b38e949da0b8a19165f4abd6`. Product ancestry supplied by
controller: `ac4c3a1724796314cc7a721bf54b0b2f0f94ff22`.
Other children are editing persistence/startup and engine/Windows tooling in the
shared checkout. This unit owns only this document. No Git mutation, product
code, formatter, analyzer, test, build, app automation or signing was performed.

**Recommended decision to present to the human:** approve Settings → Support →
Open Licenses, opening a full-page in-app index, followed by component/file
readers with Back navigation. Keep the existing Lineup theme and controls;
read all bundled notices offline, and include separate Sources and rebuilding
content. This adds no top-level menu destination or Settings category. Approve
the navigation and layout below; do not treat that approval as approval to
publish sources or distribute a build.

The strongest simpler alternative is Flutter's built-in license page populated
with native entries. It supplies familiar list/detail behavior but does not
naturally retain the existing Lineup header, return/focus contract, file-level
notice provenance, patches and rebuilding material. A small themed reader using
Flutter's license registry and the actual native resources is recommended.
Finder reveal alone is a **departure** from the recorded in-app requirement,
not an equivalent implementation; it is not recommended. A later optional
reveal action would supplement, not replace, the reader.

Authoritative requirements: [port plan §4.4](../macos-port-plan.md#44-libmpv-runtime-and-licensing)
[port plan](../macos-port-plan.md) lines 414–429 and 586–587;
[runtime shipping obligations](../macos-runtime.md#what-the-app-must-ship);
[register R-03](../open-obligations.md). The local stabilization plan's “Later
delivery and expansion” section supplies sequencing; it is intentionally not
made a durable link here because that excluded plan is deleted at closeout.

## Existing interface to retain

[Interface system](../../.interface-design/system.md) and
[theme](../../lib/ui/app_theme.dart) own colors, typography, focus and motion.
[Settings](../../lib/app/lineup_shell.dart) owns the Support category,
`_SettingsRow`, the immersive background, category rail and return destination.
[Shared page components](../../lib/ui/app_ui.dart) own `LineupTopBar`,
`LineupContentWidth`, `LineupPage` and `LineupNotice`;
[canvas](../../lib/ui/lineup_canvas.dart) owns scaling above navigation.

Add a final Support row after Diagnostics:

- Label: **Licenses**.
- Helper: “Read third-party licenses, notices, and source information.”
- Control: existing `OutlinedButton`, **Open Licenses**, styled like Open
  Diagnostics. Keep row spacing, divider, reflow and control width unchanged.

Use the active theme, including alternate themes, large focus indicators and
Reduce Motion. Use semantic theme roles, no hard-coded replacement palette.
Retain the existing 80-canvas-pixel top bar, 48 horizontal content insets,
24 vertical inset and 24 gap after the page heading. Use `LineupTypography`
page title, current body typography and current navigation-row controls;
quiet separators, no new cards, decorative amber, icons or shadows.
The content is a reading surface; its focal element is the document text.

## Reviewable layout and flow

Wireframe is structural, not a screenshot or runtime verification. All labels
below are proposed visible copy; existing branding/menu treatment stays intact.

```text
SUPPORT (existing Settings detail pane)
  Record redacted diagnostics          [existing switch]
  Diagnostics                         [Open Diagnostics]
  Licenses                            [Open Licenses]
  Read third-party licenses, notices, and source information.

LICENSES INDEX (full page; no category rail)
  [LINEUP / existing menu]                                 (top bar)
  ‹ Back to Support
  Licenses
  Third-party software used by this build.

  Native runtime
    curl                                                   ›
    dav1d                                                  ›
    ...all 19 component folders, alphabetically...          ›
    Runtime notice summary                                 ›
  Flutter and packages
    ...registry package names, alphabetically...            ›
  Fonts and engine notices
    Instrument Sans                                        ›
    Inter                                                  ›
    Engine notices                                         ›
  Sources and rebuilding                                   ›

COMPONENT FILE LIST, for example FreeType
  [same top bar]
  ‹ Back to Licenses
  FreeType
  License and notice documents bundled with this build.
    BDF-README                                             ›
    FTL.TXT                                                ›
    LICENSE.TXT                                            ›
    NOTICES.txt                                            ›
    PCF-README                                             ›
    fthash-NOTICE.txt                                       ›

DOCUMENT READER
  [same top bar]
  ‹ Back to FreeType
  FTL.TXT
  FreeType · licenses/freetype/FTL.TXT
  [vertically scrollable, selectable, wrapping full text]

SOURCES AND REBUILDING
  [same top bar]
  ‹ Back to Licenses
  Sources and rebuilding
    Credits and library replacement notice                 ›
    Runtime build information                              ›
    Exact source inventory                                 ›
    Runtime patches                                        ›
    Build recipe and lock file                             ›
    Flutter engine source and patches                      ›
```

This is a single-column navigation stack at every size: index → component →
file; Back moves one level. Flutter package entries may contain multiple license
entries; show each entry as a numbered, described document when necessary,
retaining its package attribution. Single-document entries open directly.
`Runtime patches` lists every bundled patch using the same file reader.
`Runtime notice summary` reads `licenses/NOTICES-SUMMARY.txt`; do not mistake
coverage numbers for the complete notices. Sources entries may group several
files but never replace them with abbreviated notices.

The index and lists use lazy vertical scrolling. The reader keeps heading and
Back reachable, with a single remaining-height scrolling document area and a
visible scrollbar. Keep complete text, paragraph order, attributions and license
separators. Soft-wrap lines and long URLs/hashes without changing copied text;
no ellipsis, line limit, Markdown/HTML execution or automatic URL detection in
raw notices/patches. Use existing body family/size and sufficient line spacing;
patch display may use the existing monospace convention if one is available,
otherwise keep body type. No search UI is required for this bounded slice;
alphabetical lists and preserved position provide deterministic access.

## Responsive and accessible behavior

Dimensions above are **canvas pixels**, not physical screen pixels. The current
canvas uses `max(0.8, min(width/1920, height/1080))`; do not apply another scale
or change it for Licenses. The page body can cap long reading lines at 960
canvas pixels, centered within `LineupContentWidth`; headings align with that
body. This is a proposed local reading-width constraint, not a global change to
Settings. There is no two-pane split to collapse. At widths below the existing
900 canvas breakpoint or text scale ≥2, stack the heading/metadata naturally;
never require a fixed-height header to fit scaled text. Back and headings may
join the outer scroll region in a very short window so the document remains
reachable. Text and controls take their intrinsic scaled height; no clipping or
horizontal scrolling is required to read legal text. Keep the app's existing
minimum window rules; this proposal adds no minimum size.

Initial focus is Back. Traversal order follows the visual tree: top-bar menu,
Back, then document/list controls. From initial Back, Tab moves into the content
and Shift-Tab reaches the menu; returning focus does not restart at the top bar. Enter/Space
activate buttons. Arrow, Page Up/Down, Home/End operate the focused scroll area;
mouse wheel and scrollbar also work. Focused list rows scroll into view.
Selection and Cmd/Ctrl+C copy selected document text using Flutter selection
facilities. Document text has a focusable scroll region with a descriptive
label; it is not a button per paragraph. Native text selection shortcuts retain
precedence over shell shortcuts.

Esc, Go Back and Backspace (except while an editable field owns it) pop one
Licenses level, exactly like the visible Back. Close any open app menu first.
Do not let the existing Settings Esc handler jump straight to Guide/Player
while a reader is open. Returning from a file restores its file row focus and
scroll position; component → index restores the component row; index → Support
restores Open Licenses, the Support category and Settings scroll position.
Settings' earlier return destination survives the whole excursion. Opening
Licenses never stops/tunes playback, changes a profile or saves settings.
Menu navigation to another destination dismisses the Licenses stack through
the existing shell selection guard; returning later starts at the index.
A macOS Settings command while Licenses is open returns to Settings, without
leaving a stale reader route above it.

Use heading semantics for page and group headings, button semantics and full
component/document labels for navigation rows, and text semantics for complete
license content. Do not merge an entire long document into one opaque semantic
node; preserve readable paragraph order. Metadata supplements rather than
replaces attribution. Selected/focused states stay distinct; focus indicators
use the configured theme. Announce loading/failure once via a live region,
without repeatedly announcing every parsed paragraph. No focus stealing on late
loads or retry completion. Reduced Motion adds no animated transitions; retain
existing menu behavior. VoiceOver and actual macOS keyboard selection/scroll
acceptance remain necessary after implementation; widget semantics are separate
proof.

## Data authority, loading and failure

Dart owns all presentation, selection, attribution and navigation. A small
read-only native resource adapter owns resolving the installed bundle's native
resource location. Do not ask the media player to read license files and do not
add a generic filesystem or URL-opening API.

Recommended implementation contract:

- One `LicensesRepository` aggregates Flutter `LicenseRegistry.licenses`, local
  font/engine documentation assets and native runtime document descriptors.
  Keep separate source-group results so a native failure does not hide available
  Flutter notices. Tests inject the repository at the view boundary.
- Extend the existing macOS `lineup/platform` host mechanism with narrowly named
  list/read operations. Native code locates only
  `Bundle.main.resourceURL/LineupNativeRuntime`; it enumerates `licenses/`,
  `patches/`, `BUILD-INFO.txt` and explicitly shipped source/rebuilding documents.
  The UI supplies only an opaque document ID returned by that list operation.
  Never accept a caller-selected absolute path, `..`, symlink, special file,
  network URL or alternate root. Validate canonical containment and regular
  files again at read. Avoid putting absolute bundle paths in errors.
- Return stable relative IDs, component/group attribution, display name, byte
  length and UTF-8 text on demand. Read files off the platform/UI interaction
  thread; the documents are immutable for the process lifetime. Cancel/ignore
  obsolete results when the view closes. Do not stream media or credentials.
- Package/build validation establishes completeness of expected files. Runtime
  enumeration includes extra notice files automatically; an unknown component
  gets its actual directory label, not silent omission. Reject duplicate IDs,
  invalid UTF-8 and unexpected nesting safely. Choose conservative bounds such
  as 2 MiB per document and 16 MiB for the index's complete native tree; these
  exceed the inspected tree. Exceeding a bound is a visible load failure plus
  a build validation failure, never truncation. Revisit bounds if inputs grow.
- Flutter registry license entries retain all associated package names and
  license paragraph indentation. Do not scrape package caches or load source
  repository files at runtime. Add font OFLs and applicable engine notices as
  declared Flutter assets, using the same repository reader. Avoid registering
  them twice if the build later includes them in the generated registry.

Start local loads on opening Licenses, not startup. Display “Loading licenses…”
with progress semantics. Load groups independently; show all successful groups
and a local `LineupNotice` plus **Retry** for a failed group. File load failure:
“This license document could not be loaded.” plus Retry and Back; no paths or
raw exceptions. Empty required native tree is an error, not “no third-party
software.” A failed optional source link leaves offline documents available.
Retry refreshes only the affected result and does not accumulate duplicate rows.
The screen requires no Plex session or network; Support remains reachable when
onboarding is available. Test the existing startup/onboarding route access rather
than requiring a successful account connection to read notices.

Source URLs belong only to explicit source-inventory entries. Render selectable
public URLs and integrity identities offline. If clickable opening is included,
use explicit user activation and a narrow approved HTTPS source-link operation,
not arbitrary links extracted from raw texts. The current platform API only
opens fixed `https://plex.tv/link`; do not silently generalize it. No browser
opening capability is required to read/copy the source links for this slice.

## Existing artifact inventory and concrete gaps

Observed prepared runtime: `build/macos-runtime/dist/arm64`, **not a fresh
candidate or signed package**. It contains 49 license files, 700,509 bytes total;
largest is glslang `NOTICES.txt` at 147,052 bytes; three patches total 7,381 bytes.
`BUILD-INFO.txt` SHA-256:
`b6b0f67b9d7c3e74e1089db05621c65d1aec850a3326e22f9172515ed2018899`.
Its pin-file hash matches [runtime lock](../../tool/macos/mpv-runtime.lock):
`7df202602cc5a0276a7ac8762b0b4289e33e2db4a01d8adc352ca438ab9e842c`.
These observations identify the inventory inspected; candidate verification
must repeat against the selected artifact.

| Material | Existing producer / delivered location | What remains |
| --- | --- | --- |
| Curated runtime licenses and ancillary notices | [build script](../../tool/macos/build-mpv.sh) `license_components`, `license_files`, `build_dist`; bundle `LineupNativeRuntime/licenses/` via [embedder](../../macos/Runner/Scripts/mpv_runtime.sh) | In-app index and byte-faithful reader for every file; exact candidate coverage comparison. |
| Generated per-file notices | `generate_notices` calls [collector](../../tool/macos/collect-notices.py); `NOTICES.txt` for mpv, FFmpeg, libplacebo, glslang, MoltenVK, OpenSSL, curl, lcms2, dav1d, FreeType, FriBidi, HarfBuzz, libass; top-level `NOTICES-SUMMARY.txt` | Reader must include all of these; generator examines leading source comments and does not establish legal completeness. Static subcomponents use curated texts and parent compiled-file coverage, not invented separate NOTICES files. |
| Static/header components | fast_float, SPIRV-Cross, SPIRV-Tools, SPIRV-Headers, cereal, Vulkan-Headers curated files, alongside parent components above | Display all 19 actual component directories; do not restrict to 18 dylib names. |
| Runtime provenance and upstream source links | `write_build_info` emits 13 principal source entries, archive hashes/Git commits, lock hash, three patch hashes and 18 raw dylib hashes | Expose text in app. It does not enumerate every nested source pin; ship the lock file and exact full source inventory including fast_float and MoltenVK external revisions. Raw dylib hashes are pre-signing, not final-package identities. |
| Runtime patches | Bundle `patches/mpv/0001-vulkan-mac-embed-into-host-CAMetalLayer-via-wid.patch`; `patches/ffmpeg/0001-aarch64-do-not-build-GPL-licensed-AC-3-DSP-code.patch`; `0002-aarch64-do-not-build-GPL-licensed-CRC-assembly.patch` | Make all readable in app and include in exact source delivery. |
| IJG credit | `ffmpeg/IJG-NOTICE.txt` includes the appended credit | Present credit visibly in Credits and library replacement notice, and retain the full file. |
| FreeType credit | `freetype/FTL.TXT` provides a credit template; source `include/freetype/freetype.h` in inspected 2.15.0 tree identifies 1996–2026 | Add accompanying credit: “Portions of this software are copyright © 1996–2026 The FreeType Project (https://freetype.org). All rights reserved.” Confirm against exact candidate source, retain all six FreeType documents. |
| Replacement / rebuilding notice | Requirement in [runtime docs](../macos-runtime.md#what-the-app-must-ship); no bundled instruction file is produced by current `build_dist`/embedder | Author candidate-specific notice for mpv, FFmpeg, libplacebo and FriBidi; actual library names, dependencies, exact source/build/patch links and supported modified-copy rebuild/replacement procedure. Must explain signed-copy constraints without claiming legal sufficiency. Do not execute signing or change a user's bundle. |
| Runtime build recipe and source archives | Repository has build script, lock, collector and patches; dist has patches but **not** script/lock/full sources | Prepare an immutable offline companion source package plus manifest, or approved project-controlled release mirror. Include recipe/helper closure and complete pinned sources/submodules. App ships notice, source inventory and script/lock/helper texts; large source archives may be accompanying material. A URL alone is not proof the bytes were delivered. |
| Flutter/Dart/plugin notices | Flutter build generates `NOTICES.Z`; SDK 3.47.7 `ServicesBinding.initLicenses` exposes it through `LicenseRegistry.licenses` | Consume the registry; confirm dependencies/native plugin notices and engine third-party notices for exact build. Do not substitute a hard-coded dependency list. |
| Fonts | [Instrument Sans OFL](../../assets/fonts/instrumentsans/OFL.txt), [Inter OFL](../../assets/fonts/inter/OFL.txt) exist; [pubspec](../../pubspec.yaml) declares fonts but no OFL assets/extra licenses | Explicitly bundle/read both files. SDK supports `flutter: licenses:` if using generated registry instead; verify attribution and inclusion, not merely file existence. |
| Modified Flutter engine | [engine notice](../../tool/flutter_engine/NOTICE), manifest, patch series and recipe exist in repository; Windows package explicitly copies NOTICE | macOS runtime embedder does not copy engine materials. Include applicable notice and exact selected engine/framework identity, upstream notices, patches and source/build instructions in candidate delivery. R-01 controller owns combined identity; do not reuse Windows-only DirectComposition claims on macOS. |
| Windows | [package script](../../tool/windows/package.ps1) copies app Apache license, engine patch notice, Windows provenance, mpv LGPL, FFmpeg LGPLv3/GPLv3 and libplacebo texts | Platform contents differ. This macOS beta design does not establish Windows delivery. Keep shared reader platform-neutral, and require a separate Windows resource adapter/completeness verification before claiming Windows support. Never show macOS LGPL 2.1 runtime information as Windows identity. |

A historical local Release bundle contains `NOTICES.Z` and native resources;
its identity was not verified, so it establishes presence only. Decompressing
that notice asset found neither “Instrument Sans” nor “Inter Project” nor
“flutter-plezy”; these string probes are signals for explicit inclusion checks,
not proof of complete absence or completeness of any other notice.

Exact primary inspected source SHA-256 values:

- `lib/app/lineup_shell.dart`:
  `d930a4192b276ff92e9234f1f2126a3b246b5730ac6b052ac938ec7d6cec0269`.
- `macos/Runner/Scripts/mpv_runtime.sh`:
  `0b6a993f06af4508849610b5134cb43019e5d9ce88772c6f6845753c88c24e18`.
- `tool/macos/build-mpv.sh`:
  `173f020e2673a102c81d6a262f0595bb27556f6f1cae2d8286876339447c422d`.

Local SDK source inspected at the pinned 3.47.7 checkout:
`packages/flutter/lib/src/services/binding.dart` (`initLicenses`, `_addLicenses`),
`packages/flutter_tools/lib/src/license_collector.dart` (`obtainLicenses`),
`flutter_manifest.dart` (`additionalLicenses`) and `asset.dart` (collection).
This is source inspection, not a Flutter command run.

## Implementation handoff after design approval

1. Controller records human approval of the proposed entry/navigation/reader,
   and assigns Dart ownership only after I-08 releases it. Keep the current
   persistence format and startup refusal work untouched.
2. Implement the focused repository, themed views and native read-only adapter.
   Prefer a local nested Navigator or equivalent small explicit Licenses stack
   inside the shell destination so global Back, Settings commands and menu
   selection have one authoritative owner. Do not introduce a second settings
   return-destination policy. Put readers in new focused files rather than
   expanding unrelated Settings responsibilities.
3. Add the Support callback/row and shell routing. Reuse shared components;
   extract the existing row only if sharing is needed, without cosmetic changes.
   Add font/engine assets and candidate-specific source/rebuilding resources.
   If a package-time manifest is used, derive it from the selected runtime;
   do not maintain a second hand-written list of notice files in Dart.
4. Finish source/rebuild materials as a coherent delivery unit. Recommended
   disposition is an offline companion archive prepared locally and bound to
   the candidate manifest, plus exact upstream links in-app. The controller must
   obtain any additional authorization needed for actual delivery/publication;
   no public release was authorized. The source package needs all source pins,
   nested Git dependencies, patches, lock and complete build helper closure,
   selected repaired-engine inputs and applicable notices. Do not claim this
   proposal completes that package. Broken/placeholder source links are not
   acceptable candidate content.
5. Produce real Flutter fixture renders at 1280×720 and 1920×1080, plus the
   actual minimum supported window and text-scale 2, before candidate approval.
   Show Support entry, index, a long notice and failure state with the same
   theme/focus. Keep private account/media state out. This document's wireframe
   is approval of direction only, not approval of rendered execution quality.

Anticipated files for a later assignment: Settings/shell/navigation source;
new focused Licenses Dart files and tests; macOS platform handler and native
reader tests; `pubspec.yaml`; source/notice documentation assets; narrowly
necessary resource embedding/tests. The controller must explicitly assign those
paths because they exceed this design-only unit's write authority. No storage
schema migration or media protocol change is needed.

## Verification and completion gates

Use existing [Settings tests](../../test/app/desktop_settings_test.dart),
[shell/theme tests](../../test/app/theme_shell_test.dart),
[Diagnostics navigation tests](../../test/app/desktop_diagnostics_test.dart) and
[embed fixtures](../../tool/macos/mpv-runtime-embed-test.sh) as starting points.
Add distinct behavioral proof, not snapshots mirroring implementation:

- Repository fixture: all nested notice/patch files appear exactly once with
  attribution; unknown extras included; package multi-attribution retained;
  actual bytes/paragraphs preserved; fonts and correct engine notice present.
- Read boundary: reject traversal/absolute IDs, symlinks, malformed/oversized
  files, duplicate IDs and missing required resources; no raw path leakage.
  Verify success against installed bundle resources, not only a fake root.
- Widget/navigation: Support entry during ready and onboarding states; all Back
  levels, Esc/menu precedence, retained Settings return destination, invocation
  focus/scroll restoration, route disposal during load and stale result rejection.
  Demonstrate playback is not stopped or changed by navigation.
- Loading/partial failure/retry and selection-copy; real long glslang-style text,
  long filenames/URLs, empty native tree, narrow/short layout, large text and
  large focus indicators. Semantics expose readable headings/text, enabled
  controls and failure status. Reduce Motion respects current configuration.
- Controller runs pinned formatter/analyzer and risk-matched widget/native
  checks, then package fixture comparisons. Candidate inspection compares every
  selected-runtime notice/patch byte and source inventory to the actual app,
  and records app, runtime, engine and companion-archive hashes separately.
- On the selected macOS candidate, exercise keyboard-only index/read/back,
  VoiceOver, selection/copy, scrollbar, actual minimum size and offline reading.
  This is separate from deterministic widget/native fixtures. Signed sandbox,
  Windows, legal review and beta acceptance remain separate unclaimed gates.

For this document only: source reads, local artifact inventory, `git diff
--check` and relative Markdown file/heading link validation. No product checks
were run, intentionally, under exclusive I-08 Dart ownership. The controller
should verify diff scope and rebase source claims if parallel work changes a
referenced producer. Independent legal/Plex/trademark/patent/App Store review
remains the existing pre-submission gate; no legal determination is made here.

## Outstanding decisions / proof

Human design approval of the recommended UI is the next consequential decision.
The offline source-companion recommendation also needs a concrete delivery owner
and approved destination before anything is handed to testers; publication or
sending files remains outside current authorization. Source/patch/relinking
content, implementation, real rendered/accessible behavior and exact candidate
artifact comparison remain to be completed. R-03 must not be closed merely
because this design document or the bundled raw resources exist.

## Approved implementation outcome — October 21

R-03 implementation child: `01a15cbb-c981-78f2-b79d-cdf711560da5`, worker /
gpt-6.1-sol / medium. Implementation input HEAD:
`c767d79df311c057738ff6ff885b71f0f58fe532`; original integration base remains
`dd2b0146a1d7d8e2b38e949da0b8a19165f4abd6`. Human design approval was retrieved
from the actual parent, as was original completion-callback authority. The later
ad-hoc identity `-` authorization was also verified in parent turn
`01a15ce5-40ef-72f0-b4e4-d9bcda656b26`; only the existing disposable embedding
fixture used that signing permission here. App/engine/runtime candidate builds
remain controller-owned. No Git staging, commits, pushes or branch switches were
performed by this child.

Implemented:

- macOS Settings → Support → Open Licenses, with the approved themed full-page
  index, component/file navigation and selectable full-document reader. Separate
  source groups support independent loading/failure/retry. A Copy document text
  action preserves exact raw newlines independently of paragraph selection.
- Focus and index scroll restoration at each Back level; shell Esc/Backspace,
  menu precedence and Settings commands retain shell ownership. Settings is kept
  mounted while reading, preserving its category/scroll and earlier destination.
  First-run macOS has a small Settings action in its existing top bar, opening
  Support without requiring Plex linking. The new entry is macOS-only; this does
  not advertise an incomplete Windows runtime-notice implementation.
- `lib/licenses/` owns Dart presentation/data aggregation, including Flutter
  registry package attribution and paragraph indentation, font OFLs, engine
  notice and generated source/rebuilding material. `LicenseResources.swift`
  owns bundle-relative, descriptor-based reads on a serial background queue;
  IDs are issued by listing, never interpreted as caller-selected paths.
  Bundle-directory/file symlinks, special files, invalid encoding, missing
  resources and byte/count/depth bounds fail with a sanitized error.
- The reader exposes every file in the actual runtime notice/patch trees and
  build information. Small generated `assets/licenses/` texts contain the exact
  principal/nested runtime source pins, complete recipe/helper texts, Mac engine
  patch inputs and credits/replacement procedure. Sources and rebuilding is an
  explicit list entry. No source trees or large archives were added to Git.
- `source_materials.py` prepares the final companion locally without fetching,
  building or signing. It checks runtime lock/patch identities, canonical engine
  verification, build-receipt/app/ZIP correspondence and installed resource bytes;
  then snapshots all runtime/submodule, Lineup and evaluated Flutter Git sources
  with committed helper bytes, subject to an explicit capacity budget. It
  publishes a new owned directory only after hash validation. The final real
  candidate-dependent invocation remains a controller gate.

Verification evidence (stock pinned Flutter 3.47.7): canonical format check
passed; analyzer reported no issues; the full `TZ=America/New_York flutter test`
suite passed **1,885 tests** after the product changes. Focused Licenses checks
passed **13 tests**, including the later font-complete render-fixture refinement.
Source-material tests passed **6 controlled fixtures**, covering archive/source
pin tampering, runtime patch binding, source-asset freshness, candidate/receipt/
ZIP correspondence, bounded assembly and no partial-output publication. Actual
local source inspection validated **26** runtime source archives/Git snapshots.
The prepared runtime's lock and patch bytes match the current recipe.

The standalone Swift fixture compiled and passed its boundary cases plus exact
text comparison for **53** actual prepared-runtime documents. The existing
`mpv-runtime-embed-test.sh` integration fixture passed, including its intentional
negative/recovery/signing controls. Xcode project `plutil -lint` passed.
`git diff --check` and relevant local Markdown file links were checked.
An initial canonical-format invocation found the older SDK on PATH; the check
was rerun successfully with the pinned SDK first. Earlier compile/retry/render
fixture issues were repaired before the passing results; none is left deferred.

Real Flutter fixture PNGs were written outside Git at
`/tmp/lineup-r03-renders/`: Support and index at 1280×720 and 1920×1080;
reader at both sizes, 800×600, text scale 2 and 640×360/text scale 2; partial
failure/loading at 1280×720. Pinned fonts were loaded and the rendered results
were visually inspected. Native index/Flutter-package entries in these fixtures
are explicitly synthetic; the long glslang notice uses the real prepared text.
These are widget renders, not app automation or physical acceptance. No explicit
minimum window constraint was found in the macOS window source; 800×600 is its
initial size and 640×360 is a stress fixture, not an accepted OS minimum.

Remaining proof: controller integration/review; clean selected-engine candidate
build (including AppDelegate integration); installed-bundle/offline checks;
physical keyboard/VoiceOver/actual minimum-window acceptance; real final
companion assembly/manifest comparison against the selected candidate, runtime
and durable engine; authorized source/build delivery. No final candidate or
source companion was sent/published, and no old verified app/engine/runtime or
stock cache was altered. No legal, Windows, signed-sandbox or beta acceptance is
claimed. Keep R-03 open through those applicable delivery gates.


## Focused independent-review corrections — October 21

The controller accepted three P2 findings against the initial 41-file content
manifest and reauthorized this child for focused corrections at the same input
HEAD `c767d79df311c057738ff6ff885b71f0f58fe532`.

1. Candidate validation now examines every ZIP entry before filtering file
   artifacts: root, unnormalized path components, original name, duplicates,
   declared type and directory payload are checked. Companion verification
   walks every directory entry with non-following metadata before reading its
   manifest, rejecting directory symlinks and FIFOs/special files as well as
   file symlinks. Safe real empty directories remain valid. New negative cases
   reproduce the original unrelated/traversal ZIP-directory and companion
   directory-symlink/FIFO bypasses; restored positive controls pass. The existing
   assembler was not observed creating these unsafe entries.
2. Source preparation now requires the wrapper's completed
   `.engine-provenance.json`, in addition to its earlier build receipt. It
   validates the completed envelope's selected engine, recipe, receipt digest,
   current artifact map, source/version/app identities and raw/embedded engine
   hashes, and carries the completed-envelope digest in the companion manifest.
   It retains the recorded normalized comparison instead of invoking signing
   normalization again. Absent/stale/mismatched envelopes, modified raw engines,
   and refreshed pre-comparison receipts paired with changed embedded engines
   are rejected. A positive fixture intentionally uses different raw/signed
   engine bytes, demonstrating that raw-byte equality is not assumed.
3. Onboarding Support completion preserves Settings' prior return destination;
   Guide is a fallback only when none exists. The previous stage is initialized
   in `initState`, so first-run restoration's first notification is recognized.
   Existing fixtures prove profile/server cancellation via F3 retains Player,
   restoration retains an existing Player origin, and first-run restoration
   falls back to Guide. Native playback calls, selected identities and saved
   state remain unchanged in these controlled fixtures.

Negative controls against the previous bundled helper fail all three delivery
regression groups. Temporarily reinstating the unconditional Guide assignment
fails all three Player-origin navigation cases while first-run fallback passes;
the corrected source was restored before positive/full checks. The navigation
restoration cases are controlled presentation transitions, not new physical or
live account-restoration evidence. The corrected Python suite has 8 tests and
focused Licenses suite has 17 tests. Previous Swift/native/embed and render
observations retain their original attribution because those inputs were not
changed or rerun. Final-candidate app/installed-channel/source-assembly and
physical acceptance remain the controller's exact outstanding gates.


Final correction checks passed: 17 focused Licenses tests, all 1,889 full-suite
tests with `TZ=America/New_York`, canonical pinned format check (165 files, no
changes), analyzer (no issues), 8 source-material tests, regenerated-asset
freshness and `git diff --check`. One old-helper negative-control import created
an incidental Python bytecode cache in the assets directory; freshness validation
rejected it. That test-generated cache was removed and the bundled helper
snapshot regenerated successfully. No required check remains failing. The
updated owned-content manifest in the completion callback supersedes the prior
41-file hash, with the same file set.
