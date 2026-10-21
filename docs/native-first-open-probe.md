# Native first-open developer probe

The shared native player core has an opt-in stderr probe for investigating an
initial source-open failure. It is disabled by default. The exact environment
value `LINEUP_FIRST_OPEN_DIAGNOSTICS=1` enables it when the core is constructed;
restart the process to change that choice. Other values leave it disabled.

For an approved macOS diagnostic run, use a separately identified diagnostic
app and a private stderr destination. For example, after setting those two
paths in the shell:

```sh
LINEUP_FIRST_OPEN_DIAGNOSTICS=1 \
  "$LINEUP_DIAGNOSTIC_APP/Contents/MacOS/Lineup Desktop" \
  2> "$LINEUP_PRIVATE_LOG"
```

Launching through Finder or `open` may not pass this environment to the app.
Preserve the accepted candidate and its evidence; a build containing this probe
has a separate source/build identity. This document does not authorize a build,
signing change, or live playback session. The stderr file can also contain
output from other components, so inspect and sanitize it before sharing.

Each probe line has this form:

```text
[lineup-first-open] module=core cause=end_error mpv_error=-13 http_status=403
```

Only the tag, hardcoded enum names, and optional bounded integers are emitted:

- `module`: `core`, `curl`, `ffmpeg`, `demux`, `stream`, `audio_output`,
  `video_output`, or `unknown`. Native module names require an exact allowlist
  match; arbitrary prefixes fall back to `unknown`.
- `cause`: `accepted`, `opening`, `ready`, `playlist_redirect`, `stop_accepted`,
  `end_error`, `end_error_unknown`, `end_stopped`, `end_eof`, `end_other`, `dns`,
  `connect`, `tls`, `redirect_limit`, `range`, `container`, `http`, `timeout`,
  or `unknown`.
- `mpv_error`: the original END_FILE integer only if it is between -128 and 0.
  An error end outside that range uses `end_error_unknown` and omits the integer.
- `http_status`: 100 through 599, only when the existing parser safely observes
  an HTTP error status. A terminal record can retain the status already
  correlated to that load.

The sink has no raw string parameter. It never outputs a load ID, URI, path,
host, header, token, media/account identity, raw module, raw message, or exception
text. Error text is bounded in memory and used only to select a conservative
category. Categories are hints; they do not establish the root cause. Unknown
text remains `unknown`.

For each accepted load, the probe emits each lifecycle marker at most once and
at most four ERROR/FATAL category records, for a maximum of ten lines. Category
records require the currently observed and active load to match. They stop at
FILE_LOADED, terminal END_FILE, or accepted stop. A subsequent accepted load
starts a fresh budget; an attempted replacement clears the previous probe
context. Terminal and stop summaries can follow readiness. Their order helps
distinguish the original native failure from later cleanup. Concurrent player
cores can interleave records; the probe intentionally emits no correlation ID.

The probe does not change commands, channel payloads, failure classification,
playback state, runtime configuration, TLS/reference policy, or entitlements.
It does not fix source opening or establish successful real-media playback.

The existing portable `player_core_contract` CTest captures the actual stderr
sink using fake libmpv operations. It checks default silence, exact opt-in,
privacy grammar and malicious strings, category fallbacks, original error/status
preservation, stale-event suppression, the ten-line cap, and equal public events
with the probe enabled and disabled. This is native contract evidence; the
controller must separately build and identify the diagnostic app and observe
the real failing load to diagnose the live failure.
