import 'package:flutter/material.dart';

// Compare identical finite-height progress geometry with Slider's portal hosted
// by either the route overlay (default) or a local overlay under the same fade
// and exclusion ancestors. This is an experiment, not a product mitigation.
const contained = bool.fromEnvironment('REPRO_LOCAL_OVERLAY');
void main() => runApp(const MaterialApp(home: SliderContainmentRepro()));

class SliderContainmentRepro extends StatefulWidget {
  const SliderContainmentRepro({super.key});
  @override
  State<SliderContainmentRepro> createState() => _SliderContainmentReproState();
}

class _SliderContainmentReproState extends State<SliderContainmentRepro>
    with SingleTickerProviderStateMixin {
  late final _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final _fade = CurvedAnimation(
    parent: _opacity,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );
  final _focus = FocusNode(debugLabel: 'Progress slider');
  bool _present = false;
  bool _excluded = false;
  double _value = .5;
  void _show(double alpha) {
    _opacity.stop();
    _opacity.value = alpha;
    setState(() => _present = true);
  }

  @override
  void dispose() {
    _focus.dispose();
    _fade.dispose();
    _opacity.dispose();
    super.dispose();
  }

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
        focusNode: _focus,
        value: _value,
        onChanged: (value) => setState(() => _value = value),
      ),
    );
    return Scaffold(
      body: Column(
        children: [
          Text(contained ? 'Local overlay' : 'Ancestor overlay'),
          Wrap(
            children: [
              TextButton(
                onPressed: () => _show(0),
                child: const Text('Show hidden slider'),
              ),
              TextButton(
                onPressed: () => _show(1),
                child: const Text('Show visible slider'),
              ),
              TextButton(
                onPressed: () => _opacity.forward(),
                child: const Text('Fade in'),
              ),
              TextButton(
                onPressed: () => _opacity.reverse(),
                child: const Text('Fade out'),
              ),
              TextButton(
                onPressed: () => setState(() => _excluded = !_excluded),
                child: Text(_excluded ? 'Restore origin' : 'Exclude origin'),
              ),
              TextButton(
                onPressed: () => setState(() => _value = (_value + .1) % 1),
                child: const Text('Change value'),
              ),
              TextButton(
                onPressed: () => setState(() => _present = false),
                child: const Text('Remove slider'),
              ),
            ],
          ),
          Text('Value ${(_value * 100).round()} percent'),
          const Spacer(),
          if (_present)
            ExcludeFocus(
              excluding: _excluded,
              child: ExcludeSemantics(
                excluding: _excluded,
                child: IgnorePointer(
                  ignoring: _excluded,
                  child: FadeTransition(
                    opacity: _fade,
                    child: SizedBox(
                      height: 40,
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
                          if (contained)
                            Overlay.wrap(clipBehavior: Clip.none, child: slider)
                          else
                            slider,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
