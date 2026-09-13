import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
