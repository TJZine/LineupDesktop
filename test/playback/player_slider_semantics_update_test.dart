import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/semantics_update_recorder.dart';
import '../support/test_doubles.dart';

void main() {
  final binding = SemanticsRecordingBinding();

  test(
    'structural replay accepts connected creation, destruction and reparent',
    () {
      final replay = DesktopSemanticsReplay();
      replay.apply(const [
        SemanticsUpdateRecord(0, children: [1, 2]),
        SemanticsUpdateRecord(1, children: [3]),
        SemanticsUpdateRecord(2),
        SemanticsUpdateRecord(3),
      ]);
      expect(replay.firstError, isNull);
      replay.apply(const [
        SemanticsUpdateRecord(1),
        SemanticsUpdateRecord(2, children: [3]),
        SemanticsUpdateRecord(3, value: 'moved'),
      ]);
      expect(replay.firstError, isNull);
      expect(replay.parents[3], 2);
      expect(replay.traversal.map((node) => node.id), [0, 1, 2, 3]);
      replay.apply(const [SemanticsUpdateRecord(0)]);
      expect(replay.firstError, isNull);
      expect(replay.traversal.map((node) => node.id), [0]);
    },
  );

  test('structural replay rejects an outgoing unreachable leaf', () {
    final replay = DesktopSemanticsReplay();
    replay.apply(const [
      SemanticsUpdateRecord(0, children: [1]),
      SemanticsUpdateRecord(1),
    ]);
    replay.apply(const [SemanticsUpdateRecord(1), SemanticsUpdateRecord(9)]);
    expect(
      replay.firstError,
      contains('9 will not be in the tree and is not the new root'),
    );
  });

  test('structural replay rejects pending children without initialization', () {
    final replay = DesktopSemanticsReplay();
    replay.apply(const [
      SemanticsUpdateRecord(0, children: [1]),
    ]);
    expect(replay.firstError, contains('Nodes left pending'));
  });

  testWidgets('S2 stable visible mount and value update', (tester) async {
    final h = await _Harness.mount(tester, binding, visible: true);
    h.position(const Duration(minutes: 20));
    await h.frames();
    h.expectHealthy();
    h.expectSlider();
    h.expectApprovedSliderGroupAndOrder();
    expect(
      h.replay.traversal.where((node) => node.isSlider).single.value,
      '33%',
    );
    await h.close();
  }, semanticsEnabled: true);

  final scenarios = <String, (bool, Future<void> Function(_Harness))>{
    'S1 fresh hidden entry': (
      false,
      (h) async {
        h.step('showOsd');
        h.fixture.player.showOsd();
        await h.frames();
      },
    ),
    'S3 dismissal and midfade restoration': (
      true,
      (h) async {
        h.step('closeOverlay');
        h.fixture.player.closeOverlay();
        await h.frames(6);
        h.step('restore during retirement');
        h.fixture.player.showOsd();
        await h.frames();
        h.fixture.player.closeOverlay();
        await h.frames();
        h.fixture.player.showOsd();
        await h.frames();
      },
    ),
    'S4 rapid reversal': (
      false,
      (h) async {
        h.step('rapid reversal');
        for (var i = 0; i < 6; i++) {
          h.fixture.player.showOsd();
          await h.frames(1);
          h.fixture.player.closeOverlay();
          await h.frames(1);
        }
        h.fixture.player.showOsd();
        await h.frames();
      },
    ),
    'S5 resize while menu excludes a live Slider': (
      true,
      (h) async {
        h.step('open menu');
        h.menu.value = true;
        await h.frames(3);
        h.expectHealthy();
        h.step('position while excluded');
        h.position(const Duration(minutes: 20));
        await h.frames(3);
        h.expectHealthy();
        h.step('resize while excluded');
        await h.tester.binding.setSurfaceSize(const Size(1000, 700));
        await h.frames(3);
        h.step('restore menu');
        h.menu.value = false;
        await h.frames();
        h.position(const Duration(minutes: 30));
        await h.frames();
        h.expectHealthy();
        h.expectSlider(value: '50%');
      },
    ),
    'S6 menu during entry': (
      false,
      (h) async {
        h.step('entry');
        h.fixture.player.showOsd();
        await h.frames(1);
        h.menu.value = true;
        await h.frames();
        h.position(const Duration(minutes: 25));
        await h.frames(3);
        h.menu.value = false;
        await h.frames();
      },
    ),
    'S8 retirement with position and resize': (
      true,
      (h) async {
        h.step('closeOverlay');
        h.fixture.player.closeOverlay();
        await h.frames(1);
        h.position(const Duration(minutes: 15));
        await h.frames(1);
        await h.tester.binding.setSurfaceSize(const Size(900, 650));
        await h.frames();
        h.fixture.player.showOsd();
        await h.frames();
      },
    ),
    'S10 route replacement during entry': (
      false,
      (h) async {
        h.step('entry');
        h.fixture.player.showOsd();
        await h.frames(2);
        h.step('replace route');
        unawaited(
          h.navigator.currentState!.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const Text('Other route')),
          ),
        );
        await h.frames(40);
        h.expectHealthy();
        expect(h.replay.traversal.where((node) => node.isSlider), isEmpty);
      },
    ),
  };

  for (final entry in scenarios.entries) {
    testWidgets(entry.key, (tester) async {
      final h = await _Harness.mount(tester, binding, visible: entry.value.$1);
      await entry.value.$2(h);
      h.expectHealthy();
      if (!entry.key.startsWith('S10')) h.expectSlider();
      await h.close();
    }, semanticsEnabled: true);
  }

  for (final destination in [
    'tracks',
    'miniGuide',
    'channelNumber',
    'fullGuide',
    'sleep picker',
  ]) {
    testWidgets('OSD transition to $destination keeps updates connected', (
      tester,
    ) async {
      final h = await _Harness.mount(tester, binding, visible: true);
      h.step(destination);
      switch (destination) {
        case 'tracks':
          h.fixture.player.showTracks(PlayerTrackType.subtitle);
        case 'miniGuide':
          h.fixture.player.showMiniGuide();
        case 'channelNumber':
          h.fixture.player.appendChannelDigit('7');
        case 'fullGuide':
          h.fixture.player.showFullGuide();
        case 'sleep picker':
          h.fixture.player.showSleepTimer();
      }
      await h.frames();
      h.expectHealthy();
      h.fixture.player.showOsd();
      await h.frames();
      h.expectHealthy();
      h.expectSlider();
      await h.close();
    }, semanticsEnabled: true);
  }

  testWidgets('visible Slider keyboard, pointer and menu isolation', (
    tester,
  ) async {
    final h = await _Harness.mount(tester, binding, visible: true);
    final slider = find.byType(Slider);
    final state = tester.state(slider);
    final rect = tester.getRect(slider);
    final hit = HitTestResult();
    tester.binding.hitTestInView(hit, rect.center, tester.view.viewId);
    expect(
      hit.path.any(
        (entry) => entry.target.runtimeType.toString() == '_RenderSlider',
      ),
      isTrue,
    );
    FocusNode? sliderFocus;
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (context != null &&
          (context.widget is Slider ||
              context.findAncestorWidgetOfExactType<Slider>() != null)) {
        sliderFocus = focus;
        break;
      }
    }
    expect(sliderFocus, isNotNull, reason: 'Tab must reach Slider');
    final beforeArrow = h.fixture.native.seeks.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(h.fixture.native.seeks.length, greaterThan(beforeArrow));
    final beforeDrag = h.fixture.native.seeks.length;
    await tester.dragFrom(
      rect.centerLeft + const Offset(40, 0),
      const Offset(200, 0),
    );
    await tester.pump();
    expect(h.fixture.native.seeks.length, greaterThan(beforeDrag));
    h.step('interaction menu open');
    h.menu.value = true;
    await h.frames(3);
    expect(sliderFocus!.hasPrimaryFocus, isFalse);
    expect(h.replay.traversal.where((node) => node.isSlider), isEmpty);
    final beforeMenuInput = h.fixture.native.seeks.length;
    await tester.tapAt(rect.center);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(h.fixture.native.seeks.length, beforeMenuInput);
    h.step('interaction menu restore');
    h.menu.value = false;
    await h.frames();
    expect(identical(tester.state(slider), state), isTrue);
    h.expectHealthy();
    h.expectSlider();
    h.fixture.player.closeOverlay();
    await h.frames();
    final beforeHiddenInput = h.fixture.native.seeks.length;
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(h.fixture.native.seeks.length, beforeHiddenInput);
    h.expectHealthy();
    await h.close();
  }, semanticsEnabled: true);
}

class _Harness {
  _Harness(this.tester, this.binding);
  final WidgetTester tester;
  final SemanticsRecordingBinding binding;
  final fixture = _Fixture();
  final menu = ValueNotifier(false);
  final navigator = GlobalKey<NavigatorState>();
  final replay = DesktopSemanticsReplay();

  static Future<_Harness> mount(
    WidgetTester tester,
    SemanticsRecordingBinding binding, {
    required bool visible,
  }) async {
    final h = _Harness(tester, binding);
    await tester.binding.setSurfaceSize(const Size(1280, 750));
    binding.onBatch = h.replay.apply;
    addTearDown(h.close);
    await h.fixture.player.tune('channel');
    if (visible) {
      h.fixture.player.showOsd();
    } else {
      while (h.fixture.player.overlay != PlayerOverlay.none) {
        h.fixture.player.closeOverlay();
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: h.navigator,
        builder: LineupCanvas.builder,
        home: _MenuShell(
          menu: h.menu,
          child: PlayerView(controller: h.fixture.player, openGuide: () {}),
        ),
      ),
    );
    await h.frames(5);
    h.expectHealthy();
    if (visible) h.expectSlider();
    return h;
  }

  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    binding.onBatch = null;
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
    await tester.pump(const Duration(seconds: 10));
    menu.dispose();
    await tester.binding.setSurfaceSize(null);
  }

  void step(String value) => replay.step = value;
  void expectHealthy() => expect(replay.firstError, isNull);
  void expectSlider({String? value}) {
    final sliders = replay.traversal.where((node) => node.isSlider);
    expect(sliders, hasLength(1));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(
      sliders.single.value,
      value ?? '${(slider.value / slider.max * 100).round()}%',
    );
  }

  void expectApprovedSliderGroupAndOrder() {
    final traversal = replay.traversal;
    final slider = traversal.singleWhere((node) => node.isSlider);
    final group = replay.data[replay.parents[slider.id]]!;
    expect(group.label, isEmpty);
    expect(group.value, isEmpty);
    expect(group.actions, 0);
    expect(group.children, hasLength(2));
    expect(group.children.first, slider.id);
    final portal = replay.data[group.children.last]!;
    expect(portal.traversalParent, group.id);
    expect(portal.label, isEmpty);
    expect(portal.value, isEmpty);
    expect(portal.actions, 0);
    expect(portal.children, isEmpty);
    // Gate A approves the unlabeled Slider group after the OSD controls.
    // Derive identities from the actual controls, never pin allocated node IDs.
    final controls = [
      find.byTooltip('Previous channel'),
      find.byTooltip('Pause'),
      find.byTooltip('Next channel'),
      find.byKey(const Key('player-osd-subtitles')),
      find.byKey(const Key('player-osd-audio')),
      find.byKey(const Key('player-osd-sleep')),
      find.byTooltip('Full screen'),
    ];
    var previousIndex = -1;
    for (final control in controls) {
      final id = tester.getSemantics(control).id;
      final index = traversal.indexWhere((node) => node.id == id);
      expect(index, greaterThan(previousIndex));
      expect(index, lessThan(traversal.indexOf(group)));
      previousIndex = index;
    }
  }

  Future<void> frames([int count = 30]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void position(Duration value) =>
      fixture.native.emit(fixture.native.status, position: value);
}

/// Same exclusion ancestry and pointer/focus containment as the immersive
/// LineupShell menu. Barrier taps intentionally keep it open for the assertion.
class _MenuShell extends StatelessWidget {
  const _MenuShell({required this.child, required this.menu});
  final Widget child;
  final ValueNotifier<bool> menu;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: menu,
    builder: (context, open, _) => Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: open,
          child: TooltipVisibility(
            visible: TooltipVisibility.of(context) && !open,
            child: ExcludeFocus(excluding: open, child: child),
          ),
        ),
        if (open) ...[
          ModalBarrier(
            dismissible: true,
            onDismiss: () {},
            color: Colors.black45,
          ),
          Align(
            alignment: Alignment.topRight,
            child: FocusScope(
              autofocus: true,
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: Material(
                  child: TextButton(
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Menu item'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Fixture {
  _Fixture() {
    guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => buildSchedule(
        (channel.source as ManualSource).items,
        mode: channel.playbackMode,
        seed: channel.shuffleSeed,
      ),
    )..requestViewport(0, 1);
    player = PlayerCoordinator(player: native, lineup: lineup, guide: guide);
  }
  final lineup = _Lineup();
  final native = FakeNativePlayer(
    initialStatus: const PlayerStatus(
      state: PlayerState.playing,
      message: 'Playing',
    ),
    position: const Duration(minutes: 10),
    duration: const Duration(hours: 1),
  );
  late final GuideController guide;
  late final PlayerCoordinator player;
  void dispose() {
    player.dispose();
    guide.dispose();
    lineup.dispose();
  }
}

class _Lineup extends LineupController {
  _Lineup()
    : super(
        store: MemoryAppStore(clientId: 'test'),
        credentials: MemoryCredentialStore(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    installScenario(
      LineupScenario(
        channels: [
          Channel(
            id: 'channel',
            number: 7,
            name: 'Synthetic channel',
            source: ManualSource([
              ChannelItem(
                id: 'program',
                title: 'Synthetic program',
                duration: const Duration(hours: 24),
              ),
            ]),
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime.now().subtract(const Duration(hours: 1)),
            shuffleSeed: 1,
          ),
        ],
        currentChannelId: 'channel',
        settings: const LineupSettings(dvrControlsEnabled: true),
        stage: SetupStage.ready,
      ),
    );
  }
  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://$itemId')),
      ]);
}
