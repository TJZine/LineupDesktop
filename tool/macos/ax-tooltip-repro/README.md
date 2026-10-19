# Flutter macOS tooltip AX update reproduction

Standalone runtime investigation for [M-04](../../../docs/handoffs/macos-ax-update-investigation.md).
This uses only stock Flutter widgets. It contains no Lineup application code,
media, credentials, plugins, custom semantics nodes, or forced semantics handle.
It does not patch Flutter. Its optional define compares an application workaround
against the failing default.

## Run

Use the repository's pinned Flutter **3.47.7**, Dart **3.13.5**, framework
`abaf9c523780a608bd46686fd5e53740a07077f8`, engine
`deb287481e3ce9468f3434937ced4240a70539ca`. The observed host was arm64,
macOS **27.0.1 (26A434)**. Other versions/platforms are untested.

Create a disposable stock macOS project outside the repository. With
`FLUTTER` pointing to the pinned Flutter executable and the shell initially at
the Lineup repository root:

```sh
REPRO_SOURCE="$PWD/tool/macos/ax-tooltip-repro/main.dart"
REPRO_DIR="$(mktemp -d /tmp/lineup-ax-tooltip.XXXXXX)"
"$FLUTTER" create --platforms=macos --project-name ax_tooltip_repro "$REPRO_DIR"
cp "$REPRO_SOURCE" "$REPRO_DIR/lib/main.dart"
cd "$REPRO_DIR"
"$FLUTTER" analyze lib
"$FLUTTER" build macos --release
build/macos/Build/Products/Release/ax_tooltip_repro.app/Contents/MacOS/ax_tooltip_repro \
  > "$REPRO_DIR/app.log" 2>&1
```

Enable native accessibility for this app using Accessibility Inspector or
VoiceOver. Confirm that the native tree initially exposes the three buttons
and **Tooltip origin**. Enabling Dart semantics alone is not a valid substitute
for activating the native bridge. Then:

1. Select **Show tooltip**. Confirm the native tree includes its tooltip text.
2. Select **Exclude origin**. The origin and tooltip disappear from the native
   tree; the Flutter tooltip widget and visible overlay remain mounted.
3. Select **Change tooltip message**. Inspect `app.log` for:

```text
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: <id> will not be in the tree and is not the new root
```

Node IDs are ephemeral. Native AX can retain the remaining buttons after this
first rejection. More updates can generate pending-node errors or stale repeats
of an earlier error. An intact partial tree does not establish successful updates.
Restore any temporary accessibility setting when finished.

For controls, restart the process between sequences:

- Show → Change message, without excluding the origin: no rejection expected.
- Exclude origin, without showing/updating a tooltip: no rejection expected.
- Show → Exclude origin, without changing the message: no rejection expected.

## Workaround comparison

The default retains the failing behavior. Rebuild the same stock project with:

```sh
"$FLUTTER" build macos --release --dart-define=REPRO_TOOLTIP_VISIBILITY=true
```

Repeat Show → Exclude → Change. This variant coordinates `TooltipVisibility`
with the excluded origin, removing its `RawTooltip` overlay immediately. The
native Release comparison produced zero AX errors after ten message changes;
the default variant rejects the first change. This is an application mitigation,
not a Flutter engine repair. Native accessibility must be active for both runs.

There is also a static-exclusion case. In the disposable copy, initialize
`_excluded` to `true`, rebuild the default variant, establish native AX, then
select Show tooltip. This also rejects an unreachable overlay node. The `296ab905` Lineup
transition guards alone preserve existing visual tooltips inside permanent
content exclusions; the later static-origin correction below addresses that
separate path. Permanently setting
TooltipVisibility to false there would remove the hover feature.

## Static-origin repair comparison

`static_origins.dart` is a separate stock-widget control. Copy it to the disposable
project's `lib/main.dart` instead of `main.dart`. Its default puts a tooltip under
a permanent exclusion, preserving the failing control. Build it with
`--dart-define=REPRO_REACHABLE_ORIGIN=true` to place the tooltip outside the
exclusion of its redundant visual text, beneath the canonical summary. Also add
`--dart-define=REPRO_TRACK_ROW=true` to compare a tooltip around a canonical,
actionable `Semantics(excludeSemantics: true)` row.

Restart between variants and establish healthy native AX before Show. Both
reachable-origin Release variants passed Show → ten message changes → Exclude →
Change → Restore → Show with zero AX error messages. The row's accessible action
also incremented its activation counter. The default rejected Show with an
unreachable-node error. No forced semantics handle or engine modification was
used. The standalone results justified applying equivalent structure to Lineup;
they do not establish spoken output or integrated application acceptance.

## Shared button-origin comparison

`button_origins.dart` reduces a second production trigger, Guide's Now tooltip.
Copy it to the stock project's `lib/main.dart`. Two ordinary Tooltip/TextButton
siblings share an annotated Semantics ancestor. In the default variant, their
portal parent identifiers merge into that ancestor and one identifier is lost.
Show creates a visible overlay whose traversal-child identifier has no matching
origin. A fresh native Release run rejected Show with an unknown-node error.

Build with `--dart-define=REPRO_REACHABLE_ORIGIN=true` to give the second tooltip
an explicit outer semantics container with explicit child nodes. A fresh Release
comparison exposed its full tooltip and preserved its actionable button through
ten activations/message updates with zero AX errors. The canonical button and
hover text both reached version 10. No forced Dart semantics or engine patch was
used. A separate boundary *inside* the tooltip and removing its
`excludeFromSemantics` flag failed the portable control; placement of the origin
boundary matters. Native acceptance of the equivalent Lineup correction remains
a separate gate.

## Captured boundary evidence

[first-rejection.json](first-rejection.json) contains five traced deltas from the
manual prototype, which also had an unused Reset button. Labels, values,
rectangles and flags are omitted. The final three-button source removes that
button and the pass-through tracing; IDs need not match the fixture.

| Batch | Traversal result | Native result |
| --- | --- | --- |
| 1 | Complete root 0; origin 8 reachable | Accepted |
| 2–3 | Tooltip 9 → text 10 grafted under origin 8 | Accepted |
| 4 | Parent 3 drops origin 8; nodes 8, 9, 10 become unreachable | Accepted |
| 5 | Only tooltip text 10 updates; it remains unreachable | Rejected: node 10 is not in the tree |

Before exclusion, text 10 has traversal ancestry
`0 → 1 → 2 → 3 → 8 → 9 → 10`. Overlay 9 is physically attached elsewhere:
node 1 has hit-test children `[9, 2]`, but traversal children `[2]`.
Excluding origin 8 therefore removes traversal reachability while leaving the
overlay physically attached and able to emit another semantics update.

The reachable graph is complete and acyclic throughout. This is not a missing
initial snapshot. Flutter's `dart:ui` semantics update contract says unreachable
nodes are discarded after an update. The common desktop bridge instead forwards
the unreachable record to Chromium's stricter `ui::AXTree` validator.

See the linked investigation for source ownership, controls, exact verification
results, production-evidence limits and the proposed upstream report boundary.


## Slider entering at zero opacity

Copy `slider_fade.dart` into a fresh disposable stock project's `lib/main.dart`
and use the pinned analysis/Release commands above. The committed source contains
only stock Material widgets and an ordinary animation controller: no tracing,
native observer, forced semantics, Lineup imports or engine modification.

Start a fresh process and activate native AX. Confirm the five buttons are
accessible before selecting **Show hidden slider**. That mounts a continuous
Slider under FadeTransition held at zero. The first native error names a new
unreachable full-window empty leaf. Restart before the control: **Show visible
slider** exposes a native Slider at 50% and produced zero AX errors through Quit.
The earlier traced visible-mount → Fade out control also had zero errors after
settling. Do not treat later messages after a failure as independent rejections.

Both a traced prototype and a genuinely uninstrumented stock runner reproduced
the hidden-mount failure after healthy native AX. The uninstrumented failing log
contained two messages through Quit; its separate fresh visible control had zero.
The traced prototype supplies the graph, not the committed uninstrumented source.
Private logs/AX snapshots/manifests stay in `/tmp/lineup-audit/pro-round3/`.
The same Flutter/framework/engine/host identities above apply:

| Artifact | SHA-256 |
| --- | --- |
| Committed uninstrumented `slider_fade.dart` | `2925064e9b23769c83d4ee0d3818db09867963dd2af7b1214ba3c2d815b4ad07` |
| Uninstrumented App.framework binary | `963ea5ba748f688cf113baed05e23bd11b9e424f86dc0902174b6188f3252156` |
| Traced prototype App.framework binary | `a467acd63b8b271dace824fe278f4708b697f0573c24d2f02563aee42d0aa0af` |
| Shared stock FlutterMacOS engine binary | `4c12bce183913ecdb95335257cce0cd0bfd27b37a7ff4d42f7a51203e2382445` |

[slider-first-rejection.json](slider-first-rejection.json) compares the captured
production graph (new node 378/portal token 97) with the traced stock graph (new
node 9/token 1). Both add a physically attached portal leaf whose effective origin
is missing. These are sanitized graph observations, not a native replay payload.
The production widget identity is a strong source correlation with the entering
DVR Slider; the Release trace does not directly name that widget instance.

This is another stock framework/desktop-bridge interoperability case. It does
not establish every historical M-04 cause. Do not apply alwaysIncludeSemantics
or remove visual animation globally merely to avoid the error. The investigation
records a proposed Slider-lifetime experiment and its hidden-control/retirement
risks; no application workaround for this new trigger is included.

## Local Slider overlay containment comparison

`slider_containment.dart` is a separate bounded experiment, preserving the
original `slider_fade.dart` failing source. Copy it into a disposable stock
project's `lib/main.dart`. The default uses the route's overlay; build again with
`--dart-define=REPRO_LOCAL_OVERLAY=true` to put only SliderTheme/Slider under
`Overlay.wrap(clipBehavior: Clip.none)`. Both variants have the same finite
40-pixel Stack and separate visible 4-pixel progress line, matching the relevant
Player structure. No Lineup imports, media, forced semantics or engine changes
are required. This source is **not a product mitigation**.

Restart before each fresh-mount control and establish healthy native AX before
Show. On the same pinned framework/engine/host listed above, the controller's
2026-10-19 Release comparison observed:

| Variant / separate process | Observation |
| --- | --- |
| Default, Show hidden slider | First native AX error: node 13 is not in the tree/new root; one error message through Quit. |
| Default, Show visible slider | Native Slider 50%; zero AX error messages through Quit. |
| Local overlay, Show hidden slider | Slider absent while hidden; value update then Fade in exposes 60%. Exclude → value update → Restore exposes 70%. Rapid Fade out/in and removal complete; zero AX error messages through Quit. |
| Local overlay, Show visible slider | Native Slider 50%; Fade out → value update removes Slider, Fade in → value update restores it at 70%; zero AX error messages through Quit. |

These runs used stock framework/engine binaries and stock widget source. Their
otherwise stock native runner added **stderr redirection only**, into its sandbox
temporary directory, to capture bridge errors while CUA launched the app. It did
not observe or alter semantics, input or native callbacks. These binaries are
distinct from the earlier genuinely uninstrumented Slider controls. Runtime
source SHA-256 was `501da191c41864a3fab625c18b88150bb0d1fb71dd622cb65e836b322da676d5`;
the committed copy adds only explanatory comments. Local-overlay App.framework
SHA-256 was `8298853078519f56b3a7c1009fe020f63d2b026894c8377dac22f37c49d5f5e6`;
default was `f3ebc03021f2836ded91c696e1902225c46aba086481ada5f78947731fea0aa6`.
Raw logs/source/bundles and result manifests are private under
`/tmp/lineup-audit/pro-round4/`.

Containment is promising for these sequences, **not accepted as a complete fix**.
No outgoing-delta graph was captured in this comparison, and accessibility
notification delivery was not directly observed. Keyboard/drag/focus preservation,
matched geometry/text scaling, menu during entry, route replacement and integrated
DVR insertion/removal remain unverified. The CUA screenshot was unusable for
geometry and attempted Slider click/Right/Tab did not establish keyboard focus or
adjustment; do not count them as passes. No Lineup Slider patch is included. See
the [Opus handoff](../../../docs/handoffs/macos-m04-opus-review-handoff.md) for the
remaining challenge and acceptance matrix.

## Synthetic Command+A control

`keyboard.dart` is an independent MaterialApp → Scaffold → TextField probe with a
synthetic 16-character seed. Copy it into the stock project's `lib/main.dart`.
Its pass-through HardwareKeyboard handler logs only lengths, selection, focus,
modifier state and allowlisted diagnostic key IDs; it does not log typed text.

Focus the field, request synthetic Command+A through the same automation surface,
then type two synthetic replacement characters. In the observed stock probe,
selection stayed collapsed at 16 and input appended to lengths 17/18; Dart's A
had Meta false. A temporary native pass-through observer separately recorded
combined-only Command flags, missing sided bits and keyCode 0 for flagsChanged.
That observer is not needed in this source to observe selection/Dart state, but
its native correlation is not supplied by this committed probe alone.

This reproduces outside Lineup and supports a synthetic-event/embedder conversion
compatibility diagnosis. Physical Command+A was not captured; it remains a human
check. No Lineup shortcut or engine workaround is proposed. See the investigation
for the pinned responder's sided-modifier mechanism and the distinct rapid menu
focus race; do not classify all historical Clear failures from this one control.
