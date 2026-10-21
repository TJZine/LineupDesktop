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

## License failure probe

The macOS notice reader and Dart license repository also support the exact
opt-in `LINEUP_LICENSE_DIAGNOSTICS=1`. They sample it at construction and stay
silent for unset or other values. Set it when launching a separately identified
diagnostic app through the executable as above; it is independent of
`LINEUP_FIRST_OPEN_DIAGNOSTICS`. Successful license operations produce no records.

Each failed native list/read attempt emits at most one line:

```text
[lineup-license-native] operation=list stage=root_open category=system errno=2
```

Operations are `list` or `read`. Stages are `root_open`, `bundle_child_open`,
`tree_open`, `traversal_duplicate`, `traversal_open`, `traversal_read`,
`entry_name`, `entry_stat`, `entry_directory_open`, `entry_kind`, `file_size`,
`entry_count`, `file_path`, `file_duplicate`, `file_open`, `file_stat`, `file_read`,
`file_encoding`, `tree_bounds`, `required_index`, `document_id`, or `depth_bounds`.
Categories are `system`, `invalid`, `bounds`, `missing`, or `encoding`. A syscall
failure can include its original errno only in the range 1 through 4095;
otherwise the integer is omitted. Native errors carry enums from the responsible
guard to the operation boundary, without retaining a path or raw error message.

Each failed Dart native-index/document attempt emits at most one line:

```text
[lineup-license-dart] operation=index category=native_unavailable
```

Dart operations are `index` or `read`. Categories are `native_unavailable` (the
fixed native resource error code), `missing_plugin`, `platform_other`,
`invalid_index`, `invalid_document`, or `other`. Raw exception codes, messages,
details and stack traces never enter this sink. A native failure reaching Dart
can produce one native record followed by one Dart record. Retry starts a new
attempt; there is no per-file logging.

Both sinks accept only fixed enum/category names and the bounded errno, with no
resource path, document ID, media/account identity or raw input. They preserve
original errors, method-channel results and existing UI failure/retry behavior.
They do not bypass resource validation, change filesystem permissions, add
fallbacks, or fix an unobserved cause. Whole-process stderr still requires private
handling because other components may emit unrelated output.

The existing Swift resource tests capture the real stderr descriptor and verify
exact opt-in, failure stages, successful silence and unchanged rejection/text
behavior. Existing Dart license tests capture the stderr boundary and check
fixed categories, unchanged exception kinds and successful silence. They are run
with the environment unset, set to `1`, and set to an invalid value. These checks
do not establish the failing stage in a running app; the controller must build
and reproduce it with the opt-in enabled.
