import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: TooltipRepro()));
}

/// Standalone Flutter runtime probe. No Lineup code or forced semantics.
class TooltipRepro extends StatefulWidget {
  const TooltipRepro({super.key});

  @override
  State<TooltipRepro> createState() => _TooltipReproState();
}

class _TooltipReproState extends State<TooltipRepro> {
  final _tooltip = GlobalKey<TooltipState>();
  bool _excluded = false;
  int _messageVersion = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
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
            onPressed: () => setState(() => _excluded = true),
            child: const Text('Exclude origin'),
          ),
          ElevatedButton(
            onPressed: () => setState(() => _messageVersion++),
            child: const Text('Change tooltip message'),
          ),
          const SizedBox(height: 40),
          ExcludeSemantics(
            excluding: _excluded,
            child: Tooltip(
              key: _tooltip,
              message: 'Tooltip message $_messageVersion',
              triggerMode: TooltipTriggerMode.manual,
              showDuration: const Duration(hours: 1),
              enableTapToDismiss: false,
              child: const SizedBox(
                width: 320,
                height: 64,
                child: Text('Tooltip origin'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
