import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

Future<void> loadPinnedTestFonts() async {
  const pinnedRobotoAliases = ['Roboto', '.AppleSystemUIFont', 'Arial'];
  const pinnedRobotoFiles = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ];
  const requiredMaterialFiles = [
    ...pinnedRobotoFiles,
    'MaterialIcons-Regular.otf',
  ];
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
  for (final filename in requiredMaterialFiles) {
    if (!File('$fontDirectory/$filename').existsSync()) {
      throw StateError('Pinned Flutter test font is missing: $filename');
    }
  }
  for (final family in pinnedRobotoAliases) {
    final loader = FontLoader(family);
    for (final file in pinnedRobotoFiles) {
      loader.addFont(
        File('$fontDirectory/$file').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
  for (final entry in {
    'Instrument Sans': 'instrumentsans/InstrumentSans[wdth,wght].ttf',
    'Inter': 'inter/Inter[opsz,wght].ttf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
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
