import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets(
    'visible alpha validation is opt-in and preserves padded logo rendering',
    (tester) async {
      final transparent = await _transparentLogoBytes(tester);
      await _show(
        tester,
        transparent,
        minimumVisibleSize: null,
        validateVisibleAlpha: false,
      );
      expect(find.byKey(const Key('accepted-logo')), findsOneWidget);
      expect(find.text('Readable title'), findsNothing);

      await _show(
        tester,
        transparent,
        minimumVisibleSize: null,
        validateVisibleAlpha: true,
      );
      expect(find.byKey(const Key('accepted-logo')), findsNothing);
      expect(find.text('Readable title'), findsOneWidget);

      final padded = await _rasterLogoBytes(
        tester,
        visible: const Rect.fromLTWH(160, 20, 280, 80),
      );
      await _show(
        tester,
        padded,
        minimumVisibleSize: null,
        validateVisibleAlpha: false,
      );
      final desktopRender = await _captureRenderedLogo(tester);
      await _show(
        tester,
        padded,
        minimumVisibleSize: null,
        validateVisibleAlpha: true,
      );
      final tvRender = await _captureRenderedLogo(tester);

      expect(
        tester.getSize(find.byKey(const Key('accepted-logo'))),
        const Size(420, 84),
      );
      expect(tvRender, orderedEquals(desktopRender));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'visible alpha validation does not publish a replaced logo result',
    (tester) async {
      final first = await _transparentLogoBytes(tester);
      final replacement = await _solidLogoBytes(tester);
      await tester.pumpWidget(
        _logoApp(first, minimumVisibleSize: null, validateVisibleAlpha: true),
      );
      await tester.pumpWidget(
        _logoApp(
          replacement,
          minimumVisibleSize: null,
          validateVisibleAlpha: true,
        ),
      );
      await _waitForImageDecode(tester);

      final image = tester.widget<Image>(
        find.byKey(const Key('accepted-logo')),
      );
      expect((image.image as MemoryImage).bytes, same(replacement));
      expect(find.text('Readable title'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('visible alpha validation awaits the terminal transparent result', (
    tester,
  ) async {
    final transparent = await _transparentLogoBytes(tester);
    await tester.pumpWidget(
      _logoApp(
        transparent,
        minimumVisibleSize: null,
        validateVisibleAlpha: true,
      ),
    );
    final alphaFuture = await _waitForVisibleFractionFuture(tester);
    final transparentAlphaFutureCaptured = alphaFuture != null;
    expect(transparentAlphaFutureCaptured, isTrue);
    final visibleFraction = await tester.runAsync(() => alphaFuture!);

    expect(visibleFraction, isNull);
    await tester.pump();
    final transparentFallbackFrame = find
        .text('Readable title')
        .evaluate()
        .isNotEmpty;
    expect(find.byKey(const Key('accepted-logo')), findsNothing);
    expect(transparentFallbackFrame, isTrue);

    await tester.pumpWidget(
      _logoApp(
        Uint8List.fromList(const [1, 2, 3]),
        minimumVisibleSize: null,
        validateVisibleAlpha: true,
      ),
    );
    await _waitForImageDecode(tester);
    expect(find.byKey(const Key('accepted-logo')), findsNothing);
    final intrinsicFailureAlpha = await _waitForVisibleFractionFuture(tester);
    final intrinsicFailureAlphaFuture = intrinsicFailureAlpha != null;
    final intrinsicFailureFallbackFrame = find
        .text('Readable title')
        .evaluate()
        .isNotEmpty;
    expect(intrinsicFailureFallbackFrame, isTrue);
    expect(intrinsicFailureAlphaFuture, isFalse);
    debugPrint(
      'ART-I1-R2 trace '
      'transparentAlphaFutureCaptured=$transparentAlphaFutureCaptured '
      'transparentAlphaResult=${visibleFraction == null ? 'null' : 'non-null'} '
      'intrinsicFailureAlphaFuture=$intrinsicFailureAlphaFuture '
      'fallbackFrame=$transparentFallbackFrame '
      'intrinsicFailureFallbackFrame=$intrinsicFailureFallbackFrame',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'visible alpha validation records replacement fallback and warm cache',
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
      await _show(
        tester,
        first,
        minimumVisibleSize: null,
        validateVisibleAlpha: true,
      );
      expect(
        _containsLogoColor(
          await _captureRenderedLogo(tester),
          const Color(0xFFFA2A8A),
        ),
        isTrue,
      );

      final warmFirst = Uint8List.fromList(first);
      await tester.pumpWidget(
        _logoApp(
          warmFirst,
          minimumVisibleSize: null,
          validateVisibleAlpha: true,
        ),
      );
      final lateAlphaFuture = await _waitForVisibleFractionFuture(tester);
      expect(lateAlphaFuture, isNotNull);
      var lateAlphaCompletedBeforeReplacement = false;
      unawaited(
        lateAlphaFuture!.then((_) {
          lateAlphaCompletedBeforeReplacement = true;
        }),
      );

      await tester.pumpWidget(
        _logoApp(
          replacement,
          minimumVisibleSize: null,
          validateVisibleAlpha: true,
        ),
      );
      await tester.pump();
      final pendingPixels = await _captureRenderedLogo(tester);
      final lateAlphaCompletedBeforeReplacementSnapshot =
          lateAlphaCompletedBeforeReplacement;
      expect(find.byKey(const Key('accepted-logo')), findsNothing);
      expect(find.text('Readable title'), findsOneWidget);
      expect(
        _containsLogoColor(pendingPixels, const Color(0xFFFA2A8A)),
        isFalse,
      );

      var lateAlphaCompletionObservedAfterReplacement = false;
      final lateAlphaResult = await tester.runAsync(() async {
        final result = await lateAlphaFuture;
        lateAlphaCompletionObservedAfterReplacement = true;
        return result;
      });
      final lateAObservedAfterReplacement =
          !lateAlphaCompletedBeforeReplacementSnapshot &&
          lateAlphaCompletionObservedAfterReplacement;
      final replacementAlphaFuture = await _waitForVisibleFractionFuture(
        tester,
      );
      expect(replacementAlphaFuture, isNotNull);
      final replacementVisibleFraction = await tester.runAsync(
        () => replacementAlphaFuture!,
      );
      await _waitForAcceptedLogo(tester, replacement);
      expect(lateAlphaResult, isNotNull);
      expect(replacementVisibleFraction, isNotNull);
      expect(find.text('Readable title'), findsNothing);
      final replacementPixels = await _captureRenderedLogo(tester);
      expect(
        _containsLogoColor(replacementPixels, const Color(0xFF2AFA8A)),
        isTrue,
      );

      await tester.pumpWidget(
        _logoApp(
          warmFirst,
          minimumVisibleSize: null,
          validateVisibleAlpha: true,
        ),
      );
      final warmAlphaFuture = await _waitForVisibleFractionFuture(tester);
      expect(warmAlphaFuture, isNotNull);
      expect(await tester.runAsync(() => warmAlphaFuture!), isNotNull);
      await _waitForAcceptedLogo(tester, warmFirst);
      expect(
        _containsLogoColor(
          await _captureRenderedLogo(tester),
          const Color(0xFFFA2A8A),
        ),
        isTrue,
      );
      debugPrint(
        'ART-I1-R2 trace alphaAStarted=true '
        'alphaACompletedBeforeReplacement=$lateAlphaCompletedBeforeReplacementSnapshot '
        'alphaACompletedAfterReplacement=$lateAlphaCompletionObservedAfterReplacement '
        'lateAObservedAfterReplacement=$lateAObservedAfterReplacement '
        'replacementPendingFallback=true replacementAlphaCompleted=true '
        'replacementFrame=true warmCacheAlphaCompleted=true',
      );
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
  Size? minimumVisibleSize = const Size(96, 28),
  bool validateVisibleAlpha = false,
}) async {
  await tester.pumpWidget(
    _logoApp(
      bytes,
      minimumVisibleSize: minimumVisibleSize,
      maximumVisibleHeight: maximumVisibleHeight,
      validateVisibleAlpha: validateVisibleAlpha,
    ),
  );
  await _waitForImageDecode(tester);
}

Widget _logoApp(
  Uint8List bytes, {
  double? maximumVisibleHeight,
  Size? minimumVisibleSize = const Size(96, 28),
  bool validateVisibleAlpha = false,
}) => MaterialApp(
  home: Align(
    alignment: Alignment.centerLeft,
    child: RepaintBoundary(
      key: const Key('logo-boundary'),
      child: ClearLogoImage(
        bytes,
        maximumSize: const Size(420, 84),
        minimumVisibleSize: minimumVisibleSize,
        maximumVisibleHeight: maximumVisibleHeight,
        validateVisibleAlpha: validateVisibleAlpha,
        imageKey: const Key('accepted-logo'),
        fallback: const Text('Readable title'),
      ),
    ),
  ),
);

Future<void> _waitForImageDecode(WidgetTester tester) async {
  // Image decoding happens on the engine outside the fake widget-test clock.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

Future<Future<Rect?>?> _waitForVisibleFractionFuture(
  WidgetTester tester,
) async {
  for (var i = 0; i < 20; i++) {
    final builders = tester.widgetList<FutureBuilder<Rect?>>(
      find.byType(FutureBuilder<Rect?>),
    );
    for (final builder in builders) {
      if (builder.future != null) return builder.future;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
  return null;
}

Future<void> _waitForAcceptedLogo(
  WidgetTester tester,
  Uint8List expectedBytes,
) async {
  for (var i = 0; i < 20; i++) {
    final finder = find.byKey(const Key('accepted-logo'));
    if (finder.evaluate().isNotEmpty) {
      final image = tester.widget<Image>(finder);
      if (image.image is MemoryImage &&
          identical((image.image as MemoryImage).bytes, expectedBytes)) {
        return;
      }
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
  throw TestFailure('Timed out waiting for the replacement logo frame');
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
