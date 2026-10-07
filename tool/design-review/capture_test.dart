// Local design-review capture harness. Not part of the project test suite.
// Run: TZ=America/New_York flutter test --no-pub tool/design-review/capture_test.dart
// Optional: --name '<scene> @ <config>' to narrow.
@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../../test/support/golden_test_support.dart';
import '../../test/support/ui_fixture.dart';

const _key = Key('design-review-boundary');
final _fixedNow = DateTime.utc(2026, 1, 15, 3, 17);
final _syntheticArtwork = File('assets/branding/lineup-logo-mark.png')
    .readAsBytesSync();
final _nowPlayingArtwork = <Uri, Uint8List>{
  Uri.parse('test://now-playing/poster'): File(
    'test/support/now_playing/signal-after-midnight-poster.png',
  ).readAsBytesSync(),
  Uri.parse('test://now-playing/title'): File(
    'test/support/now_playing/signal-after-midnight-title.png',
  ).readAsBytesSync(),
  for (final name in ['elias-vale', 'mina-park', 'solomon-reed', 'clara-wynn'])
    Uri.parse(
      '/library/metadata/test/now-playing/cast-${name.split('-').first}',
    ): File('test/support/now_playing/cast-$name.png')
        .readAsBytesSync(),
};

typedef Config = ({String label, Size logical, double dpr, double text});

const List<Config> _configs = [
  (label: '1280x720', logical: Size(1280, 720), dpr: 1, text: 1),
  (label: '1366x768', logical: Size(1366, 768), dpr: 1, text: 1),
  (label: '1536x864@125', logical: Size(1536, 864), dpr: 1.25, text: 1),
  (label: '1920x1080', logical: Size(1920, 1080), dpr: 1, text: 1),
  (label: '1920x1200', logical: Size(1920, 1200), dpr: 1, text: 1),
  (label: '2560x1440', logical: Size(2560, 1440), dpr: 1, text: 1),
  (label: '3440x1440', logical: Size(3440, 1440), dpr: 1, text: 1),
  (label: '3840x2160', logical: Size(3840, 2160), dpr: 1, text: 1),
  (label: '1920x1080-text150', logical: Size(1920, 1080), dpr: 1, text: 1.5),
];

typedef Shot = Future<void> Function(String state);
typedef Scene = Future<void> Function(WidgetTester tester, Shot shot);

final Map<String, Scene> _scenes = {
  // ── Onboarding ──
  'onboarding': (tester, shot) async {
    await _pump(
      tester,
      (UiFixture()..controller.stage = SetupStage.welcome).build(),
    );
    await shot('welcome');
  },
  'linking': (tester, shot) async {
    final f = UiFixture()
      ..controller.stage = SetupStage.linking
      ..controller.activePin = PlexPin(
        id: 7,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
    await _pump(tester, f.build());
    await shot('code');
    f.controller.activePin = PlexPin(
      id: 7,
      code: 'ABCD',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    f.controller.notifyListeners();
    await _settle(tester);
    await shot('expired');
  },
  'linking-failure': (tester, shot) async {
    final f = UiFixture()
      ..controller.stage = SetupStage.linking
      ..controller.error =
          'Lineup could not connect to Plex. Check your connection and request a new code.';
    await _pump(tester, f.build());
    await shot('failure');
  },
  'profiles': (tester, shot) async {
    await _pump(tester, _profileSelectionFixture().build());
    await shot('selection');
    for (var index = 0; index < 3; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await _settle(tester);
    await shot('focused-name');
  },
  'profile-pin': (tester, shot) async {
    final f = UiFixture(controller: _RejectedPinController())
      ..controller.stage = SetupStage.profiles
      ..controller.profiles = const [
        PlexHomeUser(id: 'protected', name: 'Taylor', protected: true),
        PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
      ];
    await _pump(tester, f.build());
    await _tap(tester, find.text('Taylor'));
    await shot('pin');
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await _settle(tester);
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    await shot('pin-error');
  },
  'servers': (tester, shot) async {
    await _pump(tester, _serverFixture().build());
    await shot('selection');
  },
  'account-pickers': (tester, shot) async {
    final f = _serverFixture()
      ..controller.stage = SetupStage.ready
      ..controller.profiles = const [
        PlexHomeUser(id: 'protected', name: 'Taylor', protected: true),
        PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
      ];
    await _pump(tester, f.build());
    await _tap(tester, find.byTooltip('Open Lineup menu'));
    await _tap(tester, find.byKey(const Key('app-menu-account')));
    await _tap(tester, find.text('Switch profile'));
    await shot('profiles');
    await _tap(tester, find.text('Taylor'));
    await shot('pin');
    await _tap(tester, find.text('‹ Settings · Account'));
    await _tap(tester, find.text('Switch server'));
    await shot('servers');
    await _tap(tester, find.byTooltip('Open Lineup menu'));
    await shot('menu');
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const Key('immersive-app-menu')),
        matching: find.text('Guide'),
      ),
    );
    expect(f.controller.stage, SetupStage.ready);
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
  },

  // ── Channel setup ──
  'setup-libraries': (tester, shot) async {
    await _pump(tester, _noTicker(_libraryOutcomeFixture().build()));
    await shot('scan-outcomes');
  },
  'setup-configure': (tester, shot) async {
    await _pump(tester, _setupFixture().build());
    await _tap(tester, find.byKey(const ValueKey('scan-selected-libraries')));
    await shot('sources');
    await _tap(tester, find.byKey(const ValueKey('configure-section-1')));
    await shot('playback-order');
    await _tap(tester, find.text('Mini-marathons').first);
    await shot('mini-marathons');
    await tester.ensureVisible(
      find.ancestor(
        of: find.text('Additional channel versions'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await _settle(tester);
    await shot('mini-marathons-versions');
    await _tap(tester, find.byKey(const ValueKey('configure-section-2')));
    await shot('lineup-rules');
  },
  'setup-review': (tester, shot) async {
    await _pump(tester, _noTicker(_setupFixture().build()));
    await _tap(tester, find.byKey(const ValueKey('scan-selected-libraries')));
    await _tap(tester, find.byKey(const ValueKey('review-channels')));
    await shot('first-time');
  },
  'setup-review-removals': (tester, shot) async {
    final controller = _VisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..channels = [
        Channel(
          id: 'retro-detectives',
          number: 42,
          name: 'Retro Detectives',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026, 1, 15),
          shuffleSeed: 42,
          builderKey: 'synthetic:retro-detectives',
        ),
      ];
    await _pump(
      tester,
      _noTicker(
        UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('scan-selected-libraries')));
    await _tap(tester, find.byKey(const ValueKey('review-channels')));
    await shot('existing-lineup');
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('review-build-method')),
        matching: find.text('Replace generated channels'),
      ),
    );
    await shot('replace-confirmation');
    final rosterScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('channel-setup-review-roster')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    rosterScroll.position.jumpTo(rosterScroll.position.maxScrollExtent);
    await _settle(tester);
    await shot('replace-roster');
  },
  'setup-apply': (tester, shot) async {
    final controller = _PendingVisualController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    await _tap(tester, find.byKey(const ValueKey('scan-selected-libraries')));
    await _tap(tester, find.byKey(const ValueKey('review-channels')));
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await _settle(tester);
    await shot('progress');
    controller.finishApply();
    for (var i = 0; i < 4; i++) {
      await _settle(tester);
    }
    await shot('complete');
  },

  // ── Guide ──
  'guide': (tester, shot) async {
    final f = _readyFixture()
      ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await shot('no-playback');
    f.controller.settings = f.controller.settings.copyWith(
      guideShowChannelSources: true,
    );
    f.controller.notifyListeners();
    await _settle(tester);
    final textScale = MediaQuery.textScalerOf(
      tester.element(find.byType(GuideView)),
    ).scale(1);
    expect(
      find.text('Manual lineup'),
      textScale > 1 ? findsNothing : findsWidgets,
    );
    await shot('sources-visible');
  },
  'guide-pip': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.ready,
        message: 'Synthetic',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await shot('pip');
  },
  'guide-rich': (tester, shot) async {
    final f = _readyFixture(useWordmarkArtwork: true)
      ..controller.channels = _richPlayerChannels
      ..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await _precacheNowPlaying(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    await shot('artwork-focus');
    await tester.ensureVisible(find.byKey(const Key('guide-program-synopsis')));
    await _settle(tester);
    await shot('details-reachable');
  },
  'guide-loading': (tester, shot) async {
    final controller = _PendingScheduleController()
      ..stage = SetupStage.ready
      ..channels = _channels
      ..currentChannelId = _channels[1].id
      ..settings = const LineupSettings(reduceMotion: true);
    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    await shot('loading');
  },
  'guide-error': (tester, shot) async {
    final controller = _FailingScheduleController()
      ..recoverFirstOnRetry = true
      ..stage = SetupStage.ready
      ..channels = _channels
      ..currentChannelId = _channels[1].id
      ..settings = const LineupSettings(reduceMotion: true);
    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    expect(find.text("Schedules couldn't load"), findsOneWidget);
    await shot('error');
    await _tap(tester, find.text('Retry'));
    expect(find.text("Schedules couldn't load"), findsNothing);
    expect(find.textContaining('Schedule unavailable'), findsWidgets);
    await shot('partial-retry');
  },
  'guide-empty': (tester, shot) async {
    final controller = _VisualController()
      ..stage = SetupStage.ready
      ..channels = const []
      ..settings = const LineupSettings(reduceMotion: true);
    await _pump(
      tester,
      UiFixture(controller: controller, guideClock: () => _fixedNow).build(),
    );
    await shot('no-channels');
  },

  // ── Shell ──
  'lineup-menu': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.ready,
        message: 'Synthetic',
      ),
    );
    await _pump(tester, f.build());
    await _tap(tester, find.byTooltip('Open Lineup menu').first);
    await shot('guide-invoker');
  },

  // ── Player ──
  'player-osd': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.paused,
        message: 'Paused',
      ),
    );
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    await shot('paused');
  },
  'player-now-playing': (tester, shot) async {
    final f =
        _readyFixture(
            useWordmarkArtwork: true,
            playerState: const PlayerStatus(
              state: PlayerState.playing,
              message: 'Playing',
            ),
          )
          ..controller.channels = _richPlayerChannels
          ..controller.settings = const LineupSettings(
            guideHours: 4,
            reduceMotion: true,
          );
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    await _precacheNowPlaying(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await _settle(tester);
    await shot('shelf');
    // The first image read lets pending artwork decode finish. Lay out that
    // artwork before revealing cast so its new height cannot hide the target.
    await _settle(tester);
    await tester.ensureVisible(
      find.byKey(const Key('player-now-playing-cast-name-4')),
    );
    await _settle(tester);
    final castName = tester.renderObject<RenderBox>(
      find.byKey(const Key('player-now-playing-cast-name-4')),
    );
    final details = tester.renderObject<RenderBox>(
      find.byKey(const Key('player-now-playing-details')),
    );
    Rect drawnRect(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    expect(
      drawnRect(castName).bottom,
      lessThanOrEqualTo(drawnRect(details).bottom + .5),
    );
    await shot('cast-visible');
  },
  'player-tracks': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
      tracks: [
        const PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'English',
          language: 'eng',
          codec: 'eac3',
          channelCount: 6,
        ),
        const PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Commentary',
          language: 'eng',
          codec: 'aac',
          channelCount: 2,
          commentary: true,
        ),
        const PlayerTrack(
          id: 3,
          type: PlayerTrackType.audio,
          selected: false,
          language: 'spa',
          codec: 'ac3',
          channelCount: 6,
        ),
        for (var i = 1; i <= 14; i++)
          PlayerTrack(
            id: 10 + i,
            type: PlayerTrackType.subtitle,
            selected: i == 10,
            title: i == 3
                ? 'English (SDH) — Signs and Songs with an extra long descriptive label'
                : null,
            language: const ['eng', 'spa', 'fre', 'ger', 'jpn'][i % 5],
            codec: i.isEven ? 'ass' : 'subrip',
            forced: i == 5,
            hearingImpaired: i == 3,
          ),
      ],
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await _settle(tester);
    await shot('audio');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await _settle(tester);
    await shot('subtitles');
  },
  'player-sleep': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    tester
        .widget<PlayerView>(find.byType(PlayerView))
        .controller
        .showSleepTimer();
    await _settle(tester);
    await shot('timer');
  },
  'player-states': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.buffering,
        message: 'Buffering',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    await shot('buffering');
    f.player.emit(
      const PlayerStatus(
        state: PlayerState.error,
        message: 'Playback failed: the server closed the connection.',
      ),
    );
    await _settle(tester);
    await shot('error');
  },
  'mini-guide': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    );
    await _pump(tester, f.build());
    await _open(tester, 'Player');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    await shot('shelf');
  },

  // ── Channels + Studio ──
  'channels': (tester, shot) async {
    final f = _channelManagementFixture();
    await _pump(tester, f.build());
    await _open(tester, 'Channels');
    await shot('directory');
    await _tap(tester, find.byTooltip('Actions for Saturday Cartoons'));
    await shot('row-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    await _tap(tester, find.text('Select'));
    await _tap(tester, find.text('Select all matching'));
    await shot('selection');
    await _tap(tester, find.text('Delete selected'));
    await shot('delete-confirmation');
    await _tap(tester, find.text('Cancel').last);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Reorder channels'));
    await shot('reorder');
  },
  'studio': (tester, shot) async {
    final f = _channelManagementFixture();
    await _pump(tester, f.build());
    await _open(tester, 'Channels');
    await _tap(tester, find.text('Saturday Cartoons').first);
    await shot('handpicked-air-check');
    await _tap(tester, find.textContaining('Browse library').first);
    await shot('browse');
    await _tap(tester, find.text('Select'));
    await shot('browse-selection');
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.byKey(const Key('studio-browse-add-filter')));
    await _tap(tester, find.byKey(const Key('studio-filter-genre')));
    await shot('browse-filter-picker');
    await _tap(tester, find.text('Comedy').last);
    await _tap(tester, find.text('Done'));
    await shot('browse-applied-filter');
    await _tap(tester, find.text('Library').first);
    await shot('library-programming');
    await _tap(tester, find.byKey(const Key('studio-library-add-filter')));
    await _tap(tester, find.byKey(const Key('studio-filter-genre')));
    await shot('filter-picker');
    await _tap(tester, find.text('Comedy').last);
    await _tap(tester, find.text('Done'));
    await shot('library-applied-filter');
    await _tap(tester, find.byKey(const Key('studio-library-add-filter')));
    await _tap(tester, find.byKey(const Key('studio-filter-decade')));
    await _tap(tester, find.text('2010s').last);
    await _tap(tester, find.text('Done'));
    expect(find.text('Out of date'), findsOneWidget);
    await shot('retained-empty-schedule');
  },

  // ── Settings + Diagnostics ──
  'settings': (tester, shot) async {
    final f = _readyFixture();
    await _pump(tester, f.build());
    await _open(tester, 'Settings');
    for (final category in [
      'Appearance',
      'Guide',
      'Playback',
      'Accessibility',
      'Account',
      'Support',
    ]) {
      await _tap(tester, find.text(category).first);
      await shot(category.toLowerCase());
    }
  },
  'settings-over-playback': (tester, shot) async {
    final f = _readyFixture(
      playerState: const PlayerStatus(
        state: PlayerState.playing,
        message: 'Playing',
      ),
    )..controller.settings = const LineupSettings(reduceMotion: true);
    await _pump(tester, f.build());
    await _open(tester, 'Settings');
    await shot('appearance');
  },
  'diagnostics': (tester, shot) async {
    final f = _readyFixture();
    f.controller.diagnostics.enabled = true;
    f.controller.diagnostics.add('playback', 'Playback request failed', {
      'code': 'unavailable',
    });
    f.controller.diagnostics.add('guide', 'Schedule request timed out');
    await _pump(tester, f.build());
    await _open(tester, 'Settings');
    await _tap(tester, find.text('Support').first);
    await _tap(tester, find.text('Open Diagnostics'));
    await shot('summary-events');
    await _tap(tester, find.text('Technical details'));
    await shot('technical-details');
  },

  for (final theme in LineupThemeName.values)
    'theme-${theme.storageKey}': (tester, shot) async {
      UiFixture fixture() => _readyFixture(
        playerState: const PlayerStatus(
          state: PlayerState.paused,
          message: 'Paused',
        ),
      )..controller.settings = LineupSettings(theme: theme, reduceMotion: true);
      await _pump(tester, fixture().build());
      await shot('guide-pip');
      await _open(tester, 'Channels');
      await shot('channels');
      await _open(tester, 'Settings');
      await shot('settings');
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, fixture().build());
      await _open(tester, 'Player');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await shot('player-osd');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _settle(tester);
      await shot('mini-guide');
    },
};

void main() {
  setUpAll(loadPinnedTestFonts);
  final only = Platform.environment['SCENES']?.split(',').toSet();
  final configs = Platform.environment['CONFIGS']?.split(',').toSet();
  for (final config in _configs) {
    if (configs != null && !configs.contains(config.label)) continue;
    for (final entry in _scenes.entries) {
      if (only != null && !only.contains(entry.key)) continue;
      testWidgets('${entry.key} @ ${config.label}', (tester) async {
        tester.view
          ..devicePixelRatio = config.dpr
          ..physicalSize = config.logical * config.dpr;
        tester.platformDispatcher.textScaleFactorTestValue = config.text;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await entry.value(
          tester,
          (state) => _capture(tester, config, '${entry.key}--$state'),
        );
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, Config config, String name) async {
  final context = tester.element(find.byKey(_key));
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/branding/lineup-logo-mark.png'),
      context,
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  markSubtreeNeedsPaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: config.dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('build/design-review/captures/${config.label}');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    final probes = <Map<String, Object?>>[];
    for (final element in find.byType(RichText).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderParagraph || !render.attached || !render.hasSize) {
        continue;
      }
      final transform = render.getTransformTo(null);
      final scales = _drawnScales(transform);
      final bounds = MatrixUtils.transformRect(transform, render.paintBounds);
      final rootStyle = DefaultTextStyle.of(element).style
          .merge(render.text.style);
      final probe =
          _geometryProbe(
              text: render.text.toPlainText(includeSemanticsLabels: false),
              bounds: bounds,
              style: rootStyle,
              textScaler: render.textScaler,
              fontScale: scales.font,
              letterSpacingScale: scales.letterSpacing,
            )
            ..['kind'] = 'paragraph'
            ..['widget'] = element.findAncestorWidgetOfExactType<Text>() == null
                ? 'RichText'
                : 'Text'
            ..['owner'] = element
                .debugGetDiagnosticChain()
                .skip(1)
                .take(6)
                .map((e) => e.widget.runtimeType.toString())
                .join('<')
            ..['runs'] = _spanProbes(render, rootStyle, transform, scales);
      probes.add(probe);
    }
    await File('${dir.path}/$name.json').writeAsString(jsonEncode(probes));
  });
}

({double font, double letterSpacing}) _drawnScales(Matrix4 transform) {
  final origin = MatrixUtils.transformPoint(transform, Offset.zero);
  final xAxis = MatrixUtils.transformPoint(transform, const Offset(1, 0));
  final yAxis = MatrixUtils.transformPoint(transform, const Offset(0, 1));
  return (
    font: (yAxis - origin).distance,
    letterSpacing: (xAxis - origin).distance,
  );
}

Map<String, Object?> _geometryProbe({
  required String text,
  required Rect bounds,
  required TextStyle style,
  required TextScaler textScaler,
  required double fontScale,
  required double letterSpacingScale,
}) {
  final rawFontSize = style.fontSize ?? 14.0;
  final textScaledFontSize = textScaler.scale(rawFontSize);
  final rawLetterSpacing = style.letterSpacing ?? 0.0;
  return {
    'text': text,
    'x': bounds.left,
    'y': bounds.top,
    'w': bounds.width,
    'h': bounds.height,
    'fontSize': textScaledFontSize * fontScale,
    'rawFontSize': rawFontSize,
    'textScaledFontSize': textScaledFontSize,
    'textScale': rawFontSize == 0 ? 1.0 : textScaledFontSize / rawFontSize,
    'letterSpacing': rawLetterSpacing * letterSpacingScale,
    'rawLetterSpacing': rawLetterSpacing,
    'drawnFontScale': fontScale,
    'drawnLetterSpacingScale': letterSpacingScale,
  };
}

List<Map<String, Object?>> _spanProbes(
  RenderParagraph render,
  TextStyle rootStyle,
  Matrix4 transform,
  ({double font, double letterSpacing}) scales,
) {
  final runs = <Map<String, Object?>>[];
  var offset = 0;

  void visit(InlineSpan span, TextStyle inheritedStyle, String path) {
    final style = inheritedStyle.merge(span.style);
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        final start = offset;
        offset += text.length;
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: offset),
        );
        if (boxes.isNotEmpty) {
          var localBounds = boxes.first.toRect();
          for (final box in boxes.skip(1)) {
            localBounds = localBounds.expandToInclude(box.toRect());
          }
          final probe =
              _geometryProbe(
                  text: text,
                  bounds: MatrixUtils.transformRect(transform, localBounds),
                  style: style,
                  textScaler: render.textScaler,
                  fontScale: scales.font,
                  letterSpacingScale: scales.letterSpacing,
                )
                ..['kind'] = 'span'
                ..['span'] = path;
          runs.add(probe);
        }
      }
      final children = span.children;
      if (children != null) {
        for (var index = 0; index < children.length; index++) {
          visit(children[index], style, '$path.$index');
        }
      }
    } else {
      // PlaceholderSpan contributes one object-replacement character to the
      // paragraph's selection offsets but has no text-run geometry to probe.
      offset++;
    }
  }

  visit(render.text, rootStyle, '0');
  return runs;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(RepaintBoundary(key: _key, child: child));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

Widget _noTicker(Widget child) => TickerMode(enabled: false, child: child);

Future<void> _precacheNowPlaying(WidgetTester tester) async {
  final context = tester.element(find.byKey(_key));
  await tester.runAsync(() async {
    for (final bytes in _nowPlayingArtwork.values) {
      await precacheImage(MemoryImage(bytes), context);
    }
  });
}

UiFixture _profileSelectionFixture() => UiFixture()
  ..controller.stage = SetupStage.profiles
  ..controller.profile = const PlexHomeUser(
    id: 'adult',
    name: 'Alex',
    protected: false,
    admin: true,
  )
  ..controller.profiles = const [
    PlexHomeUser(id: 'adult', name: 'Alex', protected: false, admin: true),
    PlexHomeUser(
      id: 'child',
      name: 'Family',
      protected: true,
      restricted: true,
    ),
    PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
    PlexHomeUser(
      id: 'movies',
      name: 'A deliberately long synthetic profile name',
      protected: false,
      restricted: true,
    ),
    PlexHomeUser(id: 'kids', name: 'Kids', protected: false, restricted: true),
    PlexHomeUser(id: 'sports', name: 'Sports', protected: false),
    PlexHomeUser(id: 'parents', name: 'Parents', protected: true),
    PlexHomeUser(id: 'weekend', name: 'Weekend', protected: false),
    PlexHomeUser(
      id: 'visitor',
      name: 'Visitor',
      protected: false,
      restricted: true,
    ),
  ];

UiFixture _serverFixture() {
  final selected = PlexServer(
    id: 'studio',
    name: 'Studio Server',
    owned: true,
    connections: [
      PlexConnection(
        uri: Uri.parse('https://local.synthetic.invalid'),
        local: true,
        relay: false,
      ),
      PlexConnection(
        uri: Uri.parse('https://remote.synthetic.invalid'),
        local: false,
        relay: false,
      ),
      PlexConnection(
        uri: Uri.parse('https://relay.synthetic.invalid'),
        local: false,
        relay: true,
      ),
    ],
  );
  return UiFixture()
    ..controller.stage = SetupStage.servers
    ..controller.server = selected
    ..controller.connection = PlexConnection(
      uri: Uri.parse('https://selected.synthetic.invalid'),
      local: true,
      relay: false,
      latency: const Duration(milliseconds: 126),
    )
    ..controller.servers = [
      selected,
      PlexServer(
        id: 'shared',
        name: 'Family Server',
        connections: [
          PlexConnection(
            uri: Uri.parse('https://shared.synthetic.invalid'),
            local: false,
            relay: false,
          ),
        ],
      ),
    ];
}

UiFixture _setupFixture() {
  final controller = _VisualController()
    ..stage = SetupStage.channelSetup
    ..libraries = const [
      PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
    ];
  return UiFixture(controller: controller, guideClock: () => _fixedNow);
}

UiFixture _libraryOutcomeFixture() {
  final controller = _VisualController()
    ..stage = SetupStage.channelSetup
    ..libraries = const [
      PlexLibrary(
        id: 'movies',
        title: 'Feature Films',
        type: PlexLibraryType.movie,
      ),
      PlexLibrary(id: 'shows', title: 'Series', type: PlexLibraryType.show),
      PlexLibrary(id: 'archive', title: 'Archive', type: PlexLibraryType.movie),
      PlexLibrary(
        id: 'imports',
        title: 'Recent Imports',
        type: PlexLibraryType.movie,
      ),
    ]
    ..selectedLibraryIds = const {'movies', 'shows', 'archive', 'imports'}
    ..libraryScanStatus = LibraryScanStatus.transientFailure
    ..libraryScanCompletedPages = 8
    ..libraryScanCompletedItems = 83
    ..libraryScanTotalItems = 112
    ..error = 'Plex could not complete the library scan.'
    ..scanFacts = const {
      'movies': LibraryScanFact(
        status: LibraryScanStatus.complete,
        completedPages: 4,
        completedItems: 72,
        totalItems: 72,
      ),
      'shows': LibraryScanFact(
        status: LibraryScanStatus.unsupported,
        completedPages: 2,
        completedItems: 8,
        totalItems: 8,
      ),
      'archive': LibraryScanFact(
        status: LibraryScanStatus.empty,
        completedPages: 1,
        totalItems: 0,
      ),
      'imports': LibraryScanFact(
        status: LibraryScanStatus.transientFailure,
        completedPages: 1,
        completedItems: 3,
        totalItems: 32,
      ),
    };
  return UiFixture(controller: controller, guideClock: () => _fixedNow);
}

UiFixture _readyFixture({
  PlayerStatus? playerState,
  List<PlayerTrack>? tracks,
  bool useWordmarkArtwork = false,
}) {
  final player = FixturePlayer();
  if (playerState != null) {
    player.emit(
      playerState,
      position: const Duration(minutes: 18),
      duration: const Duration(minutes: 48),
      telemetry: useWordmarkArtwork
          ? const PlayerTelemetry(
              width: 3840,
              height: 2160,
              videoCodec: 'hevc',
              gamma: 'pq',
            )
          : const PlayerTelemetry(
              width: 1920,
              height: 1080,
              videoCodec: 'h264',
            ),
      tracks:
          tracks ??
          const [
            PlayerTrack(
              id: 1,
              type: PlayerTrackType.audio,
              selected: true,
              title: 'English',
            ),
            PlayerTrack(
              id: 2,
              type: PlayerTrackType.subtitle,
              selected: false,
              title: 'English captions',
            ),
          ],
    );
  }
  final controller = _VisualController()
    ..useWordmarkArtwork = useWordmarkArtwork
    ..stage = SetupStage.ready
    ..channels = _channels
    ..currentChannelId = _channels[1].id;
  return UiFixture(
    controller: controller,
    player: player,
    guideClock: () => _fixedNow,
  );
}

UiFixture _channelManagementFixture() {
  const programs = [
    ChannelItem(
      id: 'cartoon-one',
      title: 'Moonbase Mystery',
      showTitle: 'Saturday Signals',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-two',
      title: 'The Clockwork Cove',
      showTitle: 'Saturday Signals',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-three',
      title: 'Rocket Club Rescue',
      showTitle: 'Junior Orbit',
      duration: Duration(minutes: 30),
    ),
    ChannelItem(
      id: 'cartoon-four',
      title: 'Cloud City Picnic',
      showTitle: 'Junior Orbit',
      duration: Duration(minutes: 30),
    ),
  ];
  final base = Channel(
    id: 'studio-custom',
    number: 42,
    name: 'Saturday Cartoons',
    source: const ManualSource(programs),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026, 1, 15, 3),
    shuffleSeed: 42,
  );
  final controller = _VisualController()
    ..stage = SetupStage.ready
    ..libraries = const [
      PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
    ]
    ..selectedLibraryIds = {'movies'}
    ..libraryScanStatus = LibraryScanStatus.complete
    ..channels = [
      base,
      for (var i = 1; i < 4; i++)
        Channel(
          id: 'audit-$i',
          number: 42 + i,
          name: [
            'Evening Cinema',
            'Documentary and Discovery',
            'Weekend Stories',
          ][i - 1],
          source: base.source,
          playbackMode: base.playbackMode,
          anchor: base.anchor,
          shuffleSeed: i,
        ),
    ]
    ..availableMedia = [
      for (final program in programs)
        PlexMediaItem(
          id: program.id,
          title: program.title,
          type: 'episode',
          duration: program.duration,
          grandparentTitle: program.showTitle,
          seasonNumber: 1,
          episodeNumber: programs.indexOf(program) + 1,
          parts: [PlexMediaPart(path: '/synthetic/${program.id}')],
        ),
      for (final genre in [
        'Adventure',
        'Animation',
        'Comedy',
        'Drama',
        'Fantasy',
        'Mystery',
      ])
        PlexMediaItem(
          id: 'audit-$genre',
          title: '$genre feature',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          year: genre == 'Drama' ? 2010 : 2026,
          genres: [genre],
          parts: [PlexMediaPart(path: '/synthetic/audit-$genre')],
        ),
    ];
  return UiFixture(controller: controller, guideClock: () => _fixedNow);
}

class _RejectedPinController extends FixtureController {
  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    error = 'That Plex Home PIN was not accepted.';
    notifyListeners();
    return false;
  }
}

class _CaptureDiagnostics extends Diagnostics {
  @override
  List<DiagnosticEntry> get entries => [
    for (final (index, entry) in super.entries.indexed)
      DiagnosticEntry(
        _fixedNow.add(Duration(seconds: index)),
        entry.area,
        entry.message,
        entry.context,
      ),
  ];
}

class _VisualController extends FixtureController {
  final _captureDiagnostics = _CaptureDiagnostics();

  @override
  Diagnostics get diagnostics => _captureDiagnostics;
  Map<String, LibraryScanFact> scanFacts = const {};
  bool useWordmarkArtwork = false;
  Set<String> _scannedLibraryIds = const {};
  List<PlexMediaItem>? _scannedMedia;

  @override
  Map<String, LibraryScanFact> get libraryScanFacts => scanFacts;

  @override
  Set<String> get libraryScanReadyIds => Set.unmodifiable(
    scanFacts.entries
        .where((e) => e.value.status == LibraryScanStatus.complete)
        .map((e) => e.key),
  );

  @override
  Set<String> get libraryScanRetryIds => Set.unmodifiable(
    scanFacts.entries
        .where(
          (e) => const {
            LibraryScanStatus.transientFailure,
            LibraryScanStatus.cancelled,
            LibraryScanStatus.idle,
          }.contains(e.value.status),
        )
        .map((e) => e.key),
  );

  @override
  Future<Uint8List?> artworkForPath(Uri path) async =>
      useWordmarkArtwork ? _nowPlayingArtwork[path] : _syntheticArtwork;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(
        channel,
        channel.source is ManualSource
            ? (channel.source as ManualSource).items
            : resolveContent(
                channel.source,
                playableInventory.media,
                playableInventory.playlists,
              ),
      );

  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    if (ids.isEmpty) return false;
    _scannedLibraryIds = Set.unmodifiable(ids);
    _scannedMedia = [
      for (var index = 0; index < 12; index++)
        PlexMediaItem(
          id: 'movie-$index',
          title: 'Synthetic Movie ${index + 1}',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          parts: [PlexMediaPart(path: '/parts/movie-$index')],
          genres: const ['Drama'],
          addedAt: DateTime.utc(2026, 1, index + 1),
        ),
    ];
    scanFacts = {
      for (final id in ids)
        id: const LibraryScanFact(
          status: LibraryScanStatus.complete,
          completedPages: 1,
          completedItems: 12,
          totalItems: 12,
        ),
    };
    libraryScanStatus = LibraryScanStatus.complete;
    libraryScanCompletedPages = 1;
    libraryScanCompletedItems = 12;
    libraryScanTotalItems = 12;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> commitLibraryScan(Set<String> readyIds) async {
    final scanned = _scannedMedia;
    if (scanned == null ||
        readyIds.isEmpty ||
        !_scannedLibraryIds.containsAll(readyIds)) {
      return false;
    }
    selectedLibraryIds = Set.unmodifiable(readyIds);
    availableMedia = List.unmodifiable(scanned);
    notifyListeners();
    return true;
  }

  Future<bool> setLibraries(Set<String> ids) async {
    if (!await scanLibraries(ids)) return false;
    if (libraryScanRetryIds.isNotEmpty) return false;
    return commitLibraryScan(ids);
  }
}

class _PendingVisualController extends _VisualController {
  final _apply = Completer<void>();

  @override
  Future<ChannelPlanApplyResult> applyReviewedChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    required List<Channel> expectedBase,
  }) async {
    await _apply.future;
    return super.applyReviewedChannelPlan(
      planned,
      mode: mode,
      expectedBase: expectedBase,
    );
  }

  void finishApply() => _apply.complete();
}

class _PendingScheduleController extends _VisualController {
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) =>
      Completer<ScheduleIndex>().future;
}

class _FailingScheduleController extends _VisualController {
  bool recoverFirstOnRetry = false;
  final _attempts = <String, int>{};

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async {
    final attempt = _attempts.update(
      channel.id,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (recoverFirstOnRetry &&
        channel.id == _channels.first.id &&
        attempt > 1) {
      return super.loadScheduleFor(channel);
    }
    throw const SocketException('synthetic schedule failure');
  }
}

final _channels = List.generate(
  12,
  (index) => Channel(
    id: 'channel-$index',
    number: index + 1,
    name: const [
      'Action Cinema',
      'Comedy Club',
      'Documentary',
      'Family Favorites',
    ][index % 4],
    source: ManualSource([
      for (var program = 0; program < 8; program++)
        ChannelItem(
          id: 'program-$index-$program',
          title: const [
            'The Long Way Home',
            'City Stories',
            'After Midnight',
            'World in Focus',
          ][(index + program) % 4],
          showTitle: program.isEven ? 'Lineup Originals' : null,
          duration: Duration(minutes: 24 + program * 4),
        ),
    ]),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026, 8, 13),
    shuffleSeed: index,
  ),
  growable: false,
);

final _richPlayerChannels = [
  for (final channel in _channels)
    if (channel.id != 'channel-1')
      channel
    else
      Channel(
        id: channel.id,
        number: channel.number,
        name: 'Midnight Mysteries',
        source: ManualSource([
          for (var program = 0; program < 8; program++)
            ChannelItem(
              id: 'program-1-$program',
              title: const [
                'The Last Frequency',
                'Voices in the Static',
                'A Light Below',
                'The Silent Relay',
              ][program % 4],
              showTitle: 'Signal After Midnight',
              duration: const Duration(minutes: 48),
              poster: Uri.parse('test://now-playing/poster'),
              backdrop: Uri.parse('test://now-playing/poster'),
              clearLogo: Uri.parse('test://now-playing/title'),
              summary: 'When a vanished emergency broadcast returns after twenty years, a night-shift radio engineer and a skeptical detective trace its coded warnings through a city that insists the original case never happened.',
              contentRating: 'TV-14',
              genres: const ['Mystery', 'Drama', 'Thriller'],
              year: 2026,
              seasonNumber: 1,
              episodeNumber: program + 1,
              resolution: '4K',
              videoCodec: 'hevc',
              audioCodec: 'eac3',
              audioChannels: 6,
              dynamicRange: 'HDR10',
              cast: [
                for (final (name, role, key) in const [
                  ('Elias Vale', 'Jonah Mercer', 'elias'),
                  ('Mina Park', 'Detective Hana Voss', 'mina'),
                  ('Solomon Reed', 'Arthur Bell', 'solomon'),
                  ('Clara Wynn', 'June Mercer', 'clara'),
                ])
                  ChannelCastMember(
                    name: name,
                    role: role,
                    portrait: Uri.parse(
                      '/library/metadata/test/now-playing/cast-$key',
                    ),
                  ),
                ChannelCastMember(name: 'Noa Bell', role: 'Evelyn Shaw'),
              ],
            ),
        ]),
        playbackMode: channel.playbackMode,
        anchor: channel.anchor,
        shuffleSeed: channel.shuffleSeed,
      ),
];

Future<void> _open(WidgetTester tester, String destination) async {
  await tester.tap(find.byTooltip('Open Lineup menu').first);
  await _settle(tester);
  await tester.tap(find.text(destination).last);
  await _settle(tester);
}
