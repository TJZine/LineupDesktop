# Channel Studio Product and UX Specification

Status: Product direction locked; implementation has not started

Decision date: 2026-08-27

Investigation baseline: `65082bce82f005c1ff8842b887e1a27a39115203`

Repository: `TJZine/LineupDesktop`

## Decision summary

Lineup Desktop will have one authoritative lineup with two creation paths:

- **Generate Lineup** remains the bulk workflow that proposes and refreshes
  generator-owned channels.
- **Channel Studio** is a full-page Desktop workspace for creating and editing
  one custom channel at a time.
- **Channels** remains the unified management destination for generated and
  custom channels.
- **Guide** and **Player** consume the same resulting lineup and scheduling
  behavior regardless of how a channel was created.

Channel Studio is not a required fourth step in Generate Lineup and is not a
new top-level navigation destination. Users enter it from **Channels** through
**New channel**, **Edit**, or **Duplicate as custom**. Generate Lineup completion
also offers a direct **Add a custom channel** action.

Regeneration must never delete, replace, renumber, or otherwise mutate a custom
channel. This changes the current meaning of replace mode, which replaces the
whole lineup at the investigation baseline. The new contract is explicitly
**Replace generated channels**.

## Purpose

The current Channel Setup is a substantial bulk generator. It scans selected
Plex libraries, evaluates eight strategy families, supports three build modes,
materializes stable generated identities, reviews impact, and commits a lineup
atomically. It should not be expanded into a per-channel programming tool.

The current custom editor is the actual product gap. It is a modal that exposes
name, number, a whole library or hand-picked source, watched inclusion, and a
playback enum. It cannot efficiently search a large library, explain a generated
channel, expose block size, or show the schedule that the choices will produce.

Channel Studio closes that gap while preserving the current cyclic scheduling
model. Its product promise is:

> Build a channel in under a minute and always know what it will air.

## Product intent

### Who this serves

The primary person has already connected Plex and may already have a generated
lineup. They have a concrete station idea such as “Saturday cartoons,” “comfort
comedies,” or “films from this collection.” They want to shape it without
learning broadcast-automation terminology. Five minutes before opening Studio
they were browsing their library or Guide; five minutes afterward they should
be watching the channel or making another one.

Secondary users include a large-library curator who needs search and facets, a
household steward who needs predictable inclusion choices, and an enthusiast
who cares about schedule continuity. Full broadcast schedulers are not the
primary audience for the first release.

### What they must accomplish

1. Give a station a recognizable identity and unused channel number.
2. Choose which Plex content belongs on it.
3. Choose the simple viewing rhythm of that content.
4. Inspect the real resulting on-air sequence before saving.
5. Save without disturbing unrelated channels, then optionally tune in.

### Intended feel

Studio should feel like a compact personal control room: broadcast-specific,
calm, legible, and immediately alive. It must not feel like a settings form, a
generic card dashboard, or a professional traffic-management calendar.

## Product boundaries

### Included in the first release

- A full-page Channel Studio inside the existing management shell.
- Creation and full editing of custom channels whose source is representable by
  the first-release controls, with lossless inspection and source replacement
  for other preserved source shapes.
- Read-only programming inspection for generated channels.
- Lossless **Duplicate as custom** from a generated channel.
- Whole-library, Plex playlist, Plex collection, metadata-filtered library, and
  hand-picked programming sources.
- Search, facet filtering, bulk selection, and accessible ordering for
  hand-picked content.
- Plain-language playback choices backed by the current sequential, shuffle,
  and block scheduler.
- A deterministic Air Check schedule preview.
- Explicit generator/custom ownership throughout Channels and Studio.
- Generator behavior that protects custom channels in every build mode.

### Deferred advanced programming

- Dayparts and weekday/weekend schedules.
- Reusable programming blocks.
- Fixed starts and explicit overrun policies.
- Per-show episode cursors.
- Filler, fallback, bumpers, and commercials.
- Schedule gap, overlap, and conflict resolution.

These capabilities require a stored time-based schedule model and are not to be
simulated with UI-only state or special cases in the cyclic scheduler.

### Non-goals

- M3U, XMLTV, HDHomeRun, or other tuner export.
- Always-on playout or transcoding services.
- Arbitrary scripts or a general boolean-rule language.
- A weekly Gantt/calendar editor.
- AI-generated schedules.
- Multiple editors, repositories, service locators, event buses, or a new state
  management framework.
- New native C++ behavior, helper processes, WebViews, or dependencies.
- Collaborative publishing or remote channel sharing.
- Custom station artwork in the first implementation. Existing Plex artwork may
  be used in content and schedule previews; an explicit station-art contract is
  deferred.

## Domain and visual direction

### Domain vocabulary

The design comes from the world of a channel dial, station identity, program
rundown, EPG ribbon, broadcast clock, now line, continuity cycle, station bug,
tally light, and dead-air warning. User copy may use familiar terms such as
channel, on now, up next, programming, and schedule. Internal implementation
terms such as source graph, anchor, builder key, seed, and materialize must not
leak into the primary UI.

### Color world

The physical color world is charcoal control-room glass, black equipment bays,
oxidized steel, amber/orange tally lamps, warm paper-white program logs, muted
slate labels, and a restrained red off-air lamp. The default Ember & Steel theme
already expresses this world. Studio must consume the existing
`LineupThemeRoles` so Slate & Pine, Swiss Minimal, DirecTV Classic, and
Glassmorphism remain truthful alternatives rather than receiving hard-coded
Studio colors.

Color has jobs:

- the current theme primary/focus role identifies the active editing target;
- the live accent identifies **On now** and the now line;
- primary, secondary, and muted text preserve information hierarchy;
- surface and border roles establish quiet depth; and
- error red is reserved for invalid, unavailable, or failed states.

Ownership, selection, and validity must never be communicated by color alone.

### Signature: Air Check

Air Check is the feature-specific signature: a one-channel Guide ribbon that is
always visible while authoring. It shows a small amount of past context, the
program on now, and what follows on the same clock used by the Guide. The now
line moves while Studio remains open. Selecting a program in the ribbon reveals
its timing and why it was included.

The same Air Check component appears when creating a channel, editing a custom
channel, inspecting a generated channel, duplicating as custom, and viewing the
post-save state. Compact layouts retain a reduced now/next ribbon instead of
hiding the signature.

Air Check must be produced from the same content resolution and deterministic
scheduler used by Guide and playback. It is not a mock playlist, estimate, or
second scheduling implementation.

### Defaults deliberately rejected

- **Generic settings wizard** is replaced by a station-first authoring
  workspace with a live schedule ribbon.
- **Grid of administrative cards** is replaced by one program workbench and
  one quiet station/control column below Air Check.
- **Large drag-only playlist** is replaced by searchable browsing, explicit
  selected programming, and pointer plus keyboard reorder controls.
- **Professional weekly calendar** is replaced by three understandable playback
  rhythms and a real cyclic preview.
- **Bright decorative dashboard colors** are replaced by the active Lineup
  theme, quiet surface shifts, and semantic tally colors.

### Layout and component treatment

- Continue the existing persistent management navigation and readable-width
  policy. Studio is grounded inside **Channels**, not presented as a detached
  component demo.
- The expanded workspace places the station header first, a full-width Air
  Check ribbon second, and a two-column workbench below it. Programming owns the
  wider column; identity and playback controls own the narrower column.
- Below 900 logical pixels, use one scrolling column while keeping a compact Air
  Check ribbon immediately below the header. Do not return to a modal.
- Use the existing borders-and-surface-shifts depth strategy. Do not introduce
  drop-shadow-heavy cards or a second elevation language.
- Use the existing app typography and dependencies. Times and channel numbers
  should use tabular figures when supported by the existing text stack.
- Use a four-logical-pixel spacing base, normally expressed as 8, 12, 16, 24,
  and 32 pixel intervals. Preserve existing theme radii and focus widths.
- Inputs are visually inset; the Air Check and selected-program rundown are
  visually structural, not decorative containers.
- Motion is limited to the existing fast focus/hover language and the clock
  movement necessary to keep Air Check current. Reduce Motion disables
  nonessential transitions.

Expanded structure, as an information hierarchy rather than fixed geometry:

```text
┌ Back to Channels   42 Saturday Cartoons   Custom   Saved   Cancel   Save ┐
├ Air Check   13:10 Scooby-Doo │ ON NOW 13:30 Batman │ 14:00 Animaniacs ┤
├──────────────────────────────────────────────┬─────────────────────────┤
│ Programming                                  │ Station                 │
│ Library · Playlist · Filter · Hand-picked    │ Name                    │
│ Search/facets or selected-program rundown    │ Channel number          │
│                                              │ Playback rhythm         │
│                                              │ Cycle facts / issues    │
└──────────────────────────────────────────────┴─────────────────────────┘
```

The compact structure keeps the same order, reduces Air Check to now/next, and
stacks Programming before Station and playback controls.

## Information architecture

### Channels destination

Channels is the authoritative list of all channels, sorted by channel number.
Its header actions are:

- **Generate lineup**: opens the existing bulk workflow.
- **New channel**: opens a blank custom channel in Channel Studio.

**Generate lineup** is the new user-facing name for the current **Channel
builder** action, not a second generator or a replacement implementation.

Each channel row exposes:

- channel number and name;
- **Generated** or **Custom** ownership text;
- a concise source summary;
- the user-facing playback rhythm;
- an issue indicator when content cannot currently resolve; and
- **Open** and **Delete** actions with accessible names.

Do not add a second custom-channel list or a separate Studio navigation item.

When the lineup is empty, **Generate lineup** is the primary action and **Create
a custom channel** is the secondary action. When channels exist, both creation
paths have equal visibility in the page header.

### Generate Lineup completion

Successful generation offers:

- **View lineup** as the primary completion action; and
- **Add a custom channel** as the secondary action.

The latter opens a new Studio draft after the generated lineup is durably
saved. It is not part of the generator transaction.

### Channel Studio routes

Studio has four explicit modes:

| Mode | Entry | Programming ownership | Primary action |
| --- | --- | --- | --- |
| Create custom | **New channel** | Fully editable | **Save channel** |
| Edit custom | Open a custom row | Fully editable | **Save changes** |
| Inspect generated | Open a generated row | Read-only generator recipe | **Save identity**; **Duplicate as custom** |
| Duplicate custom draft | **Duplicate as custom** | Fully editable draft | **Save channel** |

The route title and ownership label must make the current mode unambiguous.

## Studio interaction specification

### Station header

The header contains Back to Channels, the channel name or **New channel**, its
number when valid, the ownership label, save status, and the appropriate
actions. Custom drafts provide **Cancel** and **Save**. A generated channel
provides **Save identity** when its name or number is dirty and **Duplicate as
custom** as a separate action. A saved channel provides **Tune in** separately
so persistence and playback failures are never combined into one ambiguous
operation.

Leaving with unsaved changes requires **Discard changes** or **Keep editing**.
No confirmation appears when the draft is unchanged.

### Station identity

- Name is required after trimming.
- Number is required, must be from 1 through 1000, and must be unique across
  generated and custom channels.
- A new draft starts with the lowest available number.
- Duplicate as custom starts with the lowest available number and a visibly
  editable copy name; it never silently replaces the source channel.
- Name duplication is allowed because channel number is the lineup identity
  visible to tuning.
- Validation appears beside the field and in a save-attempt summary. Focus moves
  to the first invalid field after a failed save attempt.

### Programming source

A custom channel selects exactly one first-release programming source:

1. **Library**: one selected Plex movie or show library, with an **Include
   watched items** choice.
2. **Playlist**: one available Plex video playlist.
3. **Collection or filter**: one library with supported metadata facets.
4. **Hand-picked**: an explicitly ordered list of playable items.

Supported filter facets are limited to contracts the current resolver can
represent losslessly: collection, genre, studio, actor, director, decade, and
newest-first ordering. Multiple selected facets use AND across different facet
types and OR within repeated values of one type only after the data model and
resolver explicitly support that representation. Until then, the UI must not
offer an unrepresentable combination.

Do not expose a blank advanced-expression editor. The user starts by browsing a
library or named Plex object, sees the matching count and representative items,
and then narrows it with supported facets.

Changing source type retains the previous choice only in the unsaved draft so
the user can switch back without losing work. Only the active source is saved.

### Hand-picked programming

The picker includes:

- a search field over displayed title and show title;
- library and media-type filters when those facts are available;
- supported metadata facets already present in loaded Plex media;
- visible matching and selected counts;
- **Select visible** and **Clear visible** bulk actions;
- a selected-program rundown in explicit playback order; and
- Move earlier, Move later, Remove, and keyboard equivalents for every selected
  item.

Drag and drop may be added as a pointer convenience but can never be the only
ordering mechanism. Search and filtering must not silently deselect hidden
items. Previously saved items that are temporarily unavailable remain visible
in the rundown with an **Unavailable — retained until removed** explanation.

A custom channel cannot be saved with zero resolved or retained programs.

### Playback rhythm

User-facing choices map directly to the existing scheduler:

| User-facing choice | Current model | Behavior |
| --- | --- | --- |
| **In order** | `PlaybackMode.sequential` | Repeats the resolved order |
| **Mix it up** | `PlaybackMode.shuffle` | Uses the channel's stable deterministic seed |
| **Mini-marathons** | `PlaybackMode.block` | Rotates grouped shows in blocks |

Mini-marathons exposes a block size from 2 through 5 episodes and defaults to
3. It is disabled with an explanation when resolved content has no usable show
grouping. Internal enum names do not appear as unexplained labels.

### Air Check behavior

Air Check displays the current program plus enough surrounding programs to fill
the available ribbon and a bounded six-hour inspection window. It also reports:

- resolved playable item count;
- total cycle duration;
- current playback rhythm;
- selected program start and end times;
- source/facet reason for inclusion; and
- unavailable, skipped, or invalid content with a user-actionable explanation.

The preview uses the draft source, playback mode, block size, anchor, and shuffle
seed. It updates after a short deterministic input debounce but never replaces
explicit loading, empty, or error states with stale results.

For an existing channel, identity-only edits preserve its anchor and shuffle
seed. Programming or playback edits also preserve them; the resulting sequence
may therefore change immediately at save. Air Check must show the exact projected
on-air result and state **Saving these programming changes may change what is on
now** when the current program differs.

For a new channel, the draft receives one anchor and one seed when it first has
a valid resolvable source. Those exact values are saved. The preview clock may
advance while Studio remains open, but saving must not silently re-anchor or
reshuffle the channel.

Preview, Guide, and playback must agree for the same saved channel and time. A
shared pure scheduling path is the contract; copying the scheduling algorithm
into a Studio widget is prohibited.

If a safety bound truncates the inspection window, Air Check labels the preview
as truncated and retains the last projected end time. It must not silently imply
that a bounded result covers the whole requested window.

### Save and failure behavior

- Save validates identity, source representation, resolved/retained content,
  playback requirements, and the complete channel against the full lineup.
- Save uses the existing serialized controller transaction and one durable state
  write.
- While saving, mutating controls and duplicate save are disabled. Navigation
  away is blocked until the operation finishes.
- A failed save leaves the draft open, restores editing, announces the error in
  a live region, and preserves the authoritative lineup exactly.
- Successful save changes Studio to a clean saved state, announces success, and
  enables **Tune in**. Back returns to Channels and restores focus to the saved
  row.
- Tune failure does not roll back a successfully saved channel and receives its
  own error presentation.

## Ownership and regeneration contracts

`Channel.builderKey` is the current durable ownership discriminator:

- `builderKey != null` means generator-owned;
- `builderKey == null` means custom-owned.

Source shape must no longer determine ownership. A custom channel may use a
filtered library, playlist, or currently representable mixed source and still
be custom-owned.

### Generated channels

- Studio shows the generator strategy/source summary and Air Check.
- Programming source, playback rhythm, block size, anchor, and shuffle seed are
  read-only because Generate Lineup owns them.
- Name and number remain editable station identity and must survive a merge of a
  matching builder key.
- **Duplicate as custom** creates a new ID, clears `builderKey`, selects the
  lowest free channel number, and losslessly copies source, playback, anchor,
  seed, and block size into an editable draft.
- If a copied source is not directly editable in the first-release UI, Studio
  presents its current source summary and lets the user replace it with any
  supported custom source without losing the original until save.

Deleting a generated channel warns that a future generator refresh may propose
it again. Persistent generator exclusions are not part of the first release.

### Custom channels

- Generate Lineup never removes or mutates them.
- A custom channel keeps its ID, anchor, and shuffle seed across edits.
- Duplicate as custom and ordinary custom editing do not add a builder key.
- Deletion retains the existing explicit confirmation and rollback behavior.

### Build-mode semantics

The existing internal build modes may remain, but the UI and controller contract
become:

| UI meaning | Required result |
| --- | --- |
| **Replace generated channels** | Keep every custom channel; remove existing generated channels; allocate the new generated plan around all custom numbers |
| **Add generated channels** | Keep all channels and allocate every proposal to a free number |
| **Refresh generated channels** | Match by builder key; preserve custom channels; preserve matched generated ID, number, name, anchor, and seed; update generator-owned source/playback fields; keep unmatched existing channels |

Review impact must report generated creations, updates, unchanged entries, and
removals without counting preserved custom channels as removed. The replace
confirmation says exactly how many generated channels will be removed and how
many custom channels will remain.

At every materialization stage, custom channel numbers are reserved. A generated
plan cannot temporarily duplicate a custom number and rely on later validation
to catch it.

## State and recovery matrix

| State | Required presentation and recovery |
| --- | --- |
| No usable source inventory | Preserve an existing draft/source; explain that a new channel needs a selected Plex library or available video playlist and provide the owning setup route |
| Inventory loading | Keep identity editing available; show bounded progress in Programming and a noninteractive Air Check skeleton |
| Inventory cancelled or failed | Preserve the previous usable inventory and draft; offer retry for the owning scan |
| Source resolves empty | State which source/facets produced no playable programs; disable save and preserve controls for correction |
| Playlist/collection disappeared | Keep the saved source identity visible; explain that it is unavailable and allow source replacement |
| Some hand-picked items unavailable | Retain and label them until explicitly removed; do not count them as currently playable in Air Check |
| Invalid or unknown stored filter | Fail closed with a visible unsupported-filter error; never broaden the channel by silently ignoring the filter |
| Duplicate channel number | Inline error with the conflicting channel name and a **Use next available** action |
| Air Check calculating | Retain the last preview only if clearly marked stale; otherwise show progress without fabricated programs |
| Air Check failure | Keep editing available; show a retry and block save when schedule correctness cannot be established |
| Save in progress | Disable mutations and duplicate submission; announce progress |
| Save failure | Keep the draft, report no lineup changes saved, restore the initiating action's focus |
| External channel change while editing | Detect the stale base before save; require reload or deliberate reapplication rather than overwriting newer state |

The current content resolver silently ignores unknown filter keys. Studio
implementation must first make unsupported filters an explicit error so a typo
or future schema mismatch cannot broaden a household channel.

## Accessibility and input

- All functionality must work with keyboard, pointer, and current remote/select
  semantics where the management shell supports them.
- Focus order follows header, Air Check, programming, station controls, and save
  actions. Focus never enters offscreen filtered results.
- Air Check exposes a semantic list of program title, channel identity, start,
  end, current/future/past state, and selection. The moving now line is not
  announced continuously.
- Generated/custom ownership, unavailable content, selected state, and schedule
  validity use text or semantics in addition to color and iconography.
- Every drag operation has visible Move earlier/Move later alternatives.
- Search result and selected counts are announced after settled input, not on
  every keystroke.
- Loading, error, and successful save messages use bounded live regions.
- Focus is restored to the invoking Channels row after Back, Cancel, or Delete.
- Large focus indicators, Reduce Motion, theme switching, and text scaling
  continue to use existing shared settings and roles.
- At 200 percent text scale, primary fields, error messages, and actions must
  reflow without horizontal clipping. Air Check may reduce visible time range
  but cannot remove its semantic program list.

## Responsive and scale requirements

Deterministically exercise at least:

- `800 x 600`;
- `1280 x 720`;
- `1360 x 840`;
- `1600 x 900`;
- `1920 x 1080`; and
- `3840 x 2160` with the existing high-DPI regimes.

At 800 by 600, the page may scroll vertically but the current section, compact
Air Check, and save status remain understandable. At ordinary and large widths,
the workbench remains within the existing 1,120 logical-pixel readable region;
it does not stretch control lines across the display.

The media picker must remain responsive with the largest deterministically
supported library inventory. Search and filtering are derived from one loaded
inventory and must not trigger an unbounded Plex request per keystroke. Air
Check construction remains bounded and cancellable/stale-safe when performed
asynchronously. Profile before adding a new isolate or cache; use the existing
schedule worker if its ownership matches the measured need.

## Architecture and data ownership

Flutter/Dart owns all Studio UI, drafts, validation, focus, navigation,
accessibility, content resolution, schedule preview, and persistence calls.
C++ and libmpv remain unchanged.

Retain:

- one `Channel` model and serialized lineup;
- one controller transaction owner for durable mutations;
- one content-resolution contract;
- one deterministic cyclic scheduler;
- one Guide/Player consumption path; and
- `builderKey` as the generated/custom ownership seam.

A Studio draft is local route state until saved. Do not persist partial drafts,
introduce a draft database, or mutate the live `Channel` object as fields change.
Air Check consumes an immutable draft snapshot and returns an immutable preview.
Late results for an older snapshot are discarded.

The first release should use existing `LibrarySource`, `PlaylistSource`,
`ManualSource`, `MixedSource`, `PlaybackMode`, `resolveContent`, `buildSchedule`,
`scheduleWindow`, and controller save/apply transactions wherever their
contracts are sufficient. Extend a model only for a user-visible requirement
that cannot be represented losslessly; do not add speculative scheduling
interfaces for deferred dayparts.

## Implementation sequence

1. Protect custom channels in builder materialization, impact review, and all
   controller build modes. Add exact ownership and numbering regression tests.
2. Replace source-shape editability with explicit `builderKey` ownership and add
   generated inspection plus lossless Duplicate as custom.
3. Move the modal custom editor into the full-page Studio route with identity,
   unsaved-change, atomic-save, failure, and focus-restoration contracts.
4. Add supported source selection and the searchable, accessible hand-picked
   programming workbench without changing the scheduler.
5. Add Air Check through the authoritative resolver/scheduler path, including
   empty, invalid, unavailable, stale, and current-program-change states.
6. Add responsive widget coverage, semantics/input coverage, and the smallest
   stable golden set for expanded and compact Studio compositions.
7. Update the User Guide, Product Parity record, and current screenshots only
   after implementation evidence exists.
8. Run focused suites, full formatting/analyze/test verification, and inspect
   the net diff for duplicate ownership or deferred broadcast concepts leaking
   into v1.

Each sequence step should remain independently reviewable. Do not combine the
Channel Studio implementation with daypart scheduling or a broad Channel Setup
redesign.

## Acceptance criteria

### Product and navigation

- [ ] Channels presents one unified, number-ordered list of generated and custom
      channels with textual ownership.
- [ ] New channel, Edit custom, Inspect generated, and Duplicate as custom open
      the correct full-page Studio mode.
- [ ] Channel Studio is not a required Generate Lineup step or a top-level
      destination.
- [ ] Generate Lineup completion can open Channels or start a separate custom
      draft after its own transaction succeeds.

### Ownership and persistence

- [ ] Replace, add, and refresh generated modes never remove or mutate a custom
      channel.
- [ ] Generated allocation reserves every custom number.
- [ ] Refresh preserves matched generated ID, number, user-visible name, anchor,
      and seed while updating generator-owned programming fields.
- [ ] Duplicate as custom creates a new ID and free number, clears builder
      ownership, and preserves the source and scheduling recipe losslessly.
- [ ] Save is atomic; failure keeps the previous lineup and the complete draft.
- [ ] Concurrent or stale edits cannot overwrite newer channel state silently.

### Authoring and Air Check

- [ ] A custom channel can use each supported first-release source without
      losing representable Plex provenance.
- [ ] Hand-picked content supports search, facets, visible bulk actions, and
      accessible explicit ordering.
- [ ] Unavailable saved items remain visible until explicitly removed.
- [ ] Playback choices use plain language and map exactly to current scheduler
      behavior; Mini-marathons exposes a valid block size.
- [ ] Air Check uses the same resolver and scheduler result as the saved Guide
      and playback path.
- [ ] Preview exposes current and upcoming programs, item count, cycle duration,
      timing, inclusion reason, and actionable failures.
- [ ] Unsupported filters fail closed instead of broadening resolved content.
- [ ] Saving a new draft preserves the exact anchor and seed that were previewed.

### UX, accessibility, and scale

- [ ] Expanded and compact layouts preserve the Air Check signature and do not
      regress to a modal editor.
- [ ] All pointer reorder actions have keyboard-visible alternatives.
- [ ] Focus, semantic state, live-region behavior, text scaling, Reduce Motion,
      and large-focus settings pass focused tests.
- [ ] The required viewport matrix has no overflow, unreachable primary action,
      or clipped essential state.
- [ ] Large-library search and preview remain bounded, stale-safe, and
      responsive under deterministic test load.
- [ ] Existing Channel Setup, Guide, Player, persistence, and 1,000-channel
      product-spine suites remain green.

## Research references

The direction is informed by, but does not copy, these products:

- [Channels DVR Virtual Channels](https://getchannels.com/docs/channels-dvr-server/how-to/virtual-channels/)
  demonstrates the approachable content-plus-ordering mental model.
- [Channels DVR Smart Rules](https://getchannels.com/docs/channels-dvr-server/how-to/smart-rules/)
  demonstrates progressive disclosure from simple facets to advanced rules.
- [Tunarr channel programming](https://tunarr.com/configure/channels/programming/)
  and [scheduling concepts](https://tunarr.com/configure/scheduling/concepts/)
  demonstrate both the value and cost of flex, slots, filler, and linked state.
- [ErsatzTV classic schedules](https://ersatztv.org/docs/scheduling/classic/)
  demonstrate the richer broadcast model intentionally deferred here.
- [Virtual Channels help](https://virtualchannels.app/help) demonstrates a
  desktop station, on-air, timeline, and visible skipped-item model.
- [Frequency scheduling](https://docs.frequency.com/en/studio-tools/schedule/scheduling.html)
  provides the professional upper bound for drafts, gaps, and immutable past
  behavior rather than a first-release interaction target.

## Freshness and handoff

Before implementation, read `AGENTS.md`, `docs/DEVELOPMENT.md`,
`docs/architecture.md`, `docs/product-parity.md`, `docs/ui-parity.md`, this
specification, and the current channel source, builder, resolver, scheduler,
controller, Channels view, and relevant tests.

Compare current HEAD with the investigation baseline. If channel ownership,
serialization, builder modes, persistence transactions, scheduler behavior, or
management navigation materially changed, update this specification before
using it as an implementation contract.

At closeout, report changed files, deterministic verification, any physical
Windows evidence, remaining limitations, and whether independent review is
specifically recommended. Independent review is specifically recommended once
implementation changes generator/custom ownership or persistence semantics.
It remains user-controlled and must not be launched automatically.
