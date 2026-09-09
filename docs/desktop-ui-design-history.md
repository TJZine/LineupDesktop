# Desktop UI design history

Historical discussion snapshot, September 8, 2026. Not an implementation authority.
Earlier proposals and open notes below were superseded during the same discussion.
Use the [consolidated specification](desktop-ui-design-spec.md) and
[implementation plan](desktop-ui-implementation-plan.md). Visual filenames here
identify historical comparisons; only the evidence manifest identifies retained
approved directions. No production work or independent review is recorded here.

---

# Desktop UI refinement specification

Status: design in progress, September 8, 2026. No application implementation or
commits are authorized by this document. This consolidates confirmed decisions
from the ongoing collaborative design session; unresolved choices remain open.
It restores the missing target already linked from the documentation index.

Use the [interface system](../.interface-design/system.md) for Cinema Continuity
tokens and protected Player geometry, and [architecture](architecture.md) for
ownership. This document describes proposed changes, not current capabilities.
The [implementation plan](desktop-ui-implementation-plan.md) maps the work to code
and verification. Mockups are composition evidence, not real Flutter or Windows
acceptance. Earlier alternatives rejected in conversation are not requirements.

## Global decisions

- Product intent: emulate cable/live-TV programming and guides. Channels follow
  continuous schedules independently of app sessions or viewer actions; the Guide
  describes that schedule. Balance recognizable programming patterns with variety.
  Evaluate all subsequent suggestions against this intent, not playlist-player or
  on-demand browsing assumptions. App restart, tuning and opening management UI
  must not reset or randomly change a channel's established timeline.
- Primarily mouse and keyboard; preserve existing supported remote/media input.
  Generic gamepad support is not implied.
- Keep the premium upstream-inspired presentation, rich information, artwork,
  and PiP. Desktop efficiency must not erase that identity.
- Full names wrap rather than truncate. Essential information is not hover-only.
- All major surfaces must scale coherently across 1280x720, 1920x1080,
  2560x1440 and 3840x2160, including onboarding, management, Guide, Player
  overlays, Settings and dialogs. User will test 1440p and 2160p on their Windows
  monitor/TV setup. Higher resolutions must retain the approved visual hierarchy,
  legibility and premium presentation while using the available workspace;
  do not leave a fixed small interface surrounded by empty margins.
- Layout uses available screen width, with moderate growth in
  spacing and typography. The fixed centered workspace with large surrounding
  margins was rejected. Implement using logical window dimensions and text/display
  scaling, not a physical-resolution switch or whole-page shrink transform.
- Distinguish physical resolution, effective logical window size, Windows display
  scaling and independent text scaling. A 3840x2160 display at 200% scaling has
  roughly a 1920x1080 logical workspace; 4K at 100% has substantially more room.
  Preserve comfortable control sizes and balanced proportions across these
  conditions; do not let extra pixels automatically produce tiny text or excessive
  data density. Test maximized/fullscreen and resized windows, including moving
  between monitors with different display scales. Record resolution and scale in
  acceptance evidence. Existing 720p/1080p mock approvals establish direction,
  not untested 1440p/2160p or mixed-DPI acceptance.
- User clarified: preserve the same structure across all four resolutions as
  much as possible, extending the approved balanced 720p-to-1080p relationship.
  Higher resolution alone must not add columns, rearrange major regions or turn
  the interface into a denser workspace. Scale spacing/typography proportionately
  within the approved responsive approach; reflow only when effective window
  constraints or accessibility scaling require it.

- Preserve meaningful controls; do not add redundant actions or ineffective
  choices. Distinguish hover, persistent selection, tuned state, and keyboard focus.
- Escape remains contextual Back rather than a new fullscreen-exit shortcut.
  Preserve separate fullscreen controls. Backspace mirrors Back outside editable
  fields; inside editable fields it remains editing, even when empty.
- Back closes the top applicable overlay first. Back from Player opens Guide.
  Settings returns to its origin; do not introduce Guide over Settings/Player as
  a substitute for returning. Guide Back returns to Player when playback exists,
  otherwise to the Lineup menu.

## Guide — confirmed direction and behavior

### Live timeline and now marker — locked

User accepted the ground-up current-and-upcoming direction, including retiring
the Past window setting and its saved preference. No configurable history or
deliberate backward browsing into earlier half-hours. Fresh live entry and Now
start at the current half-hour boundary (08:47 -> 08:30), without extra history
padding or an artificial offset to center the now marker. Existing saved history
values cease to affect the Guide; unrelated preferences remain intact.

- Keep one thin, noninteractive current-time line, aligned exactly between the
  time ruler and program grid using one time/geometry snapshot. Preserve the
  approved live accent, with no glow, pulse, wide band or duplicate row labels.
  It must not intercept cell input, obscure focus outlines or restart tickers.
- At an exact half-hour, keep the marker visible at the grid's left boundary;
  edge fades must not hide it. Do not displace the actual time coordinate for
  aesthetics. Ruler text/marker decoration must avoid collisions without moving
  the time line. When now is outside the visible range, hide the line rather
  than pinning it misleadingly to an edge; retain the existing Now action.
- An already-started program clips to the window, but its information panel
  shows actual start/end and full-duration progress. No fake new start time.
  Incidental ended entries within the current half-hour remain inspectable and
  cannot tune. Initial live focus and Now target the airing occurrence on the
  selected channel, preserving library/search and vertical channel position.
- Rollover must not move cells under active inspection, pointer activation or
  keyboard/remote navigation. Advance the clock/marker and airing state in place;
  do not forcibly snap the viewport every half-hour. A temporarily retained older
  window is reading-position preservation, not an intentional history mode.
  Now explicitly restores the current boundary. Returning to the Guide preserves
  an intentional future view; an elapsed live window is refreshed to the current
  boundary while preserving channel/filter context. Do not auto-retune.
- Left navigation from future listings may return to the current half-hour, but
  cannot move earlier. At that boundary use the Guide's established channel-column
  focus route; do not wrap to future time or repeatedly reload an unchanged window.
- Implementation acceptance: exact boundary, just before/after rollover, long
  programs clipped on the left, short ended cells, future browsing, Guide return,
  program ending while focused, text scaling and marker alignment at all agreed
  resolutions. Re-evaluate current/ended status at activation so an expired cell
  cannot tune as if still airing. Windows evidence remains required later.

This supersedes earlier references to the configurable Guide past-time decision.

- Preserve the information area and active PiP, including existing cold-start
  handling. No shorter cold-start information design or redundant Watch button.
- Single-click inspects; double-click and Enter/remote Select tune the airing
  program. Past/future entries remain inspection-only. Returning to the currently
  tuned channel must not restart it.
- Library picker above channel column; one actual Plex library or All libraries.
  Show a full wrapping removable library label above the schedule. Removing it
  retains search. No multi-library selection in this package.
- Search by channel name/number within library scope. Search is always visible
  in the approved control strip; no show/hide preference or collapsed mode.
  Ctrl+F focuses the field. Escape in a nonempty field clears its query and
  retains field focus; Escape in an empty field returns focus to the Guide
  without hiding search. That event must not also trigger Guide Back; a subsequent
  Escape follows normal Guide Back behavior. Backspace remains text editing.
- Preserve session search, library, time and inspection across Guide/Player/
  Settings. Restart/profile/server change resets transient search/library/time.
  Now resets time while retaining filters. Filtering never retunes.
- Preserve presentation preferences through the existing settings owner, except
  the explicitly retired history/density settings and narrowed time-span choices
  below. Reflow before shrinking readable text; validate long names, short windows
  and enlarged text.
- Loading, no matches, row errors and tune errors retain usable navigation and
  appropriate active playback. Do not claim a previous stream remains playing
  unless playback state confirms it. Retry is contextual. Completing a tune after
  the user leaves must not unexpectedly navigate to Player.
- Real artwork/PiP compositions, narrow layout and exact focus behavior
  still need final matched Flutter acceptance during implementation.

### Time span and channel rows — locked

User approved one carefully refined comfortable channel-row layout. Remove the
Compact mode and its density control; saved density preferences no longer select
an alternate layout. Preserve the premium information/PiP area. Maintain consistent
proportions across 720p, 1080p, 1440p and 2160p rather than automatically increasing
row count with resolution. Enlarged text and smaller-window accommodation remain
required; these are accessibility/resizing behavior, not a second density mode.

Hours shown remains a separate horizontal setting: 2 hours by default, with 3 and
4 hours available. Remove 6/8/12-hour visible-span options without reducing how far
ahead users may browse. Mapping a previously saved removed time span remains an
implementation-plan detail to resolve explicitly before execution.

Next visual decision: title/subtitle hierarchy and row spacing in the full Guide,
with the information area and PiP present. Determine the visible row count from
that composition, not an arbitrary count target. Exact geometry is not yet locked.

### Guide row comparison — hierarchy locked; overall geometry open

User requested upstream webOS as option 1 versus a ground-up option. Inspected
the read-only Lineup checkout at `19e7f0886f8dde900b703dd086dd902836d16cf3`:
`src/modules/ui/epg/styles.cells.css`, `constants.ts`, and
`view/cells/EPGCellPresentation.ts` / `EPGCellRenderer.ts`.
Upstream uses show title plus episode subtitle, separate episode metadata/time
rail, and width/focus-specific reductions; focused episodes suppress cell time
and enable overflow tickers. Its row-height fallback is 108px; runtime geometry
is not established merely by that fallback.

`guide-row-directions.html` presents a schematic upstream-informed arrangement
versus a ground-up refinement using a stable title / Sx Ex + episode-title pair,
without per-cell time labels. Exact times remain in the shared information panel.
Both use identical synthetic schedules, PiP/info context and five-row composition
to isolate hierarchy, plus 2/3/4-hour comparisons. This is not a pixel-exact
upstream capture or a complete reproduction of its width-tier algorithm.
Five rows and shared showcase geometry are comparison scaffolding, not a newly
approved final Guide geometry. Toolbar is contextual; only row inspection and
comparison controls are demonstrated. No production changes or Windows validation.
Option 2 is recommended for stable hierarchy and title space; user selection
and narrow-cell/episode-tag refinements remain open.

User preferred option 1's top-right episode tag, with refinements from option 2.
`guide-row-refined.html` proposes independent top/bottom text lines: top-right
episode tag only consumes title-line width; omitted bottom-right time reserves
no subtitle space. Episode subtitle remains present regardless of generic width
tier. Show cell times only when the entire subtitle plus time and a comfortable
gap fit; movies can show times without inventing a subtitle. Metadata visibility
does not change merely on selection; selection activates eligible text tickers.
The three-hour Harbor Lights case is the default comparison and now retains its
unfocused subtitle. Previous option 1 is available as historical reference.
For extremely narrow cells the prototype omits the episode tag before leaving
almost no title space; this fallback, exact fit thresholds, and overall appearance
remain proposals for review. Text measurement/ticker mechanics are illustrative,
not a production acceptance test. This supersedes the prior recommendation to
move episode tags into the subtitle line and omit all per-cell times.

#### Final cell hierarchy and episode-tag rule — locked

User accepted the refined upstream-informed composition and confirmed that the
focused cell's season/episode information is available in the top information
area. Information priority is show title, episode title, episode identifier,
then per-cell time. Preserve independent top and bottom text lines and the
opportunistic time rule above.

- Keep the season/episode tag top right when the complete show title, tag and
  comfortable separation fit. If retaining it would truncate the show title,
  omit the tag and return that space to the title. Exceptionally long show
  titles that overflow even without a tag retain the title space and use the
  approved focused ticker.
- Do not move tags to the subtitle row or switch their position between cells.
  Do not reserve space for hidden tags or times. Keep episode subtitles present
  independently of tag visibility and generic cell-width tiers.
- Evaluate actual available width and rendered text, including text scaling;
  do not hide all tags solely because the Guide shows four hours.
- Focus does not change tag/time visibility or text geometry. The top information
  area supplies the complete episode identifier when inspecting a cell.
- This supersedes the prototype's extremely narrow-cell fallback: hiding only
  after almost all title space is consumed was rejected as too late. The existing
  mock remains composition evidence and does not yet demonstrate this final fit
  rule. Exact padding and text measurement require implementation verification.

Next design decision: overall Guide proportions and visible row count, retaining
the premium information/PiP area and the locked comfortable two-line cell layout.
Compare the current five-row reference with a six-row composition if it can
preserve readable type and comfortable spacing; neither count is locked yet.

Row-count comparison presented in `guide-row-count.html`: A uses five 64px rows
and a 240px information region at the 720p reference; B keeps that information
region with six approximately 53px rows; C uses a 216px information region, a
smaller 16:9 PiP and six approximately 57px rows. Cell type sizes are held constant
across these alternatives; only vertical spacing and, for C, information/PiP
geometry change. These are mock dimensions, not approved Flutter constants.
The mock includes the final title-first episode-tag fit rule.

User raised whether an extra row should depend on resolution. The comparison
scales each composition proportionally to 1080p; both canvases fit the same preview
width and therefore intentionally retain the same apparent proportions. This is
composition evidence, not native-resolution readability or Windows DPI evidence.
Recommendation pending selection: favor A for the standard 16:9 composition;
C is the stronger six-row alternative, while B has the least vertical breathing
room. Do not automatically add rows based on physical resolution alone. Any
adaptive row policy must respect usable logical height, text/display scaling and
the agreed premium information area, and remains an explicit unresolved choice.

#### Final row-count decision — locked

User accepted A as the default and sole supported standard 16:9 composition:
five comfortable channel rows with the larger information/PiP area. Do not
reintroduce Comfort/Compact, a six-row preference, or automatic extra rows based
on physical resolution. Preserve the approved proportional presentation across
720p, 1080p, 1440p and 2160p. Smaller windows and enlarged text still require
accessible accommodation; the five-row target must not force clipped content.

C is retained only as a documented future alternative. Reconsider it if actual
usage demonstrates a need for more channels per view; it is not deferred required
implementation scope. This supersedes the unresolved row-count and adaptive-row
proposals above. The mock's exact pixel values remain illustrative and require
matched Flutter validation with full content and display/text scaling.

Next design item: resolve the actual library/search/time-control strip, replacing
the composition mock's placeholder controls while preserving the already locked
library scope, search, Now and time-span behavior.

#### Guide control strip — locked

User authorized a comp of the recommended direct controls before deciding whether
to cut or relocate any. `guide-controls.html` shows the five-row A composition
with the library picker above the channel column and Search, Now and a visible
2/3/4-hour selector at the right. Remove redundant All channels text and the
placeholder Options menu. Search, Now and Hours shown retain stable positions.
The actual library name appears as a full, removable
label above the schedule, sharing the available middle portion of this strip;
it wraps when necessary without reserved space when no library is selected.
The picker caption becomes Libraries when the separate active label is present.

The synthetic comp includes default, expanded search, selected library, combined
long-library/search and no-match states. Picker selection, scoped channel search,
filter removal and hours selection are interactive examples; full application
focus/navigation, schedule continuity, arbitrary library metadata and Windows
scaling remain implementation acceptance work. Exceptionally tall wrapped labels
must not compress cell typography: accommodate the available grid viewport.
User approved this placement with one final refinement: search is always visible,
using the quiet field styling and width shown in the combined state. The initial
expansion decision protected vertical space, but expansion offers no vertical
benefit in this strip. Remove the proposed Always show search preference and all
collapsed-search requirements. Keep the placeholder Channel name or number and
an accessible search label; the clear action appears only with a nonempty query.
Ctrl+F and Escape follow the confirmed behavior above. The active library label
wraps within its available area rather than squeezing search or shifting Now and
Hours shown. The approved composition is recorded in `guide-controls.html`.
No further layout refinements were required at lock. This is design approval,
not an implemented or platform-validated feature.

Next behavior decision: inspected selection and information-panel fallback when
library/search filtering excludes the selected channel or produces no matches.

#### Filtering, inspection and no matches — locked

User accepted the following behavior without further refinements:

- If the inspected channel still matches the library/search scope, preserve its
  inspected program and timeline position. If it is excluded, inspect the first
  matching channel's program covering that same time. Filtering never tunes.
- Keep keyboard focus in search while typing. Updating inspection and the top
  information area must not move typing focus into the grid. Enter from search
  moves focus into the selected result; it does not also tune. A separate Enter
  from an airing Guide cell follows the normal tuning rule.
- With no matches, retain active PiP playback and the information area's geometry.
  Replace selected-program information with No matching channels and Try another
  channel name or number. Do not substitute currently playing details as if they
  were a selected result. Use existing search-clear and library-remove controls;
  do not add Reset filters.
- Preserve the last valid inspected channel/program and timeline through the
  empty-result interval. When results return, restore that inspection if available;
  otherwise inspect the first matching channel at the preserved time.
- Clearing search preserves the current valid inspection rather than returning
  to the top or a previously excluded channel. These are selection-restoration
  rules, not permission to reset time or playback.
- No-result Enter has no result to enter or tune. The single Escape event that
  clears search or leaves the empty field must not also execute Guide Back.

The control-strip mock predates this behavior lock; its no-match information and
selection fallback are illustrative and must not override these requirements.
Next design detail: explicit mouse access to future-time browsing and returning
through the timeline, integrated with the approved Now and Hours shown controls.

#### Mouse timeline navigation — behavior and placement locked

User accepted 30-minute steps for Earlier/Later, consistently across the 2/3/4-hour
visible spans. Keep a compact Earlier / Now / Later group beside Hours shown.
Arrow accessible labels describe Earlier by 30 minutes and Later by 30 minutes.
Earlier remains visible but unavailable at the current half-hour boundary.

- Preserve selected channel and vertical position. Preserve the inspected
  occurrence while it remains visible; otherwise inspect the nearest visible
  program on that channel. Timeline navigation never tunes.
- Keep focus on the activated arrow for repeated navigation rather than sending
  it into the grid. Rapid actions update the latest requested destination without
  queueing a long animation sequence; stale loads cannot replace newer results.
- Now restores current programming on the selected channel while preserving
  library/search filters. Existing rollover and current-boundary rules still apply.
- Distinguish the visible timeline's date from the actual clock/header date,
  including midnight crossings. No hold-to-accelerate or extra jump control.

`guide-timeline.html` proposes the visible window's starting date in the ruler's
left corner, replacing the redundant CHANNEL caption, and a compact date label
at the midnight tick when a view spans two dates. No extra header row or loss of
channel height. Live-boundary, future, midnight, tomorrow and filtered states
are available for visual review. Synthetic schedule continuation is illustrative;
it is not a scheduler algorithm, loading-race test or production browsing horizon.
User approved the arrow-group appearance and date placement with no further
visual refinements. Preserve the compact starting-date label in the ruler's left
corner and the midnight date annotation without adding another row. Display dates
and times consistently with the app's locale/time-format policy; the English
synthetic labels demonstrate hierarchy rather than mandating a hard-coded locale.

Next Guide design decision: presentation of schedule loading, partial row failure
and unavailable listings while preserving usable navigation, inspection and PiP.

#### Loading/recovery comparison — researched; recommendations not locked

User requested the recently iterated upstream webOS policy as a first-class
reference before choosing desktop behavior. Inspected upstream HEAD `fb63d1a9`
and the existing, locally modified recovery/warmup plan as contextual design
history; upstream files were not edited. Historical execution instructions are
not current authorization. Source anchors:

- `src/modules/ui/epg/runtime/EPGScheduleRefreshRuntime.ts`: targeted retry,
  matching in-flight coalescing/adoption, matching-range terminal failure,
  usable cached/held schedules, and guarded failure publication.
- `src/modules/ui/epg/view/EPGVirtualizer.ts`, `view/cells/EPGCellRenderer.ts`,
  `styles.cells.css`, `styles.motion.css`, `focus/EPGFocusNavigator.ts`, `types.ts`:
  full-row loading/retrying placeholders, skeleton shimmer with reduced-motion
  bypass, static unavailable text, and OK routing to retry rather than tuning.
- `docs/plans/2026-09-04-guide-loading-recovery-and-startup-warmup-plan.md` and
  `docs/qa/reports/2026-09-05-guide-pro-adjudication.md`: immediate Guide reveal,
  visible-first bounded work, no additional Guide automatic retry layer, targeted
  source revalidation bypassing completed negative/empty results while preserving
  useful in-flight/sibling work. Physical hidden-warmup proof gaps and deferred
  performance work remain documented upstream.
- Upstream `5b8b39dc`: preserves cached source fallback during explicit
  revalidation instead of discarding it before attempting fresh resolution.

Recommended shared product policies: reveal Guide immediately; reuse compatible,
still-usable schedules; prioritize current/focused and visible channels; reserve
loading/retrying for actual current work; settle unsuccessful work as unavailable;
retry only the requested row and coalesce repeated activation; never auto-tune on
recovery; never publish cancelled/superseded failure; retain same-range terminal
failure on ordinary scroll/reopen rather than creating an automatic retry loop.
Keep playback, channel ordering and established schedule continuity independent
of Guide loading. Cache reuse requires matching source/channel context, schedule
coverage and an explicit validity policy, not merely the existence of old data.

Ground-up desktop recommendation largely converges with upstream. Proposed visual
adaptation: a quiet row-sized placeholder with readable Loading schedule… or
Retrying… status, restrained optional motion respecting Reduce Motion, and a
static Schedule unavailable row with an explicit Retry affordance. One logical
retry action should support mouse and Enter/remote Select without duplicate focus
stops. No page-wide failure banner for an isolated channel. No user-facing warning
for background revalidation failure while a still-valid schedule remains usable;
this supersedes the preliminary suggestion to add a refresh-failed retry notice.
Do not expose fake program boundaries/durations for missing schedule data.

Do not import webOS's numeric TTLs, 96-channel background ceiling, concurrency-one
limits, 1500ms warmup point or browser-specific request scheduling as desktop
requirements. Preserve their priority/resource-ownership intent and establish
desktop bounds from its actual owners and measurements. Flutter already has
loading/ready/error rows, per-row retry, request prioritization, generation guards
and timeouts (`lib/guide/guide_controller.dart`); `_Programs` in
`lib/guide/guide_view.dart` currently displays a thin loading indicator and
Schedule unavailable — select to retry. This source review is not a completed
desktop correctness or performance audit.

Next comparison should use matched loading, one-row-unavailable, manual-retry and
usable-cache-refresh states in the approved desktop geometry. Upstream-informed
visuals must be labeled adaptations rather than actual webOS screenshots.

`guide-recovery-directions.html` now compares A (upstream-informed row-sized
shimmer skeletons and static Unavailable — OK to retry wording) with B (ground-up
static Loading schedule… / Retrying… status rows and a clear Retry affordance).
Both share approved desktop geometry and the proposed recovery policies. Scenarios
include all-loading, partial loading, one unavailable channel, manual retry,
retained valid listings after refresh failure, and recovered listings. Retry enters
a controlled demonstration state; scenario selection supplies the outcome rather
than pretending to contact a server. A is an adaptation, not a webOS screenshot.
B's text-led treatment is the current recommendation; choice remains open. The
shared information-panel fallback is illustrative and not separately approved.

#### Final recovery-row presentation and motion — locked

User selected B and accepted the final subtle-dot-pulse refinement. Use the quiet
row-sized status treatment with stationary Loading schedule… / Retrying… labels.
Only the small supporting-color dot gently varies opacity; no moving skeletons,
spinning indicator, bouncing, travelling highlight or animated text. All visible
loading/retrying dots share one calm rhythm, including rows joining an existing
loading state. The reference uses an illustrative 1.8-second cycle with modest
opacity variation; this is not a loading timeout or a required wait before showing
content. Reduce Motion uses a steady dot and unchanged text. Settled unavailable
rows are static, with Schedule unavailable and the explicit Retry affordance.
Stop loading motion when the attempt settles or the surface leaves view. Never
keep a loading animation alive to mask a terminal failure.

The updated composition reference is `guide-recovery-locked.html`; the prior A/B
file is retained only as comparison history. It demonstrates controlled loading,
retrying and outcome states, not production asynchronous correctness. The shared
recovery policies described above remain the recommended implementation basis.
No production implementation was authorized by this lock.

#### Information area during missing schedule data — locked

When the inspected channel is loading, retrying or unavailable, retain the
premium information-area geometry and display that channel's name and number
with the corresponding quiet status. Clear unrelated program metadata from the
previous inspection. PiP and actual playback remain unchanged. Keep Retry on the
affected Guide row only; do not duplicate the action in the information area.

When data arrives, show the program at the preserved inspection time only if
that channel is still inspected. Do not reclaim focus from another control or
channel, move the user back, or tune automatically. The composition reference
is illustrative; this lock defines the required selection and asynchronous
behavior rather than claiming the prototype implements it.

#### Empty schedule versus failed request — locked

Use Loading schedule… only while work is active, Schedule unavailable with Retry
for a failed request, and No programs scheduled in this time range when a
successful request establishes that the displayed range has no scheduled programs.
The confirmed empty state has no Retry action; retain the existing time controls
for browsing other ranges. The information area shows the inspected channel's
identity and the same explanation, with PiP unchanged. Do not invent program
blocks or imply permanent channel unavailability. An unknown or failed result
must not be presented as a successfully confirmed empty range.

## Welcome and Plex linking — confirmed

- Explicit browser launch. Starting sign-in requests a code without opening the
  browser. Open browser launches the valid linking URL; it is not proof of login.
- Centered horizontal group, left-aligned instructions/actions, QR on the right.
  Preserve visible QR, complete code, copy action and manual linking address.
  Brand remains above; status and cancellation share the footer. Reflow narrowly.
- Stable valid code across focus changes. Expiry disables the old code and offers
  Get a new code; no automatic browser launch or automatic code replacement.
- Browser failure retains QR/code/manual route. Success advances to profiles.
  Cancel returns to Welcome only after cancellation succeeds; failure offers retry.
  Results belong to the active linking attempt.

## Profiles, PIN and servers — confirmed

- Profiles use open avatar groups, aligned avatars, full wrapping names and nearby
  metadata. Whole group is selectable. Reduce columns rather than truncate names.
- PIN uses centered dialog, compact avatar/name identity, four indicators, keypad,
  Delete and Cancel. No redundant Clear. Reserve error space; keyboard works
  immediately; fourth digit submits. Incorrect PIN clears and restores entry.
  Backspace on empty PIN does nothing; Escape cancels to the originating profile.
- Servers use an open list with full names and ownership. Previously used denotes
  saved selection, not reachability. Current denotes the active server.
- Connection facts must be verified. Failures/retry appear with the relevant row.
  No speculative Online labels or redundant Connect for the working current server.
- Refresh only refreshes discovery; it must not automatically connect/navigate.
  Saved-server startup reconnection is a distinct behavior.
- Remove Clear saved server from this page. Show profile switching only when
  meaningful; use Back when a valid destination exists, not both Back and Cancel.

## Setup: libraries and scanning — confirmed

- Open checkbox rows, full names, quiet library type on the right (below when
  narrow). Whole-row activation, selection count and Scan selected libraries.
- Select all is tri-state and appears only for multiple libraries. Do not add
  speculative search/filter controls. Selection precedes scanning.
- Preserve selection on cancellation; return to editable selection. No extra
  cancelled screen, Resume fiction, or classification of unfinished scans as empty.
- Progress and outcomes stay in their rows; no invented percentage. All-ready
  success advances. Mixed outcomes stay for explicit Continue with ready libraries.
- Explain excluded libraries above actions. Retry failed scans retains valid
  successful results from that attempt. If none are ready, hide Continue and
  promote applicable Retry. Empty is neutral; failure is an error.
- Known unusable libraries have an explanation/recheck route. Do not silently
  remove them. Inventory eligibility is not a guarantee of successful playback.

## Setup: channel sources — confirmed

- Three configuration sections: Channel sources, Playback order, Lineup rules.
  Shared generated-count footer and Review channels action.
- Channel sources uses two columns and source-local grouping controls. All eight
  source families retain useful descriptions/examples and inclusion information.
  No expandable row design that adds height without meaningful savings.
- Grouping applies only to supported sources (genres, studios, actors, directors)
  and meaningful multi-library cases. Explain the actual grouping operation.
- Keep full labels/examples visible and wrapping. Counts distinguish qualifying
  candidates from included channels when limits apply. Disabled sources cannot
  expose effective grouping controls. Stable visual order is separate from build
  priority, edited explicitly in Lineup rules.

## Setup: playback order — confirmed

- Three choices: Shuffle, In order, Mini-marathons; one changing illustrative
  episode strip. Explain In order as preserving source order, not new chronology
  sorting for generation. Later shared Mini-marathon decisions supersede the
  original supplied-episode-order rule: generated and custom channels follow
  season/episode chronology, stay within seasons per block, and rotate shows.
  Generation's chosen mode/block size remain intact. Include specials is an
  approved builder-level Mini-marathon option beside block size, off for new
  configurations. It applies only to Mini-marathon outputs, including additional
  versions using that mode. No per-generated-channel override in Studio; show
  the effective setting read-only there. Existing generated channels retain their
  specials inclusion until explicitly updated. Apply the approved scheduling
  transition policy below.
- Additional channel versions off by default. When enabled, separate alternate
  schedules from another playback mode. Initial alternate is one where applicable.
- In order has no meaningful alternate schedule. Explain inapplicability. Prevent
  duplicate mode/block-size combinations; different block lengths may be variants.
- Show eligible counts/exclusions and actual channel impact. No eligible channels
  must not leave ineffective active settings. Changes to the primary mode resolve
  invalid combinations visibly, rather than silently adding channels or duplicates.
- Approved invalid-selection transition: clear only affected redundant/ineligible
  extras, preserve valid extras, and update counts immediately. No confirmation
  dialog, automatic substitute, or automatic restoration when switching back.
- When switching to In order, explain “Alternate schedules aren’t available with
  In order.” If an extra In order version now matches the main mode, clear it and
  show “Extra In order version removed—it now matches your main playback order.”
  A different Mini-marathon block length stays valid; an identical combination
  does not. Visible controls remain authoritative.
- Extra allocation follows the approved lineup rules below.

## Setup: lineup rules — confirmed

- Limits left, source order right, full-screen two-column composition.
- Default generated maximum 200; minimum programs 5. Movies and individual
  episodes count as programs. Extra versions count toward the generated cap;
  custom/retained channels can make the final lineup larger.
- Balanced rotation: take one eligible original from each enabled source in
  priority order, repeat, and skip exhausted sources.
- Original channels get priority over additional versions. Fill remaining capacity
  with extras only after original selection. This changes current expansion/cutoff.
- Allocate extras in rounds: one extra per eligible selected original before any
  receives its second, following approved original/source priority. Prioritize a
  requested different playback mode before alternate shuffle versions. Skip
  ineligible or duplicate versions; do not generate extras for excluded originals.
- Compact footer breakdown, for example “200 channels · 160 originals + 40 extra
  versions”, followed by “Channel limit reached · 24 extra versions excluded”.
  Report excluded originals separately when present. Omit exclusion copy when
  everything fits; when no extras are requested, simply show “160 channels”.
  All counts derive from actual allocation, not estimates. No extra panel,
  tooltip or expandable disclosure for this breakdown.
- Full-width ordering rows, name left/arrows right, quiet spanning dividers and
  whole-row hover/focus treatment. Moving arrows inward was rejected.
- Keep disabled sources visible with Off and their saved positions; inclusion
  belongs on Channel sources. Focus follows reordering, including list boundaries.
- Concise repeat/skip explanation rather than duplicating all source names below
  the list. Neutral all-fit state; amber included/excluded-by-limit feedback.
- Footer says generated channels; Review gives the final composed-lineup count.

## Review — composition approved; remaining behavior open

Approved direction: option A, compact overview above a full-width channel roster,
with a review-composition bar and a stable bottom decision/action area. This
supersedes the earlier side-summary and bottom-overview alternatives. Synthetic
390- and 1,000-channel comparisons informed the selection; mocks are not rendering
performance evidence or final pixel specifications.

- Current-to-final lineup total leads the existing-lineup overview. Keep vertical
  padding restrained to preserve roster space.
- Label the bar “Changes in this review”. Add “Includes channels being removed”
  when removals exist. Its denominator includes outgoing entries; it is not the
  final-lineup composition. Replacement review entries may exceed final channels.
- Unchanged, Updated, Added and Removed counts remain readable outside the bar.
  Counts filter the roster, expose selected state, and pair with an obvious Show
  all action. Zero removals are neutral; reserve coral for actual removals.
- Filtered count uses “Updated · 60 matching channels”. Search matches full name
  or number. Search/filter empty results must report zero accurately.
- Source breakdown is explicitly “Final generated channels”, with consistent
  quiet label/count pairs. Custom channels are excluded from this breakdown and
  their protected status is explained separately.
- Roster columns: number, full wrapping name, source, playback and change. Keep
  headers visible while the roster scrolls; preserve lazy production rendering.
  Updated entries disclose only changed fields with before-to-after values and
  a disclosure indicator that follows expanded state.
- Bottom method, explanation, Back and primary action retain stable placement.
  Removal confirmation sits immediately above. Back preserves configuration.
- First-time setup uses the same composition with “390 channels ready to create”
  and Create lineup. Omit irrelevant method selection, change filters and removal
  confirmation. The refined mock also omits the all-added composition bar.

The refined synthetic reference is `review-polished-states.html` in the task's
visualization evidence; consolidate the approved reference into repository-owned
synthetic evidence before implementation handoff. Earlier comparison mocks are
historical options, not competing implementation authorities.

Build method belongs on Review beside its consequences. Existing methods remain
in scope: update/add matching generated channels, replace generated channels, and
add as new channels. The comparison mock's omission of Add as new does not remove
that capability. Approved default for an existing lineup: Update and add.
Replace generated channels remains an explicit choice with removal confirmation;
Add as new channels remains a secondary choice for deliberately creating another
set while retaining existing channels. First-time setup uses Create lineup.
Current source still defaults to replacement; this is a planned behavior change.

Upstream reference inspected read-only September 8: sibling Lineup HEAD
`19e7f0886f8dde900b703dd086dd902836d16cf3`,
`src/modules/ui/channel-setup/steps/BuildReviewStepController.ts`, and the
September 1 LG C3 review capture. Upstream emphasizes current/final totals,
stay/leave/new composition, source totals, and confirmation rather than a full
channel roster. This is reference evidence, not authorization to copy its build
semantics or claim Desktop validation.

Approved Review transitions and empty states:
- Changing method refreshes counts, bar and roster together, preserves search and
  filter, and clears removal confirmation because consequences changed.
- While recalculating, preserve layout, show “Updating review…” and disable apply.
- When no changes are needed, show “Your lineup is already up to date”, retain the
  roster, replace Apply with View lineup, and retain Back to configure. View lineup opens
  Channels without saving a no-op plan. This supersedes the earlier Done label.
- Search with no matches shows “No matching channels” and Clear search; distinguish
  this from an empty lineup. Filter-only zero results retain Show all.
- Require confirmation only for actual removals, always with the exact count,
  including when a composition-bar segment is tiny.

Approved changed-lineup safeguard:
- Check that relevant lineup state still matches the reviewed plan before applying.
  Do not apply an outdated plan against changed state.
- Refresh counts/roster while preserving setup choices, search and filter. Show
  “Your lineup changed. Review the updated changes before applying.” inline.
- Clear removal confirmation and require another explicit Apply after refreshing.
  Ordinary tuning/playback changes do not invalidate Review.
- No additional dialog or permanent control. If refresh fails, keep Apply
  unavailable and offer Retry review.

Approved Add as new presentation:
- Third method, after Update and add and Replace generated channels. Label
  “Add as new channels”; primary action “Add channels”.
- Explanation: “Keep your existing lineup and add every channel in this selection
  as a new channel.” When matching generated channels exist, add “Matching
  channels will be added separately, not updated.”
- No additional checkbox, panel or advanced toggle. Show assigned numbers in
  Review; available numbers can include gaps, so do not promise append-at-end.
- Explain channel-number exhaustion separately from the configured generation
  limit. Display the actual selection that fits rather than imply excluded
  candidates will be added.

Approved replacement semantics:
- Replace removes existing generated channels and creates the reviewed selection
  afresh, preserving custom channels. A same-name recreated channel is Removed
  plus Added, not Updated; it receives a new identity and schedule.
- Example: 360 current → 390 final, with 350 removed, 380 added and 10 unchanged.
  State “Your 10 custom channels will be kept.” separately.
- Method explanation: “Replace all generated channels with this selection.
  Custom channels will be kept.” Confirmation: “I understand that 350 existing
  generated channels will be removed.” Use singular grammar where appropriate.
- Keep separate Removed and Added rows with visible status even when names or
  numbers match. Do not add a Replaced category that obscures actual accounting.

Edge-case mock inspection: full names wrap; single-removal count, filtered row
and confirmation remain explicit despite a tiny bar segment. Use singular/plural
copy correctly. Approved enlarged-text fallback: allow the page to scroll at 720p when needed
to keep every detail and action accessible. Normal-size layouts retain the fixed
overview and footer. Production focus/scroll checks remain required.
Synthetic reference: `review-edge-cases.html`. These checks are not Flutter or
physical Windows validation.

## Build results — wording, behavior and visual direction approved

- Progress: “Creating your lineup…” or “Updating your lineup…” with a small
  indeterminate indicator. No invented percentage, artificial delay or Cancel
  during the noncancellable save. Avoid technical commit/atomic wording.
- First-time success: “Your lineup is ready” and “390 channels in your lineup”.
  Existing-lineup success: “Your lineup is updated”, final total, and a compact
  summary of nonzero additions, updates and removals. Counts describe saved
  composition, not a guarantee that every channel can play.
- Do not repeat Review's bar/source breakdown, zero counts or duplicate completion
  headings. View lineup is primary and opens Channels. Add a custom channel is a
  quiet secondary action opening Studio. No automatic navigation.
- No changes: “Your lineup is already up to date” and “No changes needed.” Use
  View lineup and secondary Back to configure; skip saving.
- Failure: “We couldn’t create your lineup” / “We couldn’t update your lineup”.
  With confirmed rollback, use “Your lineup wasn’t saved.” for first-time setup
  or “Your existing lineup hasn’t changed.” for an existing lineup, followed by
  “Your setup choices are still here.” Include a short actionable reason when
  known. Do not claim rollback when persistence outcome is uncertain.
- Back to review is the failure primary action, preserving choices and allowing
  inspection before retry. No competing direct retry action.
- One stable headline area; a restrained completion mark replaces progress.
  No celebration effect or lingering progress bar. Respect reduced motion.
  Focus the resulting primary action without allowing a held Enter key to
  accidentally activate it.

Approved synthetic visual direction: `setup-result-states.html` in task
visualization evidence. Retain the minimal result treatment and familiar footer
actions; final spacing and focus checks remain implementation acceptance work.

## Channels — full-width directory and management refinements approved

Approved composition: A, full-width directory opening a separate Studio workspace.
B's integrated narrower roster/editor is not selected. Synthetic comparison:
`channels-directory-options.html` in task visualization evidence. The Studio
preview is partial, not an approved replacement for its complete controls or
unsaved-draft behavior.

- Number/name/source/playback/type hierarchy, full wrapping names and quiet row
  dividers. Search by name or number, All/Custom/Generated filters. Row activation
  opens Studio; remove the redundant open icon. Preserve known issue explanations
  and list search/filter/scroll/focus on return. No Needs attention filter or new
  Watch action.
- Add a custom channel is primary; Generate lineup is secondary for a populated
  lineup. Empty state reverses that emphasis and avoids duplicate header actions.
- Approved bulk management: quiet Select control reveals checkboxes, selected
  count and Delete selected. Select all matching means current search/filter
  results. Confirmation gives the count and states Plex media is unaffected.
  Selection controls disappear when finished.
- Preserve selection by channel identity across search/filter changes. Show
  “12 selected · 4 outside this view” when appropriate. Select all matching adds
  current results; Clear selection clears all; Cancel exits selection mode.
  Row activation toggles selection while in this mode instead of opening Studio.
- Delete selected opens one confirmation containing total, Custom/Generated
  breakdown and a scrollable list of full names/numbers. State “Your Plex media
  won’t be deleted.” Explain possible regeneration when generated channels are
  included. No bulk save before confirmation.
- Delete as one validated batch. On failure preserve selection for retry and use
  outcome-accurate copy; on success exit selection mode, preserve search/filter,
  and restore focus to a nearby surviving row or relevant empty-state control.

Final selection refinements recorded for implementation:
- Select all matching captures current results, not future matching additions.
  Clear search must not clear selection. Never target hidden channels merely
  because they match a query; selected identities are the authoritative scope.
- Make the selected-count summary actionable as Show selected, allowing inspection
  of the complete selection without losing the prior search/filter. Label this
  view clearly and provide Back to results. This supplements the confirmation list.
- Confirmation primary says “Delete 12 channels” (singular where appropriate),
  with Cancel initially focused. Disable deletion when selection is empty.
- If selected identities or relevant channel details change before persistence,
  refresh the confirmation and require renewed confirmation; never silently
  expand the confirmed target set. Do not invalidate on ordinary playback changes.
- Selection and reorder are separate modes. Keep unrelated mutation controls out
  of selection mode; preserve search/filter access. Repeated activation while a
  deletion is pending cannot launch a second deletion.
- Generated-channel row menu includes Duplicate as custom, opening a draft while
  retaining the original. Delete belongs in the secondary row menu.
- Rename/number and individual programming/playback editing stay in Studio.
  Generated selections are managed through Generate lineup. Deletion does not
  permanently exclude a generated source: later generation can recreate it.
- No permanent Watch buttons, general Refresh, health dashboard or separate Clear
  lineup action. Do not add controls without a distinct useful responsibility.

Approved reordering:
- Explicit Reorder channels mode, reached through a quiet action. Show the full
  lineup; retain previous search/filter for return to normal browsing.
- Explain “Channels appear in number order. Reordering changes channel numbers.”
- Preserve existing numbered positions and gaps; redistribute them according to
  the draft order. Example: moving the last of 10/20/30 first retains those same
  positions, not 1/2/3. Show old → new numbers on affected rows only.
- Drag handles plus Move up/down controls support mouse, keyboard and remote.
  Move before… / Move after… opens a searchable channel picker for long-distance
  moves across large lineups.
- Save order applies the reviewed changes together. Cancel discards the draft.
  Preserve channel identity and programming; do not introduce a separate display
  order that disagrees with numbers. No changes are saved during draft movement.

Approved toolbar/menu arrangement and final refinements:
- Normal: name/number search and All/Custom/Generated filters, with visible quiet
  Select and Reorder channels actions. Do not bury these in a generic Manage menu.
  Header retains Add a custom channel / Generate lineup.
- Selection: retain search/filters; separate wrapping action strip contains selected
  summary, Select all matching, Clear selection, Cancel and Delete selected.
  Hide unrelated mutation controls and row menus while selecting.
- Show selected is a clearly labelled inspection view; Back to results restores
  the previous query/filter. Avoid presenting an active search that suggests it
  still constrains this complete-selection view.
- Reorder: full lineup with changed-number summary, Cancel and Save order.
  Disable Save order until the draft differs. Disable boundary movement controls.
- Generated row menu: Duplicate as custom, Delete. Custom row menu: Delete only.
  No redundant Open item. Menus must remain reachable by mouse/keyboard/remote,
  stay within the viewport and restore focus to their invoking row control.
- Mutating actions remain disabled while saving; preserve drafts/selections on
  recoverable failure and guard against repeated activation.

Refined synthetic reference: `channels-management-refined.html`. Selection at
720p and changed-number reordering at 1080p were visually inspected as HTML;
this does not establish Flutter, focus, drag or physical Windows acceptance.
User accepted the refined management composition and final refinements. Current
source ownership: ChannelsView in lineup_shell.dart, Studio in
channel_studio_view.dart, persisted channel mutations in lineup_controller.dart.

## Channel Studio — consolidated design approved

Synthetic reference: `studio-layout-directions.html`. A refines the existing
full-width schedule above programming and station settings. B places compact
identity/playback fields above a programming workspace with the schedule beside
it. User selected B for sustained editing and large hand-picked channels.
Keep the programming workspace beside the persistent schedule preview, with
compact identity/playback fields above. A remains comparison evidence only.
This approves the composition, not every control or state in the mock.

Hand-picked programming uses two views in the left workspace: Browse library
and Channel programs. User approved these labels and the two-view approach;
replace the user-facing Rundown label. Each view retains its search, scroll and
selection state when switching. Keep the schedule visible on the right rather
than dividing Studio into three competing columns. Channel programs describes
the chosen source list; the schedule preview is authoritative for airing order
under shuffle or mini-marathons.

Channel programs controls approved: rows show position, full title, applicable
episode details and duration; unavailable entries remain visible with an
explanation. Remove acts on the channel entry, never Plex media. Support drag,
keyboard movement and Move to for large jumps. Searching locates entries without
changing their order; a reorder action returns to the complete list with the
entry focused so hidden rows cannot obscure its destination. Explain “Plays in
this order” for In order and “Playback order determines the schedule” for shuffle
or mini-marathons. No separate bulk-removal mode in the initial control set.
Existing repeated entries must remain individually addressable; removing an
entry in Channel programs must not remove other occurrences of the same title.

Approved: Browse library is an adding surface, with
explicit Add / Added states instead of membership checkboxes that also remove
programs. Keep removal in Channel programs. Search, library and media-type
controls remain prominent; additional facets use a compact Filters disclosure
with applied filters visible. Make all matching results reachable rather than
requiring users to narrow searches beyond the current first-100 result window.
Show Added immediately after adding to the draft, with a brief Undo opportunity
that reverses only that addition. Added reflects membership in the whole draft
across searches and filters, prevents accidental duplicate additions, and does
not remove existing repeated entries. Adding changes the draft; Save changes
remains the persistence boundary.

Approved: explicit Select mode for bulk adding, with
checkboxes for eligible programs, Add selected (N), and Cancel. Already-added
programs retain Added status and cannot be selected again. Preserve selection
across search/filter changes and disclose selections outside the current results.
Cancel clears only pending browse selection. Add selected appends the selected
programs to the draft, returns to normal browsing with position preserved, and
offers Undo for that batch alone. Ordering is selection order, exposed
in a Show selected view; never let a later search/filter change silently reorder
the pending additions. No default Add all matching action. Disable Add selected
when the selection is empty. Show selected uses the pending append order and
allows deselection; selecting an item again appends it to the pending selection.
Undo targets only entries created by that addition, preserving unrelated draft
edits and pre-existing occurrences. No additional confirmation for adding to the
unsaved draft. Any unavailable selected items must be explained explicitly;
never report the entire batch added if some entries could not be added.

Library-switch filter handling approved: preserve filter intent
when changing libraries, retain unavailable values visibly rather than silently
dropping them, and require explicit resolution of values absent from the new
library before saving. Show the actual new match count independently of value
availability; zero combined matches does not imply a filter value is invalid.
Do not equate incomplete/failed inventory with confirmed missing values. Show
Checking filters while unresolved; keep Save disabled until unavailable selected
values are explicitly replaced or removed. Offer removal of unavailable values
as an explicit action without clearing valid filters. Do not clear flagged values
merely by switching libraries; switching back revalidates the retained choices.

Source switching approved: preserve inactive choices for the current Studio
editing session; only the active source is saved. No confirmation on each switch.
Explain “Only the selected source is saved. Your other choices stay available
while editing.” Incomplete sources explain what is missing and disable Save;
never silently reuse the previous source's programming.

Existing mixed-source handling approved: preserve the combined source and show
a read-only summary of its constituent sources and composition. Do not imply
that its programming is individually editable through the three simple source
choices. Explicit Replace source enters Library / Plex playlist / Hand-picked
replacement editing; viewing the summary alone does not mutate anything. Keep
the original combined source available until successful Save so cancelling the
replacement restores it without loss. Replacement follows normal source draft,
validation and save/leave rules. State that it replaces all combined programming,
not just one constituent source. Do not add a new mixed-source builder/editor.

Source organization A approved: three choices Library / Plex playlist /
Hand-picked, with collection as a prominent optional Library field and additional
filters disclosed below. Alternatives considered: retain the current four choices
for direct collection discovery, or use Whole library / Collection / Filtered
inside Library (more explicit but duplicates overlapping choices). The existing
Library and Collection/filter editors both resolve to LibrarySource, with optional
filters; merging the UI does not require inventing a new source type. A collection
must not become difficult to discover behind a generic collapsed Filters control.
Library editor: library picker, prominent optional collection picker (Any
collection means no collection restriction, including uncollected programs),
Add filter with visible removable criteria, visible Include watched items,
matching-program count and inspectable results. Source ordering is separate from
membership filters. If a library has no collections, explain that in the
collection field without blocking whole-library or other-filter use.

Multi-select filter model approved, superseding the single-value proposal:
match ANY selected value within a criterion and ALL criteria together. Multiple
collections combine membership; the same Plex media identity matching multiple
selected values is included once. Do not deduplicate distinct media identities
by title or change intentionally repeated hand-picked entries. No configurable
Boolean-expression editor. Collection and supported categorical filter pickers
use searchable checkboxes and explicit Done. Show selected values grouped under
their criterion, with expansion for long selections. Explain “Any selected value
within each filter; all filters together.” Preserve zero-match selections and
distinguish membership filters from search used only to inspect resulting programs.
This expands the existing single-string-per-filter source contract; source
representation, persistence and all resolution paths need an implementation map
before execution. Do not treat this as a cosmetic picker-only change.

Picker behavior approved: local pending checkbox choices, Done applies
as one draft edit, Cancel/Escape discards pending picker changes, selected values
remain selected across picker searches, and clearing the final selected value
removes that criterion's restriction rather than matching nothing. Keep the
picker within the programming workspace with a scrollable value list and stable
Done/Cancel actions; no additional confirmation. For long summaries show a few
full value names plus an explicit additional-value count and accessible expansion.
Expanding a summary only reveals the full selection; it does not enter editing
or change the draft.
User selected B, the temporary full-width Programming panel, with refinements:
quiet library/criterion context, clickable selected count to inspect selected
values only, stable row ordering during checkbox changes, and restoration of
editor scroll/focus to the invoking control on Done or Cancel. Use Updating count
while a matching count is pending rather than presenting an obsolete result.
Comparison reference: `studio-filter-picker-options.html`, A anchored picker
versus B temporary full-width Programming panel, both within approved Studio B
and schedule-preview B. B recommended for long names, large value inventories
and predictable positioning. Both include searchable checkbox rows, visible
selection counts including selections outside search results, Clear selection,
stable Done/Cancel footer, and the approved pending matching-program count. This
previews membership without recalculating the schedule
until Done. The mock demonstrates Genre and Collection with synthetic values;
other Studio controls and schedule recalculation are outside this comparison.
HTML inspection of B at 720p and A at 1080p does not establish platform acceptance.

Plex playlist source retained by user approval: label the custom Studio source
Plex playlist, not a separate playlist page or editor. Explain “Uses an existing
Plex playlist. Manage its contents in Plex.” This references an existing playlist;
it does not create, edit or reorder Plex playlists. Normal generation already
creates generated playlist channels; custom Studio offers an individually managed
channel without running generation. Generated playlist programming remains
read-only. If another channel uses the same playlist identity, show its number
and full name with Open channel; do not count the channel currently being edited
as another use. Allow intentional additional channels. Use existing channel
identity/source data rather than title matching or a new duplicate-management
subsystem. Opening another channel observes the agreed unsaved-draft leave flow.
No expanded playlist-management or synchronization feature set is approved.

Ordering discussion superseded the expanded sorting-menu proposal. Collections
supply membership, not their Plex display/custom sort order. Keep playback modes
distinct from source sequencing. New custom channels default to Shuffle; existing
channels retain their saved mode. Shuffle is a stable shuffled rotation, not a new
random choice on each tune. No main-generation setting change is implied.
Fresh reproducible shuffle cycles approved for ALL shuffled channels, generated
and custom: continuity does not require repeating the identical cycle. Use a
different deterministic shuffle per complete cycle: stable across app restarts,
tunes and Guide/Studio projections, but varied between cycles. Future cycles must
be reproducible before they begin rather than randomized on completion. Preserve
once-per-cycle membership semantics, intentional source occurrences and bounded
projection; avoid immediate cross-boundary repeats where feasible without
promising unique permutations for tiny pools. This is a scheduling-model change,
not merely a new UI label. Generation's mode choices/defaults remain unchanged;
Shuffle has the same cycle behavior regardless of channel provenance. Ordered
and Mini-marathon channels retain their established sequencing and repeat their
pattern rather than adopting fresh per-cycle shuffles. Transitioning existing
shuffled schedules must preserve the established current cycle and activate fresh
subsequent cycles at its boundary, with that transition reproducible across
restarts. Exact persistence/projection design remains implementation-planning work.

Scheduling transition policy approved: automatic app upgrades preserve the entire
current cycle and activate revised scheduling behavior at the next cycle boundary.
Explicit Studio Save or builder update applies the reviewed programming changes
when saved; retain the approved warning when this changes what is on now. This
does not authorize silently changing the existing specials-inclusion preference.
Opening Studio/Guide, tuning or restarting must not reset the channel timeline.
Persist enough transition state for restart and future Guide projections to agree;
do not repeatedly defer the boundary each time the app starts. Race handling,
time arithmetic and historical model details belong in the implementation plan.
In order remains explicit: Library/collection sources use movie title order or
show/season/episode order; Plex playlists and hand-picked sources retain their
supplied sequence. Stable tie-breaks, missing metadata and preservation of existing
saved schedules still require the implementation map. Do not add the previously
floated expanded Title/Date/Rating sorting menu as an approved requirement.

Mini-marathon chronological behavior explicitly approved: a block contains
consecutive included episodes of the same show and same season, ascending by
episode number (e.g. S1E1, S1E2, S1E3 for a three-episode block). This is a
Mini-marathon scheduling rule, not a mutation of Plex or hand-picked source order.
Current blockOrder preserves supplied within-show order and does not enforce
season boundaries; implementation must address both differences deliberately.
Approved boundary behavior: a season ending before the configured block
size yields a shorter block, then rotation advances to the next show; the next
turn for the original show resumes with its next season. Missing episodes are
skipped without padding or stalling; use available included episodes in ascending
number order. Entries without usable chronology remain after numbered episodes
in a separate group, with an explanation rather than silently being excluded.
Do not classify unknown season metadata as Season 0. Exact fallback ordering
remains to be specified. After a complete rotation, repeat the established block
pattern and episode progression. User raised excluding specials as an
alternative; the subsequent specials decision below supersedes Season 0 first.

Specials option approved: Include specials is off by default for new custom
Mini-marathon channels. When enabled, Season 0 specials form their own blocks,
ordered by episode number after that show's regular seasons. Preserve existing
channel behavior until explicitly changed; missing season metadata is not a
special. Show a quiet, factual N specials excluded summary only when applicable.
User requires an elegant treatment consistent with approved Studio style.
Final presentation direction: compact subordinate controls on the same settings
row as Playback order, containing Episodes per block and Include specials; no separate panel, banner
or settings page. When inclusion is on, a short helper explains placement after
regular seasons. Keep session choices while switching playback modes; these
controls apply only to Mini-marathons. Final approved spacing is in the subsequent
space-refinement reference below, including the 1440p/2160p structural intent.
Superseded visual reference: `studio-playback-refinement.html` shows the
subordinate block-size / Include specials group in approved Studio B, with mode
switching and synthetic chronological blocks including shortened season endings.
The 1440p/2160p selections deliberately preserve the 1080p normalized composition;
they demonstrate structural intent, not native pixel/DPI validation. Other source
editors and save behavior are outside this focused control mock. The specials
inclusion switch applies only to Mini-marathons, not other playback modes.
User requested a further Studio composition refinement: Mini-marathon secondary
controls on the Playback order row and materially more visible schedule rows at
720p. Preserve Cinema Continuity cohesion, artwork and information hierarchy;
do not force density at the expense of the page's premium presentation.
Approved visual reference: `studio-playback-space-refinement.html`. Uses a shared
top settings row, tighter header/workspace spacing and a more compact selected-
program block. Synthetic 720p inspection showed four complete schedule rows;
1080p showed six with these short titles. These are fixture observations, not
guaranteed row counts for long names/enlarged text. Keep full-title wrapping,
approved synopsis expansion and accessible reflow. The normalized 1440p/2160p
composition is illustrative only. User accepted this refinement; it supersedes
the preceding stacked Mini-marathon controls and roomier preview geometry.

Approved: Mini-marathon availability and mixed-source behavior.
keep the mode visible but unavailable for movie-only sources, with an explanation
that it groups TV episodes. Mixed sources retain movies as single-program turns
alongside episode blocks, never silently dropping films. For a single-show source,
explain that there is no other show to rotate to rather than implying that block
size inserts a break. If a source change makes the selected mode inapplicable,
retain the selection, explain the mismatch and require an explicit valid mode
before saving; never silently switch modes. Loading or incomplete source data
must not be treated as confirmed movie-only content.
Presentation refinement: retain the approved shared settings row. Use a concise
contextual helper under Playback order, not a new panel/banner. Suggested copy:
movie-only option “Mini-marathons groups TV episodes”; mixed source “Movies play
individually between episode blocks”; single show “Only one show is included;
episodes continue without switching shows.” An actionable invalid-mode explanation
takes precedence over ordinary helper text: “This source has no TV episodes.
Choose another playback order.” Explanations must be reachable by keyboard/remote,
not hover-only on a disabled option. Show block/specials controls only where
applicable, while preserving their session values. Do not change the approved
overall Studio geometry for these states; verify wrapping and focus during the
combined implementation acceptance pass.
Save destination approved: remain in Studio after successful save with a quiet
saved confirmation; tuning stays a separate deliberate action. Preserve editor
position and focus rather than returning to Channels or automatically tuning.
The approved dirty-leave dialog and save/tune failure flows follow.
User accepted the proposed ordinary save/leave flow: Saving prevents repeated
submission, successful save retains position, failed save retains the draft with
an actionable error, Keep editing / Discard changes guards dirty leave with
Keep editing initially focused and Escape dismissing, and navigation is guarded
during save. No Save and leave action. User proposed an exception to disabling
Tune in for dirty drafts: confirm save-then-tune. User approved this refinement.
Locked wording:
“Save changes and tune in?” / “Your changes to this channel will be saved before
playback starts.” Actions Keep editing and Save and tune in. Persist only this
channel's draft, not a generated-lineup rebuild. Use the same save validation and
operation as normal Save; tune only after confirmed success. Save failure retains
the unsaved draft; tune failure after successful save retains the saved result and
reports playback failure without implying rollback. For incomplete/invalid drafts,
explain what must be fixed before offering save-and-tune. No discard-and-tune
alternative. Keep editing is the noncommitting dialog action; Escape dismisses
without saving or tuning. Prevent repeated activation during the save/tune sequence.

Conflict/deletion recovery approved: retain the draft. If the saved channel has
changed, offer Use saved version or Replace saved version, each with an explicit
confirmation of which complete version is discarded. Revalidate the saved base
at commit, including after confirmation; never overwrite a further change silently.
If deleted, explain that the original no longer exists and prevent ordinary Save
from recreating it. Offer Save as new custom channel and Return to Channels.
Save as new custom channel deliberately creates a fresh custom identity, strips
generation ownership and uses normal validation/preview requirements. Preserve
draft content and edits; propose an available number, show any changed number
before the user commits, and recheck availability at save. Do not overwrite an
occupied number or recreate the deleted identity. On failure retain the recovery
draft; on success remain in Studio editing the new saved custom channel. Use one
contextual recovery area consistent with Studio, not a separate recovery page.
Source-availability behavior approved: retain source selection and draft when a
playlist/library is unavailable or filters match no playable programs. Explain
the specific condition beside the relevant source controls. Prevent Save and tune
for unresolved invalid programming; do not silently substitute content or clear
choices. Confirmed zero matches offers adjustment of criteria; failed loading
offers a retry appropriate to the actual failure owner. Keep loading, unavailable
source and no matches distinct; incomplete data must not masquerade as a final
zero count. Existing previous-preview labelling applies to retained schedule
results. Use one contextual explanation/action rather than repeating the same
failure as multiple banners across Studio. Partial usable content requires an
accurate included/unavailable summary, preserving approved retained-entry rules.

Source inspection confirms generated channels allow name and number edits;
their programming and playback order remain read-only. Preserve this distinction
and the existing duplicate-as-custom route. Existing Air Check distinguishes
saved versus draft schedules, stale calculations, source availability, comparison
failures and programming changes that affect what is on now. These safeguards
must survive the layout refinement.

Schedule-preview treatment B approved by user: `studio-preview-directions.html`
keeps approved Studio B and compares A artwork-led (shallow landscape above
details) with B schedule-led (compact artwork beside details). Use B
to retain more upcoming-program space; A remains comparison evidence only.
The selected treatment includes quiet full-width schedule
rows, explicit On now versus Upcoming, selected-program details without tuning,
conditional Back to now, date context across midnight, and an unpadded text
fallback when artwork is absent. Saved/draft state and the existing changes-now
warning remain separate from artwork. Synthetic schematic artwork illustrates
proportions only, not final media rendering. HTML inspection is design evidence,
not Flutter or physical Windows validation. Loading/error/long-content behavior
is specified below but not fully demonstrated in that mock; the left editor is context,
not a complete interactive demonstration of its approved controls.

Approved preview behavior: full titles wrap; long synopses offer Read more /
Show less without losing the inspected program or schedule scroll position.
Retain prior results during recalculation with Updating preview; failures retain
the draft, offer Retry preview and label retained results Previous preview.
Preserve the inspected occurrence across recalculation when it still exists;
otherwise return to now with a short explanation. Preserve existing save
validation requirements and explain a disabled Save near the action. An old
preview must not be presented as validation of the current draft.

Schedule reach approved: six-hour extensions up to 24 future hours. User approved
current-and-upcoming only: omit completed occurrences and do not add a past-program
toggle in Studio. Keep the current occurrence's real start time even before now.
The Guide's configurable past-time setting is a separate open design decision
for the Guide pass; this Studio decision does not change Guide behavior.
Source clarification: the current six-hour window
starts one hour before now, normally providing roughly five future hours.
Approved replacement: current program plus six future hours, Show next 6 hours
appending in place up to 24 future hours, explicit dates and actual coverage end,
no partial last program or duplicate boundary occurrence, preserve selection and
scroll on extension. A failed extension should retain already-valid coverage
and allow retry without invalidating that coverage merely because expansion
failed. The 24-hour UX limit is a product decision, not a scheduler constraint.
The scheduler currently caps each projection at 1,000 occurrences; implementation
must preserve honest coverage reporting and bounded computation when extending
short-program schedules. Never label truncated coverage as the full requested day.
The current program retains its real start time even when before now; computing
it does not require displaying completed programs. The old horizontal ribbon
uses past context to place its now marker inside the timeline, whereas the
approved vertical preview has explicit On now identification.

The comparisons cover focused synthetic states rather than one complete Studio.
Combined state review reference approved by user:
`studio-consolidated-review.html`, with normal Library, generated, pending filter,
unavailable library, number collision, changed/deleted channel and save-and-tune
confirmation compositions. Number-error copy spans the identity group rather
than wrapping into a tall column beneath the narrow number input. Recovery stays
within the existing Programming region; save confirmation uses the shared warm
dialog treatment. This mock is for composition/wording review, not complete
source editing, schedule computation, focus containment or persistence behavior.
Previously approved hand-picked/playlist/mixed-source contracts remain in force
even where this review mock omits their detailed controls. Four resolution
selectors demonstrate normalized structural intent, not physical-DPI evidence.
Consolidated decision review findings — all three approved:

- Resolved scope gap: apply Mini-marathon season/episode chronology and season
  boundary rules to generated and custom Mini-marathon channels consistently,
  superseding the earlier Setup supplied-within-show-order wording, without changing
  generation's mode/block-size choices or silently applying Studio's new specials
  default to generated channels. The scheduling transition policy above is
  approved. Generated specials are
  now approved as a builder-level option, not a Studio override. User separately approved
  this cross-channel Mini-marathon behavior, in addition to fresh Shuffle cycles.
- Count clarity: source match/selected counts and scheduled playable counts are
  different when specials are excluded or entries are unavailable. Approved
  labels: 32 matching programs in the source; 30 scheduled programs in preview;
  2 specials excluded beside the playback setting. Do not imply excluded specials
  were removed from the source or combine exclusion and availability reasons.
- Pending local choices: an open filter picker or pending bulk-add selection
  has changes that have not yet joined the channel draft. Require Done /
  Add selected or Cancel before Save/Tune; explain Finish choosing genres (or
  equivalent) rather than silently ignoring or applying pending choices. This
  supplements rather than replaces the approved Save and tune confirmation.

The user accepted the combined Studio state review. Product decisions and visual
direction above are locked; reconcile older mock labels and incomplete interactions
against this ledger during implementation planning. Long-content/accessibility
stress cases and actual Flutter/Windows validation remain acceptance work, not
claims established by visual approval. Detailed stable chronology fallback rules
and implementation ownership must be mapped without reopening accepted product
choices unnecessarily.
Mock interactions do not establish production behavior or Windows acceptance.
Current owners: `lib/app/channel_studio_view.dart` and
`lib/app/channel_air_check.dart`. The referenced `docs/channel-studio-spec.md`
is absent in this checkout; use inspected source rather than treating that
missing document as verified authority.

## Player-facing overlays — shared presentation principle

User established a shared principle for Mini Guide, player OSD, and Now Playing
information: preserve as much video transparency as reasonable, emerge from the
screen edge, and blend smoothly into playback, carrying forward the upstream
webOS intent. Avoid treating these as opaque floating panels. This principle is
approved; exact gradients, focus fills, motion, and contrast treatment remain
collaborative design decisions. It does not authorize OSD/Now Playing structural
implementation or replace their protected baseline.

Proposed direction: edge-anchored warm-black gradients with stronger protection
behind information and a transparent tail beyond the last text/control. Keep
text/icons opaque, omit outer panel borders and shadows that create a hard edge,
and retain a clearly visible but translucent selection treatment. Compare against
a lighter continuous gradient using identical bright, dark, and busy synthetic
scenes before choosing strengths. Avoid scene-reactive opacity or blur as a
default without concrete evidence of need. Those details are not yet locked.

Refined comparison: `mini-guide-edge-blend.html` holds the five-channel layout
constant and offers A continuous fade versus B shaped fade (recommended), with
bright/dark coast and busy city-light synthetic backgrounds. Both remove the
outer edge/border/shadow, use translucent selection and opaque text, and extend
the fade beyond the footer. B sustains more contrast behind lower rows. These
static synthetic scenes support direction selection only; moving footage and
physical display contrast remain necessary before final opacity acceptance.

## Mini Guide — layout, gradient direction, and dismissal locked

User explicitly prefers an overlay descending from the top; do not pursue a
side panel. Keep playing video beneath it and preserve the app's warm, premium
visual language. Current implementation is top-aligned and exposes five nearby
channels (`_MiniGuide` in `lib/playback/player_view.dart`, `miniGuideChannels`
in `lib/playback/player_coordinator.dart`).

User selected A, the five-channel top layout, from
`mini-guide-top-directions.html`; B's three-channel layout is not the chosen
direction. The mock's nearly opaque background and hard bottom edge were
explicitly rejected as inconsistent with the shared overlay principle above.
The comparison proposed aligned Channel / On now / Up next columns, restrained
progress indicators, separate browsing highlight and Watching state, wrapping
names, explicit Full Guide and Close actions, and compact browse controls.
User approved B's shaped gradient from `mini-guide-edge-blend.html`: maintain
legibility behind all five rows and fade beyond the final controls. Exact
darkness remains subject to real moving-footage/display validation; do not
revert to an opaque panel. The layout A/B and gradient A/B are separate choices.
Top-entry motion should be brief and respect reduced motion.

Dismissal is approved: no inactivity timeout. Stay open while browsing/reading;
close on tuning, Back/Esc, explicit Close, or a click on video outside the
overlay. Opening the Full Guide transitions to that surface. This deliberate
browsing behavior is distinct from transient OSD auto-hide behavior.
Input contract approved:
- Single click selects; double-click or Enter/remote OK tunes. Hover does not
  change selection. Preserve pointer targets between clicks so selection does
  not move a row out from beneath an intended double-click.
- Up/Down browses one channel. Mouse wheel browses inside the overlay; visible
  arrows provide a pointer alternative.
- Full Guide opens with the browsed channel focused.
- An outside click dismisses only; consume it so it cannot also pause playback
  or activate an underlying player control.
- Show concise hints appropriate to keyboard or remote input. Full Guide and
  Close remain visibly available.

Ordinary long-text behavior is locked below; enlarged-text accommodation remains
an acceptance requirement and must not clip text vertically.
Source inspection confirms the full Guide already uses `FocusedTicker` for
focused program titles and displayed episode subtitles. It measures overflow,
waits 900 ms, scrolls at 34 logical pixels/second, pauses 600 ms at the end,
resets and repeats; Reduce Motion disables animation. Existing widget tests
cover fitting text, delayed movement, and reduced motion (not rerun in this
design pass). Mini Guide currently uses static one-line ellipsis for channel,
current, and next titles; it does not use that ticker.

User challenged automatic row growth for long text and suggested ticker reuse.
Approved: retain compact rows for ordinary title overflow and
reuse the existing focused-overflow behavior in Mini Guide, only on the selected
row. Keep numbers/times/progress fixed and unfocused rows still. This is a
locked exception to earlier wrapping language, not approval to truncate names
elsewhere. Simultaneous overflowing labels in the selected row are approved;
do not add a sequential animation queue. Reduce Motion keeps text stationary
with ellipsis and complete accessible labels. No Show full text / Hide full text
control or expanded text disclosure: user explicitly rejected that addition.
User confirmed the full Guide displays a focused program’s full title in its
top information panel, providing the stationary program-detail destination.

Ticker refinement contract: retain a
selection dwell before motion; scroll only actual overflow at a consistent
reading speed, never accelerate long titles to fit a fixed duration. Keep row
geometry and hit targets stationary. Ordinary clock/progress rebuilds must not
restart motion; changing text, available width, text scale, or reading direction
must cancel the old run and remeasure. Selection change, overlay closure, app
inactivity, and enabling Reduce Motion must stop obsolete animation/timers.
Correct RTL origin/travel requires verification: the current widget measures
direction but uses left alignment and negative-X travel. Do not claim RTL ticker
support from measurement alone. Allow a small overflow tolerance to avoid
animation for rounding-only clipping. Preserve complete accessible text without
repeated animation announcements.

The ticker comparison used a 900 ms dwell, constant reading speed, and a
1.5 second endpoint pause. Use this as the visual starting point; confirm reset
smoothness in Flutter. Soft clipping may affect moving text boundaries only,
never adjacent times or indicators. Regression coverage must include rapid
selection/closure, unchanged rebuilds, content/size changes, direction,
reduced-motion toggling, and independent rows; existing three ticker tests do
not cover these cases.

`mini-guide-ticker-review.html` is historical comparison evidence. Its full-text
reveal and related controls were rejected and must not be implemented. Its
simultaneous ticker direction was accepted. The browser prototype does not
establish Flutter ticker lifecycle, RTL, or platform accessibility correctness;
those remain implementation acceptance work.
Mock background and schedules are synthetic;
resolution selectors express composition, not physical Windows validation.

Mini Guide edge states approved:
- Show Loading schedule… only while a schedule request is pending.
- Show Schedule unavailable on failure, without fabricated times or progress.
  Missing Guide data alone does not establish that playback is unavailable.
- Keep a channel with confirmed playback unavailability selectable, explain the
  reason concisely, and prevent a tuning action known to fail.
- For fewer than five channels, show each once with no filler rows; preserve
  the current unique-channel behavior.
- On program rollover update now/next in place, preserve selected channel,
  and restart only tickers whose displayed text changed.

## Remaining campaign scope

Sleep timer narrow role approved; placement under review: current OSD moon action and S
cycle Off / 30 / 60 / 90 minutes, restarting the timer on each duration choice.
Current label shows configured duration rather than remaining time; expiry calls
stop. Proposed direction is an optional one-session playback-stop timer, default
Off, with explicit preset choice rather than cycling. Preserve app/window and
continuous channel schedule at expiry; do not make this an OS sleep/shutdown
feature. Consider 15/30/60/90/120 minute presets, remaining-time/end-time status,
and a quiet pre-expiry notice with extension/cancellation. Invocation, exact
presets, expiry presentation, and lifecycle decisions need user agreement.
End-of-program stopping, inactivity prompts, and OS power actions are distinct
choices, not implied scope of a sleep timer redesign.

The later narrow-role decision supersedes the expanded proposal above: keep a
small optional playback-stop timer, without pre-expiry warnings, extension
prompts, dedicated completion screen, or computer power actions. Existing
30/60/90 minute range plus Off is the proposed scope. Source inspection found
an OSD moon action alongside Audio/Subtitles and a separate Lineup navigation
menu, but no existing secondary playback overflow menu. Placement recommendation
is therefore to retain the quiet moon entry point and open explicit choices
rather than invent a one-item menu or mix a session control into app navigation.
Inactive tooltip: Stop playback after…; active status: Stops in N min. S opens
the same picker. This placement recommendation is pending user agreement.

User accepted retaining the moon entry point. Visual review:
`playback-timer-picker.html` shows a compact bounded warm translucent picker
above that control, with Off / 30 minutes / 1 hour / 90 minutes and active
remaining-time status. Selection applies and closes; dismissal leaves the timer
unchanged and restores focus to the trigger. Re-selecting a duration starts it
from the selection time. The checked duration represents the configured preset,
not time remaining. Surrounding OSD is illustrative context, not approval of a
replacement protected OSD layout. Mock does not run an actual timer. Final
picker appearance is approved. Timer lifecycle is approved: counting continues
while paused and across channel changes, program transitions, and Guide
browsing. Manual stop, sign-out, and app exit cancel the timer; app restart
starts Off. Computer sleep does not extend the deadline; if it expires while
suspended, prevent automatic playback resumption on wake. At expiry stop
playback, clear the timer, and show Playback stopped by timer in the existing
stopped-player presentation. Later viewing rejoins live without restarting the
timer. These are design requirements, not claims of current platform behavior.

Audio/subtitle visual direction approved: `track-panel-directions.html`.
User accepted exploring separate right-side panels. Proposed composition uses
one heading, persistent Close, quiet scrolling rows, wrapping descriptive
labels, a selected checkmark distinct from focus, and Off first for subtitles.
A has a lighter continuous right-edge gradient; B (recommended) maintains
stronger contrast behind the reading area. Both blend inward without a hard
panel boundary. Labels are synthetic examples, not a claim that all displayed
metadata is currently available. Selection in the prototype is local only;
production confirmation, pending/error states, and metadata fallback need
their subsequent behavior/code-mapping pass.

User locked B with a very slightly broader, more transparent inward fade for
both Audio/Subtitles and Mini Guide. Preserve B's legibility behind text and
controls; soften only the transition toward unobstructed video rather than
reducing opacity uniformly. For Mini Guide this means the downward fade beyond
its information; for Audio/Subtitles it means the leftward fade from the right
edge. No additional comparison is required for this approved minor refinement.
Earlier B mocks are directional evidence; carry this refinement into final
design evidence and implementation acceptance.

Audio/subtitle selection feedback approved: preserve the active checkmark until
playback confirms a new selection. Show a quiet pending indicator on the
requested track when switching takes noticeable time. On failure, keep the
panel open with a concise error and reflect the track playback actually reports
as active. Distinguish Loading tracks… from a confirmed No subtitle tracks
available state. Selection applies directly with no Apply button; keep the
panel open after selection and do not use an inactivity timeout.

Mini Guide, audio/subtitle/sleep, Diagnostics,
navigation/Settings details and remaining recovery states need a final decision
and code-mapping pass. Broad earlier acceptance is not a substitute for recording
their exact design contracts. Preserve verified Studio behavior and
existing ownership while refining it. Player OSD/rich Now Playing structural
changes are a separate user-requested follow-up, not part of this package.

## Diagnostics — scope and refined A layout locked

Purpose accepted: help a viewer understand the current playback condition and
collect useful support information. Keep the cinema palette and quiet hierarchy;
avoid a developer dashboard or monitoring charts. Layout remains undecided.

User accepted the final scope and requested layout comparison. Approved contract:
- Compact current-state summary: actual playback state, Plex selection/reachability
  stated separately when evidence exists, and recording On/Off. A selected server
  name alone must never imply a verified connection. Unknown is not healthy.
- Secondary technical details: application version/build and platform, available
  current video dimensions/codec, decoder/output and signal information. Describe
  signal telemetry as reported media information, not proof of display HDR output.
  Missing values remain unavailable; stopped playback must not present stale
  telemetry as current. Do not add speculative GPU/driver collectors or charts.
- Readable recent events: local timestamp, area and concise message; expandable
  structured details. Preserve reading position, expanded item and keyboard focus
  as events arrive. Use a quiet new-events affordance when the user is reviewing
  older entries. No severity classification inferred from message wording.
- One primary Copy redacted report action: coherent snapshot of available support
  facts and retained events, with report time/time zone and recording state.
  Available even with no events. Confirm copy success; on clipboard failure retain
  context and offer retry. Build from explicitly permitted fields, not raw player,
  account or server objects; exclude identifying names, media titles, credentials,
  URLs and paths. Brief sharing guidance, not an absolute privacy guarantee.
- Recording remains owned by Settings > Support, reached through a secondary
  Recording settings action. Explain recording must be enabled before reproducing
  a problem, events are session-only, and only the latest 250 are retained.
  Disabling recording clears the retained events, as current code does; communicate
  that effect with the setting. Distinguish recording off from on with no events.
- No initial search/filter toolbar, clear-log action, auto-upload, export-format
  choices or new diagnostic tests. The bounded event list and whole-report copy
  serve the support task without adding a log-analysis workspace.

Evidence: Diagnostics currently retains at most 250 in-memory events, clears them
when disabled, and has no severity field or copy action. The current summary
shows status.message and serverName; neither should be exported as an unchecked
free-form privacy boundary. NativePlayer exposes technical telemetry, but its
availability and freshness need implementation mapping. These are proposed design
requirements, not claims of completed behavior or platform validation.

Next visual comparison after scope confirmation: a compact summary above a wide
event list versus a modest summary column beside the event list. Both must preserve
the same full-window proportional structure across the agreed resolutions.

Comparison presented in `diagnostics-layouts.html`: A summary above / B summary
beside, with expandable technical/event details and recording-on empty/off states.
A is recommended for message width and a simpler reading sequence; B gives the
event list more height. Resolution selections represent the same proportional
16:9 composition fitted to the preview, not physical display/DPI validation.
All telemetry and events are synthetic; copy/settings buttons demonstrate local
feedback only. Layout choice remains open.

User selected A and approved promoting general playback facts into its summary:
Playback (state and method), Video (current dimensions/codec), Media signal, Plex.
Move recording state and its Settings action to the Recent events heading area.
Keep the Technical details disclosure for build/platform, decoder/output and
deeper signal facts. Revised visual spacing remains to be reviewed.

Playback method is informational: accommodate Direct Play, Direct Stream and
Transcode from reliable current-session evidence without adding method controls.
User plans future transcoding features; do not gate diagnostic reporting on the
presence of those controls. Server session reporting must be correlated to this
player's active request; missing or stale evidence must not imply Direct Play.
Existing inspected playbackDescriptor requests original media parts directly;
server session-decision reporting is not yet established by that source inspection.
Preserve available per-stream decisions in Technical details because remuxing,
audio conversion and subtitle handling can differ within one session. Media
summary must describe the received video, not silently substitute source-library
metadata when transcoding changes resolution, codec or signal.

Refined A presented in `diagnostics-refined.html`: four generously spaced playback
groups, a full-width Technical details disclosure below, recording state/settings
beside Recent events. Synthetic examples cover Direct Play SDR, Direct Stream HDR10,
Transcode SDR and stopped playback, plus recording empty/off states. Expanded
details distinguish video/audio/subtitle handling without extra controls. Browser
inspection checked the longer HDR summary and expanded transcode composition.
Preview uses one proportional 16:9 layout; it does not validate actual Windows
resolution or text scaling. User explicitly locked this refined appearance.
The earlier A/B comparison is superseded by this refined A composition.

## Settings — organization, layout and account actions locked

User accepted the recommended category order: Appearance, Guide, Playback,
Accessibility, Account, Support. Retain category navigation beside a spacious
detail pane; the later A selection below locks the refined layout.
Appearance groups theme and artwork treatment; Guide owns presentation and visible
hours; Playback provides a home for existing player-control preferences;
Accessibility owns motion and focus assistance; Account owns profile/server and
startup profile selection; Support owns diagnostic recording and Diagnostics
access. This order moves from presentation to viewing behavior, then assistance,
account management and troubleshooting. Do not change deferred Player behavior
merely by relocating its preferences. Retire Past window and Row density under
the previously approved Guide decisions.

### Settings layout — A locked; separate preview not approved

User selected A as the stronger layout: spacious consistent rows with explanations
left and controls right, within the shared category shell. B's persistent preview
pane is rejected. User raised a possible elegant pop-out theme preview but is
unsure it would justify inclusion. Recommendation: omit a separate preview in this
package; the immediate theme change already updates actual Settings surfaces,
while the Guide remains the accurate place to judge its artwork treatment. Do not
add a pop-out/hover preview, preview button or preview-only duplicate Guide renderer
without an explicit later decision. No such feature is currently approved.

#### Layout comparison history

`settings-layout-comparison.html` compares A (spacious setting rows with labels
and explanations on the left, controls aligned right) with B (the same category
shell, but Appearance uses controls beside a shared illustrative Guide-information
preview). Other categories use A's row layout in both directions. Categories
remain Appearance, Guide, Playback, Accessibility, Account, Support. The comparison
uses one full-width cinema surface with quiet separation, a shared Back/Settings
header and Lineup menu entry. It does not introduce an Apply action or Settings
search. A is recommended for consistency and simpler maintenance; B offers more
immediate explanation of visual preferences but adds preview ownership and a
more vertical Appearance form. Preview inclusion remains a product decision.

Local category/control interactions and normal/saving/failure scenarios illustrate
placement only. They do not implement actual persistence, rollback or navigation;
theme selection is a local value, not a complete simulation of all five themes.
B's synthetic preview demonstrates information background/title-artwork choices,
not approved replacements for real Plex artwork or production typography. Existing
Playback controls are carried forward for placement with their redesign deferred.
Ancillary helper copy shown outside previously locked labels is still draft.
Browser checks covered A, B, failure feedback and the simplified Guide category.
Physical resolutions, text scaling, all input paths and native surfaces still
require implementation acceptance.

### Account actions and sign-out — locked

User accepted this order within Settings > Account:
1. Plex Home profile: full name and Switch profile, followed by the startup
   profile-picker preference.
2. Plex Media Server: full name and Switch server.
3. Signed-in Plex account: account identity and a visually separated Sign out
   of Plex action. Distinguish the authenticated account from the selected Home
   profile; this replaces the old global-rail sign-out entry.

Switch profile and Switch server open the existing selection screens directly;
cancelling returns to Account. Preserve the approved full-name, PIN, server
selection and unsaved-change contracts. Opening a picker is not a new account
management feature or authorization to bypass existing guards.

Sign-out confirmation title: Sign out of Plex? Body: Playback will stop. You'll
need to link Plex again to continue. Actions: Cancel and Sign out; Cancel receives
initial focus and Back cancels. No sign-out side effects before confirmation.
Use the existing sign-out owner and truthful failure handling; the dialog must
not report success while credential cleanup has failed. This design adds no
account deletion or lineup-deletion action, and does not change saved-data policy.

### Settings save behavior — locked

Keep immediate saving for individual preferences with no Apply button. Preserve
focus and layout while a save is pending; show quiet saving feedback only when
the wait becomes noticeable. On failure, display the value actually retained and
a concise error beside the affected setting. Do not show a success notification
for every toggle. This refines feedback for the existing immediate-save workflow,
not authorization to introduce a separate settings draft or global save action.

### Full Guide presentation — PiP only locked

User chose the polished PiP Guide as the sole full Guide presentation after
reviewing and rejecting both replacement Overlay directions. Remove the Overlay
mode and the Guide presentation selector entirely; do not keep a one-option
selector, hidden mode, feature flag or dormant alternate layout. The approved
PiP composition and cold-start/no-playback handling remain authoritative.

The implementation scope includes deleting Overlay-specific layout branches,
full-screen video-behind-Guide composition, mode plumbing, obsolete setting/model
state and tests/fixtures solely covering that retired presentation. Existing
saved Overlay selections must load into the sole Guide presentation while
preserving unrelated preferences. Keep only the minimal retired-key read handling
required by the settings persistence contract; stop writing the retired setting.
Retain shared artwork, schedule, input and playback behavior used by the PiP Guide.
This removal concerns the alternate full Guide mode: Mini Guide, Player OSD,
Now Playing, audio/subtitle panels and their shared overlay infrastructure remain
in scope as previously approved. Names such as PlayerOverlay.fullGuide are not
proof that a component belongs exclusively to the retired presentation.

All Overlay comparisons below are rejected design history, not implementation
requirements. This final decision supersedes earlier approvals to retain both.

#### Superseded Overlay exploration

Retain Classic with PiP as the default and Overlay as an optional presentation.
Classic places the playing video beside program information; Overlay keeps video
full-screen behind the Guide without a separate PiP window. Both share approved
browsing, filtering, timing and selection behavior. Keeping both is approved;
the revised Overlay appearance is not yet locked. Give Overlay a focused visual
comparison and check readable information/focus over bright and busy video.
Classic mock approvals do not establish Overlay visual or native-layer acceptance.

Comparison presented in `guide-overlay-comparison.html`: A uses a continuous
vertical video scrim; B adds smoothly blended protection behind the right-hand
information area and lower grid while leaving the open upper-left region clearer.
Both retain matched information/control/row geometry with no separate PiP window.
Visible treatment and synthetic dark/bright-busy scene selectors support direct
comparison. B is recommended; neither treatment is locked yet. Browser visual
inspection covered all four combinations. Static synthetic scenes establish
composition direction only, not contrast over every real frame, motion comfort,
full input behavior, physical resolution/DPI or native video-layer validation.
The reused local Guide interactions are illustrative, not implementation evidence.

User rejected both treatments in `guide-overlay-comparison.html`: retaining the
Classic information geometry with an empty PiP position fails Overlay's purpose.
That comparison is withdrawn, not approved design evidence. User reopened whether
Overlay should exist at all and authorized a new comparison: the best of actual
desktop/webOS Overlay layouts refined versus a ground-up Overlay. Classic with
PiP alone is a valid outcome if neither merits retaining the option. This later
decision supersedes the earlier unconditional retention approval above.

Source inspection for the replacement comparison:
- Desktop `lib/guide/guide_view.dart`, `GuideLayoutPolicy`, Overlay build branch,
  `_GuideShowcase` and `_ProgramDetails`: full-width information when no picture
  is supplied, Overlay artwork, upper showcase above the schedule; no reserved
  empty PiP column. `lib/app/lineup_shell.dart` places this over the Player surface.
- Upstream `src/modules/ui/epg/styles.shell.css`: inset Overlay shell, top
  Overlay showcase, schedule and bottom now-watching dashboard; Classic hosts are
  distinct. `styles.info-panel.css` and `view/info-panel/EPGInfoPanel.ts` provide
  the Overlay poster/content composition. `styles.theme.css` supplies protective
  surfaces; exact treatment varies by theme. Source-based adaptation is not an
  actual screenshot or evidence of hardware validation.

Replacement `guide-overlay-rebuilt.html` compares A (refined existing approach:
poster plus full-width information above five comfortable schedule rows) with B
(ground-up bottom-edge Guide: compact horizontal program information above three
comfortable timeline rows, leaving the upper picture open). Both keep search,
library selection, hours and time navigation in the browsing area. B relocates
the compact navigation/now-playing strip to the bottom so the upper picture stays
clear; its omission of a separate poster is an explicit proposal, not an approved
global artwork removal. The alternatives trade visible-channel capacity and
artwork emphasis against unobstructed video. B is the recommendation for a distinct
Overlay purpose. Neither new composition, its exact footprint, nor Overlay
retention is locked. Synthetic scenes and local interactions are composition
evidence only; full text/accessibility/input/native playback need later validation.

### Artwork preferences — locked

Retain the existing visual choices under Appearance with clearer wording:
Guide information background offers Artwork colors (default), Theme background,
and Artwork backdrop. Use title artwork is enabled by default and uses available
Plex title artwork with a readable text fallback. Preserve consistent text
contrast in every background mode; use the theme background when the required
artwork is missing. Loading artwork must not shift the layout. Background choice
must not change available information or its hierarchy. These choices preserve
the atmospheric default while allowing calmer or more illustrated presentation.

### Now Playing context preference — locked

Keep the Guide header's playing-channel/program summary optional and enabled by
default. Setting label: Show now playing in Guide. Helper: Identify the playing
channel and program while browsing other listings. It distinguishes playback
from the independently inspected program in the large information area, including
when the tuned channel is outside visible rows. Hiding this supporting summary
does not remove PiP or the inspected-program information area. Do not add a button
or another header row; final layout must avoid crowding navigation. This concerns
Guide context only, not the protected Player Now Playing shelf redesign.

### Library picker availability — locked

Remove the Library filters show/hide preference. Keep the library picker available
in its approved position above the channel column; All libraries provides the
unfiltered view. A previously saved disabled preference must not hide the picker
or disable filtering in the revised Guide. Preserve the approved session filter
and reset rules. This replaces the previous ability to hide the control and clear
the active filter by disabling the preference; it does not add multiple-library
selection or change filtering behavior.

Source basis: SettingsView in `lib/app/lineup_shell.dart` currently groups player
auto-hide and DVR controls with Guide settings, and separates Appearance,
Accessibility, Account and Support. The new organization is a design decision,
not an implemented capability. Remaining switches require their own review against
the approved Guide composition before removal or behavior changes are approved.

## Lineup navigation menu — compact menu and navigation consolidation locked

The research/proposals immediately below are decision history. The later A lock,
accepted refinements and cross-surface consolidation in this section are current.

User notes this desktop-specific surface has not received their own audit and
invites ground-up brainstorming. Current `_immersiveAppMenu` in
`lib/app/lineup_shell.dart` is a 280-wide top-right card with Guide, Channels,
Settings, Diagnostics and Player destinations; no profile/server context.
Guide/Player/Settings use this menu while Channels/Diagnostics use a separate
navigation rail, whose trailing action exposes sign-out. This is source evidence,
not approval to preserve the split navigation or evidence of tested focus behavior.

Proposed purpose: quick destination switching while preserving watching/browsing
context. Compare A, a compact popover anchored to the Lineup entry point, with B,
a modest edge panel with larger navigation targets. A is recommended for the small
destination set and lower obstruction; neither layout is approved yet. Proposed
primary destinations: Guide, Player, Channels, Settings, grouping watching/browsing
before management. Keep Player visible but unavailable when there is no playback
or error state to return to; navigation must never start an arbitrary channel.
Move Diagnostics access to Settings > Support, retain its existing direct shortcut
without reassigning shortcut numbers. Keep profile/server switching and sign-out
in Settings > Account; a compact profile/server context entry may link directly
there without duplicating those actions in the menu. The account sign-out location
must be added explicitly if the existing rail action is removed.

Recommend the same menu model across major app surfaces, eliminating the current
menu/rail split if approved. Preserve selected destination, distinguish focus,
close on same-destination selection, and restore the exact invoking control on
dismissal. Outside click dismisses without activating underlying video/controls;
Back dismisses only the menu. No playback auto-hide timeout. Menu opening alone
does not navigate, change playback or discard drafts; navigation retains approved
unsaved-change guards. Content scope, account-entry value, placement and visual
comparison remain pending; these are proposals, not implementation instructions.

### Lineup menu — A and Account shortcut locked

User selected the compact anchored menu A, including the Account shortcut below
Guide, Player, Channels and Settings. B's full-height panel is rejected. Keep
full wrapping profile/server names, quiet separation and comfortable targets.

Final refinements accepted: remove the redundant visible
Current caption while retaining selected-destination styling and accessible
current-page semantics; keep focus indication distinct. For unavailable Player,
use the actionable helper Choose a channel in Guide. Anchor to the actual invoking
control, align within safe window bounds and reposition inward when needed rather
than clipping the menu. Support constrained height/enlarged text without truncating
names or losing navigation actions. Keep focus within the open menu and restore
the exact invoker on dismissal; outside clicks dismiss without passing through.
The latter input refinements establish the approved navigation contract rather
than claiming the current Flutter implementation already satisfies it.

User accepted consistent global navigation across major surfaces: replace the
global rail on Channels and Diagnostics with this shared Lineup menu, matching
Guide, Player and Settings. Keep Settings' internal category navigation; it is
not a duplicate global menu. Preserve the protected Player entry-point geometry
while using the same menu content and behavior. Reconcile exact anchoring with
each surface's invoking control during implementation. Move Diagnostics access
to Settings > Support while retaining its existing direct keyboard shortcut;
do not renumber existing route shortcuts to match the shortened menu. Account
actions require a complete explicit home before removing the old rail sign-out
entry; the Account detail refinement is the next decision.

#### Comparison evidence

`lineup-menu-comparison.html` presents A (compact anchored menu) and B (full-height
edge panel) above the same approved Settings A composition. Both show Guide,
Player, Channels, Settings and an Account entry with profile/server context.
Scenario selection includes typical names, long wrapping names and no playback;
Player remains visible with a readable explanation when unavailable. A puts the
Account entry below the destinations; B anchors it at the bottom of its panel.
Current destination, explicit Close, dismissal barrier and account navigation
are illustrated. Browser inspection covered both layouts, long names, unavailable
Player, and Escape dismissal restoring focus to the Lineup trigger.

Prototype destination changes other than Account are explanatory local feedback,
not real app navigation. Input behavior remains subject to production Flutter and
Windows validation. Numeric mock widths and 1280x720 fitted canvas are composition
references, not fixed physical-size implementation requirements. A is recommended;
exact placement still needs reconciliation with each surface's invoking control.
The proposed navigation consolidation was subsequently approved above.
Settings' internal category rail is separate from
the global navigation rail proposed for removal.

## Design closeout checkpoint

Settings A, its immediate-save feedback, artwork choices, PiP-only full Guide,
compact global menu/consolidation and Account/sign-out decisions are now recorded.
No further Account controls are recommended. Earlier headings and proposal prose
elsewhere in this chronological ledger can describe decisions subsequently
resolved in the same section; they must not be handed to implementers as live
choices. The next pass is consolidation and source mapping, not automatic
approval to design extra features or start implementing.

Before declaring the full package decision-complete, reconcile earlier approved
surface decisions, classify real remaining ambiguities separately from superseded
alternatives and engineering/verification work, and complete the draft plan.
Explicitly deferred Player OSD/Now Playing structural work and future transcoding
controls remain outside this package. Archive only approved synthetic visual
evidence, label rejected comparisons as history, and resolve broken source/design
links rather than silently treating missing documents as inspected authority.

## Handoff gate

Before implementation: resolve every open material decision, consolidate mock
references into durable repository-owned design evidence using synthetic data,
finish the code/verification map, and obtain explicit implementation instruction.
No private screenshots, media metadata, token-bearing URLs or personal paths in
repository evidence. User requested workers and independent reviewer subagents
for the later implementation, fixes and proper conventional commits. No such
execution has begun. Independent review is recommended for that implementation;
this document has not been independently reviewed.
