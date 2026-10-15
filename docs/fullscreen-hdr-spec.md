# Fullscreen HDR Presentation Specification

**Status:** Implemented, October 11, 2026; integrated physical acceptance is
pending. Windows 10 discovery is complete, and the existing composition passed; see the
[discovery result](open-obligations.md#archive-recovery-and-preservation-map).
The [implementation plan](fullscreen-hdr-implementation-plan.md) owns the
approved session, restoration, hold, guardian, and Diagnostics contracts.

## Goal

On a capable Windows display, Lineup must transition HDR and SDR presentation
automatically as the tuned program requires while fullscreen. A viewer must not
need to leave Lineup to visit Windows Settings between programs.

This is a Windows native-presentation requirement, not a metadata badge or a
Plex transcode policy. It applies to local and Plex media that reaches libmpv.

## User-facing contract

- Entering fullscreen with HDR material on a capable output activates correct
  HDR presentation automatically.
- Replacing that program with SDR material selects SDR while matching remains
  active, even if Windows HDR was originally on. Leaving fullscreen, moving to
  another display, stopping playback, or closing the app releases the old target
  and restores the state Lineup found, unless an external change relinquished
  ownership. Original-state restoration can therefore restore HDR.
- The transition preserves one current player, correct video geometry, input,
  focus, and the intended fullscreen experience. It may not leave black video,
  stale frames/audio, a stranded display mode, or an orphaned process.
- If HDR cannot be presented, libmpv must use a correct SDR fallback/tone-map;
  runtime details must not claim HDR output merely because source metadata is
  HDR.
- Moving between displays or a user changing display capability at runtime is
  handled as a fresh presentation decision.

## Current state and constraints

Lineup currently uses a borderless top-level fullscreen window and embeds
libmpv's `gpu-next` D3D11 output in a child host. Flutter stays above that host
through the repository-patched DirectComposition engine. The native player
sets `vo=gpu-next`, `gpu-api=d3d11`, `gpu-context=d3d11`, and `hwdec=auto`, and
owns HDR/SDR display matching through the native DisplayConfig controller.
libmpv adapts to the display state without additional output options or refresh.

The system's global HDR preference belongs to the user. The feature must avoid
making that preference a manual per-program prerequisite or leaving it changed
after Lineup exits. The implementation route must use supported Windows/DXGI
and libmpv behavior; it must not depend on registry writes, Settings UI
automation, undocumented controls, or a driver-specific workaround.

The approved design preserves this composition. It uses supported DisplayConfig
APIs on a dedicated native worker, with a guardian confirmed armed before any
write. Dart owns session eligibility and bounded playback holds; holds use the
existing preparing/loading presentation without changing overlay policy.

## Feasibility gate

The completed Windows 10 22H2 discovery with known SDR and HDR10 material,
recorded in the [discovery plan](open-obligations.md#archive-recovery-and-preservation-map), evaluated the current
composited D3D11/libmpv path first: its negotiated colorspace and HDR output
when fullscreen, its behavior across manual and programmatic Windows HDR
transitions, and the resulting overlay, focus, video stacking, and normal
restoration behavior.

Discovery established that the current renderer/composition can be retained.
It does not establish acceptance of the integrated matching implementation.

Windows 10 evidence covers only the legacy DisplayConfig advanced-color route.
Windows 11 24H2 and later separate HDR from automatic color management and need
their own route verification on Windows 11 hardware. Both OS versions are enabled;
the reported capability chooses the new HDR-state route or legacy advanced-color
route. Windows 11 remains unverified until the borrowed machine is tested.

Record source and output colorspace, bit depth, monitor/driver details,
fullscreen state, and visual observations. Do not infer output HDR from Plex
metadata or source transfer characteristics alone. Plex HTPC may be used as a
behavioral benchmark only after its observed transitions are captured; it is
not an implementation dependency or source reference.

Any integrated physical failure that prevents this protected composition or
restoration contract needs evidence and adjudication before a support claim.

## Ownership

- **Flutter/Dart:** fullscreen intent, session eligibility, first decoded transfer
  decision, hold sequencing, Player state, input/focus, overlays, accessibility,
  and normalized Diagnostics projection. No new matching-failure Player notice.
- **Windows native player:** output-capability detection, target mapping,
  display writes, per-target ownership/restoration, guardian lifecycle, monitor
  transitions, and bounded native telemetry.
- **libmpv:** decode, HDR/SDR color processing, tone mapping when required, and
  source/output facts.

The Windows native player remains the sole native media/presentation owner.
No Plex token, URL, or private media detail may enter presentation diagnostics
or acceptance evidence.

## Acceptance evidence

Physical Windows evidence at the exact commit is required before claiming this
behavior. Extend the HDR rows in
[Windows Native Acceptance](windows-native-validation.md#7-media-acceptance-matrix)
to include, at minimum:

- HDR10 fullscreen entry on the HDR display and verified HDR output;
- HDR-to-SDR replacement while fullscreen, and SDR-to-HDR replacement;
- fullscreen exit, stop, app exit, and crash/recovery behavior after each
  transition, confirming no stranded display state;
- moving the active fullscreen/windowed player between HDR and SDR displays;
- Player OSD, rich Now Playing, Guide/PiP/Overlay, focus, keyboard/remote, and
  video stacking across each applicable transition; and
- the packaged release, not just a developer build.

The report must distinguish source HDR metadata, the selected renderer path,
and observed display output. A build, automated test, or HDR label alone is not
platform validation.

## References

- [Windows presentation ownership](architecture.md#windows-presentation-and-ownership)
- [Windows native acceptance](windows-native-validation.md)
- [Windows runtime provenance](windows-runtime.md)
- [Current UI constraints](../.interface-design/system.md#player-protected-baseline)
