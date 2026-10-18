import 'package:flutter/material.dart';

const _reachableOrigin = bool.fromEnvironment('REPRO_REACHABLE_ORIGIN');

void main() => runApp(const MaterialApp(home: ButtonOriginRepro()));

/// Two stock tooltip buttons share an annotated semantics ancestor. Without a
/// separate origin boundary, their portal parent identifiers can collapse.
class ButtonOriginRepro extends StatefulWidget {
  const ButtonOriginRepro({super.key});

  @override
  State<ButtonOriginRepro> createState() => _ButtonOriginReproState();
}

class _ButtonOriginReproState extends State<ButtonOriginRepro> {
  final _tooltip = GlobalKey<TooltipState>();
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final tooltip = Tooltip(
      key: _tooltip,
      message: 'Full hover title $_version',
      excludeFromSemantics: true,
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(hours: 1),
      enableTapToDismiss: false,
      child: TextButton(
        onPressed: () => setState(() => _version++),
        child: Text('Visual title $_version'),
      ),
    );
    final origin = _reachableOrigin
        ? Semantics(container: true, explicitChildNodes: true, child: tooltip)
        : tooltip;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: Semantics(
          label: 'Shared non-button content',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: 'Competing origin',
                excludeFromSemantics: true,
                child: TextButton(
                  onPressed: () =>
                      _tooltip.currentState!.ensureTooltipVisible(),
                  child: const Text('Show tooltip'),
                ),
              ),
              origin,
            ],
          ),
        ),
      ),
    );
  }
}
