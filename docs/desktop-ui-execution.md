# Desktop UI campaign execution

Implementation authorized September 8, 2026. This record supplements the approved
specification and handoff; it does not replace their requirements.

## Baseline and evidence

- Starting commit: `d221efbb0aaaa7846be2d8666254fbd78bddc738` (reviewed design
  packet and worker configuration). Staged, unstaged and untracked state were
  empty. Binary patches and an untracked-content/hash manifest were captured in
  local temporary storage outside the repository before campaign edits.
- Pinned Flutter 3.47.0 / `4cf24164269a5ebf0c16a028a00727d0e77bbb05`, Dart 3.13.0,
  macOS. Baseline `TZ=America/New_York flutter test`: **737 passed**.
  Baseline `flutter analyze`: **no issues**.
- Latest readiness record is `desktop-ui-readiness-review.md`, follow-up verdict:
  ready for P0, with production implementation gated on concrete contracts.
- No physical Windows evidence has been collected in this campaign.

## Dispatch and exclusive ownership

Initial dispatch snapshot; subsequent gate results and the user-directed checkpoint
below supersede the historical in-progress labels in this table. All file leases
are released at the checkpoint.

| Task | Actual assignment | Exclusive writes | Status / evidence | Review / commit |
| --- | --- | --- | --- | --- |
| P0 persistence, operations and baseline | Orchestrator | This record | Complete; baseline tests/analyze passed | P0 frozen |
| P0 model/resolver/scheduler audit | `worker`, gpt-5.6-sol, medium | None (read-only) | Complete; contracts below | P0 frozen |
| P1 shared source/schedule | Same strong worker | Channel/model/resolver/scheduler/worker; typed Plex metadata; P1-only builder/controller/Guide/Air Check/Studio adaptations; channel/Plex/controller tests | Frozen; 194 combined core/controller/store/parser tests; final 126 focused tests; scoped analysis clean | R1 accepted; integrated model/controller commit follows R2 |
| P1 backup/recovery | Orchestrator | app_store.dart; app_store_test.dart | 30 focused store tests passed; R1 accepted | `71bed5fa` |
| L2 profile/server passive rows | `worker_luna`, gpt-5.6-luna, xhigh | onboarding_view.dart profile/server presentation only | Integrated; focused analyze passed; widget run blocked by in-progress shared edits | R2 pending |
| P2 navigation/Settings | `worker`, gpt-5.6-sol, medium | shell navigation/Settings; settings model; shared UI/theme/bootstrap; settings/theme-shell/new navigation tests | Retired runtime fields removed; Settings migration 6 passed; final approved Theme-row presentation correction in progress | R2 pending |
| P6/P7 player panels and diagnostic contract | `worker`, gpt-5.6-sol, medium | player view/coordinator; focused ticker; diagnostics model; corresponding player/diagnostic/new ticker tests | 179 focused tests and scoped analysis passed; physical contrast pending | R3 pending |
| P3 linking/PIN and scan contracts | Orchestrator | onboarding_view.dart; plex_link_launcher.dart; desktop_onboarding_test.dart; controller after R1 release | 26 onboarding tests passed across four resolutions, DPR variants and text scales; controller/diagnostics 99 passed | R2 pending |
| P4 setup/review implementation | `worker`, gpt-5.6-sol, medium | Setup view, builder and dedicated Setup/legacy tests | Compiling view checkpoint restored; allocation and interaction verification in progress | R2 pending |

Named `worker_luna` (gpt-5.6-luna, xhigh) is exposed by the runtime. L2 completed against bounded existing callbacks; core behavior remains with strong
owners. Luna also completed mechanical typed-source adaptation in Studio/review
tests, preserving raw legacy JSON. Those test-file leases are released.
Workers do not commit. Shared files transfer only after inspection and release.

## P0 operation and recovery contracts

The existing `FileAppStore.load` reads bytes, strictly decodes state and may
immediately rewrite noncanonical artwork. Its `FormatException` recovery path
quarantines the original file. New valid legacy formats must be recognized before
that path. Migration write failures must propagate as startup/save failures,
never become corruption recovery or a successful empty-state startup.

Before the first canonical migration write, retain the exact original bytes in a
local pre-refinement backup. The backup is a sibling of state, never diagnostic
output or repository evidence. Create and flush it before replacing state; backup
failure leaves original state untouched and stops the write. Preserve an existing
backup across restarts and later saves. Serialize checking/backup/replacement in
the existing store write queue. Artwork canonicalization during load uses the
same gate. Parsing and migration IO must have separate exception boundaries.

Recovery is deliberate: stop the application, preserve the current state separately,
then restore the backup only after deciding to discard subsequent changes. Older
binaries are not declared compatible with new fields. Never automatically restore
the backup over newer state, and never include its private contents in evidence.

The controller state-operation queue remains the only lineup transaction owner.
Reviewed setup apply compares the complete relevant channel list inside that queue;
batch delete compares the confirmed target identities and channel values there;
reorder compares full channel identity/number state there. Tuning/current-channel
changes do not invalidate these bases. Studio retains its existing expected-base
comparison, extended to canonical source and schedule state. Mismatch returns a
distinct stale-state outcome before persistence so the view refreshes consequences
and requires renewed explicit confirmation. One batch produces one persisted
lineup; failures preserve draft/selection and restore the previous visible state.

Settings migration accepts and validates optional retired `guideLayoutMode`,
`pastMinutes`, `guideDensity`, `libraryTabsEnabled`; canonical writes omit them.
Retained keys remain strict; legacy 6/8/12 hours map to 4, 2/3/4 are preserved.
The existing validated `audioSetupComplete` compatibility field remains unchanged.

Planned persistence tests: valid pre-change raw JSON; backup-before-load-rewrite;
backup failure with unchanged original bytes; retained backup after repeated load
and save; malformed data retains corruption behavior; canonical new round trip;
unknown/malformed retired settings rejected; unrelated retained preferences survive.
Controller tests delay state saves to prove stale-base checks occur within the queue,
no intermediate batch state persists, and rollback does not lose selections.

## P0 source and schedule contract — frozen

P0 is complete. Model changes begin in P1, with meaningful contract tests.

- `LibrarySource.filters` becomes `Map<LibraryFilter, List<String>>`; the enum
  covers genre, collection, studio, actor, director and decade. `LibraryOrder`
  separates supplied, title and addedDescending sequencing from membership.
  JSON accepts legacy singleton strings; canonical values are sorted, deduplicated
  lists. The sole valid legacy sort (`added:desc`) migrates to addedDescending.
  Empty selection removes a restriction; malformed/unknown values reject.
  People matching/identity uses trimmed lowercase values. Membership is OR within
  each criterion, AND between criteria, deduplicated by media identity for Library
  results. Manual and playlist occurrences and Mixed child order remain significant.
- Supplied order preserves legacy/generated behavior. New custom Library In order
  uses deterministic movie-title or show/season/episode order with identity ties;
  playlist/manual order remains supplied. No new sorting menu.
- Export canonical source and schedule identity from the channel model. Consumers
  include controller validation/stale-base checks, builder source keys, Guide cache
  reconciliation and Air Check recipe identity. Schedule identity includes anchor,
  seed, mode, block size, specials, version and transition; runtime coverage adds
  content generation. Categorical selection order is not a semantic edit.
- Algorithm version 1 is decoded when absent; newly constructed recipes use v2.
  Embed `ScheduleTransition` on Channel with fixed UTC boundary and full ordered
  legacy `ChannelItem` cycle, retaining duration and occurrence multiplicity.
  At first successful legacy resolution, use exactly the old algorithm and compute
  the next boundary with floor-modulo from the original anchor. Persist snapshot
  and boundary together before publishing the migrated schedule. Unresolved sources
  remain legacy until successful resolution; no invented boundary or empty snapshot.
- Project times before the boundary using the frozen periodic cycle phase-aligned
  to that boundary. At the boundary start revised cycle zero. Retain the transition
  on restarts and metadata-only saves. Explicit programming saves/builder updates
  apply the reviewed recipe immediately and retire the transition. A timestamp
  alone is insufficient. Existing library/playlist inventories were never persisted,
  so this reproduces the legacy algorithm over the first available inventory; it
  cannot reconstruct external Plex changes made before migration.
- v2 Shuffle derives each permutation from stable seed/version/signed cycle integer
  context, never runtime hashCode, clock randomness or tuning. Lookup computes the
  cycle directly and bounds cached permutations. Cross-boundary repeat avoidance
  must remain deterministic with bounded work (no recursive historical traversal);
  preserve all occurrences and accept unavoidable tiny-pool limitations.
- Mini-marathons use media kind and stable series identity from Plex metadata,
  regular season/episode chronology, shortened season-end blocks, then specials
  when enabled, then unknown chronology in supplied occurrence order. Movies get
  individual turns. Unknown season is never Season 0. Existing block recipes retain
  specials=true; new configuration defaults false. Sequential/block repeat their
  fixed pattern. Projection retains its 1,000-occurrence bound and honest end.

P1 tests cover raw legacy/new schema, malformed fields, semantic equality, filter
OR/AND/dedup, repeated occurrences, ordering, exact transition/restart/direct-future
lookup, chronology/specials/movies, invalid durations and truncated coverage.
Worker and synchronous projection must agree; Guide/Player/Air Check must share
that projection at identical clocks. Private migration snapshots never enter reports.

## R1 finding adjudication

Accepted repairs (core worker): preserve supplied Library order and transition on
metadata-only Studio save; recheck operation epoch after migration persistence;
reject malformed persisted decade selections; require explicit timezone on a new
transition boundary; mode-sensitive Library order must preserve duplicate and
metadata-only recipes; cache the frozen legacy cycle index rather than rebuild
it per projected program. Add derived unequal-duration legacy Shuffle/Mini-marathon
transition and worker/synchronous boundary evidence. A Player artwork regression
used noncanonical `test://` paths stripped by production serialization; retain the
stale-artwork assertion with canonical synthetic Plex-relative paths (repaired,
focused Player suite green). Backup/recovery review found no defect so far.

## Current integration evidence

- R1 configured independent reviewer has issued the accepted findings above;
  all repairs are closed. Independent final evidence: 221 core/persistence/Guide
  tests, 103 final scheduler/worker/controller tests and 4 Studio regressions passed.
- Onboarding behavioral/layout tests pass at four logical resolutions and text
  scales 1 and 2. Synthetic captures exposed excessive linking-group separation
  at 2160p and narrow profile names at enlarged text; a bounded Luna correction
  was integrated and inspected; final whole-surface acceptance remains open. These renders are not yet visually accepted.

- P2 focused Settings/navigation/theme checks: **22 passed**. Updated UI parity:
  **20 passed**. Root integrated early navigation/onboarding/diagnostics checks:
  **21 passed** at that snapshot; subsequent expanded onboarding: **17 passed**.
- Diagnostics screen: **6 tests passed**, including clipboard retry, stable expanded
  event position, and physical/logical DPR combinations 1280×720/1,
  1920×1080/1.25, 2560×1440/1.5, 3840×2160/2 with text scale 2. This is Flutter
  layout evidence, not physical Windows display/input evidence.
- P7 integration repair: dedicated track-request generation prevents an unrelated
  playback control from suppressing a delayed track failure; **105 coordinator
  tests passed** after repair. Grouped R3 remains pending.

- P3/P4/P5 controller APIs are integrated: staged scan/explicit ready-subset commit,
  same-scope successful scan reuse, discovery-only server refresh, reviewed apply,
  atomic batch delete/reorder and typed stale conflicts. The latest controller and
  diagnostics run passed **99 tests**. Dependent Setup, Studio and Guide workers
  own their disjoint implementation files; R2/R3 integration remains open.

## Acceptance still open

R1 is accepted. Remaining P2–P8 integration and grouped R2–R4 reviews remain
open. Four-resolution Flutter renders and independent text/display scale checks
remain incomplete across the campaign (initial onboarding matrix is complete). Physical Windows acceptance must record
the exact candidate commit, resolution, logical dimensions, display/text scales,
window state, mixed-DPI moves, native PiP/overlay layering, moving-footage contrast,
fullscreen/input, track confirmation and timer suspend/wake outcomes.

## Integrated render follow-through

- Actual protected Player OSD and Now Playing goldens at 1280×720 and
  1920×1080 pass unchanged (four images). Revised surface goldens remain open.
- Onboarding capture matrix: 26 tests passed. Root inspected normal linking at
  720p/2160p and enlarged profile content; no overflow in the tested matrix.
- Expanded Diagnostics/navigation/theme integration: 32 passed at that snapshot.
  Diagnostics includes four logical resolutions plus 125%/150%/200% DPR cases,
  each at text scale 1 and 2. Root inspected normal four-group and enlarged
  reflow captures. No physical Windows acceptance is implied.
- Render comparison found retained legacy Theme cards and track-panel chrome.
  Bounded corrective presentation is assigned to Luna (Theme row using existing
  dropdown/update API) and the strong navigation worker (tracks after timer-race
  verification). These are required approved-composition corrections.
- Guide PiP transparency regression is under the Guide worker's investigation;
  the aperture assertion is retained. Setup/Studio golden fixture interactions
  require adaptation to the newly implemented controls before image acceptance.

## R2 core subpacket — accepted

The R2 diff is split into cohesive core and navigation/Setup subpackets for careful
review. The configured reviewer accepted the frozen controller/onboarding/launcher
packet and its tests after three repairs: preserve active-server authorization
across discovery-only refresh when absent from discovery; expose the active profile
as selected to accessibility; use Back for returning profile selection. The refresh
regression performs a subsequent authenticated artwork request, not just a visual
state assertion. Full repaired packet: **119 passed**; independent two-regression
delta recheck, scoped analysis and diff check passed. Navigation/Setup remains open.

Settings Theme now uses the approved single dropdown row, with label/helper left
and controls right. Obsolete theme-card classes are removed. Its 14-case desktop
size/DPR/text-scale matrix passes; captures include Appearance and long Account
content. Retired full Guide Overlay constructor/branches are removed; PiP alpha
checks pass after repairing the opaque shell ancestor. The former overlay-only
rich/reference-free fixture is adapted to the sole PiP composition.

## Resumed integration and test cleanup

- User requested Ponytail full and lower usage, specifically removal of obsolete
  UI tests. Resumed only the existing strong P4 and P5 workers; root owns shared
  integration and the remaining Guide/Player/Diagnostics matrix work. No new
  user-facing tasks or test frameworks were created.
- P4 worker released Setup/builder and its tests: 55 focused tests, four unique
  Setup regression cases and three physical-viewport shell fixtures passed;
  owned analysis and diff checks clean. Four resolutions plus DPI/text variants
  produced 14 deterministic Flutter captures (not physical Windows evidence).
- Retired Setup layout duplicates were removed from `ui_parity_test.dart` and
  `ui_review_regression_test.dart`. Kept destructive confirmation/cancellation,
  persistence rollback, source preservation, focus ownership and pending apply.
  Legacy action selectors now follow the approved menu/source/Settings controls.
- Player/Guide capture run passed 15 tests, including all four resolutions,
  DPI/text variants and actual Flutter panel renders. Root inspected panel
  composition. Tracks correctly returns to OSD; capture tests dismiss that OSD
  before Mini Guide. Capture filesystem writes use existing `runAsync` support.
- R2B is under independent review by the existing reviewer. Accepted repairs:
  distinguish number exhaustion from generation cap; keep source-reorder focus
  with its source and transfer to the enabled arrow at boundaries; show approved
  no-change result copy; consume held activation repeats on result actions;
  expose Include specials for additional Mini-marathon outputs; index settled
  source strategies to avoid quadratic review-count work on search keystrokes.
  Focused regressions extend existing fixtures; no benchmark harness added.
- Actual Studio render exposed an integration layout concern at 1280×720;
  the P5 owner is checking persistent preview geometry before release. Golden
  updates are not acceptance until intentional composition is inspected.

### R2B — accepted

Independent reviewer accepted all six repairs at the frozen source/test hashes.
Its grouped Setup, navigation, Settings, builder and retained UI regressions ran
**97 passing tests**; scoped analysis and diff checks were clean. No additional
blocking findings. R2 core and R2B now jointly close the portable R2 gate.
The implementation commit is held until dependent extracted Channels/Diagnostics
surfaces pass R3 so that a committed application remains coherent and buildable.

Root inspected updated real Flutter onboarding, Setup and Guide golden renders;
28 selected golden updates passed. Protected OSD/Now Playing baselines remain
byte-for-byte unchanged. Removed the three retired full-screen Guide overlay
baseline images; the rich/reference-free fixtures now exercise the sole PiP
composition. P5 Studio goldens remain pending the owner's geometry repair.

### R3 Guide / Player / Diagnostics — accepted

Independent reviewer closed shared-scale omissions in Guide and Sleep Timer,
Windows full-name timezone reporting, Guide name wrapping with constrained-row
fallback, and TextPainter disposal. Guide's old test surface setters were
corrected to set physical dimensions/DPR together, keeping MediaQuery truthful.
Guide tests: **71 passed**. Guide plus Studio integration after the compact
wrapping repair: **134 passed**. Reviewer grouped repair check: **22 passed**;
updated capture matrix: **15 passed**, with 720p/2160p and enlarged-text outputs
inspected. Scoped analysis and diff checks clean. No Windows physical claim.

### R3 Channels / Studio / Air Check — repairs in progress

Initial independent review withheld acceptance despite green existing suites.
Root owns directory pending-operation gates, actionable row focus, post-delete
focus, mode-correct selection semantics/counts, empty-state action deduplication,
disabled reorder dragging while saving, and linear selection pruning. The same
strong P5 worker owns preview identity, pending picker/save interlocks, tune
currentness/outcomes, retained bulk choices, rundown navigation/identity metadata,
Mini-marathon applicability and incomplete library-scan guards. Shared empty-state
content gains a native scroll fallback for genuinely short available height.
Existing fixtures are extended only for reported behavior and vulnerable
selection/reorder layouts. This packet remains unaccepted until delta review.

macOS application build was attempted with the pinned SDK. Xcode stalled in its
`clang -v -E -dM` compiler probe (sampled blocked in output write); the task-owned
processes were stopped and a verbose diagnostic retry started. Neither attempt
is recorded as successful. This does not alter portable Dart/widget evidence.

### User-directed visual checkpoint — final acceptance paused

The user rejected treating the stress-scale captures as a finished design and
requested one focused visual correction pass, conventional commits, then a manual
visual audit together. Prior R2/R3 acceptance above means code/behavior review at
the recorded revisions, not final visual fidelity acceptance. No new review round
is running. Root owns the visual audit and dispatches only concrete corrections.

Root inspected normal-scale native Flutter captures against the archived approved
compositions. Channels card tiles were replaced by the approved quiet columnar
directory, with a Lineup context header, full-width search treatment and subordinate
metadata. Setup's old atmospheric background was replaced with the flat film
surface. Root's fresh Studio render exposed a tall duplicate Station identity and
vertical playback stack that obscured Programming; the existing strong worker
received the precise final-B shared-row correction. Protected Player OSD and
Now Playing composition remains unchanged.

New automated display/text-scale matrices and geometry-only cases were removed
at the user's request; their captures were useful exploratory evidence, not a
layout contract to lock before collaborative approval. Existing behavior, focus,
accessibility, async, persistence and scheduler regressions remain. Obsolete prior
UI assertions and retired Guide overlay baselines were also removed. No new
layout test suite is being introduced for this checkpoint.

Physical Windows acceptance remains unperformed: all four physical resolutions
(1280×720, 1920×1080, 2560×1440, 3840×2160), Windows DPI/text scale combinations,
real-video overlay contrast/layering, protected OSD/Now Playing, fullscreen,
focus/input, HDR/DirectComposition and packaging require evidence at the tested
commit. Portable captures do not establish any of those platform claims.
Both macOS build attempts stalled in Xcode's compiler probe and were stopped;
the standalone compiler probe succeeded. No native application build pass is
claimed for this checkpoint.

### Checkpoint closeout

The strong Studio worker completed the accepted A–I behavior repairs and root's
concrete final-B composition brief. Studio/Air Check suites: **86 passed**. Root
inspected the final 1280 normal-scale Studio and Channels captures and the flat
Setup review. Existing Setup/Studio capture fixtures refreshed successfully
(**9 passed**, then **2 Studio captures passed** after the last small spacing
adjustment). These are provisional visual baselines for discussion, not user
acceptance. No new permanent layout tests were added for this pass.

Review assignments are finished; no workers or reviewers remain active. The final
Studio fixes and last presentation changes have not received another independent
review: the user explicitly requested stopping after this correction/commit pass
for a collaborative visual audit. Independent review is recommended after that
audit resolves the visual direction, rather than another cycle before feedback.
The full repository suite was not repeated at closeout; targeted affected tests
and analysis are the checkpoint evidence. Earlier broader test results above
retain their original revision boundaries.

Implementation checkpoint: `efd6e91d` (`feat(desktop): implement approved UI
refinement checkpoint`), following P0 backup commit `71bed5fa`. Final grouped
Channels, parity, Settings, Setup, onboarding and Diagnostics behavior checks:
**31 passed**. Final Flutter analysis: **no issues**. Dart formatting and
`git diff --check` completed. No push, deployment or publication occurred.
Physical Windows checks remain unperformed at this implementation commit; the
next action is the user's manual visual audit, not a declaration of completion
of the full platform acceptance campaign.

### Project-wide mock comparison and correction — September 9

Implementation commit: `bc0c907e` (`refactor(ui): align desktop surfaces with
approved compositions`). This supersedes the two-surface visual checkpoint as the
current review candidate. Root personally compared fresh Flutter surface families
with the approved archive and final specification, then dispatched bounded fixes.
Historical mock behavior was not implemented. Normal captures use 100% text;
200% text captures are explicitly separate stress evidence.

| Surface family | Comparison/correction outcome |
| --- | --- |
| Linking, profiles, PIN, servers | Flat film surfaces, neutral avatars, restrained focus; compact approved PIN keypad and left-aligned server rows. Welcome unchanged. |
| Setup libraries, scan states, sources, playback order, rules, review, results | Rechecked open rows, shared playback controls, two-column rules, full-width roster and minimal results; lower scrolled configuration sections included. |
| Channels directory, selection, deletion, reorder | Rechecked current columnar directory and quiet selections; shared input/segmented styling corrected. |
| Studio Programming, browse, Library/filter picker, schedule preview | Removed enclosing Programming card and decorative preview stripe; selected details above schedule; explicit time/title gap; bounded picker list keeps Cancel/Done visible at 720p. |
| Guide and Mini Guide | Flat five-row normal Guide, quieter focus, title-first details and three aligned Mini Guide columns. Restored the required optional playing-channel/program header summary after root caught its erroneous removal; original setting behavior tests retained. |
| Settings, menu, Diagnostics | Open Settings rail/detail composition, compact Account menu group, paper-colored navigation, four-group diagnostic summary and aligned event columns. |
| Player OSD, Now Playing, tracks, timer | OSD/Now Playing geometry untouched; all four protected baseline images byte-identical. Track panels unchanged; timer freshly captured. |

Actual assignments: root owned visual adjudication, shared theme and final
verification; existing `worker`/Sol-medium owners handled Guide/Mini Guide/Studio
and Settings/Diagnostics/menu; named `worker_luna`/Luna-xhigh handled only settled
onboarding presentation. Exclusive ownership was released between packages. No
new independent reviewer round ran; all workers are finished. No permanent layout
or matrix tests were added. Removed an obsolete Settings gradient assertion while
retaining the mounted-player resource check; adapted existing semantic/control
selectors without replacing behavior coverage with layout assertions.

Verification at this source: Guide 25 passed; Mini Guide 3 passed; onboarding 6
passed; Settings 1 passed; Diagnostics/navigation 9 passed; Studio/Air Check 86
cases covered (84 combined passes plus two repaired selector reruns); filter
behavior 3 passed. Theme/shell check had 14 passes and two obsolete UI assertions,
then both repaired cases passed. Final repository Flutter analysis and diff check
were clean. Full repository tests and native builds were not repeated.

A fresh temporary capture run passed all 33 scenarios and produced 55 PNGs under
`build/desktop-ui/bc0c907e-visual-audit/`, with an index, hashes, capture harness and
logs. Eighteen existing provisional golden images were refreshed; no new golden
cases were added. The tracked harness was restored after capture. Additional
Guide spot captures used physical size/DPR 1280×720/1, 1920×1080/1.25,
2560×1440/1.5 and 3840×2160/2, all at text scale 2. Root inspected those renders;
these are portable spot checks, not an all-surface Windows acceptance matrix.
The filter-picker capture is an empty fixture state, not populated-list visual
acceptance. Synthetic video/telemetry are not native playback evidence.

Next: collaborative manual visual audit of this candidate. Physical Windows
checks remain unperformed at `bc0c907e`: all four resolutions with required DPI
and text scales across touched surfaces; keyboard/controller focus and invocation
restoration; fullscreen and native video layering/contrast; protected OSD/Now
Playing over real footage; HDR/DirectComposition and packaging. Independent
review is specifically recommended after user visual feedback is incorporated,
not another automated review cycle before that feedback. No push, deployment or
publication occurred.

### Muse finding adjudication and bounded correction — September 9

Baseline `ae48acb2`. See [adjudication](desktop-ui-muse-adjudication.md) for all
nine dispositions and the additional missing setup section-rail finding. This
record corrects the earlier overly broad setup-composition assessment; it does
not retroactively change historical evidence.

Two configured `worker_luna`/Luna-xhigh units owned linking presentation and setup
controls separately. Root personally adjudicated and inspected renders, restored
the section rail/detail composition after the setup file handoff, and corrected
uneven playback-card heights. QR quiet-zone preservation was caught during root
review. No new independent reviewer was dispatched and no Player file changed.

Verification: 72 existing setup/app/UI-regression cases passed (71 initially;
one obsolete source-switch selector repaired and its case rerun), plus 10 focused
onboarding cases. Full Flutter analysis, changed-file formatting and diff checks
passed. Five affected existing golden cases were refreshed and checked; no new
layout assertions or permanent capture matrix were added. The temporary capture
harness was restored after use.

Changed-surface captures cover all four physical resolutions at DPR1/text1 and
DPR1/1.25/1.5/2 respectively with text2. Root inspected normal composition,
expiry, playback choices and representative enlarged-text/scroll-reachability
captures. The matrix ran without framework exceptions; this is not a claim that
every pixel/state at every scale received individual visual inspection. Artifact
index, source/image hashes and reproducible temporary harnesses are under
`build/desktop-ui/muse-corrections/`. Unchanged surfaces were not recaptured in
this correction pass. No full repository test rerun or Windows validation ran.

Ready for the user's manual visual audit, not declared pixel-perfect. Production
typography/native control affordances remain; physical Windows checks still
require tested-commit evidence across resolutions/DPI/text scale, input/focus,
real-footage layering/contrast, HDR/DirectComposition and packaging. Independent
review is not specifically recommended before this manual visual feedback for
these localized changes. No push, deployment or publication occurred.
