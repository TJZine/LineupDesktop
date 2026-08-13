import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

void main() {
  testWidgets('established viewport work is independent of lineup cardinality', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    for (final count in [200, 500, 1000]) {
      final lineup = _Lineup(count);
      var loads = 0;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async {
          loads++;
          return _schedule(channel);
        },
      );
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
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('1000-channel Guide builds a bounded accessible viewport', (
    tester,
  ) async {
    final lineup = _Lineup(1000);
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
    );
    final rssBefore = ProcessInfo.currentRss;
    final firstViewport = Stopwatch()..start();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
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

    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('loading, error, retry, and program semantics stay visible', (
    tester,
  ) async {
    final lineup = _Lineup(1);
    var fail = true;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        if (fail) throw StateError('offline');
        return _schedule(channel);
      },
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

    expect(
      find.bySemanticsLabel(RegExp('Schedule failed to load')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.text('Schedule unavailable — select to retry'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('currently airing')), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('responsive PiP geometry and Guide focus remain coherent', (
    tester,
  ) async {
    final lineup = _Lineup(20);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    var tunes = 0;

    for (final size in const [
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
      Size(3840, 2160),
      Size(1360, 840),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onOpenPlayer: () {},
            onClose: () {},
            onTune: (_) async => tunes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picture = find.byKey(const Key('guide-picture-in-picture'));
      expect(picture, findsOneWidget);
      final pictureSize = tester.getSize(picture);
      expect(
        pictureSize.width / pictureSize.height,
        closeTo(16 / 9, 0.001),
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    expect(guide.focusedProgram, isNotNull);
    expect(guide.selectedProgram, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(guide.selectedProgramId, guide.focusedProgramId);
    expect(tunes, 1);

    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Now Playing context remains stable while Guide focus moves', (
    tester,
  ) async {
    final lineup = _Lineup(2)..currentChannelId = 'channel-0';
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
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

  testWidgets('vertical Guide position survives route disposal and return', (
    tester,
  ) async {
    final lineup = _Lineup(100);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    Widget buildGuide() => MaterialApp(
      home: GuideView(controller: guide, onClose: () {}, onTune: (_) async {}),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(buildGuide());
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    final remembered = guide.verticalOffset;
    expect(remembered, greaterThan(500));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(buildGuide());
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, closeTo(remembered, 1));

    await tester.binding.setSurfaceSize(null);
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

class _Lineup extends LineupController {
  _Lineup(int count)
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
}

class _Store implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<PersistedState> load() async => const PersistedState();
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
