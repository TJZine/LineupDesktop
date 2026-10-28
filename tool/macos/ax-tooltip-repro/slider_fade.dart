import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: SliderFadeRepro()));

/// Stock Slider creates its value-indicator OverlayPortal immediately.
/// Mounting it under zero opacity omits the origin from semantics while the
/// overlay child remains physically attached to the route's ancestor Overlay.
class SliderFadeRepro extends StatefulWidget {
  const SliderFadeRepro({super.key});

  @override
  State<SliderFadeRepro> createState() => _SliderFadeReproState();
}

class _SliderFadeReproState extends State<SliderFadeRepro>
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
  bool _present = false;
  double _value = .5;

  void _show(double opacity) {
    _opacity.stop();
    _opacity.value = opacity;
    setState(() => _present = true);
  }

  @override
  void dispose() {
    _fade.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
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
          onPressed: _present ? () => _opacity.forward() : null,
          child: const Text('Fade in'),
        ),
        TextButton(
          onPressed: _present ? () => _opacity.reverse() : null,
          child: const Text('Fade out'),
        ),
        TextButton(
          onPressed: () {
            _opacity.stop();
            setState(() => _present = false);
          },
          child: const Text('Remove slider'),
        ),
        Expanded(
          child: _present
              ? FadeTransition(
                  opacity: _fade,
                  child: Slider(
                    value: _value,
                    onChanged: (value) => setState(() => _value = value),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
}
