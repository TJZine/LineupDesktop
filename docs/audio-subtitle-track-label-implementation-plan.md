# Audio and Subtitle Track Label Implementation Plan

**Status:** P1 accepted on September 22, 2026; P2 is permitted. This document
records the approved UI direction for finding 4 in
[`ux-functionality-audit.md`](ux-functionality-audit.md). It does not authorize
later-package implementation, establish physical Windows behavior, or mark the
audit finding verified.

**Planning baseline:** `dev/desktop-ui-refinement` at
`424673484a82b2db897c8f52213a92432cc742b7`. Preserve the unrelated untracked
review packet at
`docs/design/desktop-ui/review-packets/lineup-1080p-cbf3dbd5/`.

P0 began on `dev/desktop-ui-refinement` at
`2338654c01cfdbb3529852b69572cbaa21c935dc`. The working tree contained only the
expected unrelated untracked review packet above. No production or test source
was changed by P0.

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

### P0 evidence record — September 19 and 22, 2026

#### Pinned identities and evidence boundary

- Package start: branch `dev/desktop-ui-refinement`, commit
  `2338654c01cfdbb3529852b69572cbaa21c935dc`. The plan's original
  `424673484a82b2db897c8f52213a92432cc742b7` starting point remains historical.
- Portable toolchain: Flutter `3.47.4`, framework
  `9584c6713b324636289d067944a46fd6b49df14b`, engine
  `06a2e2a110089dff50fe635cffd2a61e1b24fbcd`, and Dart `3.13.3`, as pinned by
  [`build-metadata.psd1`](../tool/windows/build-metadata.psd1) and
  [`DEVELOPMENT.md`](DEVELOPMENT.md#portable-commands). The only local Flutter
  checkout found was unpinned `3.47.0` at framework
  `4cf24164269a5ebf0c16a028a00727d0e77bbb05`; it was not used as evidence.
- Windows media runtime: mpv `v0.41.0-1044-g14f2d48cb`, full source commit
  `14f2d48cbc7dda61adb4bd181e107a1f3f76e533`, release asset SHA-256
  `455965297BA3F5906A63CD2B219442685BE45528A1FE806E4B228147881E41CB`, and DLL
  SHA-256 `B507529D99A4DFFDEAEC85ECEFF7661A7E3C6CA4EFD09C2014E11A1441B83EAA`, as
  pinned by [`windows-runtime.md`](windows-runtime.md#media-runtime) and the
  Windows CMake integrity checks.
- Exact source evidence below is from the detached full commit, not a moving
  manual. It establishes the source contract but is not a query of the packaged
  DLL. No Windows host, prepared DLL, redacted runtime payload, live Plex server,
  or private acceptance-media inventory was available to this macOS package.

The September 22 Windows follow-up started from clean branch
`dev/desktop-ui-refinement` at
`e9697fba1b13b9632c4181f519fdd02404e7cf61`. It verified Flutter framework
`9584c6713b324636289d067944a46fd6b49df14b`, engine
`06a2e2a110089dff50fe635cffd2a61e1b24fbcd`, the repository patch SHA-256
`3A6AA524780826F250352425BE146C6D2549FCCB11B87F993F250EFD4DBC1DCB`, and the
applied patch. The prepared mpv asset provenance matched release-asset SHA-256
`455965297BA3F5906A63CD2B219442685BE45528A1FE806E4B228147881E41CB`;
`libmpv-2.dll` matched
`B507529D99A4DFFDEAEC85ECEFF7661A7E3C6CA4EFD09C2014E11A1441B83EAA`, and
`include/mpv/client.h` matched
`1ACF99EE77C8C2A6F1D1993BD81BBC8A91D27FB5924E80171670E6139A4BD353`.

The standalone pinned-libmpv probe ran on Windows 10 Home `10.0.19045`, AMD
Ryzen 9 5900X, NVIDIA GeForce RTX 5080 driver `32.0.16.1692`, one reported
3840x2160 display at 96 DPI/100% system scaling, with `vulkan-1.dll` present.
This machine identity interprets only the metadata capture. No Lineup/Plex
application path, UI label, audible/rendered output, Narrator, HDR, or P4
acceptance scenario was exercised.

#### Exact pinned mpv contract

The authoritative implementation is
[`player/command.c` at the pinned commit](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/player/command.c#L2133-L2187).
It constructs each native `track-list` map as follows; `m_property_read_sub` then
omits only entries whose `.unavailable` member is true
([source](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/options/m_property.c#L482-L512)).

| Candidate | Exact native value | Absence behavior at the pinned commit | P0 disposition |
| --- | --- | --- | --- |
| `demux-channel-count` | `MPV_FORMAT_INT64`, sourced from `p.channels.num` | Key omitted when the count is zero | Accept for P1, still nullable and positive-only in Dart |
| `demux-channels` | `MPV_FORMAT_STRING`, sourced from `mp_chmap_to_str(&p.channels)` | Key omitted when the count is zero | Accept for P1 as a bounded fact; no friendly layout mapping until observed values are captured |
| `forced` | `MPV_FORMAT_FLAG` | Always present in the native node; false is explicit | Accept for P1; bridge absence/malformed remains `null` |
| `external` | `MPV_FORMAT_FLAG` | Always present in the native node; false is explicit | Accept for P1; bridge absence/malformed remains `null` |
| `hearing-impaired` | `MPV_FORMAT_FLAG` | Always present in the native node; false is explicit | Accept for P1; bridge absence/malformed remains `null` |
| `visual-impaired` | `MPV_FORMAT_FLAG` | Always present in the native node; false is explicit | Accept for P1; bridge absence/malformed remains `null` |
| `commentary` | `MPV_FORMAT_FLAG` | Always present in the native node; false is explicit | Accept for P1; bridge absence/malformed remains `null` |

This corrects an ambiguity in the prose manual, which describes some false flags
as potentially unavailable. At this exact commit the implementation gives these
five fields no `.unavailable` condition, so a native node contains `true` or
`false`. Nullable Dart values still matter at the Lineup trust boundary: omitted,
null, or wrong-typed bridge data is unknown and must not be coerced to false.

`title`, `lang`, `codec`, and `codec-desc` are strings and are omitted when their
source pointer is absent. mpv passes container language strings through without
BCP 47 normalization. Its lavf and Matroska demuxers suppress exact `und`; the
Matroska demuxer prefers `LanguageBCP47`, otherwise uses the legacy language value,
and supplies legacy `eng` when neither exists
([lavf source](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/demux/demux_lavf.c#L874-L882),
[Matroska source](https://github.com/mpv-player/mpv/blob/14f2d48cbc7dda61adb4bd181e107a1f3f76e533/demux/demux_mkv.c#L942-L950)).
Pinned mpv source tests contain three-letter examples (`eng`, `fra`, and `jpn`),
but those fixtures are not Lineup Windows runtime observations.

Keep `codec-desc` and all neighboring non-goal fields out of P1. The source proves
they exist, not that the approved chooser needs them. In particular, never project
`default`, `external-filename`, `ff-index`, program/stream indices, bitrate, sample
rate, decoder identity, `codec-profile`, or unlisted nodes without a separately
approved current consumer.

#### Redacted Windows field and code-shape matrix

The September 22 capture queried `track-list` directly through the verified
standalone DLL. Synthetic aliases replace media identity; titles are recorded only
as present or absent. Every recorded identity was a positive native
`MPV_FORMAT_INT64`, `type` was `MPV_FORMAT_STRING`, and `selected` was an explicit
`MPV_FORMAT_FLAG`. The synthetic IDs below preserve within-alias order without
recording private media or native stream identity.

| Synthetic alias / ID | Track and selected state | Optional strings | Candidate fields | Evidence use |
| --- | --- | --- | --- | --- |
| `stereo-01` / 1 | audio; selected `true` | title absent; `lang=eng` (`MPV_FORMAT_STRING`, three-letter); `codec=aac` (`MPV_FORMAT_STRING`) | count `2` (`MPV_FORMAT_INT64`); layout `stereo` (`MPV_FORMAT_STRING`); all five disposition fields present as `MPV_FORMAT_FLAG=false` | Ordinary stereo and missing-title case |
| `missing-language-01` / 1 | audio; selected `true` | title and language absent; `codec=aac` (`MPV_FORMAT_STRING`) | count `2`; layout `stereo`; all disposition flags false with the types above | Pinned mpv omitted the source's exact `und`; missing optional title/language case |
| `multichannel-sdh-01` / 1 | audio; selected `true` | title absent; `lang=en` (two-letter); `codec=eac3` | count `6`; layout `5.1`; all disposition flags false | Ordinary multichannel case |
| `multichannel-sdh-01` / 2 | subtitle; selected `false` | title absent; `lang=en-US` (regional); `codec=subrip` | channel count/layout absent; all disposition flags false | Ordinary embedded text subtitle |
| `multichannel-sdh-01` / 3 | subtitle; selected `false` | title present; `lang=en-US` (regional); `codec=subrip` | channel count/layout absent; `hearing-impaired=true`; other disposition flags false | Embedded SDH/hearing-impaired text subtitle |
| `multichannel-forced-01` / 1 | audio; selected `true` | title present; `lang=en-US` (regional); `codec=ac3` | count `6`; layout `5.1(side)`; all disposition flags false | Equal count with a different exact layout token |
| `multichannel-forced-01` / 2 | subtitle; selected `true` | title present; `lang=en` (two-letter); `codec=subrip` | channel count/layout absent; `forced=true`; other disposition flags false | Selected embedded forced text subtitle |
| `multichannel-forced-01` / 3 | subtitle; selected `false` | title present; `lang=en` (two-letter); `codec=subrip` | channel count/layout absent; all disposition flags false | Second ordinary embedded text subtitle |

For every row, `forced`, `external`, `hearing-impaired`, `visual-impaired`, and
`commentary` were present as `MPV_FORMAT_FLAG`. Audio rows carried
`demux-channel-count` as `MPV_FORMAT_INT64` and `demux-channels` as
`MPV_FORMAT_STRING`; subtitle rows omitted both. Every present `title`, `lang`,
and `codec` value was `MPV_FORMAT_STRING`. These observations match the pinned
source contract and preserve bridge-level nullable handling for absent or malformed
data.

The bounded authorized inventory contained nine user-video candidates. A further
technical-only scan probed 294 of at most 300 media candidates across five
non-system fixed drives without retaining names or paths. It found no additional
non-English language, script tag, commentary, visual-impaired audio, or image
subtitle case. Therefore commentary audio, audio-description audio, script tags,
image subtitles, external/Plex-managed subtitles, missing codec, and provably
identical visible metadata remain unavailable, not passed. No actual Lineup/Plex
path was exercised, so the capture makes no claim that Lineup exposes external or
Plex-managed subtitles.

The observed resolver inputs `en`, `eng`, and `en-US` are exact supported
`language_code` `0.7.1` cases. The source value `und` became an absent `lang` in
the pinned runtime, consistent with the recorded demux contract. No recurring
unsupported shape was observed, so the selected resolver remains proportionate;
script and non-English behavior remain fixture-backed rather than Windows-media
observations.

The exact observed source-layout mapping for P2 may recognize `stereo` as
`Stereo`, and both `5.1` and `5.1(side)` as `5.1 surround`. The two six-channel
tokens prove that count alone is not a layout identity. All other tokens must
remain unknown and fall back to a positive `N channels`; this evidence does not
describe decoded Windows output or passthrough.

#### Language resolver decision

Use [`language_code` `0.7.1`](https://pub.dev/packages/language_code/versions/0.7.1)
in P2, but do not add it in P0. Its published source is MIT-licensed, supports Dart
`>=3.9.0 <4.0.0` and Flutter `>=3.35.0`, and has no third-party runtime dependency
beyond the Flutter SDK already required by Lineup. Version `0.7.1` was published
May 25, 2026; its archive SHA-256 is
`bcfe7a2c88741b68f88e648c28e64d1198cf0dc3ecf9ae21cb274e5e99e2f0a3`. Its
deterministic offline enum contains the required two-letter, three-letter
terminology/bibliographic, regional, script, and special fixture codes, including
`es_419`, `pt_BR`, `zh_Hans`, `zh_Hant`, `und`, `mul`, and `zxx`. The published
archive is about 136 KiB and its five Dart library files total about 315 KiB, with
the generated table accounting for about 304 KiB.

The alternative
[`sealed_languages` `3.3.0`](https://pub.dev/packages/sealed_languages/versions/3.3.0)
is also MIT and actively maintained, but it resolves only base ISO 639-1/639-2
language identities. Regional and script display would require a second repo-owned
dataset, while the package also brings `l10n_languages`; that is more data and
adapter ownership for this contract.
A hand-written language table is smaller in bytes but would duplicate maintained
ISO aliases and the required regional/script cases. `language_code` is therefore
the smallest complete current choice.

The P2 adapter remains small and deterministic: trim input; normalize `_`/`-`,
primary/script/region casing only for lookup; perform an exact enum-code match;
and return `null` on unknown or unsupported suffixes. It must never use device
locale fallback. Use the package's native name. Preserve the cleaned original tag
when lookup returns `null`. Treat `und` as unavailable rather than a language name;
render `mul` as `Multiple languages` and `zxx` as `No linguistic content`. Lock
fixtures for `en`/`eng`, terminology/bibliographic pairs such as `fra`/`fre` and
`deu`/`ger`, mixed separators/case, `es-419`, `pt-BR`, `zh-Hans`, `zh-Hant`, an
unknown suffix, `und`, `mul`, `zxx`, and blank input before UI integration.

The dependency decision satisfies both the known plan fixtures and the observed
Windows shapes `en`, `eng`, and `en-US`. Recheck any later unsupported recurring
shape against this adapter instead of guessing or silently reducing it to a base
language.

#### P1 encoder seam and bounded identity contract

Use one production function, not a test-only duplicate: extract the current pure
track projection and its UTF-8 helper from `native_player.cpp` into a small
`track_list_encoder.h/.cpp`, then have `WindowsNativePlayer::EncodeTrackList`
delegate to it. Add one assertion-based `track_list_encoder_test.cpp` executable,
register it with CTest, and compile the same `track_list_encoder.cpp` into the
runner and test targets. Link only the existing Flutter C++ wrapper needed for
`EncodableValue`; construct `mpv_node` fixtures directly, so no live mpv handle,
general test framework, fixture library, or new dependency is needed.

The production function must enforce this exact contract:

- inspect at most 256 input entries and project only map entries;
- admit a track only when `id` is a positive `MPV_FORMAT_INT64`, `type` is exactly
  fixed literal `video`, `audio`, or `sub`, and `selected` is an
  `MPV_FORMAT_FLAG`; project those three required values without charging the
  optional-string counter;
- keep the existing 4096-byte per-string cap and preserve valid UTF-8 when
  truncating;
- keep 64 KiB as one shared optional-string-content budget across accepted
  tracks, not as a claim about total `EncodableValue` or MethodChannel message
  size; only accepted optional strings decrement it;
- after exhaustion, omit optional string values rather than emitting empty
  strings that imply known empty metadata, while continuing to project later
  valid identities and fixed-size accepted numeric/boolean facts;
- whitelist only the accepted current fields; malformed optional facts become
  absent, and sentinel/non-whitelisted keys never cross the boundary; and
- keep field names, container overhead, fixed scalars, list/map overhead, and
  MethodChannel serialization outside this counter. Any need for a total message
  bound is a separate design with separate measurement.

The focused test must exercise multiple oversized strings, a selected track late
in the list after exhaustion, 256/257 entries, truncation adjacent to 2/3/4-byte
UTF-8 sequences and invalid bytes, malformed maps/required fields/optional facts,
false versus absent descriptive flags, and a non-whitelisted sentinel. CTest must
run the produced executable from the actual generated Windows build directory and
configuration; Dart messenger tests remain adapter-only evidence.

#### Privacy and P0 gate verdict

Privacy is structural, not a cleanup step: the production whitelist excludes
`external-filename` and neighboring path/stream fields; tracked fixtures use only
synthetic titles and aliases; captures contain normalized presence/type/code-shape
facts only; and ordinary verbose logs, private titles, filenames, local paths,
server payloads, credentials, authorization headers, and token-bearing URLs are
never recorded.

**P0 gate: satisfied.** The verified pinned Windows DLL supplied ordinary stereo
and multichannel audio, embedded text subtitles, missing optional metadata,
selected and unselected positive identities, two-letter/three-letter/regional
language shapes, exact channel tokens, equal counts with different layouts, SDH,
and forced examples. Those observed values fit the recorded resolver and narrow
exact layout policy. Rare unavailable cases remain explicit and do not become
passes. P1 may proceed; this evidence does not establish application-path
selection, physical label-to-output agreement, Narrator, final UI, or P4
acceptance.

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

## Execution ledger

| Package | Accepted commit | Controller acceptance | Verification | Proof unavailable or deferred | Remaining risk | Next permitted package |
| --- | --- | --- | --- | --- | --- | --- |
| P0 — evidence and exact contract | `11d62562d90d7adb4f9d0d4969141022adf79e29`, `d6ae442592c5ffa1ce380135ed0c9fc2b15439e9` | September 22, 2026 | Confirmed both commits descend from the expected package starts; reviewed every changed line; ran `git show --check` and range `git diff --check`; independently checked repository runtime/toolchain hashes, pinned mpv field construction, the `language_code` 0.7.1 archive, the bounded matrix against the mandatory P0 cases, and added-line privacy calibration. | No Lineup/Plex application path, audible/rendered output, Narrator, HDR, external/Plex-managed subtitle, commentary, audio-description, image-subtitle, script-language, non-English, missing-codec, or identical-visible-metadata proof. These remain explicit P4, fixture, or unavailable cases as applicable. | Standalone metadata proves the bounded native facts but not application exposure or label-to-output agreement. Later packages must preserve the exact whitelist, unknown-versus-false contract, narrow layout mapping, and calibrated evidence claims. | P1 — typed native projection. |
| P1 — typed native projection | `ba46ac994eea58a5fc38a358bd756b883ae3a3dd` | September 22, 2026 | Confirmed ancestry from `704f4779e3948bfc1e817dedfc5e8ab49aa22dea`; reviewed every changed line against the accepted native/Dart boundary and focused tests; ran `git show --check` and range `git diff --check`. On the exact pinned Windows toolchain the worker observed 35 adapter tests, the encapsulation test, 110 coordinator tests, analysis, `flutter build windows`, the explicit Release `track_list_encoder_test` build, and CTest `1/1` passing; dependency and assertion-import inspection confirmed the test exercises the production encoder without live mpv. | Physical Lineup/Plex playback, audible/rendered selection agreement, Narrator, HDR/composition, packaging, and P4 acceptance were not run. | Deterministic encoder/adapter proof does not establish application-path exposure or physical output. The native CTest target is intentionally explicit rather than part of the default application build and must remain included in future native verification commands. | P2 — shared label policy. |
