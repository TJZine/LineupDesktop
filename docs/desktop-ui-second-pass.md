# Desktop UI second pass — decision log

Started October 3, 2026. A user-led second design pass over every user-facing
surface. Earlier approvals in the [approval ledger](desktop-ui-surface-approvals.md)
and [interface system](../.interface-design/system.md) are inputs that may be
challenged, not constraints. This log records only decisions the user made.

## Working agreements

- Decide every surface first, then implement family by family.
- Player OSD and Now Playing are open to structural changes; any structural
  change still needs matched before/after renders.
- Typography is open.
- Every surface is reviewed across the resolution matrix: 1280×720, 1366×768,
  1536×864 at 125%, 1920×1080, 1920×1200, 2560×1440, 3440×1440, 3840×2160 and
  1920×1080 with 150% text.
- All five themes receive a pass; expected to be mostly color work.
- Density may change, but proposals must not add negative space: a revision
  keeps or reduces the empty space of today's surface. Mock spacing that
  drifts looser is not part of any decision.
- Review evidence is local and ignored: `build/design-review/` (real Flutter
  captures from synthetic fixtures; regenerate with `capture_test.dart` and
  `make_viewer.py`).

## Foundations

### F1 · Header system — locked October 5

Reference mocks: `build/design-review/f1-headers.html`, `f1-round2.html`.

- One 80px bar at the 1080p reference (scaled like other geometry), 48px side
  insets and a quiet bottom border on every in-app page. Amended October 6
  from 96px so the Guide does not grow (today 76px) and other pages lose
  16–24px; comparison mock `build/design-review/f1-bar-height.html`. Guide's full-bleed
  grid keeps its own content insets below the bar.
- The Lineup menu button sits top-left on every in-app page (Guide, Channels,
  Settings, Diagnostics, Channel Studio). This overrides the September 12
  Settings/Diagnostics right-side placement.
- Menu button (M2): logo mark + Arial LINEUP wordmark + trailing hamburger,
  primary text color. It replaces Guide's chevron, Channels' small amber
  "≡ LINEUP", Settings/Diagnostics' "LINEUP ≡" and Studio's non-interactive
  "LINEUP / CHANNEL STUDIO". The focus ring appears only on keyboard focus.
- Location (L2): the bar carries no location. Each page's title block is the
  location; secondary pages put a named back link directly above the title
  ("‹ Back to Guide"/"‹ Back to Player" for Settings by origin,
  "‹ Settings · Support" for Diagnostics, "‹ Channels" for Studio). Top-level
  pages (Channels) have no back link. Rejected: the "← Parent / Current"
  breadcrumb in the bar, an unnamed round back button, and Back at the bar's
  right edge.
- First-run (linking, profiles, servers, setup): the same 80px bar with the logo +
  LINEUP lockup pinned top-left and no menu; setup keeps its steps on the right.
  Welcome keeps no bar.
- Exceptions: Player has no bar (menu stays in the OSD). Guide adds its playing
  context, clock and close. Setup complete drops the bar divider so its light
  runs behind it, and shows all steps as done. Below 900px the bar condenses to
  logo + hamburger.
- Behavior consequence: Studio gains a working menu, so navigating away through
  it must run the existing unsaved-changes guard.
- Studio entry points are unchanged: setup completion's "Add a custom channel",
  and Channels rows / "Add a custom channel". A direct Guide → Studio shortcut
  is not part of F1; raise it with the Guide family if wanted.

### F2 · Page width and margins — locked October 5

Reference mocks: `build/design-review/f2-layout.html`, `f2-step1.html`.

- Workspace pages (Channels, Studio, Settings, Diagnostics, setup steps 2–3):
  48px side insets at the 1080p reference, scaled. On windows wider than the
  reference ratio, page content stops at the reference width (1824px × scale)
  and centres; the F1 bar stays full width so the menu keeps its corner.
- Focused-task pages (linking, profiles, servers, setup step 1): one centred
  1040px column (scaled). Titles and content start at the column's left edge;
  profiles centres its heading and avatar grid within it.
- Setup step 1 (S1): stays a centred composition with its actions directly
  under the list. The F1 bar carries the brand and step indicator, so only the
  content layout changes between steps 1 and 2. Rejected: a left-aligned
  workspace step 1, and a shared full-width footer.
- Guide (G2): bar and grid share 20px side insets at the 1080p reference, so
  the menu button aligns with the channel column. Guide is exempt from the
  width cap; a wider window shows more schedule.
- Centred moments: Welcome and setup complete keep centred compositions.
- Proposed for the Setup family (not yet locked): one outcome notice instead of
  four restatements; keep the selection but tag unusable libraries "Won't be
  used"; a real per-row Retry for a failed scan; align the Select all checkbox
  and the type labels with the rows.

### F3 · Typography — locked October 5

Reference mock: `build/design-review/type.html` (direction E).

- Bundle fonts with the app so every platform and every capture renders the
  same type. Both families are SIL Open Font License.
- Titles use Instrument Sans 600, slightly narrowed through its width axis:
  program title 54px at 88% width, page title 44px at 92%, Guide cell and OSD
  titles at 90% (22px and 38px). Sizes are 1080p reference values.
- Everything else uses Inter: body 18/400, metadata 18/400 in secondary text,
  row and control labels 500, buttons 600, small labels 14/500 with tracking.
  Times and durations use tabular figures. Hierarchy comes from size, weight
  and color together; retire the all-bold 700 treatment.
- The narrowed width is for titles only (20px and up at the reference). Never
  narrow body text, labels or anything below 20px, and do not go below about
  85% width.
- Instrument Sans covers Latin and Latin-extended only. Title styles fall back
  to Inter (Cyrillic, Greek, Vietnamese) and then system fonts (CJK).
- The Arial LINEUP wordmark in the F1 menu button is unchanged.
- Rejected: all-Inter (A, A2), serif titles (B, B-lite), Barlow (C), and
  today's system font.
- Verification owed at implementation: variable-font width rendering and
  non-Latin fallback on physical Windows; fall back to static font instances
  if the width axis renders poorly.

### F4 · Buttons — locked October 5

Reference mock: `build/design-review/f4-buttons.html`.

- The theme owns every button style; remove the local style overrides
  (about 70 today) except genuine layout needs.
- Primary: filled projector amber, Inter 600 18px, on-accent text. One primary
  per view; it is always the next step.
- Secondary: quiet outline (strong border) with paper text. Amber is reserved
  for primary buttons and inline links.
- Text: no border, secondary text color (paper on hover). For back, cancel and
  dismiss.
- Inline link: amber text inside content only (F1 back links, a row's Retry,
  "Show next 6 hours").
- Destructive: filled on-air coral, only inside a confirmation dialog.
- Sizes: 56px standard, 44px compact (toolbars, rows, Player drawers); 8px
  radius standard, 6px compact; optional leading 20px icon.
- States: lighter fill or surface on hover; the shared focus-light ring on
  keyboard focus for every tier; disabled keeps the button's shape at reduced
  contrast (no grey slab).
- Studio's primary follows state: Save changes is primary while changes are
  unsaved, with Tune in secondary; once saved, Tune in is primary and Save
  changes is disabled.

### F5 · Navigation controls — locked October 5

Reference mocks: `build/design-review/f5-nav.html`, `f5-round2.html`.

- Three controls with one job each; actions never borrow their looks.
- Side navigation (Setup configure sections, Settings categories), N1: square
  rows; selected = selection surface + straight 3px amber leading bar + primary
  text. This is today's Settings treatment, now shared; it replaces Setup's
  rounded pill.
- Segmented control (Channels All/Custom/Generated filter, Studio source),
  S1: one bordered rounded container; selected segment = selection surface and
  600-weight primary text, no underline. Studio uses it full width.
- Tabs (Studio Browse library / Channel programs): underline tabs with an amber
  3px underline; counts in muted text.
- Channels' Select and Reorder channels become compact secondary buttons (F4),
  separated from the filter by a divider.
- Shared rule: rows are square (side nav, Mini Guide, channel lists, track
  drawer; selected = fill + straight amber bar); controls are rounded (8px,
  6px compact); keyboard focus is always the pale-gold focus-light ring and
  never resembles selection.
- Rejected: rounded selected rows, bar-only rows, bright paper-filled
  selection (reads as focus on a remote), underline inside a filled segment,
  and tabs for the Channels filter.
- Focus visibility (added October 6, app-wide): the focus ring appears only
  while the person navigates with keyboard or remote, like the browser
  focus-visible rule. Opening a view with a click shows no ring; moving the
  mouse hides the ring while keeping the focus position; the next navigation
  key shows it again. Selection (fill, amber bar, check) is always visible.
  Mouse hover is a soft paper fill. Exception: the Guide's focused cell stays
  visible because it drives the information area.

### F6 · Form fields — locked October 5

Reference mock: `build/design-review/f6-fields.html`.

- One field for text, number and dropdown: persistent label above the field
  (16/500, secondary text); inset-black fill (darker than its surface), strong
  border, 8px radius; 56px tall, 44px compact. Dropdowns add a trailing chevron.
- States: pale-gold focus ring; error = coral border with the message below;
  disabled keeps its shape at low contrast with an optional explanation below.
- Replaces Material floating labels in Studio and Episodes per block, and the
  differing boxed dropdowns in Setup rules and Settings.
- Settings and setup rows keep label + description on the left and the control
  on the right; the control is the same field without its own label.
- Search (Q1): no magnifier anywhere (Setup review loses its icon); placeholders
  start with "Search" and say what they search (Guide: "Search channels").
- Toggles and checkboxes keep their roles; off states get a visible border so
  they remain visible on dark surfaces.

### F7 · Player overlay language — locked October 5

Reference mocks: `build/design-review/f7-overlays.html`, `f7-round2.html`.
Over bright footage today, the OSD title, status and actions measure 2.6–3.7:1
and the Mini Guide hint row 2.5:1; Now Playing and the track drawers pass.

- Material: translucent warm-black, about 78% opaque everywhere text sits, with
  a short feather (about 55px at the reference) only beyond the text, plus a
  soft text shadow. The OSD band keeps today's footprint (about 228px vs
  220px). Mini Guide is dense to just below its hint row, then feathers.
- One "Overlay transparency" setting with three choices: More transparent
  (today's lighter fade; helper text notes text may be harder to read on
  bright scenes), Standard (about 78%, the default), and Reduce transparency
  (about 94%). It applies to every Player overlay.
- Per-overlay levels (amended October 6, user's choice): Standard is one 78%
  material under text on every overlay. More transparent keeps today's lighter
  OSD fade (about 45%), Now Playing (about 62%) and Mini Guide fade; overlays
  that are denser than 78% today (track drawers 82%, channel bug 88%, sleep
  popover 92%) drop to 78% at that level, so no overlay is ever lighter at
  Standard than at More transparent. Reduce transparency is 94% everywhere.
  Worst case over white footage at 78%: primary text 8.6:1, secondary 5.4:1.
  The playback-stopped slate is opaque at every level; the buffering spinner
  has no backing.
- Overlays attach to a screen edge: OSD bottom, Mini Guide top, long choice
  lists (audio and subtitle tracks) as right-edge drawers.
- Short fixed choices pop up from their OSD button in the same material; the
  sleep timer is a small popover above the Sleep button, which shows the
  remaining time ("Sleep · 42m"). Rejected: the sleep timer as a full drawer.
- Now Playing becomes the OSD's expanded state: Info (or Down) grows the same
  bottom panel upward to add poster, synopsis, badges and cast, sharing the
  progress lane. This replaces the floating Now Playing card. As a structural
  Player change it needs matched 720p/1080p real-widget renders before
  implementation, per the interface system.
- Overlay headers: Instrument Sans title plus a "Close ✕" text button. Choice
  rows use the F5 row style; keyboard focus is the pale-gold ring.
- Rejected: denser opaque scrims that darken a third of the picture, per-text
  backing patches, footage-adaptive opacity (no reliable per-frame luminance,
  HDR), and background blur (the video is drawn natively beneath Flutter; it
  would need separate native compositor work).

### F8 · Resolution behavior — locked October 5

Goal (user): the app should look structurally the same at every resolution,
window size and Windows display scale, as closely as is reasonable, the way
popular media apps treat a fixed design canvas.

Decisions:

- One scale owner at the app root (above the Navigator and overlays, so
  dialogs, menus, tooltips and banners inherit it): lay the app out at
  `window ÷ scale` and paint it scaled by `scale`, where
  `scale = min(width / 1920, height / 1080)` on the logical window size, never
  below 0.8. Every surface, Material default, letter spacing, hairline and
  focus ring then scales by the same factor. Local `* scale` multiplications
  are removed as their surfaces move under the root owner; no surface may
  scale twice.
- Windows display scaling: because the rule uses the logical window size, a
  4K display at 150% (logical 2560×1440) and at 100% (3840×2160) render the
  same structure; only physical sharpness differs.
- Below the 0.8 floor (windows smaller than about 1536×864) the virtual canvas
  shrinks and layouts reflow rather than shrinking text further; the smallest
  designed text (14px labels) never renders below about 11px.
- Aspect ratio: extra width or height never adds structure. Workspace pages
  centre within the reference width (F2); 16:10 height extends backgrounds and
  the Guide information area, not the five-row Guide; Guide alone uses extra
  width for more schedule time, as TV guide apps do.
- OS text scaling stays independent of the window rule and reflows: Guide cells
  clip to their own bounds with an ellipsis, the time line drops before the
  title shortens, the now-line draws beneath cell text, and toolbars wrap as
  whole groups.
- Standing verification: render key states at 1920×1080 and 3840×2160 and fail
  when any text's position, drawn size or letter spacing is not exactly 2×
  (geometry, not pixels). Physical Windows acceptance remains required for the
  native video rectangle under the root transform, artwork decode resolution,
  and IME/caret placement, at 4K 100% and 150%.
- Rejected: today's three rules; a per-text size floor; scaling ThemeData and
  fixing call sites individually (cannot reach several Material built-ins and
  keeps the many local multipliers that caused the drift).

Evidence, recorded before the decision. Reference mock:
`build/design-review/f8-resolution.html`; scale evidence in
`build/design-review/f8/scale/` and `probe_compare.py` (October 5, captures at
`7ec20101`, pinned Flutter 3.47.6, synthetic fixtures).

- Below the reference, three different rules apply: setup/onboarding
  interpolate 720p→1080p values, Guide switches to its own compact layout, and
  Settings, Diagnostics, Channels and Studio never shrink (`scaleFor` floors at
  1.0).
- Above the reference, scaling is not proportional even though no cap stops it.
  Method: every state rendered at 1920×1080 and 3840×2160; text geometry
  (position, drawn font size, letter spacing) compared at an expected 2× ratio,
  plus a pixel overlay of the 4K capture resized to 1080p. Results:
  - Letter spacing never scales: 2,279 text runs keep Material's default
    0.1–0.5px tracking while font size doubles, so text is narrower at 4K and
    can wrap differently (Guide synopsis).
  - Row and gap geometry drifts: Player audio/subtitle drawer rows are about 15%
    short of 2× (the subtitle list lands on a different scroll position);
    Channels rows creep upward (up to 27px at 4K by the last row); setup source
    rows (up to 57px); Studio lists (up to 60px); Guide toolbar icons shift 30px.
  - Unscaled surfaces: profile PIN dialog (every size fixed); root-level
    dialogs opened from page context (sign-out, sign-out failure, Discard
    changes, Open Generate lineup); startup splash/failure and the recovery
    banner; tooltips and scrollbars (no theme); hairlines, focus-ring widths and
    the theme panel radius stay at 1080p values.
  - Studio's browse list uses Material ListTile defaults: titles 18→32px and
    icons 18→48px instead of 36px.
  - 2560×1440 (a 4K display at 150%) shows the same pattern.
- Root cause: ThemeData is built once at fixed 1080p values and each surface
  re-scales locally; anything outside a local wrapper, Material built-in
  defaults, letter spacing and `DefaultTextStyle` escape scaling. The previous
  verification inspected individual captures by eye, which cannot see a 2–5%
  proportional drift.

## Surface families

### Onboarding — locked October 6

Reference mocks: `build/design-review/s1-onboarding.html` (round one),
`s1-onboarding-r2.html` (hybrid), `s1-onboarding-r3.html` (column width).

- Welcome: no card or bar; the composition sits directly on the atmosphere
  with a larger logo, the headline, the subtitle and the Sign in to Plex
  primary. No three-step preview: the subtitle already states the steps, and
  the preview would undercount the flow (channel setup adds three more).
- Linking (code, expired, failure) uses the F2 1040px column with today's
  vertical rhythm (title, code row, action, footer 20px below):
  - Code state: the instructions emphasise plex.tv/link; the code is large and
    tabular with a compact secondary Copy code; Open browser is primary. A
    quiet "or" divider separates "on this device" from the QR code ("Or scan
    with your phone" below it). The QR sits on warm paper, not pure white.
    The footer shows a pulsing dot (static with Reduce Motion) with "Waiting
    for sign-in · Expires in m:ss", and Cancel on the right.
  - One action slot: the primary action always occupies the same position
    (Open browser, then Get a new code after expiry or failure). One message
    slot: the code row shows the problem instead ("That code expired before
    sign-in finished." or the connection error); the title never moves and the
    footer never repeats it. The QR slot keeps its size, with a placeholder
    when expired or unavailable; the "or" divider appears only in the code
    state.
- Who's watching: Plex profile photos when available, otherwise initials on a
  distinct warm tone per profile; PIN shown as a lock on the avatar; Admin and
  Restricted as quiet chips; the active profile as an amber "Current" chip;
  equal cards with names clamped to two lines (full name on focus); focus is
  the pale-gold ring only; Sign out becomes a quiet text button.
- Profile PIN: a full-screen step replaces the dialog: "‹ Profiles" back link,
  large avatar and name, 24px PIN dots, a 104×76 keypad with a ⌫ key, and an
  inline "Incorrect PIN. Try again." that does not shift the layout. Typing
  still works; Escape goes back.
- Choose a server keeps today's open list with a direct action per row, in the
  F2 1040px column. Only the likeliest choice is filled: the current server's
  row gets the primary Continue (it has no action today) and other rows get
  compact secondary Connect; on first run the first listed server is primary.
  Connection quality gets a small dot; Refresh servers stays centred below the
  list as a secondary button. Rejected: selectable rows with a footer primary.
- Connection quality wording (everywhere `plexConnectionDescription` is shown:
  server selection and Settings › Account): warn only when it affects
  playback. Remove the "Slow" label (≥100 ms), which flags normal remote
  connections. Keep "Very slow" at ≥500 ms and "Limited" for relay
  connections; only these get a small amber dot. Healthy connections show
  quiet text such as "Direct local · 126 ms" with no dot. Unmeasured
  connections read "Not measured yet".

### Channel setup — locked October 6

Reference mocks: `build/design-review/s2-setup.html`, `s2-cards.html`.

- No added negative space on any setup screen (see working agreements); the
  mocks' extra whitespace is not part of the decision. Only content, state and
  the locked foundations change.
- Step 1 (libraries), centred per F2: one outcome notice ("1 of 4 libraries is
  ready. Continuing builds from …") replaces the subtitle summary, the coral
  scan line and the exclusion sentence; the selection is kept and unusable
  libraries carry a "Won't be used" tag; a failed row has a real Retry action;
  Select all and the library type labels align with the rows.
- Channel sources: each count states the result ("1 channel"); sources with
  nothing in the selected libraries are dimmed with "None in your libraries"
  and remain selectable; "N of M included" appears only when the channel limit
  removes some. F5 side navigation and F6 checkboxes.
- Playback order choice cards keep today's selection treatment (raised fill
  with an amber outline), by user preference; no radio or check mark. This is
  a deliberate exception to F5's "selection never resembles focus" rule, so the
  pale-gold 3px focus ring must stay clearly heavier than the 1px selection
  outline.
- The example schedule tints each show with a quiet tone so the ordering
  pattern is visible at a glance. "Additional channel versions" becomes a
  standard row (label and description left, toggle right, visible off state).
- Mini-marathons: "Episodes per block" (F6 field) and "Include specials" sit
  together in one options panel directly under the cards, shown only when
  Mini-marathons is selected; the versions row stays separate.
- Lineup rules: F6 fields for the limits; disabled reorder arrows (first row up,
  last row down) are visibly dimmed.
- Review: change badges are neutral with a glyph (＋ Added, • Updated); only
  Removed uses on-air coral. The breakdown reads "By source: Recently Added 1 ·
  Genres 1". Search has no magnifier (F6).
- Review with removals: the build method becomes a segmented control (F5) at the
  top of the summary card with its one-line explanation; the change bar uses
  neutral for unchanged/updated, amber for added and coral for removed, with a
  legend; the removal confirmation becomes a contained notice directly above
  the footer (coral icon, normal text, "I understand" checkbox) and the primary
  stays disabled until it is checked.
- Creating and complete keep the approved light composition and motion; no bar
  divider (F1); steps read as done on completion; while creating, a subline
  states what is happening ("Creating 2 channels").

### Guide — locked October 6

Reference mock: `build/design-review/s3-guide.html`.

- The Guide uses the F1 80px bar with its G2 20px insets.

- Information area: details sit in one 920px column (reference px); the
  synopsis shows at least three lines (clamped at three with an ellipsis so the
  area never grows); the progress bar spans the same column width.
- Schedule unavailable: when every visible row has failed, the grid shows one
  message ("Schedules couldn't load") with one Retry that retries all failed
  rows; the channel column stays navigable and Retry is reachable by keyboard
  and remote. If any visible row loads, failed rows keep their own row-level
  "Schedule unavailable · Retry". After a partial retry the view returns to
  per-row messages. Scrolling to unloaded rows uses the locked row-level
  loading text and shared pulsing dot. The information area still names the
  focused channel with "Schedule unavailable".
- No channels: one empty state in the grid ("No channels yet", short
  explanation, primary "Set up channels"); the information area shows no
  "Move to a program" prompt.
- Grid focus stays a fill (no outline) by user preference: a deliberate Guide
  exception to F5's ring. The focused cell must always be the strongest surface
  in the grid, clearly brighter than the selected-row fill in the channel
  column.
- Airing indicator: the coral dot moves from the trailing end of the title row
  to lead the title, so it never sits beside the following program.
- Metadata in the information area becomes one line (time · duration · year ·
  genres) plus chips (rating, resolution, audio), matching Now Playing.
- Channel column shows the channel name only; the repeated "Manual lineup"
  subtitle is removed; "Watching" remains on the tuned channel.
- Cell times: when the episode title and time both fit, the time follows the
  episode title inline ("The Last Frequency · 10:12–11:00 PM") instead of being
  pushed to the right edge. The existing fit check (title + gap + time must fit
  in full), drop order and ticker behaviour are unchanged; only the alignment
  of a time that already fits changes.
- No-playback picture area: while nothing has played yet, the stable aperture
  shows the focused program's backdrop artwork, dimmed, with "Select to watch ·
  <channel>". It uses the artwork the information area already loads, falls back
  to today's text when no artwork exists, crossfades on focus changes (instant
  with Reduce Motion), and shows no timecode. Live PiP video and the static
  playback-unavailable treatment are unchanged.

### Player — locked October 6

Reference mock: `build/design-review/s4-player.html` (footage and
transparency-level switches). Mini Guide and sleep timer content are covered by
F7.

- OSD: the Lineup menu and full-screen buttons match the other actions (same
  colour and icon size, 44px targets, tooltips "Lineup menu" and "Full
  screen"). All five actions share one hover (soft paper fill, no colour
  change) and the F5 ring for keyboard focus. Layout is today's: title, status
  and time on the left; actions with "Up next" beneath on the right;
  full-width progress lane at the bottom edge.
- Now Playing (the OSD's expanded state, per F7): HEVC joins the format chips
  (rating · resolution · HDR · video codec · audio codec · channels) and the
  lone "Playback • HEVC" line is removed. Cast shows the role under each name,
  at most four people in one row so it never wraps.
- Track drawers: the list scrolls in its own area below the header (never
  beneath the title), with short fades at its top and bottom edges. "Off" is
  the first subtitle row; the focused row is always scrolled fully into view.
  Opening a drawer with a click shows the selection but no ring (F5 focus
  visibility).
- Status states replace today's five unrelated treatments (Material error
  card, surface error, "Playback unavailable", channel-number card, unscaled
  spinner):
  - Loading and buffering: one scaled 56px amber arc on a faint track, centred,
    no backing. After about two seconds, "Starting playback…" or "Buffering…"
    appears in the channel bug.
  - Playback stopped: a full-frame opaque slate in the theme's deepest colour
    with channel eyebrow, Instrument Sans title ("Playback stopped",
    "Couldn't start playback" or "Playback unavailable"), the reason, and
    actions Retry (primary, only when retry is possible), Browse channels
    (secondary, opens the Mini Guide) and Close (text). No error icon. Channel
    up/down and the Mini Guide keep working on the slate.
  - Notices while playback continues: typed channel numbers show in the
    channel bug with the channel they will tune to ("12 · Action Cinema"); an
    unknown number reads "Not in this lineup" and fades after about three
    seconds. Other non-blocking messages (playback controls temporarily
    unavailable, the sleep-timer stop failure) use the same slot and material
    for about six seconds instead of a blocking card.

### Channels and Channel Studio — locked October 6

Reference mock: `build/design-review/s5-channels.html`. A ground-up Studio
proposal (`s5-studio-redo.html`) was considered and withdrawn: it reversed
three approvals in `docs/desktop-ui-design-spec.md` that still hold for the
page's purpose — no three-column split (hand-picked keeps Browse library and
Channel programs as two views beside the schedule), the explicit Select mode
for bulk adding, and the full-width filter picker (chosen over an anchored
popover for long names and large value lists). Approved Studio B (compact
identity/playback row above, programming left, persistent schedule right)
stays; today's problems are implementation drift, fixed below.

Studio
- Schedule preview: when a change leaves the source with nothing to play, the
  reason is explained once beside the source controls (the Matching programs
  area), not at the foot of the preview. The preview status reads "Out of date",
  the retained schedule is dimmed and labelled "Previous schedule · <source>".
  Retry appears beside the preview status only for failures a retry can fix
  (loading or comparison errors).
- Preview summary is one sentence-case line with separators ("Ch 42 · 4 playable
  · 2h cycle · In order"). "Coverage through … · 6 future hours requested"
  becomes "Schedule through 4:00 AM", sharing a line with "Show next 6 hours".
  The selected-program block, explicit On now row and date context are kept as
  approved.
- Filters return to the approved design: Search, Library and Media type stay as
  prominent fields; other facets appear as removable chips once applied
  ("Genre: Comedy, Family ✕") plus "＋ Filter", which opens the approved
  full-width picker. Applies to Browse library and Library programming. The
  approved hint copy ("Any selected value within each filter; all filters
  together.") is unchanged.
- Browse library rows: "✓ Added" (secondary text, amber check) or a compact
  "Add" button. "Select" is a compact secondary button at the end of the count
  line ("4 matching · 2 added") instead of a full-size button on its own row.
  Each row's second line includes episode and length ("Saturday Signals · S1 E3
  · 30m") at the same row height.
- Channel programs rows: drag handle at the left edge; ↑ ↓ (disabled arrows use
  the locked setup dimming), a "Move to…" compact text button in place of the
  unrecognisable icon, and ✕ "Remove from channel" in place of the trash can.
- Filter picker: opening it never shifts the page. Save and Tune in are disabled
  with the explanation as their tooltip, and the same words sit as a hint beside
  the picker's Cancel / Done.
- Empty results: "No programs match. Remove a filter or include watched items."
  in the results area instead of a bare "0 matching programs".
- A library without collections shows a disabled Collection field reading
  "None in this library" (the original approval's wording), replacing the helper
  sentence beneath it.

Channels directory (approved full-width table kept)
- Reorder page: "Move to…" compact text button replaces the icon; disabled
  arrows use the setup dimming; column header "No." matches the directory.
- Row menu (⋮) uses the theme's raised surface, 8px radius and F5 rows; "Delete…"
  carries an ellipsis because it confirms.
- Delete confirmation: channel numbers share the names' baseline.
- Already covered by foundations: Delete selected without coral (F4), Generate
  lineup without amber text (F4), segmented filter and compact Select/Reorder
  (F5), search per Q1 (F6), Studio's list-row scaling (F8).

### Settings — locked October 6

Reference mock: `build/design-review/s6-settings.html`. The approved
organisation, A layout, Account order and immediate-save behaviour
(`docs/desktop-ui-design-spec.md`, Settings) are unchanged; F1, F4, F5, F6 and
F8 already cover the header, buttons, rail, fields and scaling.

- Overlay transparency (F7) lives in Appearance as the fourth row, "Player
  overlays": helper "How much of the picture shows through Player controls and
  panels. More transparent can be harder to read on bright scenes." Dropdown
  choices with one-line descriptions: More transparent (lightest; today's look),
  Standard (default), Reduce transparency (most solid, easiest to read). Applies
  immediately; no preview renderer.
- Account server row: server name, then quality dot and the locked connection
  wording ("Remote · Limited · 340 ms"; "Slow" dropped, "Very slow" and
  "Limited" carry the amber dot), replacing the raw `plexConnectionDescription`
  string.
- Account profile row shows the profile's photo or warm-initial avatar beside
  the full name (Onboarding lock); the signed-in account row shows the account
  name.
- Every category shares one control column (280px at reference); toggles,
  dropdowns and buttons align to the same right edge.
- Dropdown menus use the themed menu (raised surface, F5 rows, selected bar),
  with one-line choice descriptions where they help (Visible hours, Player
  overlays).
- "Large focus indicators" helper: "Use thicker outlines when navigating with a
  keyboard or remote."

### Themes — locked October 6

Reference mock: `build/design-review/s7-themes.html`. Colour and naming only;
foundations (type, buttons, focus visibility, overlay transparency levels)
apply to every theme. The Overlay transparency setting decides overlay opacity;
each theme keeps its own overlay tint.

- Ember & Steel: unchanged (reference theme).
- DirecTV Classic is renamed **Satellite Blue** (the old name is another
  company's trademark). Its focused Guide cell becomes a solid gold fill
  (#FFCC00) with near-black title and time (13.9:1), replacing the 24% tint that
  left black text on dark olive (1.9:1). It remains the strongest surface in the
  grid, per the Guide lock. Stored key `directv` is unchanged.
- Swiss Minimal keeps its mint look and is renamed **Mint Noir** (the old name
  promised a black, white and red palette). Stored key `swiss` is unchanged.
- Slate & Pine: focus colour becomes a lighter sage (#A8C49E) for the focus
  ring and focused fill only (ring 5.5:1 → 8.9:1 against panels); the darker
  sage stays for primary buttons and progress.
- Glassmorphism is removed, with its Settings option. A saved `glass` choice
  loads as Ember & Steel (the default) and is not written back; other
  preferences are preserved. Remove its palette, enum value and tests/fixtures
  that exist only for it, keeping the minimal retired-key read handling the
  settings persistence contract requires.

### Diagnostics — locked October 6

Reference mock: `build/design-review/s8-diagnostics.html`. The September 12
approval stands; F1 replaces its local 96px header ("‹ Back to Support" above
the title), and F3/F4/F8 cover type, buttons and scaling.

- Technical details share the summary's four-column grid: Application, Video
  output, then Media signal spanning the last two columns with its values in
  two sub-columns, so each detail group sits under its summary.
- "● Recording on" and the "Recording settings" text button end on the content
  edge; the details chevron and event chevrons align to that same edge.
- Event categories display as sentence-case labels ("Guide", "Playback"); the
  copied report keeps the raw keys.

### Lineup menu — locked October 6

Reference mock: `build/design-review/s9-menu.html`. The approved compact
anchored menu, its destinations, Account shortcut, anchoring, focus and
dismissal contract (`docs/desktop-ui-design-spec.md`, Lineup menu) stand; F1
moves its invoker top-left.

- Rows follow F5: the current page is a square row with selection fill and the
  3px amber bar (today a rounded fill with no bar).
- The contextual Now Playing entry (September 14 audit fix) stays, drawn as a
  normal destination row with the program title as its second line. It opens
  the Player's expanded OSD (F7's Now Playing). Shown only when program
  metadata exists, as today.
- The Account shortcut is one row matching Settings > Account: avatar, profile
  name, then server with the locked connection wording and quality dot, and a
  trailing › because it opens Settings > Account.
- The "Lineup" heading and ✕ are removed; Esc, Back and an outside click
  dismiss the menu (approved behaviour).

## Implementation order

Agreed cadence: everything above is decided; build family by family. Phases
are ordered by dependency: each later phase builds on primitives an earlier
phase owns, so no surface is restyled twice. Within a phase, surfaces with
disjoint files may proceed in parallel under one integration owner.

Evidence for every phase: existing widget/unit tests stay green; the review
harness (`build/design-review/capture_test.dart`) re-renders the affected
scenes across the resolution matrix and is compared against the locked mocks;
the F8 1080p-vs-2160p geometry check passes for affected states. Harness and
mock evidence are design evidence, not physical Windows acceptance.

1. **Root scaling (F8).** Introduce the single scale owner in
   `MaterialApp.builder`; retire `LineupLayout.scaleFor`, setup's
   `value(at720, at1080)` interpolation and the Guide compact rule; remove local
   `* scale` multipliers as each surface moves under the root (no double
   scaling). Make the 1080p-vs-2160p geometry probe a repeatable check.
   First because every later phase would otherwise write scale-aware code
   twice. Gate: physical Windows acceptance of the native video rectangle,
   artwork decode resolution and IME/caret placement at 4K 100% and 150%.
2. **Theme primitives (F3, F4, F5, F6, Themes).** Bundle Instrument Sans and
   set the type roles; move every button tier and state into the theme and
   delete the local overrides; shared side-nav row, segmented control, tabs,
   themed menu and field components; the app-wide focus-visible mechanism and
   hover fill; theme palette fixes (Satellite Blue and Mint Noir names, solid
   gold focused cell, Slate & Pine focus colour) and the Glassmorphism removal
   with its retired-key load handling.
3. **Shell and navigation (F1, F2, Lineup menu).** The 80px bar with the M2
   invoker top-left, L2 back links, first-run lockup bar, the <900px condensed
   bar, workspace width cap and focused-task column; the Lineup menu rows,
   Now Playing row, Account row and header removal; Studio's menu routed through
   the existing unsaved-changes guard.
4. **Onboarding.** Welcome, linking, profiles, PIN, servers, and the shared
   connection wording change in `plexConnectionDescription`
   (`lib/plex/plex_models.dart`), which also feeds Settings, the menu and
   Diagnostics.
5. **Channel setup.** All locked step refinements, cards, badges, summary and
   apply states.
6. **Guide.** Information area, empty/failed states, airing dot, metadata line,
   inline cell times (fit/drop/ticker logic unchanged) and the no-playback
   aperture.
7. **Channels and Channel Studio.** Preview states and summary, filter chips
   with the approved full-width picker, Browse/Channel programs rows, reorder
   controls on both pages, picker without layout shift, empty results, row menu
   and delete-dialog alignment.
8. **Settings and Diagnostics.** Shared control column, Account rows, themed
   dropdown menus and helper copy; the Player overlays row lands with phase 9's
   setting. Diagnostics grid alignment, recording row and category labels.
9. **Player.** Split in two because of the protected-baseline rule:
   - 9a, within approved structure: F7 overlay material and the Overlay
     transparency setting (model, persistence default Standard, Settings
     Appearance row, per-overlay levels, per-theme tint); OSD icon buttons and
     hover; track drawer scrolling and focus-visible; sleep popover; the status
     states (slate, channel-bug notices and buffering label, scaled spinner).
   - 9b, structural: Now Playing as the OSD's expanded state, with HEVC in the
     format chips and cast roles. Before implementation, produce matched
     before/after renders from the real Flutter widgets at 1280×720 and
     1920×1080 (identical content, clock, playback state, artwork and focused
     control) and obtain the user's approval of those renders.
   - Gate: physical Windows acceptance of overlay legibility over real bright and
     HDR footage at each transparency level, and of the video rectangle beneath
     the expanded OSD.
