import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('shell keeps the deliberate destination inventory and focus', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    for (final label in [
      'Guide',
      'Channels',
      'Settings',
      'Diagnostics',
      'Player',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Channels').last);
    await tester.pumpAndSettle();

    for (final target in [
      (Icons.view_list_outlined, 'Channels'),
      (Icons.settings_outlined, 'Settings'),
      (Icons.monitor_heart_outlined, 'Diagnostics'),
    ]) {
      if (target.$2 == 'Channels') {
        // The menu transition above already selected this destination.
      } else {
        await tester.tap(find.byIcon(target.$1));
      }
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, target.$2);
      if (target.$2 == 'Channels') {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Channel builder'),
              )
              .focusNode
              ?.hasFocus,
          isTrue,
        );
      }
      if (target.$2 == 'Settings') {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Appearance'),
              )
              .focusNode
              ?.hasFocus,
          isTrue,
        );
      }
    }
  });

  testWidgets('management pages and settings reflow at desktop regimes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
      Size(2560, 1440),
      Size(3840, 2160),
    ]) {
      tester.view.physicalSize = size;
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();

      await _openImmersiveDestination(tester, 'Channels');
      await tester.pumpAndSettle();
      expect(find.text('Open Channel builder'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Channels at $size');

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Remote quality'), findsNothing);
      expect(find.text('HDR tone mapping'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'Settings at $size');
      if (size.width >= 2560) {
        expect(
          tester
              .getSize(find.byKey(const ValueKey('lineup-page-content')))
              .width,
          LineupLayout.readableWidth,
        );
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isTrue,
        );
      }
      if (size == const Size(800, 600)) {
        for (final category in ['Accessibility', 'Account', 'Support']) {
          await tester.ensureVisible(find.text(category).first);
          await tester.tap(find.text(category).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$category at $size');
        }
      }
      await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Credential-safe diagnostics'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Diagnostics at $size');
    }
  });

  testWidgets('onboarding and setup retain readable workspaces at 4k', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(UiFixture().build());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('onboarding-content'))).width,
      1180,
    );
    expect(tester.takeException(), isNull);

    final controller = FixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('channel-setup-content'))).width,
      1440,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel deletion requires explicit destructive confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.channels = [_channel()];
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await tester.pump();
    await _openImmersiveDestination(tester, 'Channels');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete Newsroom'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Newsroom?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, hasLength(1));
    expect(find.byTooltip('Delete Newsroom'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<IconButton>()
          ?.tooltip,
      'Delete Newsroom',
    );

    await tester.tap(find.byTooltip('Delete Newsroom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete channel'));
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, isEmpty);
  });

  testWidgets('Windows-style 200 percent DPI uses the 1080p logical regime', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;

    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await _openImmersiveDestination(tester, 'Settings');
    await tester.pumpAndSettle();

    expect(
      MediaQuery.sizeOf(tester.element(find.text('Settings').last)),
      const Size(1920, 1080),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('lineup-page-content'))).width,
      LineupLayout.readableWidth,
    );
  });

  testWidgets('custom channel validation stays local to the form', (
    tester,
  ) async {
    final fixture = UiFixture()
      ..controller.stage = SetupStage.ready
      ..controller.libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..controller.selectedLibraryIds = const {'movies'};
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await _openImmersiveDestination(tester, 'Channels');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create channel'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.enterText(find.byType(TextFormField).at(1), 'not a number');
    await tester.tap(find.text('Save channel'));
    await tester.pump();
    expect(find.text('Enter a channel name.'), findsOneWidget);
    expect(find.text('Enter a number from 1 to 1000.'), findsOneWidget);
  });

  testWidgets('protected profile accepts physical digits and backspace', (
    tester,
  ) async {
    const profile = PlexHomeUser(id: 'child', name: 'Child', protected: true);
    final controller = _ProfileFixtureController()
      ..stage = SetupStage.profiles
      ..profiles = const [profile];
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();
    expect(controller.pin, '1345');
  });

  testWidgets('Channel Setup remains reachable at the practical minimum', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = FixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configure channels'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Channel Setup retains its three-stage product structure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SetupFixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Plex libraries'), findsOneWidget);
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    expect(find.text('Configure the lineup'), findsOneWidget);
    expect(find.text('Content Sources'), findsWidgets);
    expect(find.text('Guide Order'), findsOneWidget);

    await tester.tap(find.text('Build Channels'));
    await tester.pumpAndSettle();
    expect(find.text('Review expected changes'), findsOneWidget);
    expect(find.text('Confirm & Replace'), findsOneWidget);
  });
}

Future<void> _openImmersiveDestination(
  WidgetTester tester,
  String destination,
) async {
  if (find.byKey(const Key('guide-app-menu')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text(destination).last);
  } else {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(destination),
      ),
    );
  }
  await tester.pumpAndSettle();
}

class _ProfileFixtureController extends FixtureController {
  String? pin;

  @override
  Future<void> selectProfile(PlexHomeUser selected, {String? pin}) async {
    this.pin = pin;
  }
}

class _SetupFixtureController extends FixtureController {
  @override
  Future<bool> setLibraries(Set<String> ids) async {
    selectedLibraryIds = Set.unmodifiable(ids);
    availableMedia = [
      for (var index = 0; index < 6; index++)
        PlexMediaItem(
          id: 'movie-$index',
          key: '/library/metadata/$index',
          title: 'Movie $index',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          genres: const ['Drama'],
          addedAt: DateTime.utc(2026, 1, index + 1),
        ),
    ];
    return true;
  }
}

Channel _channel() => Channel(
  id: 'newsroom',
  number: 7,
  name: 'Newsroom',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 7,
);
