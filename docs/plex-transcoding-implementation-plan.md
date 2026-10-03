# Plex Transcoding and Direct Stream Implementation Plan

**Status:** Product decisions settled on 2026-10-03, after adversarial review
and P0 evidence. Still open:
- the Settings design (a proposal awaiting design agreement);
- the Remote default, to check against a current official app before P4;
- P0b evidence.

Nothing here is implemented. P1 starts after P0b.

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

1. **Direct Play by default; transcode only by user choice: decided
   2026-10-03.** Automatic quality adjustment is out of scope.
   - **Original** (the default) always uses today's Direct Play path, with no
     decision request.
   - Below Original, Lineup asks for a decision, and still uses Direct Play
     whenever the decision allows it (the original fits the chosen ceiling).
   - Transcoding or Direct Stream happens only when the user has chosen a
     lower quality and the decision requires it.
   - Server-enforced remote limits are therefore not consulted at Original;
     the maintainer accepted this trade-off.
2. **Separate Home and Remote quality.** Lineup chooses by the connection's
   `local` flag; relay uses Remote. This is not identical to the server's own
   LAN classification, which uses the client IP and the server's "LAN networks"
   setting. P0 did not measure that classification (see P0 results, question
   12). Home defaults to Original.
   - **Remote default: decided 2026-10-03**, to match the official apps:
     **720p · 2 Mbps**. Community reports describe it as the long-standing
     official default
     ([forum thread](https://forums.plex.tv/t/bug-plex-app-defaults-to-2mbps-720p/449537)).
     The maintainer confirms it against a current official app's settings
     before P4. P0's 720p · 4 Mbps proposal is superseded.
3. **Quality ladder: proposed, not confirmed official.** The ladder matches
   PlexKodiConnect's own
   [transcode quality list](https://github.com/croneter/PlexKodiConnect/blob/aab8dbf3945e194b6bb4122f188f4ac2cfe8aaec/resources/settings.xml#L1058-L1077):
   - Original;
   - 4K at 50 and 35 Mbps;
   - 1080p at 40, 20, 12, 10 and 8 Mbps;
   - 720p at 4, 3 and 2 Mbps;
   - 480p at 1.5 Mbps.

   **Decided 2026-10-03:** keep this proposed ladder. Tiers stay fixed
   regardless of any one server; the server caps by source and capability.

   **Output codec and HDR: decided 2026-10-03.**
   - Follow the server's own setting. Lineup's transcode target always declares
     both H.264 and HEVC.
   - When the server has "Enable HEVC video Encoding" on (Plex Pass and
     hardware encoding;
     [Plex forum announcement](https://forums.plex.tv/t/hevc-encoding-forum-preview/888127)),
     it sends HEVC and preserves HDR.
   - Otherwise it sends H.264 and tone-maps to SDR itself.
   - P0 observed both outcomes (question 9).
   - libmpv decodes either and tone-maps HDR locally for SDR displays. HDR
     presentation stays a physical acceptance item.
4. **Track changes during a session.** In a session, the server chooses the
   audio and subtitle streams, so the Player drawer must list **Plex streams**
   (parsed from metadata) instead of libmpv tracks. A change restarts the
   session at the current position.
   - Changing the drawer's data source changes a protected surface, so it needs
     its own approval with renders.
   - **Stream selection: decided 2026-10-03.**
     - P0 showed per-request selection parameters are ignored.
     - For **transcode sessions only**, Lineup sets the user's choice with
       `PUT /library/parts/{id}` before restarting the session. That is the
       official apps' mechanism; it persists as the user's server-side default
       for that item, as in the official apps.
     - Direct Play keeps local libmpv track switching with no server write.
     - P0b verifies the PUT's effect, burn-in and text-subtitle delivery.
   - Image subtitles are burned in.
   - Text subtitles: a session load hands libmpv a single variant (see Security
     design), so an HLS subtitle rendition is not reachable. Burn text
     subtitles in at first. A later P2 extension may add a validated,
     token-free native `sub-add`.
5. **Seeking during a session: decided 2026-10-03.**
   - Always restart the session at the target offset, with a new session id.
     Debounce repeated `seekBy` presses into one restart.
   - Never seek in-session: P0 showed in-session seeks stall and shift the
     server's window (question 6).
   - Program position = start offset + libmpv `time-pos`. Program duration
     comes from metadata (libmpv reports the full original duration).
   - Seeking needs the existing DVR controls. Live tuning always starts at the
     program offset.
6. **Keep-alive: decided by P0 evidence.** Send a transcode ping every 30 s for
   each live session, including while paused. P0 measured reaping at about
   3–3.5 minutes without one. No timeline reports, so channel surfing never
   writes watch state.
7. **Badges during a session: decided 2026-10-03.** Keep source-format badges
   unchanged, and report the playback method in Diagnostics. Showing output
   format ("1080p SDR AAC" for a transcode of a "4K HDR10 TRUEHD 7.1" source)
   changes a protected surface, so it is deferred to a separately approved
   Player proposal.
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
- **Direct Play decisions.** When the decision returns Direct Play
  (`directPlayDecisionCode=1000`), Lineup never calls the HLS start (P0: HTTP
  400). It uses the existing Direct Play load instead.
- **Master validation.** Accept a master only if:
  - it has exactly one variant (`EXT-X-STREAM-INF`);
  - it has no `EXT-X-MEDIA` renditions and no other URI-bearing master tags;
  - the variant resolves to the validated server (`_isSameServerUri`), under
    the P0-recorded path `/video/:/transcode/universal/session/<session>/base/index.m3u8`;
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

Gate: the maintainer accepts the evidence and settles the product decisions.
P0 ran on 2026-10-03 (see [P0 results](#2026-10-03-p0-results)); decisions 2–6
were updated from it.

### P0b — Stream selection and true-remote evidence (Windows, maintainer-authorized)

No production code. It closes the gaps P0 left open:

- **Stream selection.** With the maintainer's authorization for server writes
  on one test item, run `PUT /library/parts/{id}` for audio and subtitle
  selection, then start a session. Confirm:
  - the selected audio track plays;
  - image subtitles are burned in, from the decision response;
  - how a selected text subtitle is delivered: a master rendition, a sidecar,
    or burned in. If a rendition appears, record whether it is still
    single-variant, and whether the rendition is token-free.

  Measure the restart latency. Restore the item's original selections
  afterwards.
- **True remote.** Use the maintainer's seedbox server (a separate, genuinely
  remote PMS on the same account):
  - token-free variant, segment and init requests;
  - two transcode tiers;
  - the Direct Play original request that returned HTTP 503 on the LAN
    "non-local" path in P0 (question 13). Record the seedbox's response shape.
    The cause of the local server's 503 comes from that server's own log, read
    through a sanitizing filter; the seedbox's log is not read.
- **HEVC setting.** Read the "Enable HEVC video Encoding" preference value on
  each server (read-only), and confirm the decision output follows it.

The maintainer is also investigating the remote Direct Play 503 independently.
If it reproduces against a genuinely remote server, it is a defect in today's
Direct Play path, to be fixed separately from transcoding.

### P1 — Dart Plex session client and stream metadata

- `PlexClient`:
  - decision;
  - session start with a client-generated session id, returning the validated
    variant URI;
  - stop (idempotent);
  - a transcode ping (keep-alive, decision 6);
  - stream selection by `PUT /library/parts/{id}`, for sessions only
    (decision 4);
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
  - order: native stop (END_FILE) → PMS stop → next start. Bound the PMS stop
    to about 2 s before a **session** start, so a single-transcode server limit
    cannot reject the new start. A Direct Play load never waits for it, and an
    unreachable PMS delays a session tune by at most that bound;
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
- **Decided 2026-10-03:** an unknown quality key falls back to `original`, for
  these two fields only, so a future ladder change cannot wipe channels and
  selections. Every other field keeps strict decoding.
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

## 2026-10-03 P0 results

**Evidence baseline:** `4e0b365b57c4b1caf5798c4d107b48d6450e27ef`,
on `codex/libmpv-reference-security-report`, after fetching the matching remote.
This section records a temporary headless Windows client, not implemented
Lineup transcoding or physical Windows acceptance. The plan decisions and
Security design above have not been changed.

Pinned runtime: libmpv `3186d369`, from the preparation contract in
`tool/windows/prepare-mpv.ps1`; DLL SHA-256
`4BA364226FD2EA5DD2C6F2333F0118462DA549FEED92360FB766A3924E313A51`.
The DLL was checked before creating each client and again before loads in the
final client. Null audio/video replaced presentation; all production global
initialization options were checked for acceptance, including
`tls-verify=yes`, `access-references=no` and `autoload-files=no`.

The client read only Lineup's `plex.account-token` entry in memory. The
installed `flutter_secure_storage` backend stores that entry in its existing
DPAPI-encrypted storage file, rather than the legacy Credential Manager
entry. The maintainer explicitly authorized continuation using that same
Lineup entry. Resources discovery used the existing `plex-client-identity`;
PMS access used only the discovered resource token. Each HTTPS connection's
unauthenticated `/identity` matched the discovered machine identifier before
any authenticated request. TLS verification and redirect refusal remained on.

Four discovery calls were made in total: setup/terminal exits required
replacement discovery after the maintainer's written continuation
authorization. This departs from the initial single-call procedure; each used
the existing Lineup identity and no account credential was used elsewhere.
An array-valued native header experiment was rejected by libmpv; that run
and an interrupted pause run are excluded from playback conclusions. Final
controls used the production single token header and a synthetic client
identifier query; token-free session loads used the synthetic identifier
header only. Early token-free child/native probes had no identifier header;
the non-local, rapid-tuning and final ladder runs supplied it. All PMS request
identity values that were supplied were `lineup-p0-probe`. PMS may list a
`lineup-p0-probe` device, which the maintainer can remove afterwards.

Session IDs were client-generated and retained only in memory. No credential,
real session ID/URL, media title/ID/path, total item duration, raw server
response, media bytes or native diagnostics were retained. No stream-selection
PUT, timeline, watched-state, preference or library writes were made.

Unless stated otherwise, timing cells are **median / maximum in seconds over
three valid runs**. Start timing begins at the authenticated master request,
includes validation and separate token-free variant/segment/init probes, and
ends after at least 0.4 seconds of native position advance. It excludes the
decision request and is not an application tune-time benchmark. Start/advance
waits were bounded to 30 seconds, stop requests to 10 seconds, and reap
observation to 15 minutes. Timed-out seeks are failures, not successful
latencies. Pause and reap scenarios ran once in the valid client.

### 1. Server context and available items

| Field | Observed result |
| --- | --- |
| PMS version | `1.43.4.10903-e5521bd8c` |
| Plex Pass | Not exposed by the allowed discovery/identity responses; not independently verified. Hardware encoding operated. |
| Hardware acceleration | On: `HardwareAcceleratedCodecs=1`; transcodes reported NVDEC/NVENC. |
| Tone mapping | On: `TranscoderToneMapping=1`; application to a particular session is discussed in question 9. |
| Concurrency limit | Not measured: bounded single-preference lookups for candidate concurrency keys returned 404. No preference writes or overload experiment. |
| LAN networks configured | No: `LanNetworksBandwidth` was empty. |
| Other household streams | None observed in sampled status/transcoder listings; this is not continuous household monitoring. |
| Item A | MKV, H.264 8-bit SDR, 1080p; two audio tracks (E-AC-3 6 channels, AAC 2 channels), 15 PGS and one SRT subtitle tracks, one part. Exact requested type available. |
| Item B | MKV, HEVC 10-bit, 4K, PQ with Dolby Vision present; metadata advertises 8-channel audio, three audio tracks, PGS and SRT subtitles, one part. Dolby Vision/PQ source; HDR10 fallback and presentation not checked. |
| Item C | No multipart item found in the movie/episode catalog scan (first Media only). |

### 2. Decisions per quality tier and response shapes

| Tier | Decision | Decision resolution | Decoded resolution | Decision video kbps | Start→advance median / max | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Original | Direct Play | 1788 × 1080 | not captured | 11422 | not measured | DP original plays |
| 4K 50 | Transcode | 3840 × 1600 | 3840 × 1600 | 20000 | 6.100 / 6.402 | 3/3 advance |
| 4K 35 | Transcode | 3840 × 1600 | 3840 × 1600 | 16485 | 6.162 / 6.165 | 3/3 advance |
| 1080p 40 | Direct Play | 1788 × 1080 | not captured | 11422 | not measured | DP original plays; HLS start 400 |
| 1080p 20 | Transcode | 1788 × 1080 | 1788 × 1080 | 18218 | 6.494 / 6.605 | 3/3 advance |
| 1080p 12 | Transcode | 1788 × 1080 | 1788 × 1080 | 10845 | 6.164 / 6.196 | 3/3 advance |
| 1080p 10 | Transcode | 1788 × 1080 | 1788 × 1080 | 9070 | 6.045 / 6.150 | 3/3 advance |
| 1080p 8 | Transcode | 1788 × 1080 | 1788 × 1080 | 7158 | 6.057 / 6.063 | 3/3 advance |
| 720p 4 | Transcode | 1192 × 720 | 1192 × 720 | 3419 | 6.225 / 6.341 | 3/3 advance |
| 720p 3 | Transcode | 718 × 434 | 718 × 434 | 1721 | 6.623 / 7.072 | 3/3 advance |
| 720p 2 | Transcode | 718 × 434 | 718 × 434 | 1236 | 6.659 / 6.694 | 3/3 advance |
| 480p 1.5 | Transcode | 720 × 434 | 720 × 434 | 994 | 6.602 / 6.617 | 3/3 advance |

The live `/transcode/sessions` response confirmed video/audio conversion
and codecs, but omitted output bitrate and, for video transcodes, output width
and height. Direct Stream included dimensions. Initial libmpv `video-bitrate`
samples were unavailable. A single additional A / 1080p 8 Mbps control,
sampled at least 20 seconds after advance, returned 6,724,077 bits/s (about
6.724 Mbps), versus its decision target of 7.158 Mbps. Other delayed tier
samples were not measured. Consequently the bitrate column is the **decision
target**, not measured live bitrate; the requested per-tier live cross-check
remains incomplete. Final decoded dimensions were collected independently with
libmpv `video-params/w` and `video-params/h`.

PMS selected output below several ceilings (including both 4K tiers and
720p at 3/2 Mbps); the precise source/server/profile cap reason was not
measured. An earlier 720p / 2 Mbps batch returned 1,721 kbps at 718 × 434;
the final batch above returned 1,236 kbps at the same dimensions. The reason
for this decision-target variation was not established.
Every decision-only listing check, including the non-local calls,
found no matching transcode entry. Stops for unused decision IDs returned 404.
No supported tier was refused for capacity in these runs.

- **Direct Play decision:** HTTP 200 XML `MediaContainer`; `generalDecisionCode=1000`, `directPlayDecisionCode=1000`, text `Direct play OK.`; `Part decision=directplay` in the final probe.
- **Conversion allowed:** HTTP 200 XML `MediaContainer`; `generalDecisionCode=1001`, `transcodeDecisionCode=1001`, text `Direct play not available; Conversion OK.`
- **Direct Play rejection within a successful conversion decision:** `directPlayDecisionCode=3001` for bandwidth, or `3000` for profile/resolution/explicit directPlay=0. These are not overall conversion failures.
- **HLS start after Direct Play decision:** HTTP 400; HTML; root `html`; title `Bad Request`; h1 `400 Bad Request`. No transcode entry. Branch to the original instead.
- **Capacity / transcoding unavailable:** Not measured: not encountered; no fabricated response fixture or configuration write.
- **Non-local Direct Play original:** Independent authenticated one-byte range control returned HTTP 503, no redirect; libmpv END_FILE reason 4/error -13. Body not retained; this is an original-file failure, not a session-child failure.

### 3. Request-local client profile

| Profile experiment | Result |
| --- | --- |
| Direct Play declaration + HLS target | Smallest tested directive set that permits Direct Play when A fits, video-copy/audio-conversion when Direct Play is disabled, and video conversion below the source ceiling. |
| Remove Direct Play declaration | Original is converted; decision explains that no direct-play profile exists for HTTP/MKV/H.264. |
| Remove audio-channel limitation only | The three A decision cases remain valid; this does not prove all multichannel source cases. |
| Explicit multichannel declaration | `audioChannelCount=8`; `add-limitation(scope=videoAudioCodec&scopeName=*&type=upperBound&name=audio.channels&value=8&replace=true)`. Accept decoded PCM without declaring passthrough. |
| Direct Stream playback | Video copy, E-AC-3→AAC audio conversion; HLS fragmented MP4; 2.450 / 2.563 seconds start→advance, 3/3 success. |

`X-Plex-Client-Profile-Extra` is request-local, with `+` joining directives:

```text
add-direct-play-profile(type=videoProfile&container=mkv,mp4,mpegts,avi,mov&videoCodec=h264,hevc,mpeg4,mpeg2video,vc1&audioCodec=aac,ac3,eac3,dca,truehd,flac,mp3,pcm&protocol=http)
+add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=h264,hevc&audioCodec=aac&replace=true)
+add-limitation(scope=videoAudioCodec&scopeName=*&type=upperBound&name=audio.channels&value=8&replace=true)
```

The broad codec/container lists are declarations, not an exhaustive playback
matrix. The smallest tested working reduction retained two directive types;
removing the HLS target was not tested, and absolute minimal lists across all
codecs were not measured. The SDR control replaces
the target's `videoCodec=h264,hevc` with `videoCodec=h264`.

Common parameters: `path` (private metadata reference, never retained),
`mediaIndex=0`, explicit `partIndex`, fresh `session`, `protocol=hls`, `offset`,
`fastSeek=1`, `directPlay=1`, `directStream=1`, `directStreamAudio=1`,
`maxVideoBitrate` and `videoBitrate` in kbps, `videoResolution=WIDTHxHEIGHT`,
`videoQuality=100`, `audioChannelCount=8`, `subtitles=none`. The controlled
audio-conversion case uses `directPlay=0`, `directStreamAudio=0`. No profile
file or server setting was written. The
[PMS API documentation](https://developer.plex.tv/pms/) describes request-local
profile augmentations and `replace=true`; observations here remain specific
to this PMS.

### 4. Master and child structure

| Case | Variants / renditions / other URI-bearing master tags | URIs and token-free children |
| --- | --- | --- |
| Started local transcodes | 1 / 0 / 0 | Relative, same origin; variant, fragmented-MP4 init and media segment succeed token-free. |
| Direct Stream | 1 / 0 / 0 | Same structure; video copy/audio conversion; variant/init/segment succeed token-free. |
| Non-local 8 and 4 Mbps | 1 / 0 / 0, all six runs | Relative, same origin; variant/init/segment succeed token-free. |
| Keys | Absent | Encrypted HLS not tested. |
| Selected subtitle masters | Not tested | Requested subtitle selection did not take effect; no conclusion about rendition masters. |

The normalized variant path is exactly:

```text
/video/:/transcode/universal/session/<session>/base/index.m3u8
```

No inspected master/variant referred to another origin. These inspected
masters satisfy the existing rule; this does not validate that rule for
selected subtitle/audio renditions, encrypted HLS, other PMS versions or relay.
Every native session load used node-map `loadfile`, a token-free variant,
per-file `access-references=yes` and `curl-max-redirects=0`. No session was
loaded with a token header and references enabled.

### 5. Offset and position

| Measurement | Result |
| --- | --- |
| Requested offset | 600 seconds; PMS `minOffsetAvailable` began near 600.017; playlist `EXT-X-START:TIME-OFFSET=600.000000`. |
| Initial libmpv time-pos | 0.459 / 0.459 / 0.459 seconds (three runs). |
| 20 seconds later | 20.437 / 20.521 / 20.479 seconds. |
| libmpv duration at both observations | Matches full original duration, unchanged (delta 0); does not match original minus 600. Actual private item durations omitted by the task privacy rule. |
| Start→advance | 6.496 / 6.647 seconds. |
| Initial mapping | Program position ≈ requested offset + time-pos; program duration is the original duration, not offset + duration. Post-seek mapping is unresolved (question 6). |

### 6. Seeking and offset restart

| Operation on an offset-600 session | Advancing | Median / max seconds | Boundary |
| --- | --- | --- | --- |
| 30 s | 0/3 | 30.044 / 30.046 | 30 s advance deadline exceeded |
| 0 s | 3/3 | 0.405 / 0.405 | advancing after seek |
| 630 s | 0/3 | 30.011 / 30.025 | 30 s advance deadline exceeded |
| 300 s | 3/3 | 20.631 / 20.796 | advancing after seek |
| Restart 600→900, new_id | 3/3 | 6.571 / 6.591 | old ID explicitly stopped; absent after new start |
| Restart 600→900, same_id | 3/3 | 6.618 / 6.700 | one entry using same ID; internal generation replacement not proven |

The repeated seek sequence was 30→0→630→300 in native absolute time.
Earlier single-run exploration reached 630 and 900 but failed at 300 and
1200; it is not included in the repeated timing table. Position jumps alone
did not establish successful seeks: failure cases had `time-pos` at the
requested value but no advance. The repeated sequence changed PMS's available
window, including a minimum near 30 seconds after seeking to 30, while native
`demuxer-start-time` remained near 610.142. It therefore does not establish a
stable source/session coordinate rule after seeking or a safe reachable range.
Do not derive an in-session seek guarantee from the initial mapping. A new-ID
restart remains the preferred measured path; decide the P3 policy before use.
An additional untimed window control for each restart mode moved PMS's minimum
from about 600.017 to 900.025 seconds, with native time-pos near 0.417 after
the restart. The same-ID entry reflected the new window, but its internal
transcoder generation cannot be distinguished from these listings.

### 7. Multipart

| Question | Result |
| --- | --- |
| Multipart item | No multipart item found in the movie/episode catalog scan (first Media only). |
| partIndex, part start/end | Not tested; explicit partIndex=0 used for A/B. No multipart substitute was simulated. |

### 8. Streams and subtitles

| Probe | Observed result | Attempt start median / max seconds | Limit |
| --- | --- | --- | --- |
| Audio alternate | Requested selection not confirmed in 3/3 | 6.480 / 6.497 | needs server write / selection mechanism unresolved |
| PGS with subtitles=burn | Requested selection not confirmed in 3/3 | 6.576 / 6.633 | needs server write / selection mechanism unresolved |
| SRT with subtitles=auto | Requested selection not confirmed in 3/3 | 6.479 / 6.500 | needs server write / selection mechanism unresolved |
| SRT with subtitles=burn | Requested selection not confirmed in 3/3 | 6.481 / 6.526 | needs server write / selection mechanism unresolved |
| Original decision, audioStreamID / audioStreamIndex | Requested AAC stereo; selected E-AC-3 6 channels retained | not a stream-change latency | Both parameters ignored in bounded controls. |
| Image burn-in confirmation | Not measured | not measured | No subtitleDecision or equivalent; zero native subtitle tracks does not prove burn-in. |
| Text-subtitle delivery / token-free rendition / sub-add | Not tested | not measured | No selected text stream, rendition or sidecar was produced. |
| Actual stream-change restart | Not tested | not measured | Timings above are unchanged-stream start attempts, not successful track changes. |

Metadata stream selection remained unchanged for A/B in the before/after
comparison. The documented alternative is `PUT /library/parts/{partId}`;
**needs server write** is the boundary for completing these sub-items, not a
claim that every undocumented per-request mechanism is impossible. No PUT was
attempted. Selected-subtitle delivery and image burn-in remain unestablished.

### 9. HDR→SDR

| 1080p / 8 Mbps target for B | Decoded output | Start median / max seconds | Tone-mapping evidence |
| --- | --- | --- | --- |
| H.264/HEVC target | 1920 × 800, HEVC, BT.2020/PQ HDR | 6.075 / 6.325 | HDR preserved; enabling the server setting alone did not force SDR. |
| H.264-only target | 1920 × 800, H.264, BT.709/BT.1886 SDR | 6.277 / 6.577 | SDR metadata confirmed; session listing has no tone-mapping attribution field. |
| Visual fidelity | Not tested | not measured | Headless metadata cannot validate tone-mapped appearance or Dolby Vision/HDR presentation. |

### 10. Keep-alive, pause, reaping and stop

| Scenario | Observed result | Boundary |
| --- | --- | --- |
| Pause 2 min, no ping/timeline | PMS listed at resume: True; native advance: True | Once; default cache/read-ahead may still request segments. |
| Pause 5 min, no ping/timeline | PMS listed at resume: False; native advance: True | Once; default cache/read-ahead may still request segments. |
| Pause 10 min, no ping/timeline | PMS listed at resume: False; native advance: True | Once; default cache/read-ahead may still request segments. |
| Ping every 30 s, no libmpv for 5 min | HTTP statuses [200]; listed: True; reload advances: True | Once; no segment client during the ping observation. |
| Abandon after native stop, no PMS stop | 180.15 < reap ≤ 210.19 seconds | Once; 30-second listing interval. |
| Stop active session twice | First statuses [200, 200, 200]; second statuses [200, 200, 200] | Three runs; cleanup confirmed absent. |
| Stop request latency | First: 0.003 / 0.003; second: 0.002 / 0.003 | Each pair is median / maximum seconds over three runs. |

**Keep-alive requirement:** the unpinged pause tests lost server state;
cached native resumption does not establish continuing playback after cached
segments are exhausted. A session ping kept state alive in the bounded test.
Use a transcode ping for each live session, including pauses, and bounded restart recovery;
30 seconds is the tested interval, not a measured minimum. No timeline writes
are needed for the measured keep-alive case.

### 11. Rapid tuning

| Start index (three five-session batches) | Start→advance median / max seconds |
| --- | --- |
| 1 | 6.535 / 7.153 |
| 2 | 6.517 / 6.565 |
| 3 | 6.513 / 6.529 |
| 4 | 6.553 / 6.563 |
| 5 | 6.519 / 6.549 |

All 15 starts advanced. Ordering was native stop/END_FILE → PMS stop →
confirmed absence → next start, with no intervening original load within a
batch. Peak sampled concurrency was one in every batch; no capacity refusal.
The configured server limit and behavior at that limit are still not measured.
Direct Play was checked after the batches rather than between their starts.

### 12. Non-local and relay

| Discovered local=false connection | Decision / playback | Output | Start median / max seconds | Sustainable playback check | Child probes |
| --- | --- | --- | --- | --- | --- |
| 1080p 8 | Transcode; 3/3 advance | 1788 × 1080; 7158 kbps decision target | 7.536 / 8.163 | 3 × 60 s; zero ≥2 s stalls and zero cache-pause samples | variant / init / segment: token-free in all runs |
| 720p 4 | Transcode; 3/3 advance | 1192 × 720; 3419 kbps decision target | 7.184 / 7.277 | 3 × 60 s; zero ≥2 s stalls and zero cache-pause samples | variant / init / segment: token-free in all runs |

Both non-local tiers retained the initial session-relative time-pos rule
and full-original duration (unchanged over the observation). At 8 Mbps,
initial time-pos was 0.500–0.542 and at 20 seconds 20.521–20.604; at 4 Mbps,
0.459 and 20.479. Position advanced approximately 60 seconds during each
60-second observation. This establishes tested playback headroom, not an
independent network throughput measurement or support for an off-LAN client.

The discovered non-local connection was used while on the LAN. PMS
`/status/sessions` exposed no playback entries/location/bandwidth fields in
these no-timeline probes, so its LAN/remote classification and agreement with
Lineup's `local=false` flag are **not measured**. Discovery provided no relay
connection: relay is **not tested**, with no simulation.

**Proposed Remote default: 720p · 4 Mbps.** Both tested tiers sustained
playback; 4 Mbps is the conservative proposed ceiling for an unmeasured remote
uplink and is not a Plex-official default claim. The maintainer must confirm
the product choice. The non-local original-file HTTP 503 reinforces treating
a Direct Play decision and successful original playback as distinct results.

### 13. Direct Play and reference restoration

| Check | Result |
| --- | --- |
| Every recorded native restoration check | 132 final-client observations; 0 restored-to-no failures; 0 active stops missing END_FILE. |
| Local original in same instance, without reference override | Advances; original remains access-references=no. Final ladder/ordinary session cleanup checked a subsequent original; rapid batches checked it afterwards. |
| Corrected non-local original control | 0/3 advance; independent original HTTP range request is 503, no redirect. References remain no; END_FILE reason=4/error=-13. |
| Exact per-END_FILE original-load procedure | Not followed at every intermediate restart/rapid/pause/abandon stop. Those stops checked restoration; originals were checked at final session cleanup or group boundaries. |
| Containment / physical presentation | Existing feasibility evidence retained; no new off-origin fixture or physical Windows acceptance claimed here. |

### Cleanup and evidence limits

Both issuing clients ran finally cleanup over their in-memory ID lists
(161 issued IDs in total, including decision-only IDs). Each also swept
`/status/sessions` and `/transcode/sessions` for exposed synthetic identifiers.
Final observation: **zero issued sessions remaining, zero attributable
`lineup-p0-probe` entries, zero cleanup errors**. Session URLs/IDs were never
persisted. Both temporary clients exited. The outside-repository harness and
normalized scratch evidence remain: automatic approval review rejected their
deletion with "blocked by policy," including a single-file deletion attempt.
They contain no credentials, real session capabilities or private media
identity, and are not included in the documentation commit.

Limits: headless Windows only; one PMS version; one tested SDR movie and one
HDR movie; local and discovered non-local connections on the LAN; multipart
coverage as qualified in question 7; no relay,
selected-subtitle delivery, encrypted HLS, actual capacity refusal,
or physical presentation. Per-tier delayed native bitrate was not measured;
full server limit context and PMS network classification were unavailable.
The discovery/header departures and per-END_FILE original sampling are
recorded above.
No production code, existing plan decisions, Security design or CI gate changed.

### Open issues for the maintainer

1. **Stream selection and subtitles block the unchanged track plan.** The
   tested start parameters do not choose alternate audio or subtitles. Resolve
   a verified per-request mechanism, or explicitly decide whether server-side
   stream preference writes are acceptable. Do not infer image burn-in or
   text-subtitle master compatibility from masters with no selected subtitles.
2. **Seeking needs a new agreed policy or stronger evidence.** Initial
   time-pos is session-relative while duration is the full original, but seek
   requests change PMS's available window and repeated forward seeks can time
   out. Prefer new-session offset restart until the source-coordinate mapping
   and safe in-session range are established. This contradicts assuming a
   broadly usable in-session seek from the earlier 30-second feasibility case.
3. **Choose HDR preservation versus SDR output in the client profile.** The
   broad HEVC target retains HDR at 1080p; the H.264-only target produces SDR.
   Tone-mapping attribution and visible fidelity remain physical acceptance.
4. **Handle Direct Play decisions explicitly.** Calling the HLS start endpoint
   after Direct Play OK gives 400. On the discovered non-local connection, the
   original itself gives 503 even though both transcode tiers play. Server
   cause/limits were not measured under the allowed preference-read scope.
5. **Close context/coverage gaps before claiming support.** Confirm Plex Pass
   and concurrency limit, capacity/unavailable error shapes, relay and
   multipart when available, and selected-subtitle masters. Complete delayed
   native bitrate cross-checks if per-tier live measurements are required;
   the session listing did not expose live output bitrate.

**P1 cannot start unchanged as an accepted full-plan handoff.** Its token-free
transport/master path evidence is viable on the two tested connections, but
the maintainer must accept the bounded evidence and settle stream-selection
scope, seeking/position assumptions, HDR profile direction and the remaining
product confirmations. The existing credential boundary must remain intact;
no token fallback is proposed. No observed token-free child or master result
contradicted the Security design. **Independent review is not specifically
recommended for these results;** seek review if resolving a future subtitle
or transport issue changes that design.
