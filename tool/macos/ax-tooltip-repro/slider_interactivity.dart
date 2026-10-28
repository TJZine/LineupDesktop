import 'package:flutter/material.dart';

const keyed = bool.fromEnvironment('REPRO_KEYED_OVERLAY');
const initiallyDisabled = bool.fromEnvironment('REPRO_INITIALLY_DISABLED');

void main() => runApp(const MaterialApp(home: SliderInteractivityRepro()));

/// Compare local-overlay lifetime across visible Slider interactivity changes.
/// Establish healthy native AX before the first transition in each fresh run.
class SliderInteractivityRepro extends StatefulWidget {
  const SliderInteractivityRepro({super.key});

  @override
  State<SliderInteractivityRepro> createState() =>
      _SliderInteractivityReproState();
}

class _SliderInteractivityReproState extends State<SliderInteractivityRepro> {
  bool _enabled = !initiallyDisabled;
  double _value = .5;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(keyed ? 'Keyed local overlay' : 'Stable local overlay'),
        TextButton(
          onPressed: () => setState(() => _enabled = !_enabled),
          child: Text(_enabled ? 'Disable slider' : 'Enable slider'),
        ),
        TextButton(
          onPressed: () => setState(() => _value = (_value + .1) % 1),
          child: const Text('Change value'),
        ),
        Text(_enabled ? 'Slider enabled' : 'Slider disabled'),
        const Spacer(),
        SizedBox(
          height: 40,
          child: Semantics(
            label: 'Playback progress',
            child: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(value: _value),
                  ),
                ),
                Overlay.wrap(
                  key: keyed ? ValueKey(_enabled) : null,
                  clipBehavior: Clip.none,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: _value,
                      onChanged: _enabled
                          ? (value) => setState(() => _value = value)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
