import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  test('cover target keeps aspect, covers both edges and never upscales', () {
    // 16:9 original into a wide, short Guide information slot: width-bound.
    final wide = CoverResizeImage.targetSize(3840, 2160, 1344, 384);
    expect((wide.width, wide.height), (1344, 756));
    // Into a 16:9 picture slot rounded to a taller bucket: height-bound.
    final picture = CoverResizeImage.targetSize(3840, 2160, 576, 384);
    expect((picture.width, picture.height), (683, 384));
    // A small original is left at its intrinsic size.
    final small = CoverResizeImage.targetSize(800, 450, 1344, 384);
    expect((small.width, small.height), (800, 450));
  });

  testWidgets('only a tight, finite slot is cover-resized and bucketed up', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox.shrink();
        },
      ),
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    final tight = CoverResizeImage.forSlot(
      context,
      bytes,
      BoxConstraints.tight(const Size(1332, 326)),
    );
    expect(tight, isA<CoverResizeImage>());
    tight as CoverResizeImage;
    expect((tight.width, tight.height), (1344, 384));
    expect((tight.imageProvider as MemoryImage).bytes, same(bytes));
    expect(
      CoverResizeImage.forSlot(
        context,
        bytes,
        BoxConstraints.loose(const Size(400, 300)),
      ),
      isA<MemoryImage>(),
    );
    expect(
      CoverResizeImage.forSlot(context, bytes, const BoxConstraints()),
      isA<MemoryImage>(),
    );
  });

  testWidgets('decodes at the cover size instead of the original', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1920, 1080),
        Paint()..color = Colors.blue,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1920, 1080);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    });
    final provider = CoverResizeImage(
      MemoryImage(bytes!),
      width: 640,
      height: 128,
    );
    final decoded = await tester.runAsync(() async {
      final stream = provider.resolve(ImageConfiguration.empty);
      final info = await (() {
        final completer = Completer<ImageInfo>();
        stream.addListener(
          ImageStreamListener((info, _) => completer.complete(info)),
        );
        return completer.future;
      })();
      return (info.image.width, info.image.height);
    });
    expect(decoded, (640, 360));
    PaintingBinding.instance.imageCache.clear();
  });

  test('image cache budget is capped on Android TV only', () {
    final tv = ImageCache();
    configureImageCache(tv, androidTv: true);
    expect(tv.maximumSizeBytes, androidTvImageCacheBytes);
    expect(androidTvImageCacheBytes, 48 * 1024 * 1024);

    final desktop = ImageCache();
    final defaultBytes = desktop.maximumSizeBytes;
    configureImageCache(desktop, androidTv: false);
    expect(desktop.maximumSizeBytes, defaultBytes);
    expect(defaultBytes, greaterThan(androidTvImageCacheBytes));
  });
}
