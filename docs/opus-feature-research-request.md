# Opus 5.5 feature validation and research request

Please independently validate the proposed Lineup Desktop additions, research
worthwhile omissions, and recommend what we should plan before implementation.
The maintainer wants to pursue these four features in addition to the separately
planned Plex transcoding capability:

1. Lineup backup/export and reviewed restore.
2. Mixed-source Channel Studio authoring.
3. Last-channel recall.
4. Preferred audio/subtitle language and accessibility tracks.

Start with [the feature opportunity report](feature-opportunity-report.md).
Challenge its claims and rankings; it is a research input, not a final design.
Research and planning recommendations are authorized. Do not implement product
changes or modify the current dependency upgrade. This request is prepared for
the maintainer to give to Opus 5.5; it does not indicate an agent was dispatched.

## Repository and current work

The local repository is `/Users/tristan/Software/LineupDesktop`. The report was
prepared on `codex/desktop-ui-second-pass`, HEAD
`eede9bb395054a54c64ff4263b861786bb907a08`. At that point, uncommitted work upgraded
Flutter to 3.47.7, upload-artifact to 7.0.2, and jni_flutter to 1.0.4+1, with
coordinated engine/marker/hash/documentation changes. Existing CI dependency
download retries predate the bump and must be preserved. Resolve the actual
branch, HEAD, and dirty work before analysis; do not infer a target from these
historical identifiers. If working elsewhere, use your accessible checkout and
record any difference from this source instead of assuming this local path exists.

Read `CLAUDE.md`/`AGENTS.md`, `.agents/project.md`, `README.md`, the relevant
architecture and interface-system sections, `docs/user-guide.md`,
`docs/product-parity.md`, and `docs/README.md`. Follow matching shared design,
review, and verification responsibilities when available. Current source and
accepted product contracts take precedence over stale audit descriptions or
historical orchestration instructions.

Keep Flutter/Dart as product/interaction owner and native code as platform/media
owner. Preserve deterministic scheduling, credential separation, profile/server
isolation, atomic persistence/rollback, stale-result rejection, and native track
confirmation. Preserve approved Player/Now Playing layouts unless proposing a
specific departure for later design agreement. Windows native acceptance and
macOS portable evidence remain different claims.

## Validate the four features

For each feature, establish the real current gap with file/symbol evidence,
identify the user scenario and benefit, compare credible alternatives, recommend
a coherent product envelope, estimate relative effort/risk, and identify the
decisions still needed. Do not reduce an agreed feature merely to shorten a diff.

Investigate these questions explicitly:

- **Backup/restore:** export scope, versioning, same-server identity versus
  cross-server remapping, merge/replace preview and conflicts, schedule anchors
  and seeds, privacy, credential/client-ID exclusions, old/future formats,
  invalid-input bounds, active playback, failed saves, and automatic snapshots.
- **Mixed sources:** existing `MixedSource` and interleave semantics, old nested
  data, repeated occurrences, unequal/empty/unavailable sources, source ordering
  versus playback rhythm, picker/editor accessibility, and one shared
  Air Check/Guide/Player scheduling policy. Separate weights and timed blocks
  from the existing concatenate/round-robin capability.
- **Last channel:** success/currentness semantics, late failures and cancellation,
  selected versus actively playing identities, live joining, context/deletion
  invalidation, persistent versus session history, and accessible interaction
  without shortcut collisions or an unapproved Player redesign.
- **Track defaults:** account/per-item/local/manual precedence, preferred and
  unknown languages, forced/SDH/audio-description/commentary metadata,
  scope/persistence and overrides, multipart transitions, observed selection
  confirmation, and Direct Play versus server-delivered tracks. Coordinate with
  `docs/plex-transcoding-implementation-plan.md`; do not invent a second track
  owner or silently write preferences to Plex. Distinguish Plex subtitle-search
  preferences from embedded-track autoselection.

## Look for worthwhile omissions

Review the complete user journey: setup/accounts, source discovery and freshness,
channel creation/programming, Guide/navigation, playback, accessibility,
recovery/portability, desktop lifecycle, and release/support. Cross-reference
current backlog and existing plans so completed work is not proposed again.

The initial peer survey covered official Tunarr, Channels, Plex HTPC, and
ErsatzTV documentation, with direct citations in the report. Recheck relevant
sources and extend the comparison where it can change the recommendation—such
as dizqueTV, Jellyfin/Emby clients, or another close desktop/virtual-TV product.
Use primary documentation/source and note versions/platform or Legacy/Next
differences. Do not treat server-side streaming/recording architecture as a
requirement for this desktop Plex client. User discussions can suggest demand
but do not prove capability, correctness, or general demand.

Specifically adjudicate favorites/channel groups, subtitle style/timing controls,
alternate media versions, timed programming blocks, bumpers/filler, Guide/source
freshness, remembered builder configuration, durable diagnostic export, and
instance/startup policy. Add further justified ideas without a fixed quota.
Check whether supposed missing capabilities are already present: Diagnostics
currently has **Copy redacted report**, and Channel Setup exposes actor/studio
library-grouping controls. Verify the end behavior before carrying old missing
rows forward.

Account separately for existing functionality, pending implementation plans,
correctness work, physical acceptance, and release-policy decisions. Avoid
casually reviving HTTP-only connections, passthrough/device controls, gamepads,
refresh-rate switching, installers/updaters, recording, offline downloads,
multiview, provider expansion, or synchronization without a concrete use case
and the necessary capability/security/product decision.

## Deliverables

Return a concise executive recommendation plus enough evidence for planning:

1. A verdict on each of the four features: proceed to planning, refine, combine,
   investigate first, or defer, with rationale and scope.
2. A source-backed peer matrix distinguishing observed facts from inference.
3. A reconciled candidate register: recommend, merge, already implemented,
   existing plan, investigate, defer, or reject. Include meaningful rejected
   options and stale backlog corrections so omissions are visible. Do not claim
   that an unbounded space of possible features has been exhaustively disproved.
4. A ranked short list based on user value, confidence, effort, maintenance cost,
   architectural fit, dependencies, and verification feasibility. Explain why
   the next small feature and next larger feature earn their cost.
5. Product/design questions needed from the maintainer before decision-complete
   implementation plans. Propose defaults with tradeoffs, but do not label
   unresolved UI, migration, or preference precedence as approved.
6. A suggested planning sequence and dependency map, especially for track
   preferences, media versions, and transcoding. These are independently
   shippable features where possible, not a mandatory serial campaign.
7. The meaningful acceptance obligations for each recommended feature, using
   existing tests and facilities where suitable. State precisely what portable
   evidence can prove and what needs live Plex or physical Windows validation.

Save the findings as `docs/feature-validation-findings.md` and link to this
report/request. Limit writes to that research document and a necessary docs-index
entry. Preserve all other work; do not commit, push, publish, change credentials,
start live Plex sessions, or dispatch other chats from this handoff alone. If
blocked by missing evidence, complete independent research and state the exact
remaining question. Implementation starts only after the maintainer accepts the
resulting scope and consequential decisions.
