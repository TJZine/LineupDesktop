# Fullscreen HDR Presentation Specification

**Status:** Planned native-media work. Defer implementation until the current
UI refresh has landed and its Player surfaces are stable.

## Goal

On a capable Windows display, Lineup must transition HDR and SDR presentation
automatically as the tuned program requires while fullscreen. A viewer must not
need to leave Lineup to visit Windows Settings between programs.

This is a Windows native-presentation requirement, not a metadata badge or a
Plex transcode policy. It applies to local and Plex media that reaches libmpv.

## User-facing contract

- Entering fullscreen with HDR material on a capable output activates correct
  HDR presentation automatically.
- Replacing that program with SDR material, leaving fullscreen, moving to an
  incapable display, stopping playback, or closing the app restores correct SDR
  presentation without a manual Windows Settings round trip.
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
sets `vo=gpu-next`, `gpu-api=d3d11`, `gpu-context=d3d11`, and `hwdec=auto`, but
does not own an explicit HDR/SDR presentation-mode transition.

The system's global HDR preference belongs to the user. The feature must avoid
making that preference a manual per-program prerequisite or leaving it changed
after Lineup exits. The implementation route must use supported Windows/DXGI
and libmpv behavior; it must not depend on registry writes, Settings UI
automation, undocumented controls, or a driver-specific workaround.

The critical design constraint is composition. Exclusive native presentation
may be needed to provide automatic HDR behavior independently of desktop HDR,
but it can conflict with the DirectComposition path that currently puts Flutter
OSD, overlays, focus, and accessibility above video. A final design must either
preserve those contracts or deliberately define and approve the fullscreen
alternative; it may not silently regress them.

## Feasibility gate

Before implementation, prove the behavior on the target Windows 10 HDR machine
with known SDR and HDR10 material. Compare:

1. The current composited D3D11/libmpv path, including its negotiated
   colorspace and HDR output behavior when fullscreen.
2. A supported application-managed fullscreen presentation path, including
   whether it can activate HDR output without a persistent global desktop-mode
   change.
3. The resulting overlay, focus, video stacking, and recovery behavior.

Record source and output colorspace, bit depth, monitor/driver details,
fullscreen state, and visual observations. Do not infer output HDR from Plex
metadata or source transfer characteristics alone. Plex HTPC may be used as a
behavioral benchmark only after its observed transitions are captured; it is
not an implementation dependency or source reference.

If no supported path satisfies the contract with the protected Player
composition, stop at the gate and bring the evidence and alternatives back for
product/design direction rather than weakening the requirement silently.

## Ownership

- **Flutter/Dart:** fullscreen intent, Player state, user-visible availability
  and fallback messaging, input/focus, overlays, accessibility, and telemetry
  projection.
- **Windows native player:** output-capability detection, libmpv output
  configuration, presentation-mode lifecycle, monitor transitions, display
  restoration, and bounded native telemetry.
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
