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
