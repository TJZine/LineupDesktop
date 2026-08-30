# Audio Passthrough Specification and Implementation Checklist

Status: planned and deliberately deferred

Decision recorded: 2026-08-30, after the bounded Audio Setup UX study at
`f2815f2c6e77a2b4217ecf8391c87006b480ae7a`.

This document specifies an optional Windows bitstream-passthrough feature. It
does not claim that passthrough is implemented, platform validated, or
supported. Current playback continues to decode supported audio through
libmpv/FFmpeg and send it to the system-selected output, normally as PCM.

## Product decision

Lineup Desktop will not keep an Audio Setup onboarding screen merely to explain
the current default. Desktop playback needs no first-run audio choice: the
operating system selects the output and libmpv decodes supported audio without
requiring receiver setup.

Passthrough is nevertheless appropriate for a home-theater application. It
will be implemented later as an ordinary, default-off setting for people who
want a compatible HDMI or S/PDIF receiver to decode selected compressed Dolby
or DTS formats. It must not return to onboarding.

The future setting is an optional output preference, not a codec-compatibility
gate. Turning it off must always preserve today's decode-to-PCM behavior.

## Current evidence and constraints

- `LineupSettings.audioSetupComplete` records only whether the explanatory
  onboarding screen was dismissed. It is not a passthrough preference and must
  never be repurposed as one.
- `SettingsView` has no Audio category or native audio-status model.
- `NativePlayer` exposes playback, tracks, video bounds, fullscreen, and
  volume, but no audio configuration or output-capability contract.
- `WindowsNativePlayer` initializes libmpv with a fixed allowlisted option set.
  The Windows method channel does not accept arbitrary mpv options.
- The Windows runner classifies audio decode and audio-output failures but does
  not report the active output mode, device, or output parameters.
- Lineup intentionally follows the system-selected output. Output-device
  enumeration and selection are separate features and are not prerequisites
  for passthrough.

libmpv's documented `audio-spdif` option supports `ac3`, `dts`, `dts-hd`,
`eac3`, and `truehd`. The option applies to HDMI as well as classic S/PDIF, but
receiver and operating-system support varies. The mpv manual also recommends
decoded multichannel PCM for ordinary HDMI use. See the upstream
[`audio-spdif` documentation](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)
and its documented
[`audio-params` and `audio-out-params` properties](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst).

## User experience specification

### Location and default

- Add an **Audio** category to the existing Settings category rail.
- Do not move unrelated settings into that category as part of this feature.
- Do not add an onboarding step, modal on first playback, or setup-completion
  flag.
- Default to decoded PCM with no passthrough formats enabled.
- Continue to use the Windows system-selected output. Say so in the settings
  description without presenting a fake device name or capability result.

### Controls

Present a compact **Bitstream passthrough** section with this meaning:

> Send only the selected formats unchanged to a compatible HDMI or S/PDIF
> receiver. Leave all formats off for recommended decoded PCM output.

Use one independently labelled switch or checkbox for each libmpv-supported
format:

| User-facing label | Persisted/native token | Required clarification |
| --- | --- | --- |
| Dolby Digital (AC-3) | `ac3` | Compatible with HDMI or S/PDIF receivers that advertise AC-3 |
| Dolby Digital Plus (E-AC-3) | `eac3` | Usually HDMI; support must not be inferred from AC-3 support |
| DTS | `dts` | DTS core, not DTS-HD |
| DTS-HD | `dts-hd` | Receiver and Windows support varies |
| Dolby TrueHD | `truehd` | Requires a compatible HDMI path |

The empty selection is the off state; do not add a second master toggle whose
state could disagree with the format selection. Summarize the current state as
either **Decoded PCM (recommended)** or **Passthrough: _selected formats_**.

Each format must have a text label and accessible checked state. Codec logos,
color, or receiver-brand imagery are unnecessary and must not carry meaning.
The group must support mouse, keyboard, and remote-style focus navigation at
800x600, 1280x720, and 1920x1080 without horizontal scrolling.

### Saving and when changes take effect

- Persist each change through the existing settings owner and show the existing
  saving/error treatment.
- Apply a changed format set to the next media load. Do not restart, seek, or
  silently interrupt the item already playing.
- While playback is active, show concise secondary text that the change applies
  on the next tune. Do not add a confirmation dialog.
- A failed save keeps the last durable format set and restores the controls to
  it, matching existing Settings behavior.

### Truthful status and failure behavior

The settings UI must distinguish three facts:

1. **Configured**: the user selected a format.
2. **Active**: the current track is actually being sent as a compressed
   bitstream.
3. **Supported**: physical Windows evidence established that the exact output
   path accepted the format.

Configuration alone must never be labelled active or supported. Do not show a
green check, receiver name, or "working" state unless the native owner reports
the corresponding runtime fact.

Before production implementation, the Windows discovery gate below must decide
whether the pinned libmpv build can report active passthrough reliably from
documented properties/events. If it can, expose a read-only current-playback
status in Settings and redacted diagnostics. If it cannot, omit live status and
state plainly that compatibility is confirmed by audible playback and the
receiver's own indicator.

An unsupported format or output path must not produce silent playback that
looks healthy. The discovery gate must select and test one of these recovery
contracts:

- retry the current load once with decoded PCM and visibly report that
  passthrough failed for that format; or
- surface the existing recoverable audio-output error with an action that
  disables that format and retries.

Do not silently fall back while continuing to claim passthrough is active. Do
not create an unbounded retry loop. The chosen recovery contract must be locked
in this document before implementation begins.

### Volume and transport behavior

The Windows discovery gate must establish how the pinned libmpv/WASAPI path
handles application volume, mute, pause, seek, track changes, replacement
tunes, and device changes during bitstream output. If application volume is not
meaningful while passthrough is active, Lineup must disable or truthfully label
that control rather than pretending to change the bitstream level. Receiver
volume remains outside Lineup's ownership.

## Persistence contract

Add a dedicated persisted collection such as `audioPassthroughFormats`. Its
canonical value is a duplicate-free list containing only the five allowlisted
storage tokens above.

- Missing field during migration: use the empty set.
- Empty list: decoded PCM.
- Unknown token, duplicate token, or non-string value: reject or quarantine
  using the settings store's established corrupt-state policy; never pass it to
  C++.
- Serialization order: use the fixed table order above for deterministic files
  and tests.
- Logout/profile/server changes: retain the application-level audio preference
  unless a later product decision deliberately makes settings profile-scoped.

Removing the obsolete onboarding completion field and adding this preference
are separate migrations. The latter must not restore Audio Setup or interpret a
previous `audioSetupComplete: true` value as consent to passthrough.

## Ownership and native contract

Flutter/Dart owns the setting, labels, persistence, accessibility, application
state, and user-visible recovery. C++ owns only validated application of the
native media option and observation of native media facts. libmpv remains the
audio engine.

The implementation must preserve these boundaries:

1. `LineupSettings` owns a typed allowlisted set of passthrough formats.
2. `LineupController` persists changes through the existing settings store.
3. The playback composition root/coordinator supplies the current durable
   format set before the next `NativePlayer.load`.
4. `NativePlayer` gains one narrow typed audio-configuration seam. It must not
   expose arbitrary mpv option names or values.
5. `WindowsNativePlayer` sends only the allowlisted format tokens over the
   existing method channel.
6. `windows/runner/native_player.cpp` validates type, count, uniqueness, and
   tokens again, then applies the corresponding `audio-spdif` value on the mpv
   worker thread before the load command.
7. Native telemetry reports only observed properties. It does not infer
   receiver capabilities.

Configuration and load commands must have deterministic ordering. A load must
use one complete immutable format snapshot; a settings change racing with a
load applies to the following load. Keep the existing bounded command queue and
current-load rejection behavior.

Do not add a general-purpose native option bridge, service locator, audio
plugin, event bus, or new dependency.

## Discovery gate: required before production coding

Use the exact pinned libmpv build and a physical Windows machine. Record the
Windows version, audio driver, connection type, receiver, sample identity, app
commit, and libmpv provenance without recording personal paths or media
metadata.

- [ ] Confirm whether `audio-spdif` can be changed after `mpv_initialize` and
      before the next load using a documented property/API path.
- [ ] Confirm the exact value required to clear all passthrough formats.
- [ ] Identify an observable, documented signal for active compressed output,
      if one exists (`audio-params`, `audio-out-params`, track codec, and audio
      output properties are candidates, not assumptions).
- [ ] Capture the native event/error sequence for a supported format and for a
      deliberately unsupported receiver/output combination.
- [ ] Decide and document the single bounded PCM recovery contract.
- [ ] Verify application volume and mute semantics during passthrough.
- [ ] Verify pause, seek, audio-track change, replacement tune, stop, and app
      shutdown do not leave stale audio or a retained exclusive device.
- [ ] Verify a Windows default-device change between loads uses the new system
      output without persisting a stale device identifier.
- [ ] Confirm whether an output-device reopen is required after the format set
      changes and whether applying the setting only on next load is sufficient.

If these checks contradict the proposed contract, update this specification
before exposing the setting. A UI toggle is not admissible until one complete
supported and one complete unsupported path are understood.

## Implementation checklist

### Slice 1: lock evidence and recovery

- [ ] Complete the physical Windows discovery gate.
- [ ] Add the selected recovery behavior and active-status evidence to this
      specification.
- [ ] Decide whether diagnostics can truthfully record configured format,
      source codec, output parameters, and fallback reason without device names
      or paths.
- [ ] Review copy against the observed Windows behavior.

### Slice 2: typed settings and migration

- [ ] Add the typed format model and deterministic storage tokens.
- [ ] Add the canonical persisted collection with an empty default.
- [ ] Migrate older settings without interpreting `audioSetupComplete` as an
      audio preference.
- [ ] Test round trips, missing-field migration, invalid types, unknown tokens,
      duplicates, deterministic order, and failed writes.

Expected owners: `lib/settings/lineup_settings.dart`, the existing settings
store/migration owner, and their focused tests.

### Slice 3: narrow player configuration

- [ ] Add one typed configuration method/value to `NativePlayer`.
- [ ] Update the production Windows adapter and test doubles.
- [ ] Apply one immutable setting snapshot before each media load.
- [ ] Preserve ordering across replacement loads and concurrent setting
      changes.
- [ ] Add Dart method-channel tests for empty, single-format, multi-format,
      rejected, stale, and failed native calls.

Expected owners: `lib/playback/native_player.dart`,
`lib/playback/windows_native_player.dart`, the playback composition/coordinator
owner, and their focused tests.

### Slice 4: validated Windows/libmpv application

- [ ] Add a bounded command and payload parser; accept no arbitrary option.
- [ ] Revalidate the five-token allowlist in C++.
- [ ] Apply/clear `audio-spdif` on the mpv worker thread before load.
- [ ] Observe only the properties proven useful by the discovery gate.
- [ ] Implement the locked one-shot recovery/error behavior.
- [ ] Keep logs redacted and do not log media URLs, headers, device identifiers,
      or private metadata.
- [ ] Compile against the pinned Windows engine and libmpv artifact.

Expected owners: `windows/runner/native_player.h`,
`windows/runner/native_player.cpp`, and the existing Windows build/test owners.

### Slice 5: Settings UI

- [ ] Add the Audio category to the existing responsive category rail.
- [ ] Implement the five labelled format controls and decoded-PCM summary.
- [ ] Use current theme roles, focus treatment, saving state, and error notice.
- [ ] Add the proven live status or the honest no-status explanation.
- [ ] Add semantics tests for category, group description, labels, checked
      states, focus order, disabled/saving state, and error recovery.
- [ ] Verify 800x600, 1280x720, 1920x1080, supported text scaling, keyboard,
      remote-style traversal, mouse, and all five themes.
- [ ] Add only durable goldens: default decoded PCM and one configured
      multi-format state at representative desktop sizes.

Expected owners: `lib/app/lineup_shell.dart`, existing Settings widget tests,
`test/app/ui_acceptance_golden_test.dart`, and related golden assets.

### Slice 6: documentation and acceptance

- [ ] Update the User Guide only after the setting is implemented.
- [ ] Update Product Parity from intentionally omitted to implemented, then to
      platform validated only after physical evidence exists.
- [ ] Extend Windows Native Acceptance with the matrix below and record the
      exact tested commit.
- [ ] Document recovery for silence, output rejection, and receiver mismatch.
- [ ] Keep PCM as the recommended default and avoid claims of universal codec,
      receiver, or Atmos/DTS:X support.

## Verification matrix

### Deterministic checks

- Settings serialization, migration, invalid input, and persistence failure.
- Settings UI semantics, focus, saving, responsive layout, and golden states.
- Configuration-before-load ordering and next-load application.
- Replacement-load currentness and bounded command behavior.
- Dart/native payload allowlisting and native error mapping.
- PCM default behavior when no formats are selected.
- Existing playback, track selection, volume, Guide, and application spine
  regressions.
- Formatting, `flutter analyze`, full Flutter tests, Windows compilation, and
  the repository-prescribed macOS build/smoke checks.

### Physical Windows matrix

Use privacy-safe samples with known tracks:

| Path | Samples | Required observations |
| --- | --- | --- |
| System speakers/headphones, PCM default | AAC, AC-3, E-AC-3, DTS, DTS-HD, TrueHD | Current decode behavior remains audible; track switching, volume, seek, and replacement work |
| Compatible HDMI receiver | Each enabled format separately | Receiver indicator and native evidence agree; audio is audible and synchronized; no false active claim |
| Compatible S/PDIF receiver | AC-3 and DTS core | Only formats valid for the tested path are enabled and observed |
| Unsupported format/output | At least one deliberate mismatch | Locked recovery behavior occurs once, remains visible, and never loops or claims passthrough |
| Mixed playlist/channel replacement | PCM and passthrough tracks alternating | Output reopens cleanly with no stale audio, lost video, duplicate player, or retained device |
| Lifecycle | pause, seek, stop, minimize/restore, device change between loads, exit | No hang, stale audio, leaked exclusive device, or misleading status |

Physical evidence is valid only for the exact commit, Windows build, driver,
connection, receiver, and format tested. It does not establish support for all
Dolby/DTS variants, receivers, GPUs, drivers, or connection topologies.

## Acceptance criteria

- Passthrough is absent from onboarding and present only as an ordinary
  default-off Settings preference.
- Empty format selection produces the established decoded-PCM path.
- Only the five documented libmpv tokens can cross the Dart/native boundary.
- Each load uses the latest complete durable configuration available before
  that load; active playback is not interrupted by a settings change.
- Configured, active, and physically supported states are never conflated.
- Unsupported output follows one tested, visible, bounded recovery contract.
- Accessibility, focus, persistence failures, responsive layouts, and all
  themes remain correct.
- Deterministic tests establish application behavior; physical Windows evidence
  establishes native output behavior at the exact tested commit.
- Documentation makes no universal format, receiver, object-audio, or platform
  support claim.

## Explicit non-goals

- Audio-output device enumeration or an in-app device picker.
- Speaker calibration, channel mapping, test tones, or room correction.
- Automatic receiver-capability inference without a proven native contract.
- Exclusive-mode controls beyond what the validated passthrough path requires.
- Transcoding, alternate-track selection, subtitle changes, or server-side
  compatibility policy.
- Making passthrough a playback prerequisite or enabling it by default.
- macOS passthrough support. The current production playback target and this
  specification are Windows; any macOS implementation needs its own evidence.
- Atmos or DTS:X marketing claims inferred solely from a TrueHD, E-AC-3, or
  DTS-HD carrier.
- A general libmpv settings console or arbitrary native-option bridge.

## Exit condition for the deferred item

This item leaves the deferred backlog only when the discovery gate is complete,
the recovery contract is locked here, the implementation slices pass their
deterministic gates, and physical Windows evidence covers both a supported and
an unsupported path at the exact candidate commit. Until then, user-facing
documentation must continue to say that Lineup decodes to the system-selected
output and does not expose passthrough controls.
