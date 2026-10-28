import 'package:flutter/material.dart';

const contained = bool.fromEnvironment('REPRO_LOCAL_OVERLAY');
void main() => runApp(const MaterialApp(home: SliderRetirementRepro()));

/// Reproduces the production AnimatedSwitcher retirement wrapper with stock
/// widgets. Native accessibility must be healthy before retiring the Slider.
class SliderRetirementRepro extends StatefulWidget {
  const SliderRetirementRepro({super.key});
  @override
  State<SliderRetirementRepro> createState() => _SliderRetirementReproState();
}

class _SliderRetirementReproState extends State<SliderRetirementRepro> {
  bool _visible = true;
  double _value = .5;

  @override
  Widget build(BuildContext context) {
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbShape: SliderComponentShape.noThumb,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        value: _value,
        onChanged: (value) => setState(() => _value = value),
      ),
    );
    return Scaffold(
      body: Column(
        children: [
          Text(contained ? 'Local overlay' : 'Ancestor overlay'),
          TextButton(
            onPressed: () => setState(() => _visible = false),
            child: const Text('Retire visible slider'),
          ),
          TextButton(
            onPressed: () => setState(() => _visible = true),
            child: const Text('Restore slider'),
          ),
          TextButton(
            onPressed: () => setState(() => _value = (_value + .1) % 1),
            child: const Text('Change value'),
          ),
          Text('Value ${(_value * 100).round()} percent'),
          const Spacer(),
          SizedBox(
            height: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              reverseDuration: const Duration(milliseconds: 350),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previousChildren)
                    ExcludeFocus(
                      child: ExcludeSemantics(
                        child: TooltipVisibility(visible: false, child: child),
                      ),
                    ),
                  ?currentChild,
                ],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                  reverseCurve: Curves.easeIn,
                ),
                child: child,
              ),
              child: _visible
                  ? Stack(
                      key: const ValueKey('slider'),
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(value: _value),
                          ),
                        ),
                        if (contained)
                          Overlay.wrap(clipBehavior: Clip.none, child: slider)
                        else
                          slider,
                      ],
                    )
                  : const SizedBox.expand(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }
}
