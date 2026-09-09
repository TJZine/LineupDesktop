import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
// Synthetic 3:1 title artwork and a 20x1200 image that fits too narrowly.
final _wideLogoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
);
final _narrowLogoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABQAAASwCAAAAADeIDU6AAAAWElEQVR4nO3IMQEAAAwCIPuX1gILsANO0kOklFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSinl1xx/t2e0Ivf9MAAAAABJRU5ErkJggg==',
);

void main() {
  test('clear logo usability follows decoded size and actual constraints', () {
    const ordinary = Size(1200, 400);
    const extremeWide = Size(1200, 20);
    const extremeNarrow = Size(20, 1200);
    const guideConstraint = BoxConstraints(maxWidth: 360, maxHeight: 52);
    const osdConstraint = BoxConstraints(maxWidth: 320, maxHeight: 68);
    const nowPlayingConstraint = BoxConstraints(maxWidth: 600, maxHeight: 132);

    for (final constraint in [
      guideConstraint,
      const BoxConstraints(maxWidth: 240, maxHeight: 36),
      osdConstraint,
      nowPlayingConstraint,
      const BoxConstraints(maxWidth: 360, maxHeight: 84),
      const BoxConstraints(maxWidth: 360, maxHeight: 58),
    ]) {
      expect(clearLogoIsUsable(ordinary, constraint), isTrue);
      expect(clearLogoIsUsable(extremeWide, constraint), isFalse);
      expect(clearLogoIsUsable(extremeNarrow, constraint), isFalse);
    }
    expect(
      clearLogoIsUsable(
        const Size(1200, 400),
        const BoxConstraints(maxWidth: 120, maxHeight: 20),
      ),
      isTrue,
    );
  });

  test('layout policy stays bounded and keeps one five-row composition', () {
    for (final size in const [
      Size.zero,
      Size(320, 240),
      Size(double.infinity, 720),
      Size(1280, double.infinity),
    ]) {
      final policy = GuideLayoutPolicy.forSize(size, hasPicture: true);
      expect(policy.showcaseHeight, isNonNegative, reason: '$size');
      expect(policy.showcaseHeight.isFinite, isTrue, reason: '$size');
      expect(policy.pictureWidth, isNonNegative, reason: '$size');
      expect(policy.pictureWidth.isFinite, isTrue, reason: '$size');
    }

    final comfortable = GuideLayoutPolicy.forSize(
      const Size(1920, 1080),
      hasPicture: true,
    );
    final enlarged = GuideLayoutPolicy.forSize(
      const Size(1920, 1080),
      hasPicture: true,
      textScale: 2,
    );
    expect(comfortable.rowHeight, closeTo(111.2, 0.1));
    expect(enlarged.rowHeight, greaterThanOrEqualTo(116));
    expect(comfortable.minimumRows, 5);
    expect(enlarged.minimumRows, 5);
  });

  testWidgets('non-positive timeline slots render safely', (tester) async {
    final lineup = _Lineup(1)..settings = const LineupSettings(guideHours: 0);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Guide Media Play jumps to now with DVR controls disabled', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 17);
    final lineup = _Lineup(1)
      ..settings = const LineupSettings(dvrControlsEnabled: false);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    guide.moveHorizontal(1);
    expect(guide.windowStart, isNot(DateTime.utc(2026, 1, 1, 11, 30)));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    await tester.pumpAndSettle();

    expect(guide.windowStart, DateTime.utc(2026, 1, 1, 12));
    expect(guide.focusTime, now);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('established viewport work is independent of lineup cardinality', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final count in [200, 500, 1000]) {
      final lineup = _Lineup(count);
      addTearDown(lineup.dispose);
      var loads = 0;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async {
          loads++;
          return _schedule(channel);
        },
      );
      addTearDown(guide.dispose);
      final elapsed = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pump();
      elapsed.stop();
      debugPrint(
        'GUIDE_CARDINALITY channels=$count firstViewportUs=${elapsed.elapsedMicroseconds} '
        'widgets=${tester.allWidgets.length} loadedRows=$loads',
      );
      expect(loads, lessThan(30));
      expect(find.text('Channel ${count - 1}'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
      lineup.dispose();
    }
  });

  testWidgets('1000-channel Guide builds a bounded accessible viewport', (
    tester,
  ) async {
    final lineup = _Lineup(1000);
    addTearDown(lineup.dispose);
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    final rssBefore = ProcessInfo.currentRss;
    final firstViewport = Stopwatch()..start();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();
    firstViewport.stop();

    expect(
      find.bySemanticsLabel(RegExp(r'^Channel 1, Channel 0')),
      findsOneWidget,
    );
    expect(find.text('Channel 999'), findsNothing);
    expect(loads, lessThan(30));

    final navigation = Stopwatch()..start();
    for (var index = 0; index < 500; index++) {
      guide.moveVertical(1);
    }
    navigation.stop();
    await tester.pump();

    debugPrint(
      'GUIDE_PROFILE channels=1000 firstViewportUs=${firstViewport.elapsedMicroseconds} '
      'navigation500Us=${navigation.elapsedMicroseconds} widgets=${tester.allWidgets.length} '
      'cachedRows=${guide.cachedRowCount} rssDeltaBytes=${ProcessInfo.currentRss - rssBefore}',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(guide.focusedChannelId, isNot('channel-0'));
    expect(loads, lessThan(40));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('1000-channel four-hour Guide stays lazy and focusable', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 15);
    final lineup = _Lineup(1000)
      ..settings = const LineupSettings(guideHours: 4, reduceMotion: true);
    lineup.channels = [
      for (var index = 0; index < 1000; index++)
        Channel(
          id: 'channel-$index',
          number: index + 1,
          name: 'Channel $index',
          source: ManualSource([
            for (var slot = 0; slot < 4; slot++)
              ChannelItem(
                id: 'program-$index-$slot',
                title: 'Program $index-$slot',
                duration: const Duration(minutes: 30),
              ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now.subtract(const Duration(minutes: 15)),
          shuffleSeed: index,
        ),
    ];
    addTearDown(lineup.dispose);
    final loadedChannelIds = <String>[];
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async {
        loadedChannelIds.add(channel.id);
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstViewport = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    firstViewport.stop();

    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    final scheduleHeight = tester
        .getSize(find.byKey(const Key('guide-schedule-list')))
        .height;
    final fullyVisibleRows = (scheduleHeight / list.itemExtent!).floor();
    final programCells = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('channel-') &&
              key.value.contains(':');
        })
        .evaluate()
        .length;

    expect(fullyVisibleRows, 5);
    expect(programCells, inInclusiveRange(40, 160));
    expect(loadedChannelIds.length, lessThan(20));
    expect(loadedChannelIds.toSet().length, loadedChannelIds.length);
    expect(loadedChannelIds, isNot(contains('channel-999')));
    expect(guide.cachedRowCount, loadedChannelIds.length);
    expect(guide.cachedRowCount, lessThanOrEqualTo(64));
    expect(guide.activeLoadCount, 0);
    expect(lineup.artworkLoads, 0);
    for (final channelId in loadedChannelIds) {
      expect(guide.row(channelId).programs.length, inInclusiveRange(8, 10));
    }

    final initialProgram = guide.focusedProgramId;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(guide.focusedProgramId, isNot(initialProgram));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(guide.focusedChannelId, 'channel-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(guide.focusedChannelId, 'channel-6');
    expect(loadedChannelIds.length, lessThan(30));
    expect(guide.cachedRowCount, lessThanOrEqualTo(64));
    expect(find.text('Channel 999'), findsNothing);

    debugPrint(
      'GUIDE_PROFILE channels=1000 hours=4 rows=$fullyVisibleRows '
      'firstViewportUs=${firstViewport.elapsedMicroseconds} '
      'widgets=${tester.allWidgets.length} programCells=$programCells '
      'scheduleLoads=${loadedChannelIds.length} cachedRows=${guide.cachedRowCount}',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading, error, retry, and program semantics stay visible', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 45);
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'semantic-channel',
        number: 1,
        name: 'Semantic Channel',
        source: const ManualSource([
          ChannelItem(
            id: 'ended-program',
            title: 'Ended Program',
            duration: Duration(minutes: 10),
          ),
          ChannelItem(
            id: 'current-program',
            title: 'Current Program',
            duration: Duration(minutes: 30),
          ),
          ChannelItem(
            id: 'upcoming-program',
            title: 'Upcoming Program',
            duration: Duration(hours: 4),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026, 1, 1, 12, 30),
        shuffleSeed: 1,
      ),
    ];
    lineup.currentChannelId = 'semantic-channel';
    var fail = true;
    var tunes = 0;
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async {
        if (fail) throw StateError('offline');
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async => tunes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('Schedule failed to load')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    final current = guide.currentProgram('semantic-channel')!;
    final startLabel = _testTime(current.scheduled.start.toLocal());
    final endLabel = _testTime(current.scheduled.end.toLocal());
    expect(find.textContaining('$startLabel–$endLabel'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        'Current Program, $startLabel to $endLabel, currently airing',
      ),
      findsOneWidget,
    );
    final currentCell = find.bySemanticsLabel(
      'Current Program, $startLabel to $endLabel, currently airing',
    );
    expect(
      find.descendant(
        of: currentCell,
        matching: find.byType(FractionallySizedBox),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Current time'), findsOneWidget);
    final rawStartLabel = _testTime(current.scheduled.start);
    if (rawStartLabel != startLabel) {
      expect(find.textContaining(rawStartLabel), findsNothing);
    }

    final channelRail = find.bySemanticsLabel(
      RegExp(r'^Channel 1, Semantic Channel, now watching'),
    );
    expect(channelRail, findsOneWidget);
    final channelSemantics = tester
        .getSemantics(channelRail)
        .getSemanticsData();
    expect(channelSemantics.flagsCollection.isButton, isTrue);
    expect(channelSemantics.hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel(RegExp(r'^Now watching$')), findsNothing);

    final upcomingCell = find.bySemanticsLabel(
      RegExp(r'^Upcoming Program, .+, upcoming$'),
    );
    expect(upcomingCell, findsOneWidget);
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 400));
    expect(guide.focusedProgramId, isNot(current.id));
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.select,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tunes, 0);
    await tester.tap(channelRail);
    await tester.pump();
    expect(guide.focusedProgramId, current.id);

    for (final status in ['currently airing', 'ended', 'upcoming']) {
      final programs = find.bySemanticsLabel(RegExp(status));
      expect(programs, findsOneWidget);
      final program = programs.first;
      final semantics = tester.getSemantics(program).getSemanticsData();
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('responsive PiP geometry and Guide focus remain coherent', (
    tester,
  ) async {
    final lineup = _Lineup(20);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    var tunes = 0;
    var closes = 0;

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [
      Size(800, 600),
      Size(1920, 719),
      Size(1280, 720),
      Size(800, 720),
      Size(600, 720),
      Size(1360, 840),
      Size(1920, 899),
      Size(1600, 900),
      Size(1920, 1079),
      Size(1920, 1080),
      Size(2560, 1440),
      Size(3840, 2160),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onOpenPlayer: () {},
            onClose: () => closes++,
            onTune: (_) async => tunes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picture = find.byKey(const Key('guide-picture-in-picture'));
      expect(picture, findsOneWidget);
      expect(
        find.byKey(const Key('guide-picture-corner-mask')),
        findsOneWidget,
      );
      final pictureSize = tester.getSize(picture);
      expect(
        pictureSize.width / pictureSize.height,
        closeTo(16 / 9, 0.001),
        reason: '$size',
      );
      final policy = GuideLayoutPolicy.forSize(size, hasPicture: true);
      expect(
        pictureSize.width,
        closeTo(policy.pictureWidth, 1),
        reason: '$size',
      );
      final list = tester.widget<ListView>(
        find.byKey(const Key('guide-schedule-list')),
      );
      final scheduleHeight = tester
          .getSize(find.byKey(const Key('guide-schedule-list')))
          .height;
      final standardFiveRowSize =
          size == const Size(1280, 720) ||
          size == const Size(1920, 1080) ||
          size == const Size(2560, 1440) ||
          size == const Size(3840, 2160);
      expect(
        (scheduleHeight / list.itemExtent!).floor(),
        greaterThanOrEqualTo(standardFiveRowSize ? 5 : 3),
        reason: '$size',
      );
      expect(
        tester.widget<Material>(find.byKey(const Key('classic-guide'))).color,
        Colors.transparent,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    final pictureSemantics = find.bySemanticsLabel(
      'Now playing picture in picture. Open full player.',
    );
    expect(pictureSemantics, findsOneWidget);
    final semantics = tester.getSemantics(pictureSemantics).getSemanticsData();
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    expect(guide.focusedProgram, isNotNull);
    expect(guide.selectedProgram, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(guide.selectedProgramId, guide.focusedProgramId);
    expect(tunes, 1);

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () => closes++,
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final classicList = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    expect(
      (tester.getSize(find.byKey(const Key('guide-schedule-list'))).height /
              classicList.itemExtent!)
          .floor(),
      greaterThanOrEqualTo(5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(closes, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Guide details project Plex metadata and artwork color', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(1, artworkBytes: _tinyPng);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Drama Seven',
        source: ManualSource([
          ChannelItem(
            id: 'episode',
            title: 'The Arrival',
            duration: const Duration(hours: 24),
            showTitle: 'Signal House',
            poster: Uri(path: '/poster'),
            summary: 'A mysterious signal changes the course of the mission.',
            contentRating: 'TV-14',
            genres: const ['Drama', 'Science Fiction'],
            year: 2026,
            seasonNumber: 1,
            episodeNumber: 2,
            resolution: '4k',
            videoCodec: 'hevc',
            audioCodec: 'eac3',
            audioChannels: 6,
            dynamicRange: 'hdr10',
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 7,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('SIGNAL HOUSE'), findsOneWidget);
    expect(find.text('S01E02'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const Key('guide-program-meta'))).data,
      contains('2026'),
    );
    expect(find.text('Drama • Science Fiction'), findsOneWidget);
    for (final badge in ['TV-14', '4K', 'HDR10', 'EAC3', '5.1']) {
      expect(find.textContaining(badge), findsOneWidget);
    }
    expect(
      find.text('A mysterious signal changes the course of the mission.'),
      findsOneWidget,
    );
    expect(lineup.artworkLoads, 1);
    expect(tester.takeException(), isNull);
    final background = tester.widget<AnimatedContainer>(
      find.byKey(const Key('guide-info-dynamic-background')),
    );
    final gradient = (background.decoration! as BoxDecoration).gradient!;
    final roles = LineupTheme.of(
      tester.element(find.byKey(const Key('guide-info-dynamic-background'))),
    );
    expect(
      (gradient as RadialGradient).colors.first,
      isNot(
        Color.alphaBlend(
          roles.progressFill.withValues(alpha: 0.48),
          roles.primarySurface,
        ),
      ),
    );
  });

  testWidgets(
    'Guide details keep loading, retry, and error scoped to focused channel',
    (tester) async {
      final now = DateTime.utc(2026, 1, 1, 12, 30);
      final lineup = _Lineup(2, artworkBytes: _tinyPng)
        ..settings = const LineupSettings(
          guideHours: 4,
          reduceMotion: true,
          guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
        );
      lineup.channels = [
        Channel(
          id: 'channel-a',
          number: 1,
          name: 'Channel A',
          source: ManualSource([
            ChannelItem(
              id: 'program-a',
              title: 'Program A',
              duration: const Duration(hours: 24),
              poster: Uri.parse('/poster-a'),
              backdrop: Uri.parse('/backdrop-a'),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now,
          shuffleSeed: 1,
        ),
        Channel(
          id: 'channel-b',
          number: 2,
          name: 'Channel B',
          source: const ManualSource([
            ChannelItem(
              id: 'program-b',
              title: 'Program B',
              duration: Duration(hours: 24),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now,
          shuffleSeed: 2,
        ),
      ];
      lineup.currentChannelId = 'channel-a';
      addTearDown(lineup.dispose);
      final firstLoad = Completer<ScheduleIndex>();
      final retryLoad = Completer<ScheduleIndex>();
      var channelBAttempts = 0;
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (channel) {
          if (channel.id == 'channel-a') {
            return Future.value(_schedule(channel));
          }
          channelBAttempts++;
          return channelBAttempts == 1 ? firstLoad.future : retryLoad.future;
        },
      );
      addTearDown(guide.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      guide.selectProgram(guide.row('channel-a').programs.first);
      await tester.pumpAndSettle();
      final details = find.byKey(const Key('guide-info-dynamic-background'));
      Finder detailText(String value) =>
          find.descendant(of: details, matching: find.text(value));
      expect(detailText('Program A'), findsOneWidget);
      expect(
        find.descendant(
          of: details,
          matching: find.byKey(const Key('guide-info-backdrop')),
        ),
        findsOneWidget,
      );

      guide.moveVertical(1);
      await tester.pump();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Loading schedule…'), findsWidgets);
      expect(
        find.descendant(
          of: details,
          matching: find.byKey(const Key('guide-info-backdrop')),
        ),
        findsNothing,
      );

      firstLoad.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Schedule unavailable'), findsWidgets);
      expect(detailText('Program A'), findsNothing);
      expect(lineup.currentChannelId, 'channel-a');

      await guide.retry('channel-b');
      await tester.pump();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Retrying…'), findsWidgets);
      expect(detailText('Program A'), findsNothing);

      retryLoad.completeError(StateError('still offline'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Guide details identify a focused ready row with no programs', (
    tester,
  ) async {
    final lineup = _Lineup(2)
      ..settings = const LineupSettings(guideHours: 0, reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    guide.moveVertical(1);
    await tester.pump();

    expect(guide.row('channel-1').state, GuideLoadState.ready);
    expect(find.text('2 • Channel 1'), findsOneWidget);
    expect(find.text('No programs scheduled in this time range'), findsWidgets);
  });

  testWidgets('PiP information color loads artwork only from source metadata', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(2);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'without-artwork',
        number: 1,
        name: 'Home Video',
        source: const ManualSource([
          ChannelItem(
            id: 'without-artwork-item',
            title: 'Family Movie',
            duration: Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 1,
      ),
      Channel(
        id: 'with-artwork',
        number: 2,
        name: 'Plex Movie',
        source: ManualSource([
          ChannelItem(
            id: 'with-artwork-item',
            title: 'Catalog Movie',
            duration: const Duration(hours: 24),
            poster: Uri.parse('/poster-that-fails'),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 2,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1920, 1080),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            pictureInPicture: const SizedBox.expand(),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(guide.focusedChannelId, 'without-artwork');
      expect(tester.takeException(), isNull, reason: '$size');
    }
    expect(lineup.artworkLoads, 0);

    guide.moveVertical(1);
    await tester.pump();

    expect(guide.focusedChannelId, 'with-artwork');
    await tester.pumpAndSettle();
    expect(lineup.artworkLoads, 1);
  });

  testWidgets('Guide omits incomplete episode coordinates', (tester) async {
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    lineup.channels = [
      for (final (index, item) in [
        const ChannelItem(
          id: 'season-only',
          title: 'Season only',
          showTitle: 'Incomplete Show',
          duration: Duration(hours: 24),
          seasonNumber: 1,
        ),
        const ChannelItem(
          id: 'episode-only',
          title: 'Episode only',
          showTitle: 'Incomplete Show',
          duration: Duration(hours: 24),
          episodeNumber: 2,
        ),
      ].indexed)
        Channel(
          id: 'channel-$index',
          number: index + 1,
          name: 'Channel $index',
          source: ManualSource([item]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: index + 1,
        ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('S01E00'), findsNothing);
    guide.moveVertical(1);
    await tester.pumpAndSettle();
    expect(find.text('S00E02'), findsNothing);
  });

  testWidgets('Guide artwork mode renders backdrop and preferred clear logo', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(1, artworkBytes: _wideLogoPng)
      ..settings = const LineupSettings(
        guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
      );
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Drama Seven',
        source: ManualSource([
          ChannelItem(
            id: 'episode',
            title: 'The Arrival',
            showTitle: 'Signal House',
            duration: const Duration(hours: 24),
            showThumb: '/poster',
            backdrop: Uri.parse('/backdrop'),
            clearLogo: Uri.parse('/clear-logo'),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 7,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => precacheImage(
        MemoryImage(_wideLogoPng),
        tester.element(find.byType(GuideView)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide-info-backdrop')), findsOneWidget);
    expect(find.byKey(const Key('guide-clear-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Signal House logo'), findsOneWidget);
    expect(lineup.artworkLoads, 3);
    final background = tester.widget<AnimatedContainer>(
      find.byKey(const Key('guide-info-dynamic-background')),
    );
    expect(
      (background.decoration! as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
  });

  for (final (description, bytes) in [
    ('invalid clear-logo bytes', Uint8List.fromList(const [1, 2, 3])),
    ('decoded narrow clear-logo', _narrowLogoPng),
  ]) {
    testWidgets('$description retains the textual title', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lineup = _Lineup(1, artworkBytes: bytes);
      addTearDown(lineup.dispose);
      lineup.channels = [
        Channel(
          id: 'channel',
          number: 7,
          name: 'Drama Seven',
          source: ManualSource([
            ChannelItem(
              id: 'episode',
              title: 'The Arrival',
              showTitle: 'Signal House',
              duration: const Duration(hours: 24),
              poster: Uri.parse('/poster'),
              clearLogo: Uri.parse('/clear-logo'),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: 7,
        ),
      ];
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      addTearDown(guide.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (bytes == _narrowLogoPng) {
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(GuideView)),
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('guide-clear-logo')), findsNothing);
      expect(
        find.byKey(const Key('guide-clear-logo-fallback')),
        findsOneWidget,
      );
      expect(find.text('SIGNAL HOUSE'), findsOneWidget);
    });
  }

  testWidgets('physical 4K at DPR 2 uses the 1080p Guide row budget', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final lineup = _Lineup(20);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(GuideView))),
      const Size(1920, 1080),
    );
    expect(
      tester.getSize(find.byKey(const Key('guide-picture-in-picture'))).width,
      closeTo(576, 0.01),
    );
    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    expect(
      (tester.getSize(find.byKey(const Key('guide-schedule-list'))).height /
              list.itemExtent!)
          .floor(),
      greaterThanOrEqualTo(5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('schedule loading labels are not repeated as live regions', (
    tester,
  ) async {
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    final pending = Completer<ScheduleIndex>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (_) => pending.future,
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final status = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Loading schedule…',
    );
    expect(status, findsOneWidget);
    expect(tester.widget<Semantics>(status).properties.liveRegion, isNot(true));

    pending.complete(_schedule(lineup.channels.single));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('search owns Escape and Enter focus without tuning', (
    tester,
  ) async {
    final lineup = _Lineup(3);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    var closes = 0;
    var tunes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () => closes++,
          onTune: (_) async => tunes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('guide-channel-search'));
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.tap(search);
    await tester.enterText(search, '   ');
    await tester.pump();
    expect(guide.searchQuery, isEmpty);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsNothing);

    guide.setSearchQuery('CHANNEL 1');
    await tester.pump();
    final searchValue = tester.widget<TextField>(search).controller!.value;
    expect(searchValue.text, 'channel 1');
    expect(searchValue.selection, const TextSelection.collapsed(offset: 9));

    await tester.enterText(search, 'Channel 2');
    await tester.pump();
    expect(guide.channels.single.id, 'channel-2');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
    expect(tunes, 0);
    await tester.tap(search);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(guide.searchQuery, isEmpty);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(closes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
    expect(tunes, 0);
    expect(closes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closes, 1);
    guide.dispose();
    lineup.dispose();
  });

  testWidgets(
    'timeline controls expose one aligned marker and 30-minute steps',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1, 23, 30);
      final lineup = _Lineup(2);
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (channel) async => _schedule(channel),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder marker() => find.byKey(const Key('guide-now-line'));
      Finder focusedCell() => find.byKey(ValueKey(guide.focusedProgram!.id));

      expect(marker(), findsOneWidget);
      expect(find.bySemanticsLabel('Current time'), findsOneWidget);
      expect(
        find.ancestor(
          of: marker(),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(marker()).dx,
        closeTo(tester.getTopLeft(focusedCell()).dx, 0.01),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('guide-earlier')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('guide-later')));
      await tester.pump();
      expect(guide.windowStart, DateTime.utc(2026, 1, 2));
      expect(find.byKey(const Key('guide-midnight-date')), findsWidgets);
      await tester.tap(find.byKey(const Key('guide-earlier')));
      await tester.pump();
      expect(guide.windowStart, DateTime.utc(2026, 1, 1, 23, 30));

      guide.moveWindow(2);
      now = guide.windowStart.add(const Duration(hours: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(marker()).dx,
        closeTo(
          tester.getTopLeft(focusedCell()).dx +
              tester.getSize(focusedCell()).width / 2,
          0.01,
        ),
      );

      guide.moveWindow(4);
      await tester.pump();
      expect(marker(), findsNothing);

      guide.dispose();
      lineup.dispose();
    },
  );

  testWidgets('removing a wrapping library label preserves channel search', (
    tester,
  ) async {
    const libraryId =
        'International television documentaries and limited series archive';
    final lineup = _Lineup(2);
    lineup.channels = [
      Channel(
        id: 'library-channel',
        number: 17,
        name: 'Library Channel',
        source: const LibrarySource(
          libraryId: libraryId,
          libraryType: PlexLibraryType.show,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now(),
        shuffleSeed: 1,
      ),
      lineup.channels.last,
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('guide-channel-search')),
      'Library',
    );
    guide.setLibraryFilter(libraryId);
    await tester.pump();

    final label = find.byKey(const Key('guide-active-library-label'));
    expect(label, findsOneWidget);
    expect(find.text('Libraries'), findsOneWidget);
    expect(tester.widget<Text>(label).data, libraryId);
    expect(tester.getSize(label).height, greaterThan(16));
    await tester.tap(find.byTooltip('Remove library filter'));
    await tester.pump();
    expect(guide.libraryFilterId, isNull);
    expect(guide.searchQuery, 'library');

    guide.dispose();
    lineup.dispose();
  });

  testWidgets(
    'standard resolutions and enlarged text do not clip Guide controls',
    (tester) async {
      final lineup = _Lineup(20)
        ..settings = const LineupSettings(reduceMotion: true);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in const [
        Size(1280, 720),
        Size(1920, 1080),
        Size(2560, 1440),
        Size(3840, 2160),
      ]) {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: GuideView(
              controller: guide,
              pictureInPicture: const ColoredBox(color: Colors.black),
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
        expect(find.byKey(const Key('guide-hours')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size');
      }
      guide.dispose();
      lineup.dispose();
    },
  );

  testWidgets('Now Playing context remains stable while Guide focus moves', (
    tester,
  ) async {
    final lineup = _Lineup(2)..currentChannelId = 'channel-0';
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = find.byKey(const Key('guide-now-playing-context'));
    expect(context, findsOneWidget);
    expect(tester.widget<Text>(context).data, contains('Channel 0'));

    guide.moveVertical(1);
    await tester.pump();
    expect(guide.focusedChannelId, 'channel-1');
    expect(tester.widget<Text>(context).data, contains('Channel 0'));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Now Playing context setting updates its Guide consumer', (
    tester,
  ) async {
    final lineup = _Lineup(2)..currentChannelId = 'channel-0';
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-now-playing-context')), findsOneWidget);

    lineup.settings = lineup.settings.copyWith(nowWatchingBanner: false);
    lineup.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('guide-now-playing-context')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('vertical Guide position survives route disposal and return', (
    tester,
  ) async {
    final lineup = _Lineup(100);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    Widget buildGuide() => MaterialApp(
      home: GuideView(controller: guide, onClose: () {}, onTune: (_) async {}),
    );

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildGuide());
    await tester.pumpAndSettle();
    const scheduleList = Key('guide-schedule-list');
    final initialScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(scheduleList),
        matching: find.byType(Scrollable),
      ),
    );
    initialScrollable.position.jumpTo(1200);
    await tester.pump();
    final rowHeight = tester
        .widget<ListView>(find.byKey(scheduleList))
        .itemExtent!;
    final remembered = guide.verticalOffsetFor(rowHeight);
    expect(remembered, greaterThan(500));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(scheduleList),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, closeTo(remembered, 1));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('focused row survives row-height resize and route recreation', (
    tester,
  ) async {
    final lineup = _Lineup(100)
      ..settings = const LineupSettings(reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    Widget buildGuide() => MaterialApp(
      home: GuideView(controller: guide, onClose: () {}, onTune: (_) async {}),
    );
    void expectFocusedRowVisible() {
      final list = tester.widget<ListView>(
        find.byKey(const Key('guide-schedule-list')),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('guide-schedule-list')),
          matching: find.byType(Scrollable),
        ),
      );
      final first = (scrollable.position.pixels / list.itemExtent!).floor();
      final visible = (scrollable.position.viewportDimension / list.itemExtent!)
          .ceil();
      expect(first, lessThanOrEqualTo(guide.focusedChannelIndex));
      expect(guide.focusedChannelIndex, lessThan(first + visible));
    }

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    for (var index = 0; index < 20; index++) {
      guide.moveVertical(1);
    }
    await tester.pump();
    await tester.pump();
    expect(guide.focusedChannelIndex, 20);

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 899);
    await tester.pump();
    await tester.pump();
    expectFocusedRowVisible();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump();
    expectFocusedRowVisible();

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('focus fully reveals a trailing partial row', (tester) async {
    final lineup = _Lineup(100)
      ..settings = const LineupSettings(reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('guide-schedule-list')),
        matching: find.byType(Scrollable),
      ),
    );
    final rowHeight = list.itemExtent!;
    scrollable.position.jumpTo(rowHeight * 3 + 5);
    await tester.pump();

    final trailingPartialRow =
        (scrollable.position.pixels / rowHeight).floor() +
        (scrollable.position.viewportDimension / rowHeight).floor();
    guide.moveVertical(trailingPartialRow);
    await tester.pump();
    await tester.pump();

    expect(guide.focusedChannelIndex, trailingPartialRow);
    final viewportTop = scrollable.position.pixels;
    final viewportBottom = viewportTop + scrollable.position.viewportDimension;
    final rowTop = rowHeight * trailingPartialRow;
    final rowBottom = rowTop + rowHeight;
    expect(rowTop, greaterThanOrEqualTo(viewportTop));
    expect(rowBottom, lessThanOrEqualTo(viewportBottom));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });
}

ScheduleIndex _schedule(Channel channel) => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

String _testTime(DateTime value) =>
    const DefaultMaterialLocalizations().formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: false,
    );

class _Lineup extends LineupController {
  _Lineup(int count, {this.artworkBytes})
    : super(
        store: _Store(),
        credentials: _Credentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    channels = List.generate(
      count,
      (index) => Channel(
        id: 'channel-$index',
        number: index + 1,
        name: 'Channel $index',
        source: ManualSource([
          ChannelItem(
            id: 'program-$index',
            title: 'Program $index',
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: index,
      ),
    );
    stage = SetupStage.ready;
  }

  final Uint8List? artworkBytes;
  int artworkLoads = 0;

  @override
  Future<Uint8List?> artworkForPath(Uri path) async {
    artworkLoads++;
    return artworkBytes;
  }
}

class _Store implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<AppStoreLoadResult> load() async =>
      const AppStoreLoadResult(PersistedState());
  @override
  Future<void> save(PersistedState state) async {}
}

class _Credentials implements CredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccountToken() async => null;
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
}
