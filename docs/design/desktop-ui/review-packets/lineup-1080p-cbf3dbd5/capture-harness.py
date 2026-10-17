from pathlib import Path
import subprocess, sys, os, shutil
flutter_binary = os.environ.get("FLUTTER_BIN") or shutil.which("flutter")
if not flutter_binary:
    raise SystemExit("Set FLUTTER_BIN or place the documented Flutter SDK on PATH.")
Path("build/desktop-ui/comparison-1080").mkdir(parents=True, exist_ok=True)
p=Path('test/app/ui_acceptance_golden_test.dart');original=p.read_text()
extra=r'''
  testWidgets('Audit channel management', (tester) async {
    final fixture = _studioFixture();
    fixture.controller.libraries = const [PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie)];
    fixture.controller.selectedLibraryIds = {'movies'};
    fixture.controller.availableMedia = [...fixture.controller.availableMedia, for (final genre in ['Adventure', 'Animation', 'Comedy', 'Drama', 'Fantasy', 'Mystery']) PlexMediaItem(id: 'audit-$genre', title: '$genre feature', type: 'movie', duration: const Duration(minutes: 90), libraryId: 'movies', genres: [genre])];
    final base = fixture.controller.channels.single;
    fixture.controller.channels = [base, for (var i = 1; i < 4; i++) Channel(id: 'audit-$i', number: 42 + i, name: ['Evening Cinema', 'Documentary and Discovery', 'Weekend Stories'][i-1], source: base.source, playbackMode: base.playbackMode, anchor: base.anchor, shuffleSeed: i)];
    await _pump(tester, fixture.build());
    await openDestination(tester, 'Channels');
    await _match(tester, 'channels-directory.png');
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all matching'));
    await tester.pumpAndSettle();
    await _match(tester, 'channels-selection.png');
    await tester.tap(find.text('Delete selected'));
    await tester.pumpAndSettle();
    await _match(tester, 'channels-delete-confirmation.png');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder channels'));
    await tester.pumpAndSettle();
    await _match(tester, 'channels-reorder.png');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saturday Cartoons'));
    await tester.pumpAndSettle();
    await _match(tester, 'studio-handpicked.png');
    await tester.tap(find.textContaining('Browse library').first);
    await tester.pumpAndSettle();
    await _match(tester, 'studio-browse.png');
    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    await _match(tester, 'studio-library.png');
    await tester.tap(find.descendant(of: find.byKey(const Key('studio-filter-genre')), matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await _match(tester, 'studio-filter-picker.png');
  });

  testWidgets('Audit portable scale spots', (tester) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final item in [(1280.0, 720.0, 1.0), (1920.0, 1080.0, 1.25), (2560.0, 1440.0, 1.5), (3840.0, 2160.0, 2.0)]) {
      final fixture = _readyFixture(playerState: const PlayerStatus(state: PlayerState.ready, message: 'Synthetic playback'));
      await _pump(tester, fixture.build(), viewport: Size(item.$1, item.$2));
      tester.view.devicePixelRatio = item.$3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await _match(tester, 'guide-${item.$1.toInt()}x${item.$2.toInt()}-dpi${item.$3}-text2.png');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
  });
  testWidgets('Audit setup lower sections', (tester) async {
    final controller = _VisualController()..stage = SetupStage.channelSetup..libraries = const [PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie)];
    await _pump(tester, UiFixture(controller: controller, guideClock: () => _fixedNow).build());
    await tester.tap(find.byKey(const Key('scan-selected-libraries'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('configure-section-1'))); await tester.pumpAndSettle();
    await _match(tester, 'setup-playback-order.png');
    await tester.tap(find.text('Mini-marathons')); await tester.pumpAndSettle();
    await _match(tester, 'setup-mini-marathons.png');
    await tester.tap(find.byKey(const ValueKey('configure-section-2'))); await tester.pumpAndSettle();
    await _match(tester, 'setup-lineup-rules.png');
  });
  testWidgets('Audit diagnostics', (tester) async {
    final controller = FixtureController();
    controller.diagnostics.enabled = true;
    controller.diagnostics.add('playback', 'Playback request failed', {'code': 'unavailable'});
    controller.diagnostics.add('guide', 'Schedule request timed out');
    await _pump(tester, MaterialApp(debugShowCheckedModeBanner: false, theme: LineupTheme.forName(LineupThemeName.emberSteel), home: Scaffold(body: DiagnosticsView(controller: controller, playback: const PlaybackDiagnosticSnapshot(state: PlayerState.stopped), onRecordingSettings: () {}))));
    await _match(tester, 'diagnostics-events.png');
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    await _match(tester, 'diagnostics-events-expanded.png');
  });

  testWidgets('Audit missing surfaces', (tester) async {
    final linking = UiFixture()
      ..controller.stage = SetupStage.linking
      ..controller.activePin = PlexPin(id: 7, code: 'ABCD', expiresAt: DateTime.now().add(const Duration(minutes: 4)));
    await _pump(tester, linking.build());
    await _match(tester, 'linking-normal.png', precacheLogo: true);
    linking.controller.activePin = PlexPin(id: 7, code: 'ABCD', expiresAt: DateTime.now().subtract(const Duration(seconds: 1)));
    linking.controller.notifyListeners(); await tester.pumpAndSettle();
    await _match(tester, 'linking-expired.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final fixture = _readyFixture(playerState: const PlayerStatus(state: PlayerState.ready, message: 'Synthetic playback'));
    await _pump(tester, fixture.build());
    await tester.tap(find.byTooltip('Open Lineup menu'));
    await tester.pumpAndSettle();
    await _match(tester, 'lineup-menu.png');
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    for (final category in ['Appearance', 'Guide', 'Playback', 'Accessibility', 'Account', 'Support']) {
      await tester.tap(find.text(category).first);
      await tester.pumpAndSettle();
      await _match(tester, 'settings-${category.toLowerCase()}.png');
    }
    await tester.tap(find.text('Open Diagnostics'));
    await tester.pumpAndSettle();
    await _match(tester, 'diagnostics-summary.png');
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    await _match(tester, 'diagnostics-expanded.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final timerFixture = _readyFixture(playerState: const PlayerStatus(state: PlayerState.ready, message: 'Synthetic playback'));
    await _pump(tester, timerFixture.build());
    await openDestination(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    final playerView = tester.widget<PlayerView>(find.byType(PlayerView));
    playerView.controller.showSleepTimer();
    await tester.pumpAndSettle();
    await _match(tester, 'sleep-timer.png');
  });
'''
pos=original.index('\n}\n\nFuture<void> _pump')
s=original[:pos]+extra+original[pos:]
s=s.replace('const _viewport = Size(1280, 720);', 'const _viewport = Size(1920, 1080);')
s=s.replace('..physicalSize = viewport;', '..physicalSize = const Size(1920, 1080);')
s=s.replace("import 'dart:io';", "import 'dart:io';\nimport 'package:lineup_desktop/app/diagnostics_view.dart';\nimport 'package:lineup_desktop/diagnostics/diagnostics.dart';\nimport 'package:lineup_desktop/ui/app_theme.dart';")
s=s.replace("  await expectLater(boundary, matchesGoldenFile('goldens/$name'));",r'''  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(boundary);
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('build/desktop-ui/comparison-1080/current');
    await directory.create(recursive: true);
    final captureName = name.replaceAll('1280x720', '1920x1080');
    await File('${directory.path}/$captureName').writeAsBytes(bytes!.buffer.asUint8List());
  });''')
try:
    p.write_text(s)
    with open('build/desktop-ui/comparison-1080/capture-reproduction.log','w') as log:
        result=subprocess.run([flutter_binary,'test','--no-pub',str(p),'--name',sys.argv[1] if len(sys.argv)>1 else '^(?!.*(?:portable scale|at 1920|compact desktop|large desktop|compact custom)).*$'],stdout=log,stderr=subprocess.STDOUT)
finally:
    p.write_text(original)
raise SystemExit(result.returncode)

raise SystemExit(result.returncode)
