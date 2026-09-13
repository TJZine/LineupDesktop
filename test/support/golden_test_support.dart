import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _maxCrossMacOsGoldenDiffPercent = 0.001;
const _maxCrossMacOsGoldenChannelDelta = 70;

/// Keeps screenshot goldens strict while allowing sparse cross-macOS raster
/// differences at text and icon edges.
class CrossMacOsGoldenFileComparator extends LocalFileComparator {
  CrossMacOsGoldenFileComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final masterBytes = await getGoldenBytes(golden);
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      masterBytes,
    );
    if (result.passed) {
      result.dispose();
      return true;
    }

    try {
      final difference = await _measureDifference(imageBytes, masterBytes);
      if (difference.sameDimensions &&
          difference.diffPercent <= _maxCrossMacOsGoldenDiffPercent &&
          difference.maxChannelDelta <= _maxCrossMacOsGoldenChannelDelta) {
        return true;
      }

      final error = await generateFailureOutput(result, golden, basedir);
      final policy = difference.sameDimensions
          ? 'Observed ${difference.changedPixels}px changed pixels '
                '(${(difference.diffPercent * 100).toStringAsFixed(3)}%) with '
                'a maximum RGBA channel delta of '
                '${difference.maxChannelDelta}/255. The cross-macOS allowance '
                'is <= 0.1% of pixels and <= 70/255 per channel.'
          : 'Equal image dimensions are required; the cross-macOS allowance '
                'does not apply to size changes.';
      throw FlutterError('$error\n$policy');
    } finally {
      result.dispose();
    }
  }

  Future<_PixelDifference> _measureDifference(
    List<int> testBytes,
    List<int> masterBytes,
  ) async {
    final testImage = await _decodePng(testBytes);
    try {
      final masterImage = await _decodePng(masterBytes);
      try {
        final sameDimensions =
            testImage.width == masterImage.width &&
            testImage.height == masterImage.height;
        if (!sameDimensions) {
          return const _PixelDifference(
            sameDimensions: false,
            changedPixels: 0,
            diffPercent: 1,
            maxChannelDelta: 0,
          );
        }

        final testRgba = await testImage.toByteData();
        final masterRgba = await masterImage.toByteData();
        if (testRgba == null || masterRgba == null) {
          throw StateError('Could not decode golden images as RGBA pixels.');
        }

        var changedPixels = 0;
        var maxChannelDelta = 0;
        for (var offset = 0; offset < testRgba.lengthInBytes; offset += 4) {
          var changed = false;
          for (var channel = 0; channel < 4; channel++) {
            final delta =
                testRgba.getUint8(offset + channel) -
                masterRgba.getUint8(offset + channel);
            final absoluteDelta = delta.abs();
            if (absoluteDelta > 0) {
              changed = true;
            }
            if (absoluteDelta > maxChannelDelta) {
              maxChannelDelta = absoluteDelta;
            }
          }
          if (changed) {
            changedPixels++;
          }
        }
        final totalPixels = testImage.width * testImage.height;
        return _PixelDifference(
          sameDimensions: true,
          changedPixels: changedPixels,
          diffPercent: changedPixels / totalPixels,
          maxChannelDelta: maxChannelDelta,
        );
      } finally {
        masterImage.dispose();
      }
    } finally {
      testImage.dispose();
    }
  }

  Future<ui.Image> _decodePng(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}

GoldenFileComparator installCrossMacOsGoldenComparator({Uri? testFile}) {
  final previous = goldenFileComparator;
  final defaultTestFile = previous is LocalFileComparator
      ? previous.basedir.resolve('golden_comparator_test.dart')
      : Uri.file(Platform.script.toFilePath());
  goldenFileComparator = CrossMacOsGoldenFileComparator(
    testFile ?? defaultTestFile,
  );
  return previous;
}

void restoreGoldenFileComparator(GoldenFileComparator previous) {
  goldenFileComparator = previous;
}

class _PixelDifference {
  const _PixelDifference({
    required this.sameDimensions,
    required this.changedPixels,
    required this.diffPercent,
    required this.maxChannelDelta,
  });

  final bool sameDimensions;
  final int changedPixels;
  final double diffPercent;
  final int maxChannelDelta;
}

Future<void> loadPinnedTestFonts() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (flutterRoot.parent.path != flutterRoot.path &&
      !File(
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).existsSync()) {
    flutterRoot = flutterRoot.parent;
  }
  final fontDirectory =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  if (!Directory(fontDirectory).existsSync()) {
    throw StateError(
      'Pinned Flutter material-fonts directory is missing: $fontDirectory',
    );
  }
  final requiredFonts = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'MaterialIcons-Regular.otf',
  ];
  for (final filename in requiredFonts) {
    if (!File('$fontDirectory/$filename').existsSync()) {
      throw StateError('Pinned Flutter test font is missing: $filename');
    }
  }
  // Golden tests map platform family names to pinned Roboto; this Arial alias
  // is a deterministic test surrogate, not physical Arial evidence.
  for (final family in ['Roboto', '.AppleSystemUIFont', 'Arial']) {
    final loader = FontLoader(family);
    for (final file in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]) {
      loader.addFont(
        File('$fontDirectory/$file').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
  final icons = ByteData.sublistView(
    await File('$fontDirectory/MaterialIcons-Regular.otf').readAsBytes(),
  );
  await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
}

void markSubtreeNeedsPaint(RenderObject object) {
  object.visitChildren(markSubtreeNeedsPaint);
  object.markNeedsPaint();
}
