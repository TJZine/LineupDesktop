import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/focus_ink.dart';

void main() {
  testWidgets(
    'header shape scales paint to zero and follows null interpolation',
    (tester) async {
      final shapes = <String, ShapeBorder>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            androidTv: true,
            largeFocusIndicators: true,
          ),
          home: Builder(
            builder: (context) {
              final shape = LineupFocusFrame.shape(context, focused: true)!;
              shapes.addAll({
                'zero': shape.scale(0),
                'half': shape.scale(.5),
                'one': shape.scale(1),
                'lerpZero': ShapeBorder.lerp(null, shape, 0)!,
                'lerpHalf': ShapeBorder.lerp(null, shape, .5)!,
              });
              return Column(
                children: [
                  for (final entry in shapes.entries)
                    RepaintBoundary(
                      key: ValueKey(entry.key),
                      child: SizedBox(
                        width: 160,
                        height: 60,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(shape: entry.value),
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
      await tester.runAsync(() async {
        final pixels = <String, List<int>>{};
        for (final key in shapes.keys) {
          expect(shapes[key]!.dimensions, EdgeInsets.zero);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(ValueKey(key)),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          pixels[key] = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          image.dispose();
        }
        expect(pixels['zero']!.every((byte) => byte == 0), isTrue);
        expect(pixels['lerpZero'], orderedEquals(pixels['zero']!));
        expect(pixels['lerpHalf'], orderedEquals(pixels['half']!));
        int alpha(List<int> bytes) {
          var total = 0;
          for (var i = 3; i < bytes.length; i += 4) {
            total += bytes[i];
          }
          return total;
        }

        expect(alpha(pixels['half']!), greaterThan(0));
        expect(alpha(pixels['half']!), lessThan(alpha(pixels['one']!)));
      });
    },
  );
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
