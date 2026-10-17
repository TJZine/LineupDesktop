# Guide Freshness and Collection Revalidation Investigation

**Status (October 8, 2026):** Scenario A is resolved by canonical shuffle input
with deterministic regression evidence. Scenario B, live-session collection
refresh and live/physical observations remain deferred. The upstream references
below describe investigation context, not a compatibility target.

## Why this matters

Lineup is expected to be a long-lived TV guide, not a snapshot of whatever
order Plex happened to return during one earlier session. Two common operating
conditions can invalidate that assumption:

1. A cold start reconnects to Plex and rebuilds the in-memory library
   inventory. Plex may return the same collection membership in a different
   order. A seeded schedule that consumes that mutable order can select a
   different current program and shift the rest of the day despite no intended
   channel edit.
2. A user may automate Plex collection maintenance with Kometa or similar
   tooling. A run can add/remove members, rename a collection, or delete and
   recreate a collection with the same human-readable name but a new Plex
   identity. A saved channel may then resolve stale or empty content, producing
   unavailable Guide rows and failed tuning.

The first risk is a schedule-continuity/correctness problem even when every
item remains playable. The second is a source-identity and recovery problem;
real membership changes are expected, but an obsolete reference must not be
confused with a temporary server failure or silently rebound to the wrong
collection.

## Reported Desktop symptoms to investigate

Scenario A was confirmed by the October 7 review and resolved on October 8.
Scenario B remains an investigation brief, not a current product claim.

### A. Cold-start source-order drift — resolved October 8, 2026

1. Create a shuffled collection-derived channel with stable item identities and
   durations.
2. Exit Desktop, then reconnect/revalidate the same Plex server and libraries.
3. Cause or observe the same items arriving in a different order, without a
   membership or duration change.
4. Compare the current program, its elapsed position, and a future Guide window
   at the same wall-clock time before and after restart.

**Confirmed mechanism and correction:** at implementation starting SHA
`4f89dcad5d94907226eb8dbf52054387eb483254`, legacy shuffle consumed the supplied
list directly, and v2 shuffle retained that list as its cycle input. The new
permutation regressions failed on that source. `buildSchedule` now copies and
sorts shuffle input by `ChannelItem.id` before either legacy shuffle or v2 cycle
shuffle; duration breaks ties between differing snapshots of the same identity.
The generic seeded shuffle and sequential/block policies remain unchanged.

**Identity and occurrence evidence:** PMS parsing uses the media `ratingKey` as
`PlexMediaItem.id`, which `channelItemFor` carries unchanged. It identifies a
whole program within the selected server, including all multipart parts. Library
resolution already deduplicates inventory records by this ID. Playlists and
mixed sources intentionally retain repeated occurrences of a media ID; sorting
preserves every occurrence and its duration instead of manufacturing uniqueness
by dropping repeats. Equal-ID/equal-duration occurrences are interchangeable for
schedule timing. No new persisted identity or source shape is needed.

**Accepted update behavior:** the user accepted a one-time schedule shift for
existing shuffled channels on the first launch after this update, without a
migration flag. Channel seeds and anchors remain unchanged. Already persisted
legacy transition cycles keep their frozen order until their stored boundary;
canonical shuffle applies to the subsequent cycles. Real membership or duration
changes still change the schedule; this correction only removes response-order
sensitivity for an unchanged set of occurrences and durations.

**Actual portable evidence (October 8):**
`TZ=America/New_York flutter test --no-pub test/channels/scheduler_test.dart test/channels/content_resolver_test.dart test/channels/schedule_worker_test.dart`
passed **54 tests**, and `flutter analyze` reported no issues. The regressions
cover all permutations of small fixtures across legacy/v2 shuffle, negative and
far-future cycles, ordered IDs, offsets, current program/start/end/elapsed,
windows spanning cycles, repeated IDs including differing durations, unchanged
sequential/block ordering, membership and duration negative controls, unchanged
seeds/anchors, and a deliberately noncanonical frozen transition cycle. Fresh
reordered collection-library, playlist and mixed inventories also pass through
the production isolate worker and the actual Guide controller's current-program
and window projection using existing synthetic fixtures. Logs are in ignored
`build/remediation-2026-10-08/P12/`.

This is deterministic source-order continuity evidence. It does not establish
actual Plex response permutation frequency, live refresh, automatic membership
revalidation, native playback or physical Windows cold-start acceptance. H2 and
the separately scoped physical session remain pending.

### B. Automated collection mutation/recreation

1. Create a channel from a collection, preserving its collection name, selected
   library, source representation, item set, and schedule fingerprint in a
   redacted test record.
2. Run a controlled automation or equivalent Plex operation that changes
   membership, then separately deletes/recreates the collection with the same
   name where feasible.
3. Reopen Desktop or trigger the relevant revalidation path; also test the app
   left running across the automation window.
4. Observe source resolution, Guide row state, retry behavior, current-channel
   behavior, persistence, and whether a valid same-name source remains usable.

**Suspected impact:** an unavailable row, unavailable initial tune, stale Guide
schedule, or an unexpected schedule replacement. The exact symptom and root
cause remain unproven until the Desktop path is observed.

## Current Desktop facts (inspect again before changing code)

### October 7, 2026 collection inventory implementation

Collection inventory now comes from Plex's collection listing and children
endpoints, including smart collections and show/season members inherited by
episodes. Scanned library items replace their Collection tags with this
authoritative membership. Saved `LibrarySource` collection filters still identify
titles within their library; no collection `ratingKey` is persisted and no
migration is required. A collection deleted and recreated under the same title
resolves after the next complete scan. A children 404 triggers one bounded re-list
during that scan; confirmed deletion, per-title failure, and unavailable membership
remain distinct. Synthetic transport and controller tests cover same-title
recreation and saved schedule/content continuity. Live-session refresh,
real membership-change policy and live Plex acceptance remain deferred.
Source-order drift is resolved by the October 8 correction above.

Channel Setup Update review distinguishes confirmed source absence from incomplete
discovery. Only unmatched builder-owned channels whose every dependency has
complete scan evidence and resolves to zero playable items are offered under
**Source not found**. Keep is the default; removal is explicit and uses the
existing atomic channel-save path. Failed collection titles, unavailable
membership, failed/unavailable playlists, unscanned libraries, and incomplete
`MixedSource` dependencies retain their channels. A source found by a newly
settled retry cannot be removed using an older empty inventory. This foreground
review adds neither live-session refresh nor collection rebinding.

These observations are from the current source, not an assertion that they are
sufficient or correct under the above scenarios.

- Collection-generated channels are currently persisted as a `LibrarySource`
  with the collection's **name** in `filters['collection']`; Desktop does not
  currently persist an upstream-style collection key for this source. The
  resolver matches that name against the authoritative `collections` membership
  annotated onto scanned library items. See [channel sources](../lib/channels/channel.dart) and
  [content resolution](../lib/channels/content_resolver.dart).
- At selected-server restoration, the controller reloads selected libraries
  before declaring the app ready when persisted channels exist. It then builds
  schedules from the newly loaded in-memory media/playlist inventory. See
  [server restoration](../lib/app/lineup_controller.dart) and
  [schedule worker](../lib/channels/schedule_worker.dart).
- `buildSchedule` canonicalizes shuffle occurrences by stable media ID and
  duration before seeded ordering, including the v2 cycle input. Sequential and
  block modes still consume their supplied order under their existing policies.
  See [scheduler](../lib/channels/scheduler.dart).
- The current collection filter is exact name matching. A recreated collection
  with the same name may therefore continue to work after a complete fresh
  inventory scan, unlike upstream's key-based failure. Conversely, a rename,
  incomplete inventory, different case, duplicate names, or a scan
  failure could behave differently. Do not assume either automatic recovery or
  a 404 failure without a Desktop reproduction.
- Desktop's public model documents bounded startup/channel-setup scanning and
  stale-result rejection, but this brief has not established a periodic,
  live-session library revalidation policy. Determine whether a running Desktop
  process observes the daily automation before promising that behavior.

## Upstream Lineup evidence (behavioral reference only)

An available upstream Lineup checkout was inspected at `19e7f088` on
2026-09-08. Its recent fixes are strong investigation leads, but its webOS
architecture, persisted source shape, cache lifetimes, and UI runtime are not
compatibility targets for Desktop.

### Stable shuffle across a reordered Plex response

Upstream commit [`9eaf10b8`](https://github.com/TJZine/Lineup/commit/9eaf10b8ebf6779a4799600b7206645a4f0982d5)
identified mutable Plex response ordering as insufficient input to a seeded
shuffle. It copies and sorts resolved content by stable media rating key before
applying the existing seed. Its regression evidence compares reordered input at
the schedule level: ordered items, offsets, current program, and time window
remain equal. It intentionally leaves sequential and block semantics unchanged.

**Desktop investigation implication:** first prove identity uniqueness and
desired ordering semantics for `ChannelItem.id`, especially for multipart
media and mixed sources. If a stable-order rule is adopted, it belongs in the
shared Dart scheduling owner, applies consistently to every shuffle entry point,
and must not silently change sequential or block policy. A one-time schedule
shift for existing shuffled channels is possible and needs an explicit product
decision/evidence note.

### Guarded recovery of a recreated collection reference

Upstream commit [`5b1f7a14`](https://github.com/TJZine/Lineup/commit/5b1f7a14b5a7c0a6eb86c829a3cd5c9f1f1ee0de)
addressed a different source model: a saved collection **key** returned a
confirmed HTTP 404 after a collection was recreated. It made recovery
deliberately narrow:

- distinguish confirmed missing (HTTP 404) from an existing empty collection,
  authentication failure, timeout, malformed response, cancellation, and other
  transport failures;
- list collections completely within the saved library, not across libraries;
- require that the obsolete key is absent and exactly one case-sensitive,
  same-name replacement exists;
- verify that the replacement resolves to usable filtered content before any
  saved-reference mutation;
- preserve channel ID/number/order, seed, anchor, filters, and playback
  settings; persist the repair before publishing its schedule; and
- limit durable repair to an explicit foreground resolution/retry path. Its
  background schedule materialization stayed non-mutating.

Its companion commit
[`7e716692`](https://github.com/TJZine/Lineup/commit/7e716692fd94eae501b0dc5eb60514f2a90e7d1d)
then prevented Guide publication from using the pre-repair channel snapshot.
The published schedule must carry the repaired/current source owner, or future
refreshes can discard the recovery and reintroduce an unavailable row.

**Desktop investigation implication:** this is a useful safety bar, not a
feature to copy. Desktop has no persisted collection key today, so adding one
would be a schema and migration decision only if tests show name-based sources
cannot meet the desired contract. Any future identity repair must preserve
profile/server/library scope, refuse ambiguous names, be atomic with durable
state, invalidate stale Guide/player work through the controller's content
generation, and never convert network/auth/cancellation errors into an empty or
rebound channel.

### Revalidation and Guide resilience

Upstream commit [`5b8b39dc`](https://github.com/TJZine/Lineup/commit/5b8b39dcf53cefe47924d20e54246d236f8ac3f7)
kept a known-good cached schedule/content fallback when a forced revalidation
encountered a network error, while scheduling recovery. Earlier Guide runtime
work, notably
[`c18d6aef`](https://github.com/TJZine/Lineup/commit/c18d6aef3ee1a79128b6d1372657c353a81df17b),
also separates visible-row readiness, bounded warmup, cancellation, and stale
schedule publication.

**Desktop investigation implication:** a fresh scan must not replace a usable
Guide with an unavailable/empty schedule solely because an intermediate request
failed or became superseded. Conversely, a successful authoritative inventory
change must invalidate every derived schedule that depended on it. Reuse
Desktop's existing controller epoch, content generation, and channel revision
contracts rather than importing upstream cache machinery.

## Investigation questions and decision gates

| Question | Evidence required before design | Do not assume |
| --- | --- | --- |
| Does an identical item set in a different Plex order change a Desktop shuffled schedule? | Confirmed before correction; October 8 permutation regressions now prove invariance. Live frequency/physical restart remain pending. | That the seeded PRNG alone provides continuity. |
| Which stable identity is valid for all Desktop schedule inputs? | October 8 parser/resolver trace and multipart/playlist/mixed tests establish media ID, retaining intentional occurrences. | That a display title, collection name, or occurrence list is unique. |
| Does a recreated same-name collection become unavailable on Desktop? | Controlled before/after inventory and resolver evidence. | Upstream's key-based 404 applies to Desktop. |
| Does Desktop observe an automated collection change while it remains open? | A bounded live-session experiment and call-path trace. | Startup revalidation implies periodic refresh. |
| Should real membership/duration changes retain today's schedule, shift predictably, or take effect at a boundary? | Product decision after measuring the viewer impact. | Response-order invariance solves actual content drift. |
| Can a future source repair be automatic? | Scope, ambiguity, persistence, cancellation, and UI-recovery proof. | Same name means same intended collection. |

## Required regression coverage if the investigation confirms work

Items 1–2 and the distinction between response-order drift and real changes in
item 3 have deterministic regression coverage from the October 8 scenario-A
correction. A new live membership-change policy remains deferred. Items 4–7 retain their separate startup/revalidation/source-repair
scope; the correction does not claim new live-refresh behavior. Coverage to
preserve or extend for future work:

1. same IDs/durations with every meaningful input permutation preserve the
   shuffled schedule's ordered IDs, offsets, program-at-time, and Guide window;
2. sequential and block behavior retain their separately approved semantics;
3. a true membership or duration change has the explicitly selected policy and
   does not masquerade as source-order drift;
4. cold startup restores a persisted collection-derived channel using fresh
   inventory, without stale schedules published from a superseded operation;
5. collection rename, deletion, same-name recreation, duplicate same-name
   collections, empty collection, transient network failure, authentication
   failure, and cancelled scan remain distinguishable;
6. a failed revalidation retains a valid prior schedule only under an explicit
   bounded fallback policy, while a confirmed authoritative source change
   invalidates stale Guide/player state; and
7. profile/server/library changes, concurrent channel edits, persistence
   failure, and application disposal cannot commit a repair or schedule from an
   obsolete scope.

For a confirmed native/Desktop behavioral fix, supplement deterministic tests
with a physical Windows run: cold start, channel tuning, Guide/mini-Guide
navigation, a live revalidation scenario, and relaunch. Record only redacted
media identifiers and no Plex credentials, URLs, server addresses, or private
collection names.

## Non-goals until separately approved

- Copying upstream webOS modules, caches, persistence format, or UI behavior.
- A generic background sync service, polling loop, event bus, or migration
  framework without reproduced Desktop need and an approved ownership model.
- Fuzzy, cross-library, case-insensitive, or user-invisible automatic matching
  of renamed collections.
- Claiming collection automation support, same-day continuity, or periodic
  Guide freshness before the exact Desktop behavior is reproduced and verified.

## Suggested handoff

For future collection-refresh work, investigate scenario B against the current
Desktop source; trace startup, inventory, schedule-worker, Guide-cache and Player
coordination paths, then return with evidence and a scoped proposal. Preserve
scenario A's deterministic continuity regressions and accepted update behavior;
collect its remaining live/physical observations separately. The assignee should
read this brief,
[Architecture](architecture.md), and the current source first. The upstream
commits are context, not a substitute for inspecting Desktop.
