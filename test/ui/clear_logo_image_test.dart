import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  testWidgets(
    'OSD rejects tiny visible, tall, empty and broken title artwork',
    (tester) async {
      final cases = <(Size, Rect?, bool)>[
        (const Size(600, 120), const Rect.fromLTWH(0, 0, 600, 120), true),
        (const Size(600, 120), const Rect.fromLTWH(240, 50, 100, 12), false),
        (const Size(100, 600), const Rect.fromLTWH(0, 0, 100, 600), false),
        (const Size(2400, 40), const Rect.fromLTWH(0, 0, 2400, 40), false),
        (const Size(600, 120), null, false),
      ];
      for (final (size, visible, accepted) in cases) {
        final bytes = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          if (visible != null) {
            canvas.drawRect(visible, Paint()..color = Colors.white);
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return data!.buffer.asUint8List();
        });
        await _show(tester, bytes!);
        expect(
          find.byKey(const Key('accepted-logo')),
          accepted ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Readable title'),
          accepted ? findsNothing : findsOneWidget,
        );
      }
      await _show(tester, Uint8List.fromList([1, 2, 3]));
      expect(find.text('Readable title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _show(WidgetTester tester, Uint8List bytes) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.centerLeft,
        child: ClearLogoImage(
          bytes,
          maximumSize: const Size(420, 84),
          minimumVisibleSize: const Size(96, 28),
          imageKey: const Key('accepted-logo'),
          fallback: const Text('Readable title'),
        ),
      ),
    ),
  );
  // Image decoding happens on the engine outside the fake widget-test clock.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}
