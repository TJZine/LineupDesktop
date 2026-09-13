# Desktop proportional scaling pass

September 12, 2026. The user authorized preserving the approved overall
composition across resolution and OS display scaling, with fresh sequential
Luna implementation tasks. This extends the adaptive work; it does not reopen
the locked 1080p designs or approve the three deliberately skipped surfaces.

## Settled implementation direction

- Use the Flutter logical viewport and the shared 1920×1080 reference scale.
  Do not multiply by device pixel ratio again. At 3840×2160/DPR1 the reference
  scale is 2; at the same physical size/DPR2 it is 1.
- Preserve existing compact-window behavior below the reference size. Preserve
  the normal-text 1080p appearance. Scale component dimensions, spacing and
  typography together above the reference size.
- Preserve system text enlargement independently. Allow wrapping, scrolling and
  compact arrangements when needed; do not clamp accessibility text or scale
  the entire app as an image.
- Work sequentially in this checkout: shared Settings/Diagnostics, setup and
  onboarding/channel management, Guide, then Player. Split a family further
  when its distinct sizing owners warrant a smaller implementation task.

## Group 1 — shared scale, Settings and Diagnostics

Luna task `01a0971a-df9c-7b00-b0f7-95aa90568c9a` returned its exclusive lease.
Astra integrated the changes, corrected Diagnostics button sizing and expanded
event alignment, and preserved the default Settings dropdown popup height policy.

The shared scale no longer stops at 1.35. Settings native controls and relevant
spacing now scale with the reference, and Diagnostics responsive thresholds and
event columns account for enlarged text. No report data or controller behavior
changed.

Verification: 15 existing Settings, Diagnostics, navigation and parity checks
passed; the Diagnostics checks passed again after integration. Targeted analysis,
format and diff checks passed. Twelve real-widget captures cover Account with
long names, expanded technical details and an expanded event at 1080p, 1440p,
2160p/DPR1 and 2160p/DPR2/text200%. The three normal-text 1080p captures are
pixel-identical to the fresh pre-scaling reference. Astra inspected representative
4K and enlarged-text captures. Source and capture hashes are in
[group 1 evidence](design/desktop-ui/scaling/group-1-evidence.json).

Captures use synthetic content and portable test fonts; they are local ignored
artifacts, not physical Windows acceptance. High-resolution Settings/Diagnostics
geometry is checked; other component exceptions remain in progress. Native
video placement, Windows typography/input and live monitor-DPI transitions still
require physical Windows evidence at the tested commit.

Independent review has not been requested or run. No separate review is
specifically recommended for this presentation-only group.

## Group 2a — channel setup

Luna task `01a0972b-e577-7652-be45-d820ba1ed032` completed the initial pass and
a bounded follow-up, then released its lease. Setup now interpolates its existing
720p and 1080p dimensions only within that interval, then scales the 1080p endpoint
using the shared reference. Controls, spacing and adaptive thresholds follow the
same rule. Enlarged dropdown labels receive sufficient width and row height;
the compact configuration/review layout keeps its footer outside the scrolling
content. Scan, allocation, review and apply behavior remains with existing owners.

The 15 existing setup behavior checks passed. Analysis, format and diff checks
passed. Initial portable captures covered five states at 1080p, 1440p, 2160p
and 2160p/DPR2/text200%. Final follow-up captures covered those five states at
1080p, 2160p, 2160p/DPR2/text200% and 720p/text200%, plus enlarged open/closed
numeric and grouping dropdowns and a native-4K switch with whole-row activation.
All five final normal-text 1080p captures are byte-identical to their preserved
pre-change references, independently confirmed by Astra. Astra inspected the
final native-4K Sources, enlarged open dropdowns and compact enlarged Review.
[Source and capture hashes](design/desktop-ui/scaling/group-2a-evidence.json)
identify the final evidence. Earlier 1440p captures precede the control follow-up.

This completes portable setup scaling integration, not physical Windows
validation or a new approval of the skipped Mini-marathons design. Independent
review was not run; no separate review is specifically recommended for this
presentation-only group. The existing Windows evidence boundary still applies.

## Group 2b — onboarding

Luna task `01a0975b-7b68-7b63-a14a-d5115a669ba2` returned its lease for onboarding
and the geometry of the shared notice/empty-state widgets. Profile portraits,
badges and spacing, linking QR captions and spacing, server rows and onboarding
buttons now follow the shared viewport scale. Astra additionally corrected the
empty-server caller's inherited typography; the shared empty-state widget still
leaves text scaling with its caller. PIN entry and authentication logic were not
changed.

Ten existing onboarding checks passed, including after Astra's integration.
Analysis, formatting and diff checks passed. Seven normal-text 1080p captures
(Welcome, Profiles, Servers and four linking states) are byte-identical to the
preserved baseline, confirmed by Astra. Portable captures also passed at 1440p,
2160p and 2160p/DPR2/text200%; additional empty-server/error-notice states were
exercised. Astra inspected final native-4K Profiles, enlarged Linking and the
corrected native-4K empty-server state. [Evidence hashes](design/desktop-ui/scaling/group-2b-evidence.json)
exclude superseded empty-server captures. The final empty-server typography fix
was recaptured at native 4K; it preserves the scale1 font values.

No independent review was run or is specifically recommended for this group.
Physical Windows acceptance remains outstanding.

## Group 2c — Channels directory and overlays

Luna task `01a09773-cfa8-72f2-9abb-e97141cf8918` completed the initial pass and
a bounded overlay follow-up, then returned its lease. Header controls, action
padding, selection controls, reorder icons and row menus now scale with the
shared reference. Number columns accommodate enlarged text. Move dialog sizing
and typography scale locally, with scrolling retained. Astra caught and returned
an initially unscaled Move text theme and an incorrect popup constraint override;
the follow-up preserves Flutter's default popup width policy at scale1. Channel
state, health, ordering and deletion behavior remain with their existing owners.

Twelve existing Channels/navigation checks passed, along with targeted analysis,
formatting and diff checks. Main-view captures passed at 1080p, 1440p, native
2160p and 2160p/DPR2/text200%. Final popup, Move and Delete captures passed at
1080p, native2160p and 2160p/DPR2/text200%. All six normal1080 states are
byte-identical to true pre-change references, independently confirmed by Astra.
Astra inspected the corrected native4K Move dialog and enlarged Reorder/Delete.
[Source and capture hashes](design/desktop-ui/scaling/group-2c-evidence.json)
record the evidence and distinguish earlier main-view captures from final overlays.

No independent review was run or is specifically recommended for this
presentation-only group. Physical Windows validation remains outstanding.

## Group 2d — Studio and schedule preview

Luna task `01a09791-b55f-7561-9f1f-64d80e5d4c0e` completed Studio and Air Check
presentation scaling, with bounded follow-ups after Astra's visual inspection.
Studio's inherited body text now receives the viewport scale once. Native
controls, local dialogs, editor fields, spacing and preview rows follow the
shared reference. Astra corrected one remaining standard-button font owner;
Luna then removed the native ListTile height limit from enlarged Browse actions
using a local row layout above scale1. Original scale1 rows remain intact.
Scheduling, save/currentness and source-selection behavior were preserved.

The final combined existing suite passed 91 checks (67 Studio and24 Air Check);
analysis, formatting and diff checks passed. Final portable capture runs cover
1080p, 1440p, native2160p and2160p/DPR2/text200%, including opened dropdowns,
Move, save/tune confirmation, native controls and Browse Add/Undo/selection.
Astra confirmed 13 normal1080 matches byte-for-byte: seven main views, five
supplementary states and recovery. Checked Browse selection has different inner
scroll positions between fixtures and is not claimed pixel-identical. Astra
inspected final native4K and enlarged Browse actions and the corrected native
Library/Move controls. [Source and capture hashes](design/desktop-ui/scaling/group-2d-evidence.json)
identify the final artifacts and evidence limitations.

These are synthetic portable captures, not Windows acceptance. No independent
review was requested or run, and none is specifically recommended for this
presentation-only group. Physical Windows validation remains outstanding.

## Group 3 — Guide

Luna task `01a097e3-c21a-7921-9175-bfec44eee9a4` returned its lease after
bounded integration follow-ups. Guide geometry, native controls, program-cell
measurements and preview/detail spacing follow the shared viewport scale.
The header accommodates enlarged text; controls share an available-width wrap
policy. Popup rows grow independently of their closed selected labels. Existing
rail allocation limits remain, without clamping actual accessibility text.
Normal text retains five rows; enlarged content remains scrollable. Fractional
raster seams receive local opaque coverage around the existing PiP aperture.
No controller, tuning, artwork lifetime or native playback owner changed.

Forty existing Guide, ticker and navigation checks passed, with targeted analysis,
format and diff checks. Final captures cover 1080p, 1440p, native2160p, native2160p
with text200%, 2160p/DPR2/text200%, and 720p/text200%; additional checks cover
the compact wrap boundary. Open library/hours menus, selected library/search
and a standalone Retry placeholder were captured. Astra verified five normal1080
images byte-for-byte and inspected the corrected native4K controls and enlarged
PiP. [Evidence hashes](design/desktop-ui/scaling/group-3-evidence.json) identify
the final sources and captures.

This is portable presentation evidence, not physical Windows validation. Native
video layering, Windows fonts/input and live monitor-DPI transitions remain
unvalidated. Independent review was not run and is not specifically recommended
for this presentation-only group.

## Group 4a — Player controls

Luna task `01a09815-dfcd-7a91-8982-fdc7eb3652e0` returned its OSD presentation
lease after a follow-up for initially missed option-action scaling. Identity,
action controls, spacing, caller-owned artwork limits, channel badge and progress
geometry now follow the shared viewport scale. Enlarged option actions can wrap.
The locked gradient, playback operations and artwork behavior remain unchanged;
Now Playing's shared badge branch is preserved.

Final focused checks passed: 18 OSD, one OSD clear-logo, two Guide clear-logo and
six navigation checks, plus analysis, format and diff checks. Twenty-six portable
capture cases cover normal1080,1440,native4K artwork, enlarged text at DPR1/2,
DVR, long track labels, disabled subtitles and compact windows. Astra confirmed
six normal1080 captures byte-identical and inspected final native4K actions and
enlarged DVR. [Evidence hashes](design/desktop-ui/scaling/group-4a-evidence.json)
identify the sources/captures.

The earlier full PlayerView run had66 passes and one track-panel font assertion
failure. Astra reproduced that failure on the pre-OSD commit: the test injects
a logical3840x2160 viewport with DPR2 and expects the retired1.35 font cap.
The remaining track-panel scaling group must resolve this; full-suite success
is not claimed. Physical Windows validation remains outstanding. No independent
review was run or is specifically recommended for this presentation-only group.

## Group 4b — Now Playing

Luna task `01a09838-016b-74a0-a6b2-591415e44758` returned its presentation
lease. The attached shelf, poster limits, typography, cast columns and name
measurements now scale from the1080 reference; the separate1500px shelf cap
is removed. Detail content still scrolls within a content-driven height cap,
with progress/time outside the scroll. Artwork lifetime, name abbreviation,
metadata and transitions remain unchanged.

Astra updated the existing native4K shelf/poster expectations to match the
approved proportional dimensions; all13 Now Playing behavior checks passed.
Worker clear-logo, navigation and OSD checks passed, with20 portable Now Playing
captures across sizes and content states. Astra verified four Now Playing and
two OSD normal1080 pairs byte-identical, and inspected final native4K and enlarged
artwork/cast shelves. [Evidence](design/desktop-ui/scaling/group-4b-evidence.json)
records final hashes and checks. The known track-panel cap assertion remains
for the drawer group; full PlayerView success is not yet claimed.

Physical Windows validation remains outstanding. No independent review was run
or is specifically recommended for this bounded presentation-only group.

## Group 4c — Audio, Subtitles and Sleep timer

Luna task `01a09848-3cb3-7c31-8969-538fc3d5160f` returned its drawer lease.
The protected rail/fade geometry now follows the uncapped shared reference above
1080p while retaining its compact floor. Native row spacing, selected/pending
indicators, Close controls and error typography scale together. Sleep timer
height respects the available viewport; Astra preserved its compact checkmark
size and scaled its corner radius. Track selection, focus, timer behavior and
the approved gradient remain unchanged.

All67 existing PlayerView checks passed again after integration, resolving the
previously recorded obsolete track-panel cap expectation. The worker completed
54 portable captures including deep selection, pending/error/focus, empty
subtitles and active timer states; Astra recaptured14 sleep cases after the final
correction. Astra verified all eight normal1080 PNGs byte-identical and inspected
native4K Audio and enlarged active Sleep. [Evidence hashes](design/desktop-ui/scaling/group-4c-evidence.json)
identify final sources/captures. Analysis, formatting and diff checks passed.

Empty Audio intentionally remains closed under existing product behavior.
Portable captures do not establish physical Windows acceptance. No independent
review was run or is specifically recommended for this presentation-only group.
Mini Guide, the shared Lineup menu and remaining Player status sizing still
require the scaling pass before campaign closeout.
