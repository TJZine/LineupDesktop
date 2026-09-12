# Resume collaborative desktop UI review — surfaces 30–32

Prepared September 12, 2026 at the user's request. This is an operational
continuation of the existing intentional workflow, not a fresh redesign or audit.
Read this entire document before acting. Latest explicit user request is to
prepare a comprehensive handoff; the next task resumes the authorized drawer work.

## 1. Starting state and authority

Workspace: LineupDesktop, existing local checkout. Branch:
`dev/desktop-ui-refinement`. Before this handoff documentation commit, HEAD is
`b07412a0` (Now Playing evidence lock). Recheck actual HEAD, branch and status.
At handoff preparation, the ONLY untracked item was the pre-existing extracted
packet `docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/`.
Preserve it. Do not reset, stash, clean, discard, or overwrite existing changes.
Other user work may occur between sessions; recheck instead of trusting this snapshot.

Read, in order:
1. `AGENTS.md`.
2. `docs/desktop-ui-collaborative-handoff.md`, especially September 12 amendment.
3. Its authority/evidence links: `.interface-design/system.md`, relevant
   `docs/DEVELOPMENT.md` and `docs/architecture.md` sections,
   `docs/desktop-ui-design-spec.md`, `docs/design/desktop-ui/README.md`,
   `docs/desktop-ui-readiness-review.md` (historical evidence only), and
   `docs/desktop-ui-muse-adjudication.md`.
4. `docs/desktop-ui-surface-approvals.md` (current surface ledger).
5. This resume document and the selected mock sources/refinements.

The September 12 amendment supersedes older subagent/extra-task wording.
Do not follow historical completed-plan agent procedures as current instructions.
Use Ponytail full with repository overrides; interface-design for visual work;
Dart quality and test design skills when applicable. Read full skills without
truncation. Apply the visualize skill for inspecting original HTML fragments.

## 2. Exact collaboration and task workflow

Root is Astra, personally responsible for inspecting mock and current real UI,
settling the visual brief, difficult logic/contracts, reviewing changes, fresh
captures, final evidence and user acceptance. User sees the comparison on their
Windows machine; root CANNOT see that view. Follow its surface IDs/order together.
Do not ask which surface to start: the next group is already 30/31/32.

Implementation uses a FRESH USER-FACING TASK for each surface family:
- model `gpt-5.6-luna`, reasoning `xhigh`;
- `create_thread`, project LineupDesktop, environment `local`;
- same saved checkout/branch, NO isolated worktree;
- call list_projects to resolve current project ID (last seen
  `local-8c633241263023433fa4ceaef19f114e`);
- no subagents, no automatic/independent reviewers;
- report actual task/model/assignment and emit created-thread directive;
- settled brief with exclusive files, CURRENT source excerpts, exact visual
  corrections, preserved behavior, bounded checks, and completion instructions;
- root does NO parallel work/edits while task has its lease;
- do NOT poll/monitor/read progress. Pause until final DONE or user reports done.
- explicitly authorize ONE completion message back to the NEW root task ID using
  send_message_to_thread; do not reuse the old root ID accidentally.
- completed task releases lease; root then reviews, fixes within approved scope,
  captures affected states and presents them. Root owns tricky artwork contracts.

Old root ID was `01a08782-d72c-7ae1-9085-b3c2e71cb6aa` (historical only).
Last completed Now Playing task was `01a095f8-109d-7c02-93fa-d99dbee1be69`.
Its lease is released. Do not reuse it for tracks/timer.
NO task has been created for surfaces30–32. User allows more than one sequential
Luna task if useful; one task is simplest because all three share PlayerView.
No independent review unless user explicitly asks. At closeout state whether
independent review is specifically recommended; recent bounded passes: not needed.

## 3. Latest user authorization — do not re-ask

User requested audio/subtitles drawers30/31, including long names, and a quick
mock-alignment/polish pass on sleep timer32. They cannot critique the frozen black
background captures well. They explicitly authorized root's general first-pass
refinements to be implemented BEFORE presenting new visuals. Present all three
for approval/adjustments on BOTH bright and dark backgrounds. This is not a lock.

Root promised to inspect current UI/references, dispatch a fresh Luna task, then
review and capture. Implementation has NOT begun. There is not yet a settled
exact punch list; derive it from the actual references/current UI within the
user's authorized first-pass polish scope. Do not claim earlier assistant
intentions are observed findings or user-approved specific geometry.

Carry forward the user's repeated visual preference: keep video overlays as
transparent as readability allows. Muted/dark text was the main readability
problem. Brighten text first. Do not casually darken gradients/backings. Preserve
premium restrained style, clear hierarchy, aligned controls and readable labels.
For technical track names, do NOT apply the cast middle-initial abbreviation.
Preserve distinguishing language/codec/commentary/accessibility/forced information;
wrap sensibly, constrain extremes, and expose full names on hover/semantics.

## 4. Mock packet and browser incident — important

Frozen starting packet:
`docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/comparison.html`
and `manifest.json`; packet provenance `cbf3dbd580d7c8147c1327342811c56fa4af6bfb`.
It is NOT automatically current after edits. Do not overwrite/rebuild it or
recapture the whole app for isolated work. Read review-packets/README.md.

Original mock files can be HTML FRAGMENTS, not standalone pages. The established
workflow is to read the available visualize skill, prepare its appropriate
local host/wrapper for the original fragment, serve only relevant local content
on loopback, and inspect via browser HTTP. Preserve authored mock appearance;
this is inspection, not restyling/replacing the mock. Reuse a suitable existing
server after checking it; otherwise start a scoped server under tool policy.
Do not guess an old localhost port is still running. Prior ambient ports included
58538/58539, but availability was not verified. No server was intentionally closed
by the prior root in this sequence. Recent displayed images were Flutter captures,
not browser screenshots.

Incident: root incorrectly tried to navigate browser directly to
`file:///.../docs/design/desktop-ui/track-panel-directions.html`. Browser returned
an explicit security rejection prohibiting attempts to reach that page by a
workaround/alternate route. Root stopped browser work and did not serve the page.
User requested a fresh session handoff after this. This document is NOT authority
to evade that rejection or assume a new task clears a restriction. Follow active
tool policy; if it still prohibits the intended inspection, report the exact
limitation rather than retrying blocked paths or claiming visual inspection.
Do not repeat the mistaken file-URL attempt. Where permitted, begin with the
proper visualize/local HTTP workflow. The full visualize skill must be read.
Last known skill package: openai-bundled/visualize/1.0.37; resolve current catalog.

References and exact frozen viewer settings:
- surface30 Audio tracks: `track-panel-directions.html`, `tp-size=1920`,
  `tp-treatment=strong`, `tp-kind=audio`.
- surface31 Subtitles / long names: same reference and size/treatment,
  `tp-kind=subtitles`.
- Approved track variant: RIGHT-EDGE B ONLY, slightly softer inward fade tail.
  Other directions are history. Actual pending/confirmed/error behavior is spec-owned.
- surface32 Sleep: `playback-timer-picker.html`, st-size `1920 × 1080`,
  st-state `off`; also inspect active remaining-time state.
- Sleep choices Off / 30 minutes / 1 hour / 90 minutes. Picker geometry is reference;
  surrounding old mock OSD is context, NOT authority to undo newly locked OSD.

Mock SOURCES were partially read in prior task. They were NOT visually inspected
for this group. No updated drawer screenshot has been presented to user.

## 5. Production owners and behavior guardrails

`lib/playback/player_view.dart`:
- `_SleepTimerPicker` around2485: bottom-right anchored compact picker, selected
  preset check, countdown, scroll cap, trigger focus restoration after selection.
- `_Tracks` / `_TracksState` around2592: right-edge full-height fade/rail,
  track list, Subtitles Off row, loading/empty, pending selection and errors.
- `_TracksState` owns ScrollController; initial selected offset currently assumes
  74px rows. If changing row heights, examine selected-row visibility without
  introducing speculative infrastructure. Root retains difficult focus/currentness.
- Title labels/metadata come from existing helpers; inspect before changing.
- Preserve native-confirmed selection, pending spinner, failure feedback, selected
  vs focused distinctions, keyboard navigation, closing/restoration, off semantics.
`lib/playback/player_coordinator.dart`: showTracks(type), showSleepTimer,
selectTrack, setSleepTimer, overlay and focus contracts. Do not delegate changes
here for visual polish. Do not change native engine/telemetry/track identity.

Bound likely task lease to PlayerView + existing player_view_test.dart. No shared
UI/theme/global settings changes without concrete need. OSD28 and NowPlaying29
are LOCKED; don't change them as a side effect of drawer work.

## 6. Captures, checks, and current unfinished harness

Use production Flutter widgets over synthetic painted bright/dark scenes,
not HTML imitations, screenshot edits/composites, or native-video claims.
Capture affected surface at1920x1080, DPR1, text100%, pinned fonts, no resize/upscale.
For protected structural comparisons also use matching1280x720 baseline/candidate.
Do not recapture whole app. Keep clocks/content/focus/settings identical when
comparing. Differing movie/episode fixtures previously confused review: explicitly
match content when comparing artwork enabled/disabled or backgrounds.

Pinned tools:
`/Users/tristan/.cache/lineup-flutter/3.47.2/flutter/bin/flutter`
(and sibling dart). Run TZ=America/New_York, --no-pub.
Use existing meaningful behavior tests, focused analysis/format/diff checks.
NO new UI layout tests/goldens. Do not run broad suites repeatedly for tiny changes.
Group remaining adaptive1440p/2160p, DPI/text/accessibility at checkpoints.
Physical Windows video/HDR/DirectComposition/focus/platform claims require
exact-commit physical evidence, not these captures.

Ignored local capture helpers (preserve; not in git):
- `build/desktop-ui/surface-28/capture_test.dart` (OSD, working).
- `build/desktop-ui/surface-29/capture_test.dart` (NowPlaying, working).
- `build/desktop-ui/surface-30-32/capture_test.dart` (NEW, UNFINISHED).
The last helper derives from29, opens selected drawer over the painted scene.
Its first attempted run FAILED TO COMPILE: three PlayerTrack constructors on
line67 lack required `selected:false` (IDs2,3,4). Add those in the ignored harness
before running. Audio log:
`build/desktop-ui/surface-30-32/baseline/audio.log`.
No subtitles/sleep run occurred after that failure. NO valid30–32 baseline PNGs.
Also inspect/fix any other fixture issue before claiming capture success.

Environment for drawer harness:
DRAWER=audio|subtitles|sleep
MINI_CAPTURE_DIR=build/desktop-ui/surface-30-32/<candidate-or-baseline>
OSD_CAPTURE_WIDTH=1280 for720p; unset/1920 for1080p.
Main loops bright/dark. Names intended <drawer>-bright/dark-1920x1080.png.
Make output directory first. Harness includes pinned fonts and async image settle.
Use synthetic descriptive long audio/subtitle tracks, multiple states, no Plex data.
Add active timer and meaningful selected/pending/empty checks as appropriate,
without a broad state matrix of unnecessary image captures. Parent owns captures.

## 7. Recently locked surfaces — do not reopen

Full authoritative state for earlier surfaces is in approval ledger. Completed
through29, including MiniGuide27. Do not restart the design phase.

OSD28:
- implementation `10750c5a`; lock/evidence `7b2a22c8`.
- durable evidence `docs/design/desktop-ui/approved/2026-09-12-player-osd/`.
- warm brighter typography, show/logo primary + independent compact episode facts,
  borderless16px action-group gaps, preserved original gradient colors/stops.
- user personally set large-screen logo max520x128 (smaller360x72 unchanged).
- alpha bounds trim transparent margins at original visible scale,8px facts gap.
- shared ClearLogoImage optional max/minVisible opt-in. Bounded alpha scan512,
  normalizedRect with1sample edge protection, original image rendered clipped;
  default other consumers unchanged. Root owns this logic. No fake image editing.
- 67 focused tests at final OSD, captures and analysis passed. Final720p trim,
  grouped adaptive/accessibility/Windows moving-footage checks recorded pending.

NowPlaying29:
- implementation `dc9de607`; lock/evidence `b07412a0`.
- durable evidence `docs/design/desktop-ui/approved/2026-09-12-now-playing/`.
- original transparency preserved; brighter metadata, compact episode/runtime,
  year/genres then technical badges/facts, consistent28/24 episode title.
- fallback show name normal-case20px medium desktop/16dense.
- original poster width, content-driven bounded height, scrollable details with
  progress visible; native Stack/Padding (custom worker RenderBox was removed).
- artwork padding trimmed via existing shared opt-in, fallback not logo-constrained.
- cast desktop104px/dense72px columns, aligned portraits, fixed2line name slots,
  tooltip/full semantics. Full names fitting2lines unchanged; overflow names with
  >2 whitespace tokens shorten interior tokens to initials, preserving first/last.
  Example Alexander Maximilian Montgomery -> Alexander M. Montgomery. This is
  display-only abbreviation, not culturally aware semantic name parsing; extreme
  names can still ellipsize. Do not apply this algorithm to track labels.
- final68 focused tests (including compact name/full tooltip/full semantics),
  analyzer, formatting and four1080p capture cases passed.
- user explicitly locked conditional on compact names, condition completed.
- grouped final720p names/adaptive/accessibility/Windows evidence pending.

## 8. Acceptance and closeout

Parent must inspect outputs before showing user. Present actual PNGs as absolute
Markdown image paths; concise findings and limitations. For this group user wants
updated audio/subtitles/sleep together on light/dark backgrounds after first pass.
Do not mark any of30–32 locked until explicit visual approval. Conditional final
small-change lock can be honored only when that precise change is complete.

On lock, preserve final evidence with source hashes/commit and image hashes in
versioned approved folder, record pending platform/adaptive checks. Make coherent
conventional LOCAL commits for accepted code and evidence/docs. No push, deploy,
publish, independent reviewer, or unrelated user-facing task. Frozen original
comparison remains immutable. Untracked extracted packet remains untouched.

## 9. Concrete next steps

1. Read authorities; recheck HEAD/status and fresh tools/skills availability.
2. Inspect correct mock variants through permitted visualize/HTTP workflow;
   obey incident limitation above. Do not pretend source reading is visual review.
3. Repair unfinished capture harness required selected fields; inspect real
   current audio/subtitles/timer over bright/dark scenes. No implementation yet.
4. Settle exact first-pass brief within user's existing authorization. No extra
   permission needed for this general polish pass. Retain transparency/readability
   priority and all track/timer/focus behaviors.
5. Create ONE fresh Luna/xhigh local task with exclusive files/current excerpts,
   exact corrections/checks and completion routed to NEW root task. Report assignment.
6. Pause without monitoring or parallel work. Resume on DONE, inspect/fix, fresh
   affected captures, present all three for approval/adjustments. Continue until
   user explicitly locks each. Do not forget sleep active/off and long names.
