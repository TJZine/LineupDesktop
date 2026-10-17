# Lineup Desktop feature opportunities

October 14, 2026. Prepared for product review and independent validation by the
Opus 5.5 agent before implementation planning.

The four additions the maintainer wants to pursue are lineup backup and restore,
mixed-source Channel Studio authoring, last-channel recall, and preferred audio,
subtitle, and accessibility tracks. All have a concrete place in the current
product. Backup and restore offers the largest protection for user effort;
last-channel recall is the smallest useful addition. Mixed-source editing exposes
an existing domain capability. Track preferences need the closest coordination
with the separately planned Plex transcoding work.

Further research also identified candidates beyond those four. Favorites is the
strongest new everyday-use candidate. Guide freshness and alternate media-version
selection already appear in repository backlog material and deserve explicit
reconciliation. These recommendations express value and scope, not final UI,
data-format, or implementation decisions.

## Source and product constraints

The inspected checkout is `codex/desktop-ui-second-pass` at
`eede9bb395054a54c64ff4263b861786bb907a08`, with the uncommitted dependency upgrade
to Flutter 3.47.7, upload-artifact 7.0.2, and jni_flutter 1.0.4+1. Preserve that
work and the earlier CI download-retry changes. Recheck the actual checkout when
using this report; the commit alone does not identify the working tree.

Flutter/Dart owns application and interaction policy. Windows C++/libmpv owns
platform and media mechanisms. Preserve profile/server isolation, atomic save
and rollback, credential separation, deterministic schedules, stale-result
rejection, and native-observed track confirmation. The approved Player and Now
Playing layout needs design agreement before a material departure. Windows is
the playback target; macOS remains a portable development surface.

The [transcoding plan](plex-transcoding-implementation-plan.md) remains the
authority for reduced-bitrate Home/Remote playback. Its discovery and design
conditions are separate from interest in these four additions. Physical Windows
acceptance remains a release obligation regardless of which feature is selected
next.

## Four additions selected for further planning

### F1 Lineup backup and reviewed restore

A user who has spent hours arranging channels should be able to recover after
data damage or moving their installation. Current
[FileAppStore](../lib/persistence/app_store.dart) stores canonical state in
`state.json`, quarantines invalid data, and starts with empty state after format
failure. Its `.pre-desktop-ui` backup protects a specific migration. Neither is
a user-facing ongoing export/restore workflow.

Recommended direction: a versioned export of explicitly selected lineup data
and optional settings, followed by validation and a readable restore preview.
Begin by supporting the same Plex server/library identities. Cross-server media
remapping is a distinct portability problem, not something an importer should
guess. Preserve channel recipes, numbering, ordering, anchors, seeds, and any
schedule-transition state needed to reproduce existing behavior. Credentials,
client identity, tokenized resource URLs, and unrelated profiles must not be
included implicitly. An export can still contain private media metadata.

Resolve before planning: active-profile export versus a deliberately selected
multi-profile archive; merge versus replace; conflict handling; global settings
versus profile-specific data; unavailable source references; format evolution;
whether automatic local snapshots are part of this feature or a later extension.

Meaningful proof includes a semantic export/restore round trip, schedule identity
at a fixed clock, wrong-server and future-format handling, bounded invalid-input
rejection, conflict preview, and failed-save rollback. Cancelling a preview must
leave both saved and active state unchanged. A restored recipe is not a guarantee
that its Plex media is still accessible.

Relative scope: medium, with persistence and privacy risk. Tunarr documents manual
and scheduled backup archives, but its restore procedure is manual. Lineup's
reviewed in-app restore would be its own product design. [Tunarr backup](https://tunarr.com/configure/system/backup/)

### F2 Mixed-source authoring in Channel Studio

A user should be able to make a channel from several libraries, collections,
playlists, or hand-picked sources—for example, alternating episodes from two
sitcom sources. [MixedSource](../lib/channels/channel.dart) already represents
multiple child sources and an `interleave` choice. The
[content resolver](../lib/channels/content_resolver.dart) implements concatenation
and round-robin interleaving. However,
[ChannelStudioDraft.configureSource](../lib/app/channel_studio_draft.dart) gives a
mixed source no editable source choice; the view preserves it until replacement.

Recommended direction: expose that capability through an agreed source-list
editor, reuse existing child-source pickers, and keep Air Check tied to the same
resolver and scheduler as Guide and Player. Explain concatenation and alternating
content plainly. Weighted rotation and time-of-day programming are additional
policies, not interchangeable names for the current `interleave` behavior.

Resolve before planning: nested mixes versus a flat authoring model; how existing
nested data remains inspectable; repeated media occurrences when sources overlap;
unequal source lengths; empty or temporarily unavailable sources; how source
order combines with the channel's playback rhythm. Do not silently deduplicate
intentional repeated occurrences or flatten old data into different programming.

Meaningful proof includes inspect/edit/save round trips for existing mixes,
unequal and empty inputs, deliberate repeated occurrences, cancellation and
conflict recovery, and equivalent Air Check/Guide/Player results at a fixed clock.
Source-order changes should have explained schedule consequences.

Relative scope: medium, mostly Flutter/Dart. ErsatzTV Legacy uses ordered
collection schedule items; this supports the value of authoring source rotations
without making its streaming-server design a Lineup requirement.
[ErsatzTV classic schedules](https://ersatztv.org/docs/scheduling/classic/)

### F3 Last-channel recall

Let a viewer switch from A to B and then return to A without searching or knowing
its number. Current [PlayerCoordinator.previousChannel](../lib/playback/player_coordinator.dart)
calls `_tuneOffset(-1)`: it means the neighboring channel, not the one previously
watched. Existing Guide, Mini Guide, search, and number-entry paths already tune
channels and should converge on the same recall semantics.

Recommended direction: retain the last two successful channel identities for
the active profile/server session and offer an accessible action and agreed
shortcut. Recall joins the channel's live scheduled position. It must not become
an implicit DVR resume or require a Player layout redesign.

Resolve before planning: when a tune counts as successful, including native
confirmation versus command acceptance; whether history persists across launch;
behavior after deletion, sign-out, profile/server switch, or a failed recall;
shortcut placement and conflicts. Requested, saved-current, and actively playing
channel identities remain distinct. Failed or superseded work must not promote
a history entry.

Meaningful proof includes A/B toggling, rapid superseding tunes, delayed native
results, failures, deletion, context switches, and keyboard/focus accessibility.
Reusing a mocked transport does not establish physical Windows input behavior.

Relative scope: small, with modest asynchronous-state risk. Channels offers a
last-channel action; its remote gesture is a comparison point rather than a
shortcut to copy into a desktop app. [Channels Live TV](https://getchannels.com/docs/apps/usage/live-tv/)

### F4 Preferred language and accessibility tracks

Viewers should not have to select the same audio language, subtitles, SDH, or
audio-description track after every scheduled program change. Current
[LineupSettings](../lib/settings/lineup_settings.dart) has no track preference
fields. [PlayerTrack](../lib/playback/native_player.dart) exposes language,
forced, hearing-impaired, visual-impaired, and commentary facts when available.
Manual selection already uses asynchronous confirmation and current-load guards
in [PlayerCoordinator.selectTrack](../lib/playback/player_coordinator.dart).

Recommended direction: define one track-selection policy with an explicit
source/default mode, language preferences, and optional accessibility choices.
Preserve user overrides and distinguish absent metadata from a known negative
flag. Inspect Plex account and per-item preferences before deciding whether
Lineup should inherit, override locally, or offer both. Do not silently write
preferences back to Plex.

Resolve before planning: precedence among account defaults, local preferences,
per-item selections, and session overrides; unknown language fallback; forced
subtitle behavior; whether commentary is excluded by default; SDH versus audio
description priorities; preference scope and persistence; override lifetime
across multipart content and program changes. The transcode plan's Plex stream
selection and session-restart semantics must share the policy rather than become
a second competing owner.

Meaningful proof includes ambiguous/missing metadata, manual override retention,
new parts and programs, stale native events, unavailable preferred tracks,
selection timeout/failure, and the Direct Play/transcode boundary. Physical
media samples must establish actual native and server-delivered track behavior.

Relative scope: medium, potentially larger when integrated with transcoding.
Plex documents language defaults and persistent manual-item precedence. Its SDH
and forced-subtitle *search* preferences are not evidence of automatic selection
of embedded accessibility tracks.
[Plex language settings](https://support.plex.tv/articles/204985278-account-audio-subtitle-language-settings/)

## Comparable applications and additional candidates

Official documentation was reviewed on October 14, 2026 for Tunarr, Channels,
Plex HTPC, and ErsatzTV. Tunarr and ErsatzTV are server-oriented channel systems;
Channels and Plex HTPC supply useful viewing and accessibility comparisons.
ErsatzTV Legacy and Next have different scope: Next emphasizes streaming and
transcoding with third-party scheduling. A Legacy scheduling feature must not be
presented as a confirmed Next capability.
[ErsatzTV Next](https://ersatztv.org/next-docs/)

The following are recommendations inferred from those comparisons and current
Lineup source. Peer availability establishes a useful pattern, not demonstrated
demand among Lineup users.

| Candidate | Value and preliminary recommendation | Decisions and evidence needed |
| --- | --- | --- |
| Favorites and optional channel groups | Highest-priority new candidate: a smaller everyday Guide/surfing set without deleting or reordering the whole lineup. Channels supports favorites and channel groups. Start by evaluating favorites; assess groups separately. | Profile/server versus device scope, favorites-only surfing, number-entry behavior, deletion/import handling, focus restoration, and distinction between channel groups and Plex media collections. Current models/settings expose no favorites field. [Channels management](https://getchannels.com/docs/apps/usage/manage-channels/), [channel groups](https://getchannels.com/docs/channels-dvr-server/how-to/channel-collections/) |
| Subtitle presentation and timing adjustments | Strong companion to F4: text size/position and a reversible subtitle offset can solve readability or sync problems that selecting the correct track does not. Plex HTPC exposes text subtitle presentation; Plex also documents subtitle offsets. | Renderer support for text versus styled/image or server-burned subtitles, bounded values, reset behavior, persistence scope, native acknowledgments, and avoiding overlap with track-selection policy. Audio delay is a related but separate decision. [HTPC settings](https://support.plex.tv/articles/htpc-settings/), [subtitle offsets](https://support.plex.tv/articles/subtitle-offsets/) |
| Time-of-day or weekly programming blocks | Highest-value longer-term programming candidate: morning cartoons or a Friday movie rather than one continuously repeated recipe. Tunarr provides fixed-time slots. This changes the schedule domain substantially. | Timezone/DST, midnight boundaries, duration overflow, gaps, reruns, missing sources, deterministic episode progress, clock changes, migration, and schedule consistency across Guide/Air Check/Player. Keep distinct from F2. [Tunarr time slots](https://tunarr.com/configure/scheduling/time-slots/) |
| Bumpers and bounded filler | Potential optional extension for the television feel and gaps in timed blocks. Tunarr uses filler around programs/slots. Defer until its value and timing rules justify added programming states. | Whether filler counts as Guide content, exact duration/overrun policy, repetition, missing clips, seeking and program transitions. No implication that Lineup should download third-party advertisements or add arbitrary network sources. [Tunarr filler](https://tunarr.com/configure/library/filler/) |

## Previously suggested work that must be reconciled

The [product-parity audit](product-parity.md), current source, and existing plans
contain further suggestions. They are not all new features, and their old status
labels cannot substitute for checking today's behavior.

| Area | Current evidence and action for validation |
| --- | --- |
| Alternate Plex media versions | `parseMediaItem` in [plex_client.dart](../lib/plex/plex_client.dart) keeps the first `Media` record. Explicit edition/version selection is a real candidate. Determine how differing durations affect live schedule offsets and how selection interacts with transcoding. Do not confuse media versions with audio tracks or sequential parts. |
| Guide and collection freshness | An [existing investigation](guide-freshness-collection-investigation.md) leaves live-session refresh and collection mutation/recreation open. Canonical shuffle response-order drift was already resolved. Validate refresh needs, preserve authoritative versus partial/failed scan distinctions, and never silently rebind a same-name collection. A consolidated lineup health view is a possible UX addition, not proof that current per-source retry is absent. |
| Saved Channel Builder configuration | The audit raises remembering strategy choices and defining edit-setup versus start-over behavior. Reconcile with the [setup reentry plan](setup-reentry-startup-plan.md) and current implementation; saving a builder recipe is distinct from saving the channels it produced. |
| Durable diagnostic export | Current [DiagnosticsView](../lib/app/diagnostics_view.dart) already builds and copies a redacted support report. Evaluate a reviewed save-to-file/report bundle only for value beyond that capability. The audit's description of display-only diagnostics is stale. Preserve opt-in recording, bounded allowlists, and private-data review. |
| Desktop instance and startup policy | Single-instance restore/focus remains a recorded decision. Assess user intent for multiple windows and shared-state writes before treating it as a bug. Launch destination/fullscreen preferences are optional separate choices, not a reason to disrupt existing saved-lineup startup. |
| Actor/studio combined programming | The audit labels combine mode missing, while current Channel Setup exposes library-grouping controls for actors/studios. Verify generated results and clarify what “combined” means before recommending new work. |

Credential compensation, authorization errors, buffering, native test coverage,
and physical acceptance belong in correctness/reliability work, not a marketing
feature list. Signing, runtime mirroring/notices, installer/update channels, and
first-release distribution are release decisions. HTTP-only server support,
audio-device selection/passthrough, gamepads, and display refresh-rate switching
need explicit security/product or native capability decisions; a peer offering
them does not approve them for Lineup. Offline downloads, recording, multiview,
non-Plex providers, and cross-device synchronization would materially expand the
product and currently have no evidence here that warrants prioritizing them.

## Recommendation for the next review

Validate all four selected additions, then rank the extra candidates without
requiring a particular feature count. My provisional order is F1 for protecting
user work, F3 for a small usability win, and F2 for richer programming. F4 should
be designed early alongside transcoding so track ownership and preferences are
coherent, even if implementation follows later. Favorites is the strongest
additional candidate for near-term consideration; subtitle comfort and alternate
media versions deserve the next comparison. Guide freshness should be judged
as reliability work before richer scheduling increases its consequences.

The reviewer should account for every meaningful candidate as recommend, merge,
already implemented, existing plan, investigate, defer, or reject. A bounded
survey cannot prove that no other useful feature exists. The useful completeness
claim is that the inspected backlog and peer capabilities were systematically
checked and that worthwhile omissions and remaining research gaps are explicit.

Use the [Opus research request](opus-feature-research-request.md) for the next
pass. Return decisions and unresolved questions before writing implementation
packages. Interest in the four additions does not settle new UI, data migration,
Plex preference writes, or broader product scope.
