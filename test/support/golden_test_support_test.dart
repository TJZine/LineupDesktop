@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts an exact match', () async {
    final pixels = _solidPixels(4, 4, 128);
    final goldenBytes = await _pngForPixels(pixels, 4, 4);
    final fixture = await _fixture(goldenBytes);

    expect(
      await fixture.comparator.compare(goldenBytes, fixture.golden),
      isTrue,
    );
  });

  test('accepts a bounded sparse color variation', () async {
    final goldenPixels = _solidPixels(64, 64, 128);
    final testPixels = Uint8List.fromList(goldenPixels)
      ..[0] = goldenPixels[0] + 1;
    final fixture = await _fixture(await _pngForPixels(goldenPixels, 64, 64));

    expect(
      await fixture.comparator.compare(
        await _pngForPixels(testPixels, 64, 64),
        fixture.golden,
      ),
      isTrue,
    );
  });

  test('rejects a wrong image size', () async {
    final fixture = await _fixture(
      await _pngForPixels(_solidPixels(1, 1, 128), 1, 1),
    );

    await _expectRejected(
      fixture,
      await _pngForPixels(_solidPixels(2, 1, 128), 2, 1),
      'image sizes do not match',
    );
  });

  test('rejects a strong isolated pixel change', () async {
    final goldenPixels = _solidPixels(64, 64, 128);
    final testPixels = Uint8List.fromList(goldenPixels)..[0] = 255;
    final fixture = await _fixture(await _pngForPixels(goldenPixels, 64, 64));

    await _expectRejected(
      fixture,
      await _pngForPixels(testPixels, 64, 64),
      '70/255',
    );
  });

  test('rejects a broad small-color change', () async {
    final fixture = await _fixture(
      await _pngForPixels(_solidPixels(32, 32, 128), 32, 32),
    );

    await _expectRejected(
      fixture,
      await _pngForPixels(_solidPixels(32, 32, 129), 32, 32),
      '1024px',
    );
  });
}

Future<void> _expectRejected(
  _ComparatorFixture fixture,
  Uint8List testBytes,
  String expectedMessage,
) async {
  try {
    await fixture.comparator.compare(testBytes, fixture.golden);
    fail('Expected the golden comparison to fail.');
  } on FlutterError catch (error) {
    expect('$error', contains(expectedMessage));
  }
}

Future<_ComparatorFixture> _fixture(Uint8List goldenBytes) async {
  final directory = await Directory.systemTemp.createTemp(
    'lineup-golden-comparator-test',
  );
  addTearDown(() => directory.delete(recursive: true));
  await File('${directory.path}/golden.png').writeAsBytes(goldenBytes);
  return _ComparatorFixture(
    CrossMacOsGoldenFileComparator(
      Uri.file('${directory.path}/golden_comparator_test.dart'),
    ),
    Uri.parse('golden.png'),
  );
}

Uint8List _solidPixels(int width, int height, int value) {
  final pixels = Uint8List(width * height * 4);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = value;
    pixels[offset + 1] = value;
    pixels[offset + 2] = value;
    pixels[offset + 3] = 255;
  }
  return pixels;
}

Future<Uint8List> _pngForPixels(Uint8List pixels, int width, int height) async {
  final imageCompleter = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    imageCompleter.complete,
  );
  final image = await imageCompleter.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

class _ComparatorFixture {
  const _ComparatorFixture(this.comparator, this.golden);

  final CrossMacOsGoldenFileComparator comparator;
  final Uri golden;
}
