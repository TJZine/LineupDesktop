# Guide Freshness and Collection Revalidation Investigation

**Status:** Deferred investigation. Start after the current UI refresh lands and
its Guide integration is stable. This is a bug report and investigation brief,
not evidence that Desktop has the upstream defect or a pre-approved port.

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

The following are hypotheses to reproduce, classify, or disprove on Desktop;
they are not current product claims.

### A. Cold-start source-order drift

1. Create a shuffled collection-derived channel with stable item identities and
   durations.
2. Exit Desktop, then reconnect/revalidate the same Plex server and libraries.
3. Cause or observe the same items arriving in a different order, without a
   membership or duration change.
4. Compare the current program, its elapsed position, and a future Guide window
   at the same wall-clock time before and after restart.

**Suspected impact:** the Guide appears to have shifted or becomes inconsistent
with a viewer's expected channel rhythm. The existing deterministic seed alone
does not protect against this if its input list is unstable.

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

These observations are from the current source, not an assertion that they are
sufficient or correct under the above scenarios.

- Collection-generated channels are currently persisted as a `LibrarySource`
  with the collection's **name** in `filters['collection']`; Desktop does not
  currently persist an upstream-style collection key for this source. The
  resolver matches that name against the `collections` tags carried by every
  scanned media item. See [channel sources](../lib/channels/channel.dart) and
  [content resolution](../lib/channels/content_resolver.dart).
- At selected-server restoration, the controller reloads selected libraries
  before declaring the app ready when persisted channels exist. It then builds
  schedules from the newly loaded in-memory media/playlist inventory. See
  [server restoration](../lib/app/lineup_controller.dart) and
  [schedule worker](../lib/channels/schedule_worker.dart).
- `buildSchedule` applies `seededShuffle` directly to the supplied content. It
  does not first canonicalize by a stable media identity. This makes an
  order-permutation reproduction plausible for `PlaybackMode.shuffle`; block
  ordering also needs its own analysis because it groups and iterates the
  supplied sequence. See [scheduler](../lib/channels/scheduler.dart).
- The current collection filter is exact name matching. A recreated collection
  with the same name may therefore continue to work after a complete fresh
  inventory scan, unlike upstream's key-based failure. Conversely, a rename,
  incomplete/stale tag inventory, different case, duplicate names, or a scan
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
| Does an identical item set in a different Plex order change a Desktop shuffled schedule? | A deterministic test and/or redacted cold-start reproduction that permutes only input order. | That the seeded PRNG alone provides continuity. |
| Which stable identity is valid for all Desktop schedule inputs? | Source inspection plus duplicate/multipart/mixed-source tests. | That a display title or collection name is unique. |
| Does a recreated same-name collection become unavailable on Desktop? | Controlled before/after inventory and resolver evidence. | Upstream's key-based 404 applies to Desktop. |
| Does Desktop observe an automated collection change while it remains open? | A bounded live-session experiment and call-path trace. | Startup revalidation implies periodic refresh. |
| Should real membership/duration changes retain today's schedule, shift predictably, or take effect at a boundary? | Product decision after measuring the viewer impact. | Response-order invariance solves actual content drift. |
| Can a future source repair be automatic? | Scope, ambiguity, persistence, cancellation, and UI-recovery proof. | Same name means same intended collection. |

## Required regression coverage if the investigation confirms work

At a minimum, add focused Desktop tests for:

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

Assign one investigation task after the UI refresh: reproduce the two scenarios
against the current Desktop source; trace the existing startup, inventory,
schedule-worker, Guide-cache, and Player coordination paths; then return with
evidence and a scoped proposal. The assignee should read this brief,
[Architecture](architecture.md), and the current source first. The upstream
commits are context, not a substitute for inspecting Desktop.
