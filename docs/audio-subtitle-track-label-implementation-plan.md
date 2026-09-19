# Audio and Subtitle Track Label Implementation Plan

**Status:** Planning-only implementation handoff, September 19, 2026. This
document records the approved UI direction for finding 4 in
[`ux-functionality-audit.md`](ux-functionality-audit.md). It does not authorize
implementation, establish physical Windows behavior, or mark the audit finding
verified.

**Starting point:** `dev/desktop-ui-refinement` at
`424673484a82b2db897c8f52213a92432cc742b7`. Resolve and record the actual target
commit before implementation. Preserve the unrelated untracked review packet at
`docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/`.

## Goal

Replace raw libmpv-facing audio and subtitle labels with a stable, truthful
presentation that is readable from couch distance, preserves the approved Player
track drawer, and retains enough supporting detail to distinguish real choices.

Completion means that:

- language is presented with a recognizable self-name when the supplied code can
  be resolved safely;
- meaningful titles and explicit purpose/accessibility facts distinguish tracks;
- channel layout and codec/format facts are readable rather than raw identifiers
  without inferring speaker topology from channel count;
- unavailable metadata degrades to a stable type-and-ID fallback;
- the drawer, compact OSD label, tooltip, and accessibility description derive
  from one Dart-owned policy;
- the UI never fabricates a fact that libmpv did not supply; and
- representative physical Windows playback proves that the selected label
  corresponds to the audio heard or subtitles rendered.

## Authority and constraints

- Flutter/Dart owns presentation policy, text, layout, focus, semantics, and the
  Player overlay. C++ owns only the bounded projection of factual libmpv metadata.
- The current right-edge drawer geometry, gradient, scrolling, selection,
  pending/error behavior, focus restoration, and close behavior are approved and
  remain authoritative. See [the interface system](../.interface-design/system.md#player-protected-baseline)
  and [the locked track evidence](design/desktop-ui/approved/2026-09-12-tracks-sleep/evidence.json).
- Keep the existing confirmed-selection contract: a request remains pending until
  native state reports the selected track; failure retains the prior confirmed
  selection and displays the existing inline error.
- The pinned Windows runtime is mpv `v0.41.0-1044-g14f2d48cb`, full commit
  `14f2d48cbc7dda61adb4bd181e107a1f3f76e533`. Confirm the exact `track-list`
  fields against that source/runtime, not only a moving online manual.
- The native encoder's current 64 KiB counter bounds projected string contents;
  it is not a bound on the complete serialized MethodChannel message. Required
  track identity must remain projectable after optional string budget is spent.
- Preserve unknown separately from false. An absent native boolean must remain
  `null`; it must not become a negative claim.
- Do not expose raw filenames, private media titles, paths, Plex credentials,
  token-bearing URLs, or unredacted native payloads in tracked fixtures or
  acceptance evidence.

## Approved UX direction

The track selector is a couch-distance chooser, not a codec inspector. Each row
answers two questions in order:

1. What experience will this track provide?
2. Which factual technical details distinguish it from the alternatives?

Use the existing two-tier row:

- **Primary:** self-named language plus a meaningful title or purpose.
- **Secondary:** explicit purpose/accessibility facts, audio channel layout, and
  friendly codec or subtitle-format facts, in that order.

Examples are target grammar, not fixture claims:

| Track | Primary | Secondary |
| --- | --- | --- |
| Audio | `English — Original theatrical mix` | `5.1 surround • DTS` |
| Audio | `English — Audio description` | `5.1 surround • Dolby Digital` |
| Audio | `English — Director commentary` | `Stereo • AAC` |
| Audio | `Español (Latinoamérica)` | `5.1 surround • AAC` |
| Subtitle | `English — SDH` | `SRT (text)` |
| Subtitle | `English — Forced` | `PGS (image)` |
| Subtitle | `Español (Latinoamérica)` | `External • SRT (text)` |

The `5.1 surround` examples assume an exact recognized `demux-channels` value.
A source that supplies only a count is labeled conservatively, such as
`6 channels`.

The following decisions are fixed:

- Use recognizable language self-names such as `Español`, `Français`, and
  `Deutsch`, with a self-named regional qualifier when the supplied tag supports
  one reliably.
- Language leads when present. A meaningful native title is an editorial
  qualifier; it does not replace language.
- Explicit accessibility and purpose facts outrank codec details.
- A recognized source channel layout is useful and belongs in the secondary
  line. A count without a recognized layout is displayed only as `N channels`.
- Show `External` when known true. Do not show `Embedded` by default; absence of
  `external` may be unknown, and embedded state rarely helps choose a track.
- Do not show the container `default` flag. It is neither the confirmed selection
  nor a user recommendation and has no current product-policy consumer.
- Keep subtitle `Off` as the first distinct action, not a fabricated track.
- Use track IDs only for the stable fallback (`Audio track 3`) or as the last
  discriminator for otherwise indistinguishable rows. When required for
  disambiguation, place `Track N` at the start of the supporting tier so it
  remains visible even when long text is ellipsized.
- Do not add chips, badges, extra icons, a details expander, or a second drawer.
  Retain one primary and one supporting text tier.

## Non-goals

- No preferred-language, forced-subtitle autoselection, or new playback setting.
- No change to track-selection commands, request/load/stop identities,
  acknowledgements, timeouts, restoration, or playback lifetime.
- No inference of Atmos, commentary, audio description, SDH, forced state,
  external state, or channel layout from filenames or arbitrary title text.
  Explicit native purpose flags may supply their corresponding labels; a title
  remains visible editorial text rather than becoming a typed fact.
- No attempt to translate user-authored track titles.
- No broad media-inspector UI, diagnostics expansion, or native telemetry log.
- No Player drawer geometry, transparency, typography, animation, navigation, or
  OSD structure redesign.
- No dependency added merely to avoid a small formatter. A language-data
  dependency is allowed only if the evidence gate below demonstrates that it is
  the smallest reliable way to satisfy the approved self-name coverage.

## Current flow and owners

| Responsibility | Current owner | Planned responsibility |
| --- | --- | --- |
| Native fact projection | `WindowsNativePlayer::EncodeTrackList` in `windows/runner/native_player.cpp` | Whitelist only accepted factual fields; project valid ID/type/selection independently of optional-string exhaustion; keep track, per-string, and optional-string bounds. |
| Method-channel decoding | `_decodeTrack` in `lib/playback/windows_native_player.dart` | Validate each optional value and construct the typed Dart model without unchecked casts. |
| Typed track model | `PlayerTrack` in `lib/playback/native_player.dart` | Carry only facts used by the approved presentation. |
| Presentation policy | Private helpers in `lib/playback/player_view.dart` | Move shared policy to one small playback-owned Dart file if pure policy tests justify it. |
| Drawer and OSD | `_Tracks` and OSD actions in `lib/playback/player_view.dart` | Consume the shared display result while retaining existing widget behavior. |
| Selection lifecycle | `PlayerCoordinator` | Remain unchanged unless compilation requires mechanical model fixture updates. |

## Native metadata contract

### Evidence gate

Before changing the production whitelist, capture bounded, redacted `track-list`
examples from the pinned runtime for the media actually available to acceptance:

- ordinary stereo and multichannel audio;
- commentary and audio-description audio where available;
- equal channel counts with different reported layouts where available;
- multiple languages, including at least one two-letter code, one three-letter
  code, and one regional tag if the runtime supplies them;
- ordinary, SDH/hearing-impaired, forced, external, text, and image subtitles
  where available; and
- missing title, missing language, missing codec, and identical visible metadata.

Record only normalized field presence, types, and synthetic/redacted values. Do
not commit raw `external-filename`, private titles, paths, server responses, or
ordinary verbose logs. If a media category is unavailable, retain a synthetic
adapter fixture and mark physical acceptance for that category not run.

Confirm the exact runtime behavior for these candidate libmpv fields:

- `demux-channel-count`
- `demux-channels`
- `forced`
- `external`
- `hearing-impaired`
- `visual-impaired`
- `commentary`

Default to omitting `codec-desc`: another long optional string increases native
budget pressure, and the exact codec identifier already supports the bounded
friendly-name policy below. Reconsider it only if the evidence matrix demonstrates
a required label that cannot be represented truthfully from `codec`. Treat
`codec-profile` and any narrower DTS tier as a separate product decision.

Do not carry `default`, `external-filename`, stream indices, bitrate, sample rate,
decoder identity, or other neighboring fields without a separately approved
current UI use. Carry `demux-channels` only for the concrete source-layout label
policy below; unknown layout strings remain bounded facts and are never interpreted
as system-output topology.

### Typed model target

Subject to the evidence gate, extend `PlayerTrack` with the smallest used set:

- `int? channelCount`
- `String? channelLayout`
- `bool? forced`
- `bool? external`
- `bool? hearingImpaired`
- `bool? visualImpaired`
- `bool? commentary`

Retain `title`, `language`, `codec`, `selected`, `type`, and `id`. Optional native
values remain optional in every fake and caller, so existing substitutes do not
need fabricated defaults.

Reject malformed optional values locally during decoding by treating them as
unavailable; this applies to the existing `title`, `lang`, and `codec` strings as
well as every new fact. A malformed optional display fact must not discard an
otherwise selectable track. A valid selectable ID is a positive integer; reject
the track when its ID is zero, negative, a string, or a floating-point value.
Treat zero, negative, string, and floating-point channel counts as unavailable
rather than coercing them or discarding an otherwise valid track. Continue
rejecting a track whose required `type` is invalid. Keep the public track list
immutable.

Descriptive booleans preserve three bridge states: true, false, and
absent/malformed. The pinned runtime normally emits the proposed disposition
properties as booleans, so nullable Dart values preserve bridge-level absence;
they do not reconstruct whether the original container omitted the flag. Never
turn false into a negative content claim. Keep required `selected` control state
separate from descriptive booleans.

### Identity-preserving native bounds

The current encoder shares one 64 KiB string-content budget across every track
and sends `type` through the same budget-consuming helper as optional display
strings. Once optional strings exhaust the budget, a later valid track can lose
its required type and be rejected by Dart. Adding metadata would aggravate this
inherited defect.

Correct the invariant inside the bounded native projection:

- validate and project `id`, the known fixed `type` literal, and `selected`
  independently of the optional-string budget;
- retain the 256-track limit and the existing per-string cap;
- retain the existing 64 KiB shared limit as an optional-string-content budget,
  so an oversized early title can remove later optional display facts but never
  a later selectable track;
- shed or truncate optional metadata before losing valid identity; and
- preserve valid UTF-8 when truncating.

Simply increasing `kMaxMetadataBytes` is not sufficient. Adding fields must not
allow one oversized value to bypass the bounds, expose non-whitelisted nodes, or
remove a valid late selected track.

The existing Dart messenger tests receive maps after C++ encoding and cannot
prove this invariant. Add the smallest focused native test seam for the actual
track encoder, using the repository's CMake/CTest facilities without introducing
a general native test framework. Exercise multiple oversized values, a selected
track late in the list, 256/257 tracks, UTF-8 truncation boundaries, malformed
entries, and non-whitelisted sentinel fields.

## Dart presentation policy

### One display result

Use one immutable value or record owned by playback presentation with the fields
actually consumed by the UI:

- drawer primary text;
- ordered drawer secondary facts;
- compact OSD text; and
- complete tooltip text and one coherent actionable semantics description.

Do not create a service, formatter interface, dependency-injection seam, or
generic media-metadata framework. A small pure function and value are sufficient.
Extract them from `player_view.dart` only because the drawer, OSD, semantics, and
pure tests must share the same rule.

The formatter may inspect peer tracks of the same type to add the smallest factual
discriminator when base labels collide. Disambiguation succeeds only when the
visible chooser differs, not merely when full strings or tooltips differ. If ID is
the only discriminator, prepend `Track N` to supporting text rather than appending
it after a long truncatable value. The native track count is already bounded to
256, so a simple readable comparison is preferable to a cache or index. Preserve
`(type, id)` as row key and selection identity; labels never become keys, sorting
authorities, or command identities.

### Normalization

- Trim title, language, codec, and channel-layout values; whitespace-only is
  absent.
- Compare duplicate text case-insensitively after conservative whitespace and
  separator normalization. Do not perform fuzzy matching or semantic inference.
- Preserve Unicode and user-authored title casing.
- Keep unknown language and codec values visible in cleaned original form rather
  than dropping them or inventing a name.
- Avoid repeating the same normalized fact in both primary and secondary text.
- If all human-facing facts are absent, use `Audio track N` or
  `Subtitle track N`.

### Language self-names

The implementation must resolve the actual code shapes observed at the evidence
gate, including relevant ISO 639-1, ISO 639-2 terminology/bibliographic aliases,
and BCP 47-style regional tags. Lookup normalization must not change the stored
native value.

Before adding a package, compare candidate data sources against the captured code
matrix. A candidate must allow Lineup's resolver to:

- be pure Dart or Flutter and work on Windows and macOS;
- supply self-names, not only English exonyms;
- cover the observed two-letter, three-letter, and regional forms or permit a
  small explicit alias layer;
- have an acceptable license, active maintenance, bounded transitive cost, and
  deterministic offline data; and
- return `null` for unknown input rather than guessing, whether the package does
  so directly or a small safe adapter catches its documented failure shape.

`sealed_languages` and `language_code` are candidates, not preselected
dependencies. Prefer one qualifying existing package over a large copied table.
If neither covers the observed contract without substantial adapters, keep a
bounded repo-owned map for the observed high-value codes and regions, preserve raw
unknown values, and document that coverage as intentionally incomplete. Do not
claim full localization from a hand-written subset.

The resolver fixture is broader than captured media. Lock expected results for
ISO aliases plus `es-419`, `pt-BR`, `zh-Hans`, `zh-Hant`, unknown suffixes, and
the special values `und`, `mul`, and `zxx`. Preserve script and numeric-region
distinctions; do not silently discard them or infer names from the machine locale.
An unresolved full tag uses its cleaned raw value. Follow
[BCP 47](https://www.rfc-editor.org/rfc/rfc5646.html) syntax only for parsing and
lookup; it does not authorize inventing a display name.

### Titles and purpose

- Append a meaningful native title after the language with an em dash when it
  adds information: `English — Director commentary`.
- Do not append a title that is only the same resolved language or a raw codec.
- For audio only, explicit `visualImpaired == true` supplies
  `Audio description` unless that same accessibility fact is already visibly
  represented. Do not mechanically apply this label to another track type.
- For subtitles only, explicit `hearingImpaired == true` supplies `SDH` unless
  that same accessibility fact is already visibly represented. An unrelated title
  such as `Festival edition` does not suppress SDH. The semantics description says
  `subtitles for deaf and hard-of-hearing viewers` rather than relying on the
  abbreviation.
- For subtitles only, explicit `forced == true` supplies `Forced` unless that
  disposition is already visibly represented. Its spoken explanation is
  `marked as forced`; do not claim `foreign-language dialogue only`, cue content,
  or automatic-selection behavior from the flag.
- For audio only, explicit `commentary == true` supplies `Commentary` unless the
  same purpose is already visible. A descriptive title remains visible whether or
  not the flag exists; overlapping flag/title information appears once.
- When multiple applicable purpose flags are true, retain each distinct fact in
  the established purpose-before-technical order.

### Audio channel presentation

Use `demux-channels` only through an exact, evidence-backed mapping of layouts
supplied by the pinned runtime. Recognized source layouts may produce familiar
labels such as `Mono`, `Stereo`, `5.1 surround`, or `7.1 surround`. Unknown or
absent layouts fall back to the positive count as `N channels`; six channels do
not by themselves establish 5.1, and eight do not establish 7.1. If neither fact
is usable, omit the channel detail.

Test equal counts with different layouts and unknown layouts with known counts.
Do not infer Atmos, DTS:X, LFE presence, speaker placement, passthrough, or actual
system-output layout. The label describes bounded source-container metadata, not
the post-decode Windows output.

### Friendly codec and subtitle formats

Use a bounded, test-backed mapping for common exact codec identifiers, including:

- `aac` -> `AAC`
- `ac3` -> `Dolby Digital`
- `eac3` -> `Dolby Digital Plus`
- `truehd` -> `Dolby TrueHD`
- exact generic DTS identifier -> `DTS`
- `flac` -> `FLAC`
- `opus` -> `Opus`
- `subrip` -> `SRT (text)`
- `ass`/`ssa` -> `ASS (styled text)` / `SSA (styled text)` as appropriate
- `hdmv_pgs_subtitle` -> `PGS (image)`
- exact pinned-runtime DVD subtitle identifier -> `VobSub (image)`

Use the mapping, then a cleaned raw codec as fallback. Do not use a generic codec
identifier to claim a DTS profile or tier. Adding `codec-profile` or restoring
`codec-desc` requires a separate concrete decision backed by accepted native
evidence. Never infer a brand tier or object-audio mode that the exact identifier
does not establish.

### Compact OSD label

Keep the OSD action concise:

- selected language self-name when available;
- a short explicit purpose such as `SDH`, `Forced`, or `Audio description` when
  it materially distinguishes the selected track;
- a concise literal title discriminator after language when peers would otherwise
  make confirmation ambiguous, without interpreting the title as a typed fact;
- meaningful title when language is absent; and
- the existing bare category (`Audio` or `Subtitles`) when no compact fact exists.

Do not put channel layout, codec, external state, or track IDs into the normal OSD
action. A selected track's untruncated full identity remains available through its
tooltip and accessibility description. Keep the existing single-line ellipsis
behavior; a long title may truncate visually but must not alter selection identity.

## Flutter integration and accessibility

- Retain the existing `ListTile` geometry, three-line bounds, row dividers,
  selected fill, focus surface, checkmark, pending progress indicator, scrolling,
  initial selected-row focus, and `Off` behavior.
- Feed primary and secondary text from the shared display result. Do not create
  per-widget formatting branches.
- Tooltip text contains the complete normalized description without raw duplicate
  fields.
- Reconcile `ListTile`, title, subtitle, checkmark, pending progress, and tooltip
  semantics so each row exposes one coherent actionable identity rather than
  concatenated duplicate announcements. Do not exclude the actionable control or
  rely on the tooltip, which remains excluded from semantics.
- The row's semantics expose track type, untruncated complete description,
  activation action, and confirmed selected state. Pending is distinct from
  selected and must not announce a requested track as already confirmed.
- `Off` remains one actionable subtitle choice. The full spoken meaning of `SDH`
  is available without separately repeating title, subtitle, and checkmark text.
- A failed selection keeps the prior selected row and existing error surface. A
  display-only metadata update issues no native command.
- Preserve the existing error live region, and prove that unrelated rebuilds do
  not repeatedly announce stale pending or error state.
- Preserve all approved colors, type styles, rail/fade widths, gradient stops,
  spacing, and close/control placement.

## Implementation packages and gates

### P0 — evidence and exact contract

1. Record target HEAD, status, pinned Flutter/libmpv identities, and existing
   unrelated changes.
2. Capture the bounded redacted Windows field matrix described above.
3. Confirm each proposed field and type against pinned mpv source/runtime.
4. Resolve the language-data approach against observed codes and record its
   license/dependency decision.
5. Define the native encoder test seam and identity-preserving optional-string
   budget before adding longer metadata fields.

**Gate:** no production native-field expansion until field availability and
language-code shapes are established. Missing rare media does not block portable
implementation when its state remains explicitly unverified.

### P1 — typed native projection

1. Repair `EncodeTrackList` so valid ID/type/selection survive optional-string
   exhaustion, then extend the whitelist with only accepted fields.
2. Add the focused native encoder tests for string exhaustion, late selection,
   256/257 tracks, UTF-8 truncation, malformed maps, and sentinel fields.
3. Extend `PlayerTrack` and `_decodeTrack` with typed nullable facts; validate
   existing optional strings and positive ID domain at the same boundary.
4. Update existing fakes mechanically; do not add defaults they do not know.
5. Extend adapter tests for present, false, absent, malformed, successive snapshots,
   and ignored non-whitelisted values. Do not claim those tests cover C++ encoding.

**Gate:** native encoder and Dart adapter tests pass; Windows native code compiles
against prepared libmpv; identity retention, UTF-8 bounds, positive IDs, stale-fact
removal, and unknown-versus-false behavior are reviewed.

Suggested commit if the final diff remains independently reviewable:
`feat(player): expose factual track metadata`.

### P2 — shared label policy

1. Implement the pure display result and formatter.
2. Add the approved language resolution, purpose, channel, codec, fallback,
   de-duplication, and peer-disambiguation rules.
3. Replace the current private raw-label helpers; delete obsolete alternatives.
4. Prove the policy with table-driven Dart tests through its public playback-owned
   seam, not private widget probes.

**Gate:** the accepted label matrix is deterministic, purpose facts are not
invented or suppressed by unrelated titles, equal counts do not invent topology,
unknown values remain truthful, and no production UI has two formatting
implementations.

Suggested commit: `fix(player): present human-readable track labels`.

### P3 — drawer, OSD, semantics, and visual proof

1. Integrate the display result into the existing drawer and compact OSD action.
2. Add focused widget assertions for text hierarchy, semantics, pending/selected
   state, Off, long content, enlarged text, and missing data.
3. Produce matched before/after real-widget renders at 1280x720 and 1920x1080 on
   the approved bright and dark synthetic scenes, with identical content, focus,
   and playback state. Include audio and subtitles.
4. Inspect 800x600, 1360x840, 1600x900, 4K/high-DPI, and text scale 2 for
   wrapping, scrolling, focus visibility, and reachability. Do not update an
   approved baseline merely to make a test pass.

**Gate:** the approved drawer structure is unchanged, hierarchy remains legible
on bright and dark video, every row remains reachable and visibly distinguishable,
and the semantics tree exposes one actionable untruncated identity with confirmed
and pending state kept distinct.

Keep P2 and P3 in one commit if separating them would temporarily duplicate the
formatter or leave production UI on an intermediate contract.

### P4 — Windows acceptance and closeout

1. Create a separate clean acceptance worktree at the candidate SHA, leaving the
   unrelated untracked review packet in the development checkout untouched. Run
   the application from that clean worktree with the exact patched engine.
2. For every available representative track, compare the displayed label with the
   redacted native facts and independently observable audible/rendered result.
   Record a known spoken cue, subtitle cue, or timestamp that distinguishes each
   selected stream; comparing the label only with the metadata that generated it
   is insufficient.
3. Verify embedded/external text and image subtitles, Off, multiple audio tracks,
   failed switching, rapid switching, keyboard/mouse navigation, focus return,
   resizing, fullscreen, DPI, and overlay composition.
4. Run a physical Windows Narrator scenario covering row navigation, one coherent
   announcement, selected versus pending state, activation, Off, SDH expansion,
   and selection failure. Portable semantics tests do not establish Windows AT.
5. Distinguish standalone pinned-mpv metadata capture from selection through the
   actual Lineup/Plex application path. An external sidecar opened only in a
   standalone player does not prove that Lineup exposes it.
6. Repeat the relevant `AUDIO-1`, `AUDIO-2`, `SUB-1`, `SUB-2`, Tracks, Input, and
   Multi-monitor/DPI rows in `windows-native-validation.md` at the exact tested
   commit. Mark unavailable media explicitly rather than claiming coverage.
7. Record candidate SHA, patched engine and libmpv identities, display/scaling,
   media-case aliases, cues/timestamps, and observations. Any fix creates a new
   candidate and requires affected scenarios to be rerun.
8. Append dated evidence to `ux-functionality-audit.md`, update `user-guide.md`
   with the final label policy, and record any durable Player presentation rule in
   `.interface-design/system.md` without duplicating implementation detail.

**Gate:** finding 4 may become `verified` only after portable checks, approved
visual comparison, native build proof, exact-commit physical Windows label-to-
output verification, and Narrator acceptance pass. Otherwise record the narrower
achieved state and the specific remaining gate.

## Regression matrix

| Area | Required cases |
| --- | --- |
| Native encoder | Required identity survives optional-string exhaustion; late selected track; multiple oversized strings; 256/257 tracks; UTF-8 truncation boundary; malformed map; non-whitelisted sentinel absent. |
| Native decode | Old and new optional fields present, false, absent, null, wrong type; zero/negative/non-integer ID; malformed count; valid selected track after malformed data; successive snapshot removes a former fact; immutable track list; unknown remains null. |
| Language | Two-letter, three-letter terminology and bibliographic alias, mixed case/separator, already-human name, Unicode self-name, `es-419`, `pt-BR`, `zh-Hans`, `zh-Hant`, unknown suffix, `und`, `mul`, `zxx`, blank value. |
| Title | Blank, language duplicate, codec duplicate, commentary, audio description, long Unicode, punctuation/case variants, arbitrary user title. |
| Purpose | Unrelated meaningful title plus each applicable true flag; commentary without title; overlapping title/flag; simultaneous flags; false/unknown; generated wording restricted to relevant track type; forced never claims cue content. |
| Channels | Recognized and unknown layouts; equal counts with different layouts; known count without layout; 1, 2, 6, 8, unusual positive count; zero/negative/malformed/absent; no invented LFE/topology. |
| Codec | Every accepted exact mapping, unknown codec, blank codec, subtitle text/image distinction, generic DTS remains DTS, no invented profile/Atmos/passthrough claim. |
| Disambiguation | Identical language/title, different layouts, different codecs, external versus non-external, long identical prefixes with differing tails, completely identical rows with `Track N` visible at start of supporting text. |
| Drawer | Audio, subtitles, Off, selected, focused, pending, failed, loading, empty, 256-row scrolling, long labels, tooltip, one actionable semantics node and activation action, existing error live region without repeat announcements. |
| OSD | Compact language/purpose and bounded literal title discriminator, Off, missing facts, single-line ellipsis, complete tooltip/semantics identity, drawer agreement. |
| Layout | 800x600, 1280x720, 1360x840, 1600x900, 1920x1080, 4K/high-DPI, text scale 1 and 2, bright and dark moving-video backgrounds. |
| Update stability | Metadata and peer-set updates while focused or pending preserve `(type, id)` identity, focus, and confirmed selection; display-only update sends no native command. |
| Windows runtime | Independent cue/timestamp proves audible/rendered stream matches selected label; embedded/Plex-external and text/image cases when available; failed and rapid switching preserve confirmed state; Narrator announcement and activation pass. |

## Verification commands

Use the repository-pinned Flutter `3.47.4` revision
`9584c6713b324636289d067944a46fd6b49df14b` with Dart `3.13.3`.

Focused portable checks:

```sh
dart format <changed Dart paths>
TZ=America/New_York flutter test test/playback/windows_native_player_test.dart
TZ=America/New_York flutter test test/playback/windows_native_player_encapsulation_test.dart
TZ=America/New_York flutter test test/playback/player_track_label_test.dart
TZ=America/New_York flutter test test/playback/player_view_test.dart
TZ=America/New_York flutter test test/playback/player_coordinator_test.dart
flutter analyze
git diff --check
```

Full portable closeout:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
TZ=America/New_York flutter test
git diff --check
```

On Windows, run the portable tests in the documented timezone context, then:

```powershell
flutter build windows
ctest --test-dir .\build\windows\x64 -C Release --output-on-failure
pwsh -File .\tool\windows\run.ps1
```

P1 must register the focused native encoder test with CTest and confirm the actual
generated build directory/configuration; adjust the command to that generated
location rather than silently skipping the target. The stock-engine Windows build
and CTest establish compile/link and encoder-contract proof only. Actual Player
and overlay acceptance uses the patched-engine launcher and the physical procedure
in `windows-native-validation.md`. Package acceptance is required only if the work
is being used to support a release/package claim.

## Risks and rollback

- **Misleading metadata:** container channel count may not equal Windows output.
  Mitigation: recognize only evidence-backed source layouts, fall back to
  `N channels`, and make no output/passthrough claim.
- **Selectable-track loss under metadata pressure:** optional strings can exhaust
  the shared native budget before a later track's required type. Mitigation:
  project identity independently, bound optional metadata, and exercise the actual
  C++ encoder at exhaustion and UTF-8 boundaries.
- **Language-data bloat or gaps:** a package may be broad but fail actual Plex/mpv
  tags. Mitigation: decide after the captured matrix, require raw fallback, and do
  not claim complete localization.
- **Title duplication:** arbitrary titles can repeat language, codec, or purpose.
  Mitigation: conservative exact normalization only; prefer a harmless duplicate
  over destructive fuzzy rewriting.
- **Drawer density:** more facts can reduce visible rows. Mitigation: preserve two
  tiers, omit low-value facts, inspect the adaptive matrix, and keep scrolling.
- **Native contract drift:** adding fields can accidentally touch lifecycle or
  selection behavior. Mitigation: keep the patch in `EncodeTrackList` and typed
  decoding; do not alter request identities or commands.
- **Duplicate or missing announcements:** composing new semantics atop `ListTile`,
  child text, checkmarks, progress, and the error live region can duplicate or
  suppress actionable information. Mitigation: assert the resulting semantics
  tree and activation, then verify Narrator on physical Windows.
- **Privacy:** raw titles and external filenames may expose private media. Mitigation:
  never whitelist filenames and commit only synthetic/redacted fixtures.

Each proposed commit is independently revertible. Reverting P2/P3 restores the
current normalized raw-label policy while retaining harmless optional native
facts from P1. Reverting P1 also removes those fields. Use normal reverts; do not
rewrite shared branch history.

## Review questions before implementation

The plan review should specifically challenge:

1. Whether the proposed native fields are available with the stated types in the
   pinned mpv commit and the corrected encoder protects required identity while
   bounding optional strings.
2. Whether the recognized `demux-channels` mapping is narrow enough and every
   unknown layout falls back to count without invented topology.
3. Whether default omission of `codec-desc` and generic DTS labeling avoid
   unnecessary budget and profile claims.
4. Whether the language dependency gate is decisive enough and avoids both a
   fragile tiny map and unnecessary package weight.
5. Whether any label rule could confuse source-track facts with decoded/system
   output facts.
6. Whether the compact OSD policy hides any fact needed for the frequent selection
   task.
7. Whether the regression matrix proves semantics, focus, adaptive layout, native
   selection confirmation, and privacy without redundant tests.

**Independent review:** specifically recommended before implementation because
the change crosses the native MethodChannel boundary and finalizes a protected,
high-use Player UI contract. The requested GPT Pro plan review satisfies the
planning-stage review; concrete code and physical Windows evidence still require
normal implementation self-review and acceptance.
