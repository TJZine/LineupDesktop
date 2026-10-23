import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/focus_ink.dart';

void main() {
  for (final name in LineupThemeName.values) {
    testWidgets(
      '$name header shape is zero-inset and matches the existing focus frame pixels',
      (tester) async {
        ShapeBorder? shape;
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              name,
              androidTv: true,
              largeFocusIndicators: true,
            ),
            home: Builder(
              builder: (context) {
                shape = LineupFocusFrame.shape(context, focused: true);
                return Column(
                  children: [
                    const RepaintBoundary(
                      key: ValueKey('frame'),
                      child: LineupFocusFrame(
                        focused: true,
                        child: SizedBox(width: 200, height: 100),
                      ),
                    ),
                    RepaintBoundary(
                      key: const ValueKey('shape'),
                      child: SizedBox(
                        width: 200,
                        height: 100,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(shape: shape!),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pump();
        expect(shape!.dimensions, EdgeInsets.zero);
        await tester.runAsync(() async {
          final images = <ui.Image>[];
          for (final key in ['frame', 'shape']) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(ValueKey(key)),
            );
            images.add(await boundary.toImage(pixelRatio: 1));
          }
          final frame = await images[0].toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final header = await images[1].toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(
            header!.buffer.asUint8List(),
            orderedEquals(frame!.buffer.asUint8List()),
          );
          for (final image in images) {
            image.dispose();
          }
        });
      },
    );
  }
  for (final (tv, large, focused) in [
    (false, true, true),
    (true, false, true),
    (true, true, false),
  ]) {
    testWidgets(
      'header shape leaves ordinary shape untouched: tv=$tv large=$large focused=$focused',
      (tester) async {
        ShapeBorder? shape;
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              androidTv: tv,
              largeFocusIndicators: large,
            ),
            home: Builder(
              builder: (context) {
                shape = LineupFocusFrame.shape(context, focused: focused);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(shape, isNull);
      },
    );
  }
}
