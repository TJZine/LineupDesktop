# Desktop UI implementation handoff

Status: design-only delivery plan, September 8, 2026. Product directions are
consolidated in the [specification](desktop-ui-design-spec.md); execution is not
authorized by this file. No implementation workers, application changes or commits have run for this
handoff. See the [readiness review](desktop-ui-readiness-review.md) for the
separately authorized planning review and its exact limits. Read the [visual manifest](design/desktop-ui/README.md)
with the relevant surface: older mock omissions never remove later requirements.

## Authority and working rules

Use [Development](DEVELOPMENT.md), [Architecture](architecture.md), the
[interface system](../.interface-design/system.md), and
[Windows acceptance](windows-native-validation.md). Current source describes the
baseline; this spec describes the approved target. Missing historical Guide/PiP,
Studio and audio-passthrough documents are not inspected authority. Do not infer
behavior from their former index descriptions or reconstruct them speculatively.

Flutter/Dart owns product policy, presentation, input, accessibility and scheduling.
Retain the existing native player boundary. This campaign is not an engine,
DirectComposition, codec or transcoding-controls redesign. Apply the repository's
Dart quality, Flutter test-design and Ponytail skills during their relevant work.
Prefer existing owners/primitives; do not add a new navigation framework, event
bus, service locator, generic form system or second scheduler.

After explicit implementation authorization, the orchestrator rechecks the actual
checkout and assigns bounded workers. Shared-file work is serialized. Workers
must be told they are not alone, must preserve others' edits, and must report
files changed, contracts implemented, tests/evidence, limitations and deviations.
Reviewers review concrete diffs and acceptance evidence; the orchestrator
adjudicates findings and repairs before the corresponding conventional commits.
No autonomous material UI departures. Routine implementation choices within the
approved contracts do not need another design approval.

## Orchestration policy — user update

The user selected a new implementation session, a stronger orchestrator with
`worker` / `worker_luna` assignments by risk, detailed Luna briefs, and grouped
review to reduce usage. Follow the [orchestration handoff](desktop-ui-orchestration-handoff.md)
for the role fallback, task-card template, file leases, concrete mechanical task
seeds and R1–R4 review gates. This overrides any interpretation below requiring
one reviewer per worker, package or commit. Review grouping does not weaken
verification or authorize delegating unresolved contracts to Luna.

## Confirmed source and verification map

Paths and symbols were checked in this checkout during design; line numbers are
intentionally omitted because the implementation will move them. Inspect full
flows and callers before editing, especially the shared controller and shell.

| Responsibility | Existing owners | Existing coverage to extend/reuse |
| --- | --- | --- |
| Shared appearance/layout | `lib/ui/app_theme.dart`, `lib/ui/app_ui.dart`, `lib/app/lineup_app.dart` | `test/app/theme_shell_test.dart`, `tool/visual/ui_acceptance_golden_test.dart` |
| Global routes, menu, contextual Back | `LineupShell` in `lib/app/lineup_shell.dart`; Player input in `lib/playback/player_view.dart` | theme shell, product spine and player-view tests |
| Linking, profiles, PIN, servers | `lib/app/onboarding_view.dart`; attempt/scope owners in `lib/app/lineup_controller.dart`; `lib/plex/plex_client.dart` | `test/app/product_spine_test.dart`, app acceptance goldens, Plex transport/parser tests |
| Libraries, setup, Review and results | `lib/app/channel_setup_view.dart`; scan/apply in controller; `lib/channels/channel_builder.dart` | product spine, channel builder tests, app acceptance goldens |
| Channels and batch management | `ChannelsView` in shell; `saveChannel`, `deleteChannel`, serialized state operations in controller | product spine and channel/Studio tests |
| Studio draft and preview | `lib/app/channel_studio_view.dart`, `lib/app/channel_air_check.dart` | `test/app/channel_studio_view_test.dart`, scheduler/resolver tests, app goldens |
| Source membership and persistence | `lib/channels/channel.dart`, `lib/channels/content_resolver.dart`, `lib/plex/plex_models.dart`, `lib/persistence/app_store.dart` | `test/channels/content_resolver_test.dart`, `test/persistence/app_store_test.dart`, product spine |
| Shared schedules/projections | `lib/channels/scheduler.dart`, `lib/channels/schedule_worker.dart`; Guide/Player/Air Check consumers | `test/channels/scheduler_test.dart`, `test/channels/schedule_worker_test.dart`, Guide and player coordinator tests |
| Full Guide/filtering/recovery | `lib/guide/guide_view.dart`, `lib/guide/guide_controller.dart`; shell presentation composition | `test/guide/guide_view_test.dart`, `tool/visual/guide_sparse_golden_test.dart`, theme shell |
| Tickers | `lib/guide/focused_ticker.dart`; Guide and Mini Guide consumers | existing ticker coverage in Guide tests; player-view tests |
| Mini Guide/tracks/timer | `_MiniGuide`, `_Tracks`, OSD moon/key handling in player view; `lib/playback/player_coordinator.dart` | `test/playback/player_view_test.dart`, `test/playback/player_coordinator_test.dart` |
| Settings and migration | `SettingsView` in shell, `lib/settings/lineup_settings.dart`, controller/store | `test/settings/lineup_settings_test.dart`, persistence, theme shell |
| Diagnostics and support facts | `DiagnosticsView`/`_DiagnosticsSummary` in shell; `lib/diagnostics/diagnostics.dart`; `lib/playback/native_player.dart`, Plex client/models for established evidence | `test/diagnostics/diagnostics_test.dart`, native adapter/coordinator and shell tests |

## Sequenced implementation packages

Each package includes production work, its risk-matched tests and documentation.
This is a dependency sequence, not permission to start. Keep commits coherent;
use the suggested conventional subject only when it matches the actual final diff.

### P0 — baseline and contract preparation

Owner: orchestrator, read-only source investigation plus implementation notes.
Before edits, capture HEAD/status and a recoverable baseline of staged, unstaged
and untracked campaign changes: binary-capable staged/unstaged patches plus copies
and hashes of untracked files, stored locally outside tracked/private evidence.
A reviewed design-packet commit can replace this snapshot for those committed
files, but still capture any remaining dirty state. Classify campaign-owned versus
unrelated changes; never absorb unrelated work into campaign commits. The user
has authorized committing the finished design packet and worker-role configuration
in the preparation session; inspect its actual commit and any later edits rather
than assuming the workspace is clean. Identify existing user changes, resolve current
baseline tests and inspect the relevant contracts. Confirm the old settings/source
schema and schedule identity/projection paths. Record the exact migration shape,
fixtures and rollback compatibility before P1 writes persisted data.
P0 is read-only for production/tests: record contract decisions and planned test
cases; P1 starts by implementing the agreed meaningful tests and contracts.
Required P0 outputs: legacy active-cycle representation, transition version/boundary,
multi-value source schema, legacy sort handling, semantic equality/cache identity,
stale-base rules and migration backup/recovery. FileAppStore.load can already
rewrite canonical state and quarantine FormatException results. Capture backup
before any migration-triggered canonical write, including during load; recognize
valid legacy schema before the corruption path. Verify backup failure behavior
and restart/recovery ordering before permitting writes. The evidence
must explain how the current cycle remains reproducible, not merely assert that a
version number solves it. Do not make speculative native changes for Diagnostics.

Exit: concrete ownership assignments, reproducible baseline and the data gates
below resolved from source. If fulfilling an approved requirement needs a new
product decision, bring that specific conflict to the user before dependent work.
This gate is engineering preparation, not a new broad UI brainstorm.

### P1 — source, scheduling and persistence contracts

Exclusive owner: channel model/resolver/scheduler/worker and associated store
migration; integrate controller/Guide/Air Check consumers serially with their owners.
Implement multi-value categorical filters, ordered source handling, Mini-marathon
chronology/specials and deterministic fresh shuffle cycles. Preserve legacy current
cycles until the approved boundary; explicit saves apply reviewed changes at save.
Generation keeps its chosen mode/defaults. Do not combine membership search with
saved criteria or mutate Plex ordering.

Acceptance: old/new source round trips, unknown/corrupt field rejection, OR-within/
AND-between/dedup, repeated hand-picked occurrences, exact cycle boundaries,
restarts, future projections, missing chronology, short seasons, specials,
mixed movies/episodes, empty/invalid duration and truncated coverage. Compare
Guide, Player and Studio at identical clocks around a transition. Test repeated
migration/restart so the boundary cannot slide forward indefinitely.

Suggested commit: `feat(channels): preserve continuity across refined playback cycles`.
Risk/rollback: persisted schema and schedule interpretation; revert dependent
consumers together. An older binary may reject new canonical fields. Do not claim
downgrade safety without a tested migration/export path; define a local pre-migration
backup/recovery procedure in P0 before writing the new schema, never commit private data or blindly
overwrite newer user changes with that backup.

### P2 — shared layout, navigation, Settings and PiP-only integration

Exclusive owner: shell, app theme/UI primitives, settings model; coordinate Guide
changes in one integrated package rather than parallel edits to shell. Establish
shared full-window spacing and responsive constraints using the existing tokens.
Implement compact global menu A, exact-invoker focus, Account actions, immediate
row-local setting feedback and six Settings categories. Add Account sign-out home
and guards before removing the global rail. Retire Guide Overlay, history, density
and library-picker visibility preferences with strict migration. Retain PiP and
its no-playback state. Keep protected Player geometry.

Acceptance: all retained preferences survive old settings, canonical new writes
omit retired fields, cold-start/full Guide/Player return, category state, menu
bounds and focus, same-route close, disabled Player, outside click consumption,
shortcuts unchanged, dirty navigation and credential-cleanup failure. Test settings
save rejection against the value actually retained. Theme changes must update the
actual app without losing focused control or pending-operation ownership.

Suggested commit(s): `feat(ui): unify navigation and settings`; separate coherent
`refactor(guide): retire alternate overlay presentation` if it can stand alone.
Risk/rollback: routes and settings migration are shared; revert coherent packages,
not an isolated enum deletion. Shared Player overlays are not retirement targets.

### P3 — onboarding and library selection/recovery

Exclusive owner: onboarding view; controller auth/profile/server/scan portions
integrated serially. Implement approved linking/PIN/server/library composition and
recovery with full names and correct action scope. Keep explicit browser launch,
valid-code stability, expiry, attempt cancellation, profile PIN and discovery-only
refresh. Cancelled scans preserve selection and successful results are reusable
only in the valid attempt/scope.

Acceptance: browser failure with usable QR/code; expiry/regeneration; late success
after cancellation/profile change; fourth-digit submit, wrong PIN and empty
Backspace; server discovery does not reconnect; partial/empty/failed/cancelled scans,
retry retention and Continue only with confirmed ready libraries. Verify long
names and actionable errors at narrow/enlarged layouts.

Suggested commit: `feat(onboarding): refine linking and library recovery`.
Risk/rollback: auth and scan lifetimes; no credential or saved-data-policy changes.
Revert UI plus any changed attempt handling together.

### P4 — setup allocation, Review and results

Exclusive owner: setup view and builder; controller apply integrated serially.
After P1, implement the three configuration sections, builder specials control,
originals-first extra allocation and exact counts. Implement top-overview Review,
all three build methods, changed-lineup safeguard and truthful result states.
Preserve lazy roster rendering and a single serialized commit owner.

Acceptance: cap boundaries, exhausted sources, disabled source priority, duplicate
extra exclusion, originals/extras count conservation, number exhaustion, protected
customs, Update and add default, same-name replacement Removed+Added, method-change
confirmation reset, stale review refresh and no-op View lineup. Verify small,
390- and 1,000-channel synthetic reviews, including outgoing+incoming counts
larger than final lineup. Commit failure retains choices and does not falsely
promise rollback. Noncancellable persistence has no fake Cancel.

Suggested commit: `feat(setup): clarify allocation review and build outcomes`.
Risk/rollback: destructive method consequences and counts must match committed
plan. Revert builder and Review together; do not roll back an actual user lineup
by changing the UI or silently restoring a fixture.

### P5 — Channels management and complete Studio

Exclusive owner: Studio/Air Check plus ChannelsView sections; controller mutations
serialized. Depends on P1/P2; use P4 generation semantics. Implement full-width
directory, selection/Show selected/batch delete, explicit reorder preserving number
positions, and Studio B with tall schedule preview. Complete all source editors,
pending picker/add rules, multi-value filters and source availability handling.
Retain generated name/number edits with read-only programming, duplicate as custom,
conflict/deletion recovery, Save stays and confirmed Save and tune in.

Acceptance: selection identities across filters; deletion reconfirmation on change;
atomic reorder with gaps and stale numbers; no write while dragging; repeated
manual entries individually addressable; browse all results beyond first 100;
selection-order batch add and scoped Undo; mixed source replacement/cancel;
missing filters versus loading/zero; saved versus draft preview; extension failure
retains valid coverage; save/tune and conflict/deletion races. Exercise full names,
long synopses, large channel programs and all combined-state scenarios.

Suggested commit(s): `feat(channels): add deliberate bulk management` and
`feat(studio): refine programming and schedule workspace` at independently
working boundaries. Risk/rollback: channel identity and unsaved edits; never use
several individual saves to emulate one batch. No Plex-media deletion.

### P6 — Guide, Mini Guide and ticker behavior

Exclusive owner: Guide view/controller/ticker; player-view Mini Guide integrated
serially. Depends on P1/P2. Implement five-row PiP Guide, measured cell fitting,
always-visible controls, 30-minute navigation, selection restoration and row-local
recovery. Implement five-channel top Mini Guide with shaped gradient, distinct
Watching/browsing states and selected-row simultaneous tickers.

Acceptance: 2/3/4 hours, four resolutions/logical scales, title/subtitle/time fit,
exact now-line boundaries, rollover during pointer/keyboard inspection, future
return and empty search restoration. Cover partial loading, valid-cache refresh
failure, targeted retry coalescing, no automatic retry loop on reopen, cancelled
results, confirmed empty and tune completion after leaving. Ticker lifecycle,
reduced motion, RTL, resize and stationary hit targets need real widget tests.
Mini Guide outside click only dismisses, no inactivity timeout or full-text reveal.

Suggested commit: `feat(guide): refine browsing recovery and mini guide`.
Risk/rollback: input and schedule requests cross owners; retain previous verified
coverage until replacements prove shared behavior. Physical video layering required.

### P7 — track panels, timer and Diagnostics

Exclusive owner: player view/coordinator; Diagnostics shell portion/diagnostics
owner integrated serially. Implement right-edge track panels with confirmed active
state and retained error context; explicit timer picker plus deadline lifecycle.
Implement four-group Diagnostics A, bounded events and allowlisted report copy.
Integrate only reliable current-load/session telemetry; Unknown is valid when the
server provides no correlated decision. No transcode controls or new collectors.

Acceptance: rapid track choices/rollover/close and stale completions; Off/30/60/90,
reselect duration, pause/tune/Guide continuation, manual-stop/sign-out cancellation,
suspend/wake expiry, stop failure and no unintended resume. Copy report with
recording off/empty/bounded events, clipboard failure and seeded secret/identity
fields; no unchecked free-form status/name export. Clear stale facts when playback
ends/replaces. Test event-reading scroll/focus preservation.

Suggested commits: `feat(player): refine track selection and playback timer` and
`feat(diagnostics): present current playback facts and redacted reports`.
Risk/rollback: native confirmation/lifecycle and privacy; do not infer server
method from source metadata or HDR output from stream signal. Keep report building
within the established diagnostics boundary.

### P8 — integration, physical acceptance and closeout

Owner: orchestrator plus user-requested independent reviewers after code exists.
Review net diff and each coherent package for correctness, ownership, input,
accessibility, style, migration, privacy and missing tests. Reproduce/adjudicate
findings, repair, rerun affected checks, then create proper conventional commits.
Avoid one indiscriminate campaign-sized commit. A reviewer finding is not an
instruction to add an unapproved feature.

Update active user-guide/interface/architecture/parity documentation to describe
what was actually implemented and its evidence. Retain historical evidence dates.
First pass portable review/verification and create the coherent candidate commit.
Then package/test that exact commit on Windows and record its evidence; R4 closes
cross-batch portable review separately from physical acceptance. If fixes follow,
retest affected claims at the new commit. Unperformed hardware checks remain
explicit gaps, never “passed” because HTML or goldens looked correct.

## Data and operation gates

### Settings retirement

`LineupSettings.fromJson` currently validates a canonical key set and enum values;
removing keys naively can reject the entire saved state. Accept and validate the
known legacy fields `guideLayoutMode`, `pastMinutes`, `guideDensity`, and
`libraryTabsEnabled` when present, discard their behavior, and write only the new
canonical schema. New-schema reads must not require retired fields. Preserve
strict checks for unrelated unknown/malformed values and every retained preference.
Old 6/8/12-hour spans map to 4; 2/3/4 stay unchanged; new default is 2. Keep the
existing retired onboarding-flag contract unless deliberately migrated with proof.
Do not reset an account's settings to achieve PiP-only behavior.

Delete Overlay-exclusive `_GuideShowcase`/Guide layout branches and shell video
stack composition only after tracing shared consumers. `PlayerOverlay.fullGuide`
is a route/overlay state, not evidence of the removed visual mode. Keep Mini Guide,
OSD, Now Playing, tracks/timer and shared native presentation owners. Remove mode-
only goldens/cases, preserving shared sparse/empty/input/artwork coverage.

### Source and schedule model

Current `LibrarySource.filters` is `Map<String,String>`; the resolver includes
categorical membership and a legacy `sort: added:desc` case. New multi-selection
must normalize legacy single values without turning sort into a membership facet.
Preserve existing source behavior unless the approved explicit edit/transition
changes it. Use one typed source contract across builder, persistence, resolver,
Guide equality/cache keys and Studio stale-base comparisons. Stable categorical
selection order must not change semantic membership. Do not deduplicate repeated
manual occurrences merely because they share media identity.

Current `ScheduleIndex` repeats one ordered list; `programAt` uses duration/modulo
and the worker builds that index from resolved content, seed and mode. A fresh
shuffle per cycle therefore requires shared projection changes, not randomizing
only the preview. Define an explicit algorithm version and stable transition
boundary using the existing schedule owner. Derive cycle permutations from stable
seed/version/cycle context; never from runtime hash codes, tune count or current
clock randomness. Preserve occurrence multiplicity and total valid duration.
Bound lookup/cache work; avoid iterating every elapsed historical cycle.

Before migration writes, prove how old active-cycle content/order/durations remain
reproducible across restart. Persist the necessary legacy cycle snapshot or an
equally sufficient stable input representation when existing data cannot do so;
a timestamp/version alone is insufficient. No arbitrary new scheduling service.
Use UTC instants for arithmetic and local times only for presentation. Preserve
known prior scheduling behavior until the recorded boundary; do not recalculate
that boundary on every app start. Explicit edits use the approved reviewed save
semantics and changes-now warning.

For new custom Library In order, use deterministic movie title or show/season/
episode order, with stable identity/occurrence tie-breaks. For Mini-marathons,
numbered episodes precede separate unknown-chronology entries; preserve supplied
order within the unknown group. Season 0 is a known special, not missing metadata.
Plex playlists and hand-picked In order retain supplied occurrence sequence.
Existing generated In order choices do not acquire Studio's new source sorting.

### Writes, recovery and side effects

Use the controller's existing serialized state-operation boundary. Review apply,
bulk delete/reorder and Studio conflict replacement must compare relevant reviewed
state inside that operation; UI-only checks before awaiting are insufficient.
Do not invalidate on normal playback progress/tuning. On mismatch retain draft,
refresh consequences and require the specified renewed confirmation. One accepted
batch produces one validated persisted lineup; no intermediate renumbered state.

`PlayerCoordinator.logout` first awaits `lineup.logout`, then scope cleanup. Put
the new confirmation before invoking this flow; do not add an early independent
native stop/credential wipe. Preserve truthful cleanup failure reporting and
existing scope invalidation. Track/timer/tune completions require current session,
load/operation and surface checks as applicable, not one global busy flag.

Guide retry must revalidate the requested failed source/range without discarding
valid sibling work or creating an automatic second retry layer. Audit actual
cache validity and request ownership in GuideController; adopt the upstream
policy, not its numeric TTL/concurrency constants. Failed/cancelled/empty are
different states. Preserve valid prior preview coverage during extension failures.
The current 1,000-occurrence projection cap requires honest actual coverage ends;
do not label truncated short-program results a complete 24-hour preview.

## Input and state acceptance matrix

| Context | Input/state contract |
| --- | --- |
| Editable field/PIN | Backspace edits even when empty; PIN fourth digit submits; empty PIN Backspace does nothing |
| Guide search | Ctrl+F focuses; Escape clears nonempty query, then returns focus from empty field; never cascades into route Back |
| Menu/dialog/picker | Focus contained; exact invoker restored; Back cancels/dismisses just the top scope; outside clicks consumed when dismissing |
| Player | Contextual Back opens Guide; Escape is not reassigned to fullscreen exit; retain separate fullscreen controls |
| Settings | Back returns to origin; Account picker cancellation returns to Account |
| Guide program | Click inspects; double-click/Enter/remote OK tunes only the currently airing occurrence; recheck at activation |
| Mini Guide | Up/down and inside wheel browse; no hover selection; stable targets for double-click; no auto-hide |
| Dirty Studio/management | Explicit leave guard, noncommitting action initially focused; pending picker choices resolved before Save/Tune |
| Async result | Publish only to matching request/source/profile/server/load/draft context; never reclaim focus or auto-tune after navigation |
| Pending mutation | Prevent repeated submit; retain relevant draft on failure; no invented cancellation or rollback success |

Preserve route shortcuts Ctrl+1 Guide, Ctrl+2 Channels, Ctrl+3 Settings,
Ctrl+4 Diagnostics, Ctrl+5 Player and existing equivalent letter shortcuts.
Do not renumber them to match the new menu. Supported remote/media mappings stay;
generic gamepad implementation is outside scope.

## Verification and evidence

Follow the pinned SDK/toolchain in Development. For implementation run focused
meaningful tests first, then required format/analyze/test checks:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
```

Use the documented macOS environment for the required exact alpha suite and the
optional local visual checks. Do not update images merely to make tests pass:
inspect optional renders against the spec with matching content, clock, artwork,
focus and playback states. Existing tests may need replacement when they encode
retired modes, but shared behavior must retain coverage. Native changes, if
justified by an actual boundary need, require the documented native and physical
verification rather than only Dart tests.

Every major surface needs synthetic normal/loading/empty/failure where applicable,
full names/long episode titles, no/missing artwork, keyboard focus, reduced motion
and enlarged text. Use 1280x720, 1920x1080, 2560x1440 and 3840x2160; record physical
resolution, logical window constraints, display scaling, text scaling and window
state separately. Include Windows 100/125/150/200% scale as applicable, maximized,
fullscreen/restored and mixed-DPI monitor moves. Preserve proportional structure,
not fixed tiny central canvases or increased density solely at higher resolution.
The user's 1440p monitor/2160p TV are explicit acceptance targets.

Windows proof includes PiP layering/resize, overlay fades on dark/bright/busy moving
footage, fullscreen, focus/remote inputs, track switching and timer suspend/wake.
Media signal telemetry is not HDR-display proof. Record exact tested commit,
environment and outcome, with redacted/synthetic artifacts only. Goldens, browser
mocks and macOS development builds cannot establish physical Windows support.

## Completion and handoff choice

A package is complete only after its accepted behavior, tests, integration,
review/fixes and honest evidence are recorded. The campaign closes with a net-diff
scope audit: no retired Overlay paths/preferences, no duplicate owners, no lost
approved controls, no accidental protected Player redesign, and no private data.
Engineering discoveries that require new material UX return to collaborative design.

The user selected a fresh implementation session using this plan, the complete
spec, manifest and orchestration handoff. The stronger orchestrator completes P0
contracts before implementation workers depend on them; this is not a promise
that the current prose already supplies every algorithm or Luna task signature.
No execution session is created automatically. Independent review is specifically
recommended and is part of the user's requested later implementation workflow.

## Initial design consolidation verification record

Before the subsequently authorized readiness review on September 8, 2026:
consolidated active requirements separately from chronological
history; archived 27 unchanged synthetic comparison fragments with approved-portion
annotations. Local links in the spec, plan, manifest, documentation index and
interface system resolve. All 39 explicitly named source/test paths in this plan
exist. The design artifacts passed the personal-path/token-pattern check; this is
not a general security audit. Tracked documentation passed `git diff --check`.
No application tests were run for this prose/archive-only pass; no application
implementation, independent subagent review, physical Windows validation or commits
were performed. These facts must not be generalized into implementation readiness
or correctness claims beyond the documented design handoff.
