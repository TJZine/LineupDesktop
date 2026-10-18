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
