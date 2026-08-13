import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

void main() {
  const goldenClock = _GoldenClock();

  testWidgets('populated Guide with PiP', (tester) async {
    final lineup = _GoldenLineup();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: _schedule,
      clock: goldenClock.call,
    )..requestViewport(0, 10);
    await tester.pump();
    await _pump(
      tester,
      const Size(1920, 1080),
      GuideView(
        controller: guide,
        pictureInPicture: const ColoredBox(
          color: Color(0xFF090A0D),
          child: Center(
            child: Text('PLAYBACK SURFACE', style: TextStyle(fontSize: 18)),
          ),
        ),
        onOpenPlayer: () {},
        playbackMessage: 'Playing synthetic fixture',
        onClose: () {},
        onTune: (_) async {},
      ),
    );

    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('baselines/guide_1920x1080.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('compact focused and tuned Guide', (tester) async {
    final lineup = _GoldenLineup()..currentChannelId = 'channel-3';
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: _schedule,
      clock: goldenClock.call,
    )..requestViewport(0, 10);
    await tester.pump();
    guide.moveVertical(3);
    await _pump(
      tester,
      const Size(1280, 720),
      GuideView(
        controller: guide,
        playbackMessage: 'Playing synthetic fixture',
        onClose: () {},
        onTune: (_) async {},
      ),
    );

    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('baselines/guide_compact_1280x720.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });
}

Future<void> _pump(WidgetTester tester, Size size, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.dark,
      home: RepaintBoundary(
        key: const Key('golden-root'),
        child: ColoredBox(color: LineupTheme.obsidian, child: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _GoldenClock {
  const _GoldenClock();
  DateTime call() => DateTime(2026, 8, 13, 20, 15);
}

Future<ScheduleIndex> _schedule(Channel channel) async => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

class _GoldenLineup extends LineupController {
  _GoldenLineup()
    : super(
        store: _Store(),
        credentials: _Credentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    channels = List.generate(
      12,
      (channel) => Channel(
        id: 'channel-$channel',
        number: 101 + channel * 3,
        name: [
          'Action Cinema',
          'Comedy Club',
          'Documentary',
          'Evening Drama',
        ][channel % 4],
        source: ManualSource([
          for (var program = 0; program < 8; program++)
            ChannelItem(
              id: 'item-$channel-$program',
              title: [
                'The Long Way Home',
                'City Stories',
                'After Midnight',
                'World in Focus',
              ][(channel + program) % 4],
              showTitle: program.isEven ? 'Lineup Originals' : null,
              duration: Duration(minutes: 24 + program * 4),
            ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime(2026, 8, 13, 18),
        shuffleSeed: channel,
      ),
    );
    stage = SetupStage.ready;
  }
}

class _Store implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'golden';
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
