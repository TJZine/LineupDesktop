import '../support/device_profile_test_support.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/licenses/licenses_repository.dart';
import 'package:lineup_desktop/licenses/licenses_view.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/focus_ink.dart';
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
    bool isTv = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(
          theme,
          largeFocusIndicators: true,
          formFactor: profileFor(isTv).formFactor,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: DeviceProfileScope(
            profile: profileFor(isTv),
            child: LineupCanvas(child: child!),
          ),
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

  testWidgets('bundled subtitle fonts expose their offline OFL documents', (
    tester,
  ) async {
    final source = LicensesRepository().sources.singleWhere(
      (s) => s.title == 'Fonts and engine notices',
    );
    final items = await source.load();
    final names = [
      'JetBrains Mono',
      'Source Serif 4',
      'Courier Prime',
      'Comic Neue',
      'Dancing Script',
      'Alegreya Sans SC',
    ];
    // Read the actual bundled assets outside fake async, then let the UI's
    // reads complete inside its own zone without depending on host file IO.
    final documents = <String, String>{};
    await tester.runAsync(() async {
      for (final item in items) {
        documents[item.id] = await item.read!();
      }
    });
    final offline = LicensesRepository(
      assets: _PreloadedLicenseAssets(documents),
    ).sources.singleWhere((s) => s.title == source.title);
    await show(tester, [offline]);
    for (final name in names) {
      await open(tester, name);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SIL OPEN FONT LICENSE', findRichText: true),
        findsWidgets,
        reason: name,
      );
      await open(tester, '‹ Back to Licenses');
    }
    expect(tester.takeException(), isNull);
  });

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

  testWidgets(
    'Android D-pad reaches Copy, reading and Back without trapping controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final highlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      try {
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
        final text = List.filled(80, 'License paragraph.').join('\n\n');
        Color? actionInk(String label) => tester
            .widget<RichText>(
              find
                  .descendant(
                    of: find.widgetWithText(TextButton, label),
                    matching: find.byType(RichText),
                  )
                  .first,
            )
            .text
            .style
            ?.color;
        await show(tester, [
          LicenseSource(
            'Runtime',
            () async => [
              LicenseItem.list('component', 'Component', [
                LicenseItem.document('notice', 'Notice', () async => text),
              ]),
            ],
          ),
        ], isTv: true);
        final roles = LineupTheme.of(tester.element(find.byType(LicensesView)));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Component');
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Notice');
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        expect(scroll.offset, 0);
        expect(actionInk('‹ Back to Component'), roles.onFocus);
        expect(actionInk('Copy document'), roles.primaryText);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Copy license document',
        );
        expect(actionInk('‹ Back to Component'), roles.primaryText);
        expect(actionInk('Copy document'), roles.onFocus);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(clipboard, text);
        expect(find.text('Document copied'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'License document',
        );
        final surface = tester.widget<ColoredBox>(
          find.byKey(const Key('licenses-reading-surface')),
        );
        expect(
          surface.color,
          LineupTheme.of(tester.element(find.byType(LicensesView)))
              .focusedSurface,
        );
        final paragraph = tester.widget<Text>(
          find.text('License paragraph.').first,
        );
        expect(paragraph.style!.color, const Color(0xFF090806));
        expect(actionInk('‹ Back to Component'), roles.onFocus);
        expect(actionInk('Copy document'), roles.onFocus);
        final background = tester.renderObject<RenderBox>(
          find.byKey(const Key('licenses-reading-surface')),
        );
        final inset = LineupFocusFrame.contentClearance;
        expect(
          tester.getRect(find.byType(CustomScrollView)),
          Rect.fromPoints(
            background.localToGlobal(Offset(inset, inset)),
            background.localToGlobal(
              Offset(
                background.size.width - inset,
                background.size.height - inset,
              ),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(scroll.offset, 48);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Copy license document',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'License document',
        );
        // Reach both bounds using the same remote keys, retaining reader focus.
        for (var i = 0; i < 100; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, scroll.position.maxScrollExtent);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'License document',
        );
        for (var i = 0; i < 100 && scroll.offset > 0; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Copy license document',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licenses back');
        expect(actionInk('Copy document'), roles.primaryText);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Notice');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        FocusManager.instance.highlightStrategy = highlightStrategy;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android loading and failed documents retain Back and Retry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final pending = Completer<String>();
    var attempts = 0;
    try {
      await show(tester, [
        LicenseSource(
          'Runtime',
          () async => [
            LicenseItem.document(
              'notice',
              'Notice',
              () => attempts++ == 0
                  ? pending.future
                  : Future.value('Recovered notice'),
            ),
          ],
        ),
      ], isTv: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Loading license document…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licenses back');
      pending.completeError(StateError('synthetic private path'));
      await tester.pumpAndSettle();
      expect(
        find.text('This license document could not be loaded.'),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic private path'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        (FocusManager.instance.primaryFocus?.context
                    ?.findAncestorWidgetOfExactType<OutlinedButton>()
                    ?.child
                as Text?)
            ?.data,
        'Retry',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Recovered notice'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licenses back');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop reader keys still scroll from the Back action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await show(tester, [
        LicenseSource(
          'Runtime',
          () async => [
            LicenseItem.document(
              'notice',
              'Notice',
              () async => List.filled(80, 'Desktop paragraph.').join('\n\n'),
            ),
          ],
        ),
      ]);
      await open(tester, 'Notice');
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, 48);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Licenses back');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

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

  testWidgets(
    'native Android index labels render with notice identity retained',
    (tester) async {
      const channel = MethodChannel('lineup/platform');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => [
          {'id': 'build', 'path': 'BUILD-INFO.txt', 'bytes': 10},
          {
            'id': 'summary',
            'path': 'licenses/NOTICES-SUMMARY.txt',
            'bytes': 10,
          },
          {
            'id': 'activity',
            'path': 'licenses/androidx.activity__activity/Apache.txt',
            'bytes': 10,
          },
          {
            'id': 'media3',
            'path': 'licenses/androidx.media3__media3-exoplayer/Apache.txt',
            'bytes': 10,
          },
          {
            'id': 'okhttp',
            'path': 'licenses/com.squareup.okhttp3__okhttp/Apache.txt',
            'bytes': 10,
          },
        ],
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      });
      for (final android in [true, false]) {
        debugDefaultTargetPlatformOverride = android
            ? TargetPlatform.android
            : TargetPlatform.macOS;
        final groups = await LicensesRepository().sources.first.load();
        for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
          await show(
            tester,
            [LicenseSource('Native runtime', () async => groups)],
            size: size,
            isTv: android,
          );
          await tester.pumpAndSettle();
          for (final group in groups) {
            expect(find.text(group.title), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          final directory = Platform.environment['LINEUP_LICENSE_RENDER_DIR'];
          if (directory != null) {
            await tester.runAsync(() async {
              final image = await tester
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const Key('license-render')),
                  )
                  .toImage(
                    pixelRatio: LineupCanvas.scaleFor(
                      size,
                      formFactor: profileFor(android).formFactor,
                    ),
                  );
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(directory).create(recursive: true);
              await File(
                '$directory/index-${android ? 'tv' : 'desktop'}-${size.width.toInt()}x${size.height.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

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

class _PreloadedLicenseAssets extends CachingAssetBundle {
  _PreloadedLicenseAssets(this.documents);
  final Map<String, String> documents;
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      documents[key]!;
  @override
  Future<ByteData> load(String key) =>
      throw UnsupportedError('Text assets only');
}
