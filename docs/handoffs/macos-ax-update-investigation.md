# macOS accessibility update investigation — M-04

Status: **unresolved**. This follows the [macOS discovery audit](macos-app-audit-report.md).
The Dart repairs for M-02/M-03 address directory semantics boundaries and icon
names separately. They do not establish that M-04 is fixed. The corrected
Release candidate `1b2f64f4` subsequently reproduced M-04 as recorded below.

## Recorded failure and toolchain

The original local `/tmp/lineup-audit/app.log` contains **1,508** failures:

- 1,218: `Nodes left pending by the update: <node id>`.
- 290: `<node id> will not be in the tree and is not the new root`.
- First, line 71: `Failed to update ui::AXTree, error: 2026 will not be in the tree and is not the new root`.
- Last, line 2066: the same removed-node error for node 490.

Every occurrence was logged from `flutter/shell/platform/common/accessibility_bridge.cc(114)`.
Node IDs are ephemeral semantics identifiers. Raw logs remain local.
The audit reproduced bursts during Guide/Player overlays and management navigation,
including returning from Settings after enabling DVR and revealing controls.

| Input | Identity |
| --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 |
| Framework | `abaf9c523780a608bd46686fd5e53740a07077f8` |
| Engine | `deb287481e3ce9468f3434937ced4240a70539ca` |
| Host | arm64, macOS 27.0.1 (26A434) |
| Original audit app | `platform/macos`, `fa1760872ffc69dd61644cb09e0b0a64a130f5f4`, Release |

## Corrected-candidate production reproduction

The unchanged real Release bundle at `1b2f64f4` reproduced the bridge failure:

1. Complete startup with existing state; obtain the native Guide AX tree.
2. Enter native fullscreen from Guide before any media load.
3. Select a currently airing program, then reveal Now Playing with `I`.
4. Inspect the native tree and stderr; the visible overlay remains rendered,
   while the tree can collapse to its application container.
5. Navigate through Settings/Channels and back to Player; some full trees recover,
   including corrected icon names, but later transition errors continue.

In `/tmp/lineup-audit/post-fix-app.log`, line 19 is the first rejected update
(removed node 134); line 678 is the last (removed node 569). The completed run
contains **614** errors: **373** pending-node and **241** removed-node failures.
It exited through native Quit with completed libmpv shutdown. The first-tune
status/pause fix passed separately; video playback did not establish AX health.
Native directory, Player-return and Guide snapshots exposed the repaired
controls between bursts. Thus M-02/M-03 had real effects while M-04 remained.

This is a short reproducible **production sequence**, not a standalone engine
reproducer. The media-free reduction below still returned a negative result;
the first invalid semantics delta remains the missing discriminating evidence.

## Source evidence and limit

Paths below are relative to the pinned Flutter SDK's `engine/src/flutter/`:

- `shell/platform/common/accessibility_bridge.cc:50–124`: `CommitUpdates()`
  computes reparent removals and ordered updates, calls `tree_->Unserialize(update)`,
  clears pending updates, then logs the tree error and returns before dispatching
  accessibility events. Line 114 emits the observed message.
- The same file, lines 214–280, constructs reparent-removal and parent-before-child
  updates.
- `third_party/accessibility/ax/ax_tree.cc:1330–1350` rejects a node update whose
  ID will not exist in the updated tree and is not its new root.
- The same file, lines 1779–1787, rejects nodes left pending after an update.

This locates the observed failure at the Flutter semantics-to-native AX boundary.
It does not identify the first invalid delta, establish an engine-only cause, or
link the directory/name issues causally to M-04. No engine patch was applied.

## Minimal attempted reduction — negative result

A disposable Flutter macOS application forced semantics on and scheduled 200
swaps, 350 ms apart, using 200 ms `AnimatedSwitcher` transitions. It retained the
app's outgoing-child `ExcludeFocus(ExcludeSemantics(...))` pattern, a directory
TextField/buttons and a tooltip-only icon, without media or production data.
The formatted source below is the executed attempt, with formatting-only changes:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  runApp(const MaterialApp(home: Repro()));
}

class Repro extends StatefulWidget {
  const Repro({super.key});
  @override
  State<Repro> createState() => _ReproState();
}

class _ReproState extends State<Repro> {
  int phase = 0;
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      setState(() => phase++);
      if (phase == 200) timer.cancel();
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        const Center(child: Text('Background')),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            children: [
              for (final child in previousChildren)
                ExcludeFocus(child: ExcludeSemantics(child: child)),
              if (currentChild != null) currentChild,
            ],
          ),
          child: phase % 3 == 0
              ? Center(key: ValueKey(phase), child: const Text('Player'))
              : phase % 3 == 1
              ? Center(
                  key: ValueKey(phase),
                  child: Column(
                    children: [
                      const TextField(
                        decoration: InputDecoration(
                          hintText: 'Search channels',
                        ),
                      ),
                      for (int i = 0; i < 10; i++)
                        FilledButton(
                          onPressed: () {},
                          child: Text('Channel $i'),
                        ),
                    ],
                  ),
                )
              : Center(
                  key: ValueKey(phase),
                  child: IconButton(
                    tooltip: 'Pause',
                    onPressed: () {},
                    icon: const Icon(Icons.pause),
                  ),
                ),
        ),
      ],
    ),
  );
}
```

To recreate, create the disposable project, save the source above as `lib/main.dart`,
then build and launch it. Use the pinned Flutter executable:

```sh
FLUTTER=/Users/tristan/.cache/lineup-flutter/3.47.7/flutter/bin/flutter
"$FLUTTER" create --platforms=macos --project-name lineup_ax_repro \
  --org dev.lineup.audit /tmp/lineup-audit/ax-repro
cd /tmp/lineup-audit/ax-repro
# Save the source above as lib/main.dart before building.
"$FLUTTER" build macos --release
open -n build/macos/Build/Products/Release/lineup_ax_repro.app \
  --stdout /tmp/lineup-audit/ax-repro-open.log \
  --stderr /tmp/lineup-audit/ax-repro-open.log
```

**Observed result: zero AXTree errors across the 200 scheduled transitions.** The
app was stopped afterward. This attempt did not reproduce M-04 and establishes
no fix or successful workaround. Original source and output remain local at
`/tmp/lineup-audit/ax-repro/lib/overlay_attempt.dart`, `ax-repro-build.log` and
`ax-repro-open.log`. A later static directory experiment was prepared but not
launched and supplies no additional native evidence.

## Follow-up proposal

The corrected-candidate run confirmed that the failure persists through playback,
Guide/Player overlays and management navigation. The next useful evidence is an
upstream-ready reduction with the first rejected delta; repeating the same broad
route sweep would not identify its owner. Widget tests alone cannot close M-04.

Prepare an upstream Flutter investigation draft with the identities,
sanitized error strings and sequence above. Capture the semantics delta immediately
before the **first** rejected native update on synthetic content: node IDs,
parent/child ordering, roles and flags, with all labels scrubbed. Reduce that
transition into a media-free reproducible project. Describe the current minimal
attempt explicitly as non-reproducing.

A Flutter-version comparison or semantics-subtree recreation is a possible
isolated workaround experiment after identifying the triggering transition;
neither is established or applied here. Restart did not prevent recurrence in
the audit. No engine patch, upstream publication or successful runtime acceptance
is claimed by this investigation.
