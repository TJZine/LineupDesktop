# Production macOS session-clock fixture

This five-cell experiment documents the pre-alignment desktop trim. Use the
[current desktop alignment matrix](../../native/session-alignment/README.md)
to validate the production path with predecessor retention and an alignment seek.

This standalone validation target compiles the real macOS adapter, Flutter codec
conversion, `PlayerCore`, `LibmpvOperations` and session stream callback. It does
not open a separate ctypes player. Its factory differs only by selecting null
video/audio output and the local fixture CA, following the authenticated-reference
fixture. Delegating operation spies observe the real command and options without
rewriting them.

This is the five-positive follow-up. The first cycle's child-302 negative and
second cycle's corrected nested-HLS negative are accepted and are not rerun.
Their original freezes/lists/preparations/results remain unchanged. The earlier
empty-MAP nested control made no media read; pinned FFmpeg's initialization path
supports empty-init EOF as its diagnosis, without an instrumented return trace.
The corrected eight-byte MAP plus remaining media text exercised the actual
nested child-IO EPERM marker with zero sentinel contact.

The exact schedule is copy at 10, 21 and 605 s, then encode at 10 and 605 s.
No sentinel listener, adversarial response or policy status file is launched by
this follow-up. Both negative classifiers and bounded barrier/attack helpers
remain covered offline; their previously accepted runtime receipts are reused.
A child operator stop or structural failure always fails a cell. No production,
endpoint, player-policy or clock-oracle change is part of this correction.

The five positives reuse the previously generated, independently timed public
corpus. Only the new fixture URI text changes to flat synthetic PMS namespace
names; timing tags and generated media bytes are unchanged. Each load enters
through `LineupNativePlayer` with the required whole original `sessionPlaylist`;
the production callback validates and trims it. A positive result requires no
HTTP request for the original variant, no empty prefix walk, and first media
index equal to the original segment containing the offset.

The actual private load map must contain exactly four keys:
`access-references=yes`, `curl-max-redirects=0`, `demuxer=lavf` and the fixed
`demuxer-lavf-o` dictionary selecting `format_whitelist=hls,mov` and
`protocol_whitelist=https,tls,tcp`. The per-file lavf selector prevents generic
MPV playlist fallback. HLS is still probed from the opaque `.m3u8` filename;
there is no global demuxer selector or HLS format forcing. Effective values are
read back from the running client, including the decoded MPV node dictionary,
TLS verification, reference permission and redirect limit. The command spy also
requires an exact `lineup-session://<32 lowercase hex>.m3u8` capability shape.

The observation retains provisional `FILE_LOADED` facts, then waits for a
qualified paused playback restart with decoded and null-output video dimensions,
picture type, finite position, raw demuxer start and the effective security
settings. It records actual production `time-pos` and `demuxer-start-time`
channel events separately, releases pause, and samples 25 times at nominal
250 ms over six seconds. Raw snapshot and production position ages must remain
at most 0.5 s; the stable demuxer-start event may age. The reference-video clock
gate is unchanged, including for encode; an observed disagreement fails the cell.

Stop cleanup uses the same one-second budget, starting before the stop command.
Production `stopResult` follows PlayerCore's observed `idle-active`/zero playlist
count; it does not prove that mpv has finished unloading. In pinned mpv,
`cmd_stop` sets PT_STOP, `idle-active` can immediately reflect it, and the unload
path updates idle before restoring per-file option backups. `END_FILE` is emitted
after those backups are restored. The fixture therefore waits for the current
fresh client's matching playlist-entry END_FILE (STOP for positives, ERROR for
previous expected-negative helper coverage), idle=true, playlist-count=0 and
all four policies equal to their pre-load baseline. A missing/foreign/duplicate
entry fence fails correlation. The deadline is checked after synchronous getters
as well as before them; a late successful read cannot pass. Persistent mismatch
fails. The receipt retains immediate/final per-option checked/restored booleans,
fixed end reason, idle/count facts, wait duration and timeout. No raw option
values or entry IDs are published. Native disposal follows this bounded fence. These are headless clock
observations, not first displayed pixels. No `startSeconds`, `startPosition` or
seek is supplied.

Build and offline boundary checks (no media loads):

```sh
python3 -m unittest discover -s tool/macos/session-clock -p 'test_*.py' -v
python3 tool/macos/session-clock/run.py --prepare \
  --runtime /absolute/pinned/runtime \
  --flutter-root /absolute/pinned/flutter \
  --fixture-dir /absolute/frozen/mpv-synthetic \
  --output-dir /absolute/new/preparation
```

Preparation verifies the existing runtime lock and library closure, compiles the
real adapter target, runs pure native boundary tests and parses all five follow-up whole
input playlists through the actual native validator. These checks never create
or initialize a media client. It writes `identity.json`, binding all sources,
reused helpers/corpus, runtime libraries and client/stream-callback headers,
Flutter framework binary and headers. Do not prepare over an existing directory.

Before the primary command, the controller obtains independent review of the
source and exact list and freezes a JSON object with:

- `version: 1`, the exact five-cell `schedule`, `maximumHTTP: 320` and
  `maximumBytes: 167772160`;
- `inputs`, containing every path/hash from prepared `identity.json` plus the
  executable/list/review/helper inputs;
- `harness`/`harnessSha256`, `identityPath`/`identitySha256`, `fixtureDir`;
- server `certificatePath`/`certificateSha256` (`localhost.crt`) and the existing
  server `privateKeyPath`; separately, mandatory client
  `clientCaPath`/`clientCaSha256` (`ca.crt`);
- `listPath`/`listSha256`, `reviewPath`/`reviewSha256`.
  Both historical fixed status filenames remain checked for stale inputs at
  preflight; this five-positive follow-up writes neither.

Changed or omitted prepared dependencies fail before resources start. The
private key is never copied into evidence. The server leaf certificate and the
client trust root are separate frozen inputs: native clients use the existing
root CA, with no reliance on trusting a leaf certificate as a partial chain and
no system trust writes. Both certificate hashes are checked before resources.
Then, only within the controller's
reviewed authorization:

```sh
python3 tool/macos/session-clock/run.py \
  --authorized-production-session-synthetic \
  --freeze /absolute/reviewed/freeze.json \
  --output-dir /absolute/new/cycle
```

The exclusive claim precedes listeners or child processes. There is one child
per cell and no harness retry. Each child has a 15 s startup/25 s active bound,
then bounded native shutdown; the parent has a 35 s guard and bounded
terminate/kill reaping. Server-observed HTTP caps are 64 requests/32 MiB per
positive, 320 requests/160 MiB total, and 2 MiB per response. Accepted connections are counted
separately. Native connection or transfer attempts that fail before reaching the
server's HTTP parser are not fully observable here; these server counters do not
claim a complete native physical-attempt budget. Production cache/retry defaults are not changed
for the measurement. Any unexpected failure, guard, unlisted request or
unconfirmed cleanup stops the matrix. After each child, owned sockets/handlers
must drain; final shutdown checks that the owned listener is absent.

Stdout/stderr are captured with byte caps. The runner rejects whole manifest,
original variant, init/media URI and URL-shaped canaries, including escaped
JSON, before persistence. Native events are scanned after the real Flutter
codec and only a closed numeric result is retained. Stderr is persisted only
as fixed redacted lines, never raw native diagnostics. Server-observed HTTP
requests and accepted connections, ranges, statuses, byte counts, original
indices and cleanup receipts remain auditable within the observation limits
above.
No Plex, account/Keychain, emulator, physical display or Windows target is
accessed by this fixture.
