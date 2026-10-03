# Plex Transcoding and Direct Stream Implementation Plan

**Status:** Draft, revised after adversarial review on 2026-10-03. The
maintainer answered the first product decisions on 2026-10-03. Items marked
**[confirm]** still need maintainer confirmation. The Settings design is a
proposal awaiting design agreement. Nothing here is implemented, and P1 starts
only after P0 evidence is accepted.

**Planning baseline:** `codex/libmpv-reference-security-report` at
`510c91d2d8a30c12505e996a060241fb0862b649`.

## Goal

Let users play a channel at reduced bitrate when bandwidth cannot sustain the
original file, using Plex server transcoding or Direct Stream, without
weakening the authenticated-reference hardening.

Completion means that:

- users choose Home and Remote streaming quality, and Lineup requests a Plex
  playback decision instead of always using Direct Play;
- tuning starts the session at the live program position; part changes,
  seeking, channel and program changes, stop and authorization recovery behave
  as they do for Direct Play;
- every server session or decision Lineup creates is stopped, or is left to
  PMS reaping only after a crash or network loss;
- libmpv follows references only for Plex-generated, token-free session
  playlists on the validated server, never with a credential attached, and
  Direct Play originals stay contained;
- the Plex credential never appears in a URL given to libmpv, a log or
  diagnostics; and
- representative physical Windows playback proves the behavior at the exact
  commit.

## Authority and constraints

- [`AGENTS.md`](../AGENTS.md): Dart owns product logic and Plex networking; C++
  owns only native media behavior.
- [Architecture](architecture.md), credential/native-player note (~line 180).
- [Reference investigation](libmpv-authenticated-reference-investigation.md):
  sections "mitigation" and "per-load reference policy feasibility".
- [`.interface-design/system.md`](../.interface-design/system.md): new Settings
  UI needs design agreement. The Player OSD and track drawer are a protected
  baseline, so any change to their structure or **data** needs matched renders
  and separate approval.
- [Windows native acceptance](windows-native-validation.md).
- [Flutter Test Design](../.agents/skills/flutter-test-design/SKILL.md).

## Evidence already established

Headless, on pinned libmpv `3186d369` and one local PMS:

- a per-file `access-references=yes` applies to one load and is restored on
  completion, stop and replacement;
- a transcode session (MPEG-TS) and a Direct Stream session (fragmented MP4;
  video copy, audio transcode) played, sought forward 30 s within the session,
  and stopped;
- every playlist and segment URL was relative and on the same PMS origin;
- only the start/master request needed the token; variant playlists, segments
  and init resources worked without it **on that PMS and connection type**,
  which is not a documented Plex rule; and
- Direct Stream needed a correct request-local client profile (augmentation
  with `replace=true`).

Not established: remote or relay connections, renditions (audio/subtitle
`EXT-X-MEDIA`), multi-variant masters, start offsets, stream selection, burn-in,
keep-alive, multipart, server limits and failure responses, HDR→SDR output,
physical playback, and what the official Plex apps do in any of these cases.

## Current flow and owners

| Step | Owner | Today |
| --- | --- | --- |
| Part URLs | `PlexClient.playbackDescriptor` (`plex_client.dart` ~788) | Direct Play part URLs, validated by `_directPlayUri` |
| Media metadata | `PlexClient` item parsing (~1156) | First `Media` only; codecs, no Plex stream IDs |
| Playback request | `LineupController.playbackFor` / `_playbackRequest` (~1538, ~1626) | Fixed part URIs, PMS resource token, token-refresh recovery |
| Loads | `PlayerCoordinator` | Four "load `parts[i].uri`, then seek" sites: tune (`_loadPlayback`), `_advancePart`, part-changing seek, `_recoverAuthorization` |
| Tracks | Coordinator + Player drawer | libmpv `track-list` IDs; `selectTrack` uses mpv IDs |
| Native load | `NativePlayer.load` → `native_player.cpp` (~870–910) | With token: node-map `loadfile` with header and `curl-max-redirects=0`. **Without token: plain `loadfile`, no per-file options.** HTTPS enforced only with a token (`windows_native_player.dart` ~110) |
| Settings | `LineupSettings` | Strict decode; optional fields are always written; an invalid state quarantines the **whole** `state.json` (`app_store.dart` ~180–200) |
| Badges | `player_view.dart` (~1208) | From catalog metadata (source format) |

Lineup sends no Plex timeline, session or client-profile headers today.

## Product decisions

The maintainer chose to match the official Plex apps. Plex's support site could
not be read programmatically, so where this plan describes official-app
behavior it is labelled an assumption until confirmed.

1. **When to transcode: user-selected.** Automatic quality adjustment is out of
   scope. **[confirm]** Whether **Original** skips the decision API (today's
   Direct Play path), or asks for a decision like the official apps. Asking
   lets the server enforce remote bitrate limits and per-user restrictions.
   Recommended: ask for a decision only when the quality is below Original, and
   record server limits as a P0 question.
2. **Separate Home and Remote quality.** Lineup chooses by the connection's
   `local` flag; relay uses Remote. This is not identical to the server's own
   LAN classification, which uses the client IP and the server's "LAN networks"
   setting. P0 records whether the two disagree. Home defaults to Original; the
   Remote default comes from P0 evidence.
3. **Quality ladder: proposed, not confirmed official.** The ladder matches
   PlexKodiConnect's own
   [transcode quality list](https://github.com/croneter/PlexKodiConnect/blob/master/resources/settings.xml):
   - Original;
   - 4K at 50 and 35 Mbps;
   - 1080p at 40, 20, 12, 10 and 8 Mbps;
   - 720p at 4, 3 and 2 Mbps;
   - 480p at 1.5 Mbps.

   **[confirm]** The maintainer supplies the official app's Remote Quality list
   (e.g. a screenshot) to replace or confirm it. Tiers stay fixed regardless of
   any one server; the server caps by source and capability.
4. **Track changes during a session.** In a session, the server chooses the
   audio and subtitle streams, so the Player drawer must list **Plex streams**
   (parsed from metadata) instead of libmpv tracks. A change restarts the
   session at the current position.
   - Changing the drawer's data source changes a protected surface, so it needs
     its own approval with renders.
   - **[confirm]** P0 determines whether stream choice can be passed per
     request, or needs `PUT /library/parts/{id}`. The PUT writes the user's
     server-side stream preference, which other clients also see. Recommended:
     per-request only, and no server-side writes without approval.
   - Image subtitles are burned in.
   - Text subtitles: a session load hands libmpv a single variant (see Security
     design), so an HLS subtitle rendition is not reachable. Burn text
     subtitles in at first. A later P2 extension may add a validated,
     token-free native `sub-add`.
5. **Seeking during a session (assumption, not confirmed official behavior).**
   Seek within the generated session when the target is inside it; the
   feasibility run showed a 30 s forward in-session seek working. Restart the
   session at the target offset otherwise, debouncing repeated `seekBy` presses
   into one restart. Seeking needs the existing DVR controls; live tuning
   always starts at the program offset.
6. **Keep-alive. [confirm]** Plex timeline reports (`/:/timeline`) update watch
   progress, On Deck and watched state, so channel surfing would mark items
   watched. Recommended: no timeline reports. Use a transcode ping or segment
   activity if P0 shows one is needed, and treat watch-state writes as a
   separate product decision.
7. **Badges during a session. [confirm]** Source-format badges ("4K HDR10
   TRUEHD 7.1") are misleading for a 1080p SDR AAC transcode. Showing output
   format changes a protected surface, so it needs approval. Recommended:
   source badges unchanged, plus the playback method in Diagnostics, until a
   Player proposal is approved.
8. **Server can't transcode.** When the decision is transcoder at capacity,
   transcoding disabled, or 4K unsupported, show a clear Player error naming
   the cause, with Retry. Never silently fall back to Direct Play, because the
   user chose a lower quality for bandwidth. P0 records the actual responses.
9. **UI: proposal awaiting design agreement.**
   - **Settings → Playback** gains two `_Dropdown` rows above the existing
     controls: **Home streaming quality** ("Choose quality on your home
     network.", default Original) and **Remote streaming quality** ("Choose
     quality away from home or through Plex Relay.").
   - There is no group heading, because `_SettingsSection` has no subheadings
     and adding one would be a new pattern.
   - The first new row takes `first: true` from the auto-hide row.
   - Option text reads "1080p · 8 Mbps" and "Original quality". The category
     description becomes "Control playback quality and controls."
   - Accessibility: `_Dropdown` speaks the displayed text. A spoken form like
     "8 megabits per second" needs a semantics change to `_Dropdown`, so it is
     included in the proposal for agreement.
   - **Player:** no change in this plan beyond decisions 4 and 7, each of which
     needs its own approved proposal.

## Security design

- **Direct Play is unchanged.** Global `access-references=no` and
  `autoload-files=no`, per-file token header, `curl-max-redirects=0`.
- **Session start is Dart-only.** The controller starts the session through
  `PlexClient` under the existing `_withPmsAuthorization`, sending the token
  only as a header. It uses a client-generated session id, so a superseded or
  timed-out start can still be stopped. It pins `mediaIndex=0`, to match the
  Direct Play version selection.
- **Master validation.** Accept a master only if:
  - it has exactly one variant (`EXT-X-STREAM-INF`);
  - it has no `EXT-X-MEDIA` renditions and no other URI-bearing master tags;
  - the variant resolves to the validated server (`_isSameServerUri`), under
    the transcoder session path;
  - it is HTTPS, with no user info and no `X-Plex-Token` query.

  Refuse anything else as a session error. P0 records whether real Plex masters
  satisfy this.
- **Session load to libmpv:**
  - the variant URL with **no token**;
  - node-map `loadfile` with per-file `access-references=yes` **and**
    `curl-max-redirects=0`;
  - Dart rejects non-HTTPS session loads whether or not a token is present.

  libmpv then fetches the variant, its segments, `EXT-X-MAP` and `EXT-X-KEY` by
  itself. Because no credential is attached, any off-origin URI that later
  appears in the variant receives no token. That is the security boundary;
  Dart's checks only narrow it.
- **No credential fallback.** If any child request (variant, segment, init,
  key) requires the token on a connection type, transcoding is unavailable on
  that connection type and the user sees an error (decision 8). A
  token-carrying session load with references on is never used: libmpv's
  reference option is not an origin filter, and a token would reach any URI the
  variant contains. Re-planning for that case needs an origin-filtered
  transport.
- **Never** log or record the token, session ids or session URLs. Diagnostics
  stay allowlist-based.

## Implementation packages

### P0 — Plex session contract evidence (Windows, maintainer-authorized PMS)

No production code. See the P0 handoff for the procedure. It must establish:

- **Server context:** PMS version, Plex Pass, hardware transcoding,
  tone-mapping and concurrency limit.
- **Decisions:** the decision per ladder tier, and the minimal request-local
  client profile. That includes declaring multichannel audio as acceptable:
  Lineup decodes to PCM with no passthrough.
- **Server limits:** whether decision-only calls create server state, and the
  server-limit and failure responses.
- **Master structure:** single variant? renditions?
- **Positions:** offset start, and the `time-pos`/`duration` mapping rule.
- **Seeking:** in-session seek range, and restart latency with the same
  versus a new session id.
- **Multipart:** `partIndex`.
- **Streams:** per-request stream selection versus PUT; image burn-in from the
  `subtitleDecision`; text-subtitle delivery.
- **HDR→SDR:** output with tone mapping.
- **Keep-alive:** requirements without timeline writes, reap time, and `stop`
  idempotence.
- **Rapid-tuning load.**
- **Remote and relay:** token-free children, server LAN classification versus
  the `local` flag, sustainable bitrate, and a proposed Remote default.
- **Direct Play:** unchanged afterwards.

Gate: the maintainer accepts the evidence and confirms the **[confirm]** items.

### P1 — Dart Plex session client and stream metadata

- `PlexClient`:
  - decision;
  - session start with a client-generated session id, returning the validated
    variant URI;
  - stop (idempotent);
  - keep-alive, if P0 requires it;
  - client-profile construction;
  - all master validation;
  - parsing of Plex audio and subtitle streams from item metadata.
- Tests: strict HTTP fixtures that reject unexpected requests. Assert the
  method, path, parameters and headers, and that no token appears in any URL.
  Refuse masters with multiple variants, renditions, an off-origin or HTTP
  variant, user info or a token query. These are the transport owner's
  `network` and `security` cases.

### P2 — Native session load kind

- Extend `NativePlayer.load` with an explicit load kind: Direct Play or Plex
  session. A session load always uses node-map `loadfile` with
  `access-references=yes` and `curl-max-redirects=0` and no header. Dart
  enforces HTTPS for both kinds.
- Extend the gated `authenticated_reference` test (a gated native test on the
  pinned DLL):
  - a session-style HLS plays with the override and no token header;
  - the override is restored after completion, stop and replacement;
  - a redirecting session variant is refused;
  - a session variant with an off-origin segment sends no token to B;
  - Direct Play containment still passes.

  Prove the session case fails without the override.
- Update the `native_player.dart` contract comment and the architecture note,
  calibrated as "gated native test on pinned DLL".

### P3 — Playback integration

- **Request model.** A session request carries a controller-owned start
  function `(partIndex, offset) → (variant URI, session handle)`, because a
  session URI depends on the offset. The four load sites call it instead of
  load-then-seek: tune, `_advancePart`, part-changing seek, and authorization
  recovery.
- **Recovery.**
  - A native 401/403 on a session load is not a token problem; it gets one
    bounded session restart at the current position. A repeated 401/403 means
    child requests need the token on this connection type, so it shows the
    decision 8 error with no credential fallback.
  - A token failure on session *start* uses the existing
    `_withPmsAuthorization` recovery.
  - A reaped or killed session (a native failure mid-play) gets exactly one
    bounded restart, then a Player error.
- **Session lifecycle.** For replace, channel change, program end, stop and
  dispose:
  - order: native stop (END_FILE) → PMS stop (bounded) → next start, so a
    single-transcode server limit cannot reject the new start;
  - orphaned sessions after a crash or network loss rely on PMS reaping, with
    the time P0 measured;
  - stops include decision-only calls if P0 shows they create state.
- **Positions.** Map session positions to program positions per the P0 rule;
  `seekBy` uses the mapped duration.
- **Seeking.** In-session seek when the target is inside the session, otherwise
  a debounced restart (decision 5).
- **Track changes.** Plex-stream track changes restart the session (decision
  4, after its approval).
- **Diagnostics.** Report the playback method, with session ids and URLs
  redacted.
- **Tests.** Coordinator lifecycle tests use the **real `PlexClient` over a
  strict HTTP fake**, because stop requests are user-visible requests, and a
  native fake. Cover:
  - offset start;
  - part advance;
  - in-session seek versus restart;
  - debounce;
  - rapid channel changes with no leaked sessions and no stray starts;
  - start failure and recovery;
  - a mid-session failure restart;
  - a stale completion after replacement.

### P4 — Settings and UI (after design agreement)

- Persist `homeStreamingQuality` and `remoteStreamingQuality` as optional
  `LineupSettings` fields with stable string keys (e.g. `original`,
  `1080p-8000`).
- **[confirm]** An unknown key either quarantines the whole state, as strict
  decoding does today, or falls back to `original`. Recommended: fallback for
  these two fields only, so a future ladder change cannot wipe channels and
  selections.
- Add old-serialized-state and unknown-key cases to the store owner test
  (`test/persistence/app_store_test.dart`).
- **Downgrade risk:** an older build rejects the new keys and quarantines the
  whole `state.json` (channels, profiles, selections), not just settings.
  Acceptable before MVP; record it.
- Implement the agreed Settings rows (decision 9). Tests own visible selection,
  persistence and reload, through the existing settings UI owner.

### P5 — Windows physical acceptance and docs

- Add acceptance rows to `docs/windows-native-validation.md`, using
  representative tiers rather than every tier:
  - Original, one 1080p tier, one 720p tier, and one 4K tier if supported;
  - Direct Stream;
  - live-offset tune;
  - part advance;
  - seek (in-session and restart);
  - track-change restart;
  - burned-in image subtitles;
  - rapid channel changes with no leaked PMS sessions;
  - pause beyond keep-alive;
  - server-limit error;
  - remote/relay;
  - Direct Play containment unchanged.
- Update `docs/user-guide.md` and the architecture note.

## Regression matrix (summary)

| Behavior | Owner |
| --- | --- |
| Decision/start/stop requests, master validation, stream parsing | P1 strict HTTP tests |
| Session load kind, redirect refusal, token-free off-origin, restoration, Direct Play containment | P2 gated native test |
| Session lifecycle, offsets, restarts, cleanup, failures | P3 coordinator tests (real `PlexClient` over strict HTTP fake) |
| Quality persistence, unknown/old state, UI | P4 store and settings UI owners |
| Visible and audible playback, bandwidth, relay | P5 physical acceptance |

## Risks

- **Undocumented token-free children.** A future PMS could require the token on
  child requests, which would disable transcoding on that connection type (by
  design). Diagnostics name the cause.
- **Session churn on the server.** Mitigation: client-generated ids, ordered
  stop-before-start, P0 load measurements.
- **Restart latency** on track changes and out-of-session seeks. Mitigation:
  in-session seeks, debounce, and a loading state.
- **Subtitle fidelity.** Text subtitles are burned in at first.
- **Protected Player surfaces.** Track data source and badges need separate
  approvals. Without them, track changes are unavailable during a session.
- **Downgrade** quarantines the whole state file (P4).
