import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

void main() {
  tearDown(debugResetClearLogoCache);

  testWidgets('decode settlement handles empty, pending and completed caches', (
    tester,
  ) async {
    await tester.runAsync(clearLogoDecodesSettled);

    final bytes = await _solidLogoBytes(tester);
    await tester.pumpWidget(_logoApp(bytes));
    expect(find.text('Readable title'), findsOneWidget);
    expect(find.byKey(const Key('accepted-logo')), findsNothing);

    await tester.runAsync(clearLogoDecodesSettled);
    await tester.pump();
    final image = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    expect(image.debugDisposed, isFalse);
    expect(find.text('Readable title'), findsNothing);

    await tester.runAsync(clearLogoDecodesSettled);
    expect(tester.takeException(), isNull);
  });

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
  testWidgets('desktop rejects empty alpha and keeps padded contain geometry', (
    tester,
  ) async {
    await _show(
      tester,
      await _transparentLogoBytes(tester),
      minimumVisibleSize: null,
    );
    expect(find.byKey(const Key('accepted-logo')), findsNothing);
    expect(find.text('Readable title'), findsOneWidget);
    final padded = await _rasterLogoBytes(
      tester,
      visible: const Rect.fromLTWH(160, 20, 280, 80),
    );
    await _show(tester, padded, minimumVisibleSize: null);
    expect(
      tester.getSize(find.byKey(const Key('accepted-logo'))),
      const Size(420, 84),
    );
    expect(
      _containsLogoColor(await _captureRenderedLogo(tester), Colors.white),
      isTrue,
    );
  });

  testWidgets(
    'replacement never publishes stale artwork, including warm bytes',
    (tester) async {
      final first = await _rasterLogoBytes(
        tester,
        color: const Color(0xFFFA2A8A),
        visible: const Rect.fromLTWH(0, 0, 600, 120),
      );
      final replacement = await _rasterLogoBytes(
        tester,
        color: const Color(0xFF2AFA8A),
        visible: const Rect.fromLTWH(0, 0, 600, 120),
      );
      await _show(tester, first, minimumVisibleSize: null);
      final previous = tester
          .widget<RawImage>(find.byKey(const Key('accepted-logo')))
          .image!;
      await tester.pumpWidget(
        _logoApp(Uint8List.fromList(first), minimumVisibleSize: null),
      );
      expect(find.text('Readable title'), findsOneWidget);
      await tester.pumpWidget(_logoApp(replacement, minimumVisibleSize: null));
      expect(find.text('Readable title'), findsOneWidget);
      expect(previous.debugDisposed, isTrue);
      await _waitForImageDecode(tester);
      expect(
        _containsLogoColor(
          await _captureRenderedLogo(tester),
          const Color(0xFF2AFA8A),
        ),
        isTrue,
      );
      expect(
        _containsLogoColor(
          await _captureRenderedLogo(tester),
          const Color(0xFFFA2A8A),
        ),
        isFalse,
      );
      await _show(tester, first, minimumVisibleSize: null);
      expect(
        _containsLogoColor(
          await _captureRenderedLogo(tester),
          const Color(0xFFFA2A8A),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('size buckets and DPR own and release their raster handles', (
    tester,
  ) async {
    final bytes = await _solidLogoBytes(tester);
    await _show(tester, bytes);
    final first = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    await tester.pumpWidget(_logoApp(bytes, maximumSize: const Size(421, 85)));
    expect(
      tester.widget<RawImage>(find.byKey(const Key('accepted-logo'))).image,
      same(first),
    );
    await tester.pumpWidget(_logoApp(bytes, maximumSize: const Size(300, 60)));
    expect(find.text('Readable title'), findsOneWidget);
    expect(first.debugDisposed, isTrue);
    await _waitForImageDecode(tester);
    final resized = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    expect(resized.width, lessThanOrEqualTo(300));
    expect(resized.height, lessThanOrEqualTo(60));
    await tester.pumpWidget(
      _logoApp(bytes, maximumSize: const Size(300, 60), dpr: 2),
    );
    expect(resized.debugDisposed, isTrue);
    expect(find.text('Readable title'), findsOneWidget);
    await _waitForImageDecode(tester);
    final highDpr = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    expect(highDpr.width, greaterThan(resized.width));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(highDpr.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV canvas scale bounds the decode at painted physical size', (
    tester,
  ) async {
    // Fire TV: 1920x1080 window at DPR 2 is a 960x540 logical view that
    // LineupCanvas scales by 0.5 to its 1920x1080 canvas, so one canvas pixel
    // paints one physical pixel.
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = await _solidLogoBytes(tester, size: const Size(1600, 320));
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: true),
        builder: LineupCanvas.builder,
        home: Align(
          alignment: Alignment.centerLeft,
          child: ClearLogoImage(
            bytes,
            maximumSize: const Size(420, 84),
            imageKey: const Key('accepted-logo'),
            fallback: const Text('Readable title'),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(ClearLogoImage));
    expect(LineupCanvas.scaleOf(context), 0.5);
    expect(LineupCanvas.physicalPixelRatioOf(context), 1);
    await _waitForImageDecode(tester);
    final image = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    // Contained in the 8-pixel bucket of 420x84 physical pixels (416x80).
    // Previously canvas size x DPR: 840x168, four times the painted pixels.
    expect((image.width, image.height), (400, 80));
    // Geometry is unchanged: the logo still fills the canvas slot.
    expect(
      tester.getSize(find.byKey(const Key('accepted-logo'))),
      const Size(420, 84),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('remounting the same bytes and slot paints on the first frame', (
    tester,
  ) async {
    final bytes = await _solidLogoBytes(tester);
    await _show(tester, bytes);
    final first = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.debugDisposed, isTrue);

    await tester.pumpWidget(_logoApp(bytes));
    expect(find.byKey(const Key('accepted-logo')), findsOneWidget);
    expect(find.text('Readable title'), findsNothing);
    final remounted = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    expect(remounted.debugDisposed, isFalse);
    expect(remounted, isNot(same(first)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cached empty logo falls back immediately on remount', (
    tester,
  ) async {
    final bytes = await _transparentLogoBytes(tester);
    await _show(tester, bytes);
    expect(find.text('Readable title'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(_logoApp(bytes));
    expect(find.text('Readable title'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    await _waitForImageDecode(tester);
    expect(find.text('Readable title'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eviction disposes cached masters but not mounted clones', (
    tester,
  ) async {
    const pink = Color(0xFFFA2A8A);
    final mounted = await _rasterLogoBytes(
      tester,
      color: pink,
      visible: const Rect.fromLTWH(0, 0, 600, 120),
    );
    Widget pair(Uint8List other) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: const Key('logo-boundary'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClearLogoImage(
                mounted,
                maximumSize: const Size(420, 84),
                imageKey: const Key('accepted-logo'),
                fallback: const Text('Readable title'),
              ),
              ClearLogoImage(
                other,
                maximumSize: const Size(420, 84),
                imageKey: const Key('other-logo'),
                fallback: const Text('Other title'),
              ),
            ],
          ),
        ),
      ),
    );

    final first = await _solidLogoBytes(tester);
    await tester.pumpWidget(pair(first));
    await _waitForImageDecode(tester);
    final handle = tester
        .widget<RawImage>(find.byKey(const Key('accepted-logo')))
        .image!;
    // Mounted logo plus nine others exceed the capacity of eight, so the
    // least recently used entry (the mounted logo's) is evicted.
    for (var i = 0; i < 9; i++) {
      await tester.pumpWidget(pair(await _solidLogoBytes(tester)));
      await _waitForImageDecode(tester);
      expect(find.byKey(const Key('other-logo')), findsOneWidget);
    }
    expect(handle.debugDisposed, isFalse);
    expect(
      tester.widget<RawImage>(find.byKey(const Key('accepted-logo'))).image,
      same(handle),
    );
    expect(
      _containsLogoColor(await _captureRenderedLogo(tester), pink),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting an in-flight decode cannot publish later', (
    tester,
  ) async {
    final bytes = await _solidLogoBytes(tester, size: const Size(3800, 1000));
    await tester.pumpWidget(_logoApp(bytes));
    await tester.pumpWidget(const SizedBox.shrink());
    await _waitForImageDecode(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _solidLogoBytes(
  WidgetTester tester, {
  Size size = const Size(600, 120),
}) async {
  return _rasterLogoBytes(tester, visible: Offset.zero & size, size: size);
}

Future<Uint8List> _transparentLogoBytes(WidgetTester tester) =>
    _rasterLogoBytes(tester);

Future<Uint8List> _rasterLogoBytes(
  WidgetTester tester, {
  Size size = const Size(600, 120),
  Rect? visible,
  Color color = Colors.white,
}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (visible != null) {
      canvas.drawRect(visible, Paint()..color = color);
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
  return bytes!;
}

Future<void> _show(
  WidgetTester tester,
  Uint8List bytes, {
  double? maximumVisibleHeight,
  Size? minimumVisibleSize = const Size(96, 28),
}) async {
  await tester.pumpWidget(
    _logoApp(
      bytes,
      minimumVisibleSize: minimumVisibleSize,
      maximumVisibleHeight: maximumVisibleHeight,
    ),
  );
  await _waitForImageDecode(tester);
}

Widget _logoApp(
  Uint8List bytes, {
  double? maximumVisibleHeight,
  Size? minimumVisibleSize = const Size(96, 28),
  Size maximumSize = const Size(420, 84),
  double dpr = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(devicePixelRatio: dpr),
    child: Align(
      alignment: Alignment.centerLeft,
      child: RepaintBoundary(
        key: const Key('logo-boundary'),
        child: ClearLogoImage(
          bytes,
          maximumSize: maximumSize,
          minimumVisibleSize: minimumVisibleSize,
          maximumVisibleHeight: maximumVisibleHeight,
          imageKey: const Key('accepted-logo'),
          fallback: const Text('Readable title'),
        ),
      ),
    ),
  ),
);

Future<void> _waitForImageDecode(WidgetTester tester) async {
  // The engine decoder runs outside the fake widget-test clock.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

bool _containsLogoColor(Uint8List rgba, Color expected) {
  final argb = expected.toARGB32();
  final red = (argb >> 16) & 255;
  final green = (argb >> 8) & 255;
  final blue = argb & 255;
  for (var offset = 0; offset < rgba.length; offset += 4) {
    if (rgba[offset + 3] >= 240 &&
        (rgba[offset] - red).abs() < 24 &&
        (rgba[offset + 1] - green).abs() < 24 &&
        (rgba[offset + 2] - blue).abs() < 24) {
      return true;
    }
  }
  return false;
}

Future<Uint8List> _captureRenderedLogo(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('logo-boundary')),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });
  return bytes!;
}
