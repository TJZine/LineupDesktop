import 'package:flutter/material.dart';

const _reachableOrigin = bool.fromEnvironment('REPRO_REACHABLE_ORIGIN');
const _row = bool.fromEnvironment('REPRO_TRACK_ROW');

void main() => runApp(const MaterialApp(home: StaticOriginRepro()));

/// Stock-widget comparison of a permanently excluded tooltip and a reachable
/// origin with one canonical label. Native accessibility must be activated.
class StaticOriginRepro extends StatefulWidget {
  const StaticOriginRepro({super.key});

  @override
  State<StaticOriginRepro> createState() => _StaticOriginReproState();
}

class _StaticOriginReproState extends State<StaticOriginRepro> {
  final _tooltip = GlobalKey<TooltipState>();
  int _version = 0;
  int _activations = 0;
  bool _excluded = false;

  @override
  Widget build(BuildContext context) {
    final visual = Text('Visual title $_version');
    final canonical = 'Complete canonical title $_version';
    final tooltip = Tooltip(
      key: _tooltip,
      message: 'Full hover title $_version',
      excludeFromSemantics: true,
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(hours: 1),
      enableTapToDismiss: false,
      child: _reachableOrigin
          ? _row
                ? Semantics(
                    label: canonical,
                    button: true,
                    selected: true,
                    onTap: () => setState(() => _activations++),
                    excludeSemantics: true,
                    child: visual,
                  )
                : ExcludeSemantics(child: visual)
          : visual,
    );
    final origin = _row && _reachableOrigin
        ? tooltip
        : Semantics(
            label: canonical,
            explicitChildNodes: true,
            child: _reachableOrigin
                ? tooltip
                : ExcludeSemantics(child: tooltip),
          );
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () => _tooltip.currentState!.ensureTooltipVisible(),
              child: const Text('Show tooltip'),
            ),
            ElevatedButton(
              onPressed: () => setState(() => _version++),
              child: const Text('Change tooltip message'),
            ),
            ElevatedButton(
              onPressed: () => setState(() => _excluded = !_excluded),
              child: Text(_excluded ? 'Restore origin' : 'Exclude origin'),
            ),
            Text('Activations: $_activations'),
            const SizedBox(height: 40),
            ExcludeSemantics(
              excluding: _excluded,
              child: TooltipVisibility(visible: !_excluded, child: origin),
            ),
          ],
        ),
      ),
    );
  }
}
