import 'dart:async';
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
  testWidgets(
    'visible height cap is opt-in and retains minimum artwork guards',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 600, 120),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(600, 120);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      await _show(tester, bytes!);
      expect(tester.getSize(find.byType(ClearLogoImage)).height, 84);
      await _show(tester, bytes, maximumVisibleHeight: 56);
      expect(find.byKey(const Key('accepted-logo')), findsOneWidget);
      expect(tester.getSize(find.byType(ClearLogoImage)), const Size(280, 56));
      await _show(
        tester,
        bytes,
        maximumVisibleHeight: 56,
        minimumVisibleSize: const Size(300, 28),
      );
      expect(find.byKey(const Key('accepted-logo')), findsNothing);
      expect(find.text('Readable title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('intrinsic logo probing releases a cold image handle', (
    tester,
  ) async {
    final referenceHandles = await _measureColdReferenceHandles(
      tester,
      await _solidLogoBytes(tester, size: const Size(620, 120)),
    );
    final bytes = await _solidLogoBytes(tester);
    final stream = MemoryImage(bytes).resolve(const ImageConfiguration());
    ImageInfo? captured;
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (captured != null) {
        info.dispose();
      } else {
        captured = info;
      }
    });
    stream.addListener(listener);
    var listenerRemoved = false;
    try {
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
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      stream.removeListener(listener);
      listenerRemoved = true;
      await _clearImageCache(tester);

      expect(captured, isNotNull);
      expect(
        captured!.image.debugGetOpenHandleStackTraces()!.length,
        referenceHandles,
      );
    } finally {
      if (!listenerRemoved) stream.removeListener(listener);
      captured?.dispose();
      await _clearImageCache(tester);
    }
  });

  testWidgets(
    'intrinsic logo probing releases cached handles across replacement',
    (tester) async {
      final referenceHandles = await _measureColdReferenceHandles(
        tester,
        await _solidLogoBytes(tester, size: const Size(620, 120)),
      );
      final firstBytes = await _solidLogoBytes(tester);
      final replacementBytes = await _solidLogoBytes(
        tester,
        size: const Size(480, 120),
      );
      await _show(tester, firstBytes);
      final captured = await _captureImageInfo(firstBytes);
      try {
        await _show(tester, replacementBytes);
        await _show(tester, firstBytes);
        await _show(tester, replacementBytes);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _clearImageCache(tester);

        expect(
          captured.image.debugGetOpenHandleStackTraces()!.length,
          referenceHandles,
        );
      } finally {
        captured.dispose();
        await _clearImageCache(tester);
      }
    },
  );
}

Future<int> _measureColdReferenceHandles(
  WidgetTester tester,
  Uint8List bytes,
) async {
  final stream = MemoryImage(bytes).resolve(const ImageConfiguration());
  ImageInfo? captured;
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    if (captured != null) {
      info.dispose();
    } else {
      captured = info;
    }
  });
  stream.addListener(listener);
  var listenerRemoved = false;
  try {
    for (var i = 0; i < 4 && captured == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    expect(captured, isNotNull);
    stream.removeListener(listener);
    listenerRemoved = true;
    await _clearImageCache(tester);
    return captured!.image.debugGetOpenHandleStackTraces()!.length;
  } finally {
    if (!listenerRemoved) stream.removeListener(listener);
    captured?.dispose();
    await _clearImageCache(tester);
  }
}

Future<Uint8List> _solidLogoBytes(
  WidgetTester tester, {
  Size size = const Size(600, 120),
}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(Offset.zero & size, Paint()..color = Colors.white);
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
  return bytes!;
}

Future<ImageInfo> _captureImageInfo(Uint8List bytes) async {
  final stream = MemoryImage(bytes).resolve(const ImageConfiguration());
  final delivered = Completer<ImageInfo>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    if (delivered.isCompleted) {
      info.dispose();
    } else {
      delivered.complete(info);
    }
  });
  stream.addListener(listener);
  try {
    return await delivered.future;
  } finally {
    stream.removeListener(listener);
  }
}

Future<void> _clearImageCache(WidgetTester tester) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  await tester.pump();
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  Uint8List bytes, {
  double? maximumVisibleHeight,
  Size minimumVisibleSize = const Size(96, 28),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.centerLeft,
        child: ClearLogoImage(
          bytes,
          maximumSize: const Size(420, 84),
          minimumVisibleSize: minimumVisibleSize,
          maximumVisibleHeight: maximumVisibleHeight,
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
