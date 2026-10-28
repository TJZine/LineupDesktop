import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/licenses/licenses_repository.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';

class FixtureLicenses extends LicensesRepository {
  FixtureLicenses(this.groups);
  final List<LicenseSource> groups;
  @override
  List<LicenseSource> get sources => groups;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPinnedTestFonts);
  Future<void> show(
    WidgetTester tester,
    List<LicenseSource> sources, {
    Size size = const Size(1280, 720),
    double scale = 1,
    VoidCallback? back,
    LineupThemeName theme = LineupThemeName.emberSteel,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(theme, largeFocusIndicators: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: LineupCanvas(child: child!),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('license-render'),
            child: LicensesView(
              repository: FixtureLicenses(sources),
              onBack: back ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
  }

  final example = [
    LicenseSource(
      'Native runtime',
      () async => [
        LicenseItem.list('freetype', 'FreeType', [
          LicenseItem.document(
            'ftl',
            'FTL.TXT',
            () async => 'Copyright © test\n\n    Indented text.\n',
            subtitle: 'FreeType · licenses/freetype/FTL.TXT',
          ),
        ]),
      ],
    ),
  ];

  testWidgets('component/file/back retain focus and exact full-document copy', (
    tester,
  ) async {
    var left = 0;
    String? clipboard;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester, example, back: () => left++);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licenses back');
    await open(tester, 'FreeType');
    await open(tester, 'FTL.TXT');
    expect(find.text('Copyright © test'), findsOneWidget);
    expect(find.text('    Indented text.\n'), findsOneWidget);
    await open(tester, 'Copy document');
    expect(clipboard, 'Copyright © test\n\n    Indented text.\n');
    expect(find.text('Document copied'), findsOneWidget);
    await open(tester, '‹ Back to FreeType');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'FTL.TXT');
    await open(tester, '‹ Back to Licenses');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'FreeType');
    await open(tester, '‹ Back to Support');
    expect(left, 1);
  });

  testWidgets(
    'group partial failure, loading, retry and dispose ignore stale work',
    (tester) async {
      var attempts = 0;
      final pending = Completer<List<LicenseItem>>();
      await show(tester, [
        ...example,
        LicenseSource('Unavailable', () async {
          if (attempts++ == 0) throw StateError('private path must not appear');
          return [
            LicenseItem.document('retry', 'Recovered', () async => 'All text'),
          ];
        }),
        LicenseSource('Slow', () => pending.future),
      ]);
      expect(find.text('FreeType'), findsOneWidget);
      expect(find.text('These licenses could not be loaded.'), findsOneWidget);
      expect(find.text('Loading licenses…'), findsOneWidget);
      final renderDirectory = Platform.environment['LINEUP_LICENSE_RENDER_DIR'];
      if (renderDirectory != null) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('license-render')),
              )
              .toImage(pixelRatio: .8);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(renderDirectory).create(recursive: true);
          await File('$renderDirectory/partial-failure-1280x720.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.textContaining('private path'), findsNothing);
      await open(tester, 'Retry');
      expect(find.text('Recovered'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.complete([]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('document failure and retry preserve Back and sanitize errors', (
    tester,
  ) async {
    var attempts = 0;
    await show(tester, [
      LicenseSource(
        'Documents',
        () async => [
          LicenseItem.document('bad', 'Notice', () async {
            if (attempts++ == 0) throw StateError('secret diagnostics');
            return 'Recovered document';
          }),
        ],
      ),
    ]);
    await open(tester, 'Notice');
    expect(
      find.text('This license document could not be loaded.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret diagnostics'), findsNothing);
    await open(tester, 'Retry');
    expect(find.text('Recovered document'), findsOneWidget);
  });

  testWidgets('index scroll position and row focus survive document return', (
    tester,
  ) async {
    await show(tester, [
      LicenseSource(
        'Many components',
        () async => [
          for (var i = 0; i < 40; i++)
            LicenseItem.document(
              'item-$i',
              'Component $i',
              () async => 'Full text',
            ),
        ],
      ),
    ]);
    await tester.scrollUntilVisible(find.text('Component 20'), 300);
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await open(tester, 'Component 20');
    await open(tester, '‹ Back to Licenses');
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      closeTo(scroll, 1),
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Component 20');
  });

  testWidgets('long real notice renders across sizes, text scales and themes', (
    tester,
  ) async {
    final file = File(
      'build/macos-runtime/dist/arm64/licenses/glslang/NOTICES.txt',
    );
    final text = file.existsSync()
        ? file.readAsStringSync()
        : List.filled(
            200,
            'Copyright fixture\n\nFull license terms and https://example.invalid/${'a' * 120}\n',
          ).join();
    final directory = Platform.environment['LINEUP_LICENSE_RENDER_DIR'];
    for (final entry in [
      (const Size(1280, 720), 1.0, '1280x720', LineupThemeName.emberSteel),
      (const Size(1920, 1080), 1.0, '1920x1080', LineupThemeName.emberSteel),
      (const Size(800, 600), 1.0, '800x600', LineupThemeName.slatePine),
      (const Size(1280, 720), 2.0, 'text-scale-2', LineupThemeName.emberSteel),
      (
        const Size(640, 360),
        2.0,
        'short-large-text',
        LineupThemeName.emberSteel,
      ),
    ]) {
      await show(
        tester,
        [
          LicenseSource(
            'Native runtime',
            () async => [
              LicenseItem.document(
                'glslang',
                'glslang NOTICES.txt',
                () async => text,
              ),
            ],
          ),
        ],
        size: entry.$1,
        scale: entry.$2,
        theme: entry.$4,
      );
      await open(tester, 'glslang NOTICES.txt');
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Copy document'), 150);
      await tester.ensureVisible(find.text('Copy document'));
      await tester.pump();
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Copy document'), findsOneWidget);
      semantics.dispose();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      if (directory != null) {
        await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('license-render')),
              )
              .toImage(pixelRatio: LineupCanvas.scaleFor(entry.$1));
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/reader-${entry.$3}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
