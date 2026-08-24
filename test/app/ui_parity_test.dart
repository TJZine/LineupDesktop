import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
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
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('immersive-route-semantics')),
          )
          .excluding,
      isTrue,
    );
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Card>()
            ?.key,
        const Key('immersive-app-menu'),
      );
    }
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
      if (target.$2 != 'Channels') {
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

      await openDestination(tester, 'Channels');
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
      UpstreamOnboardingView.maxContentWidth,
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
      UpstreamChannelSetupView.maxContentWidth,
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
    await openDestination(tester, 'Channels');

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

  testWidgets('channel deletion cancellation tolerates a removed opener', (
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
    await openDestination(tester, 'Channels');

    await tester.tap(find.byTooltip('Delete Newsroom'));
    await tester.pumpAndSettle();
    fixture.controller
      ..channels = const []
      ..notifyListeners();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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
    await openDestination(tester, 'Settings');

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
    await openDestination(tester, 'Channels');
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

  testWidgets('profile badges remain reachable from 800x600 through 4K', (
    tester,
  ) async {
    final controller = FixtureController()
      ..stage = SetupStage.profiles
      ..profile = const PlexHomeUser(
        id: 'profile',
        name: 'Profile',
        protected: true,
        admin: true,
        restricted: true,
      )
      ..profiles = const [
        PlexHomeUser(
          id: 'profile',
          name: 'Profile',
          protected: true,
          admin: true,
          restricted: true,
        ),
      ];
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(800, 600), const Size(3840, 2160)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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

  testWidgets('Channel Setup exposes distinct scan states and actions', (
    tester,
  ) async {
    Future<_SetupFixtureController> pumpStatus(
      LibraryScanStatus status, {
      String? error,
    }) async {
      final controller = _SetupFixtureController()
        ..stage = SetupStage.channelSetup
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ]
        ..libraryScanStatus = status
        ..libraryScanCompletedPages = 3
        ..libraryScanCompletedItems = 50
        ..libraryScanTotalItems = 100
        ..error = error;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
      );
      await tester.pump();
      return controller;
    }

    final scanning = await pumpStatus(LibraryScanStatus.scanning);
    expect(
      find.bySemanticsLabel('Scanning selected libraries'),
      findsOneWidget,
    );
    expect(find.text('Pages scanned: 3 · Items scanned: 50'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel scan'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    await tester.tap(find.text('Cancel scan'));
    await tester.pump();
    expect(scanning.libraryScanStatus, LibraryScanStatus.cancelled);

    for (final state in [
      (LibraryScanStatus.empty, 'Selected libraries are empty'),
      (LibraryScanStatus.unsupported, 'No playable media found'),
      (LibraryScanStatus.cancelled, 'Library scan cancelled'),
    ]) {
      await pumpStatus(state.$1);
      expect(find.bySemanticsLabel(state.$2), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry scan'), findsOneWidget);
    }

    await pumpStatus(
      LibraryScanStatus.transientFailure,
      error: 'Plex did not respond in time. Try again.',
    );
    expect(find.bySemanticsLabel('Library scan failed'), findsOneWidget);
    expect(find.textContaining('did not respond'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry scan'), findsOneWidget);

    await pumpStatus(LibraryScanStatus.complete);
    expect(find.bySemanticsLabel('Library scan complete'), findsOneWidget);
    expect(find.text('Pages scanned: 3 · Items scanned: 50'), findsOneWidget);
    expect(find.text('Retry scan'), findsNothing);
  });

  testWidgets('dedicated scan cancellation is not presented as a failure', (
    tester,
  ) async {
    final controller = _BlockingScanController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..selectedLibraryIds = const {'movies'}
      ..availableMedia = const [
        PlexMediaItem(
          id: 'committed',
          title: 'Committed',
          type: 'movie',
          duration: Duration(minutes: 1),
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => UpstreamChannelSetupView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Configure channels'));
    await controller.started.future;
    await tester.pump();
    await tester.tap(find.text('Cancel scan'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Library scan cancelled'), findsOneWidget);
    expect(find.byType(LineupNotice), findsNothing);
    expect(find.text('Library loading failed.'), findsNothing);
    expect(controller.selectedLibraryIds, {'movies'});
    expect(controller.availableMedia.single.id, 'committed');
  });

  testWidgets('Channel Setup does not reclaim focus after a layout remount', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SetupFixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    final outsideFocus = FocusNode(debugLabel: 'Outside Channel Setup');
    addTearDown(controller.dispose);
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TextButton(
              focusNode: outsideFocus,
              onPressed: () {},
              child: const Text('Outside'),
            ),
            Expanded(child: UpstreamChannelSetupView(controller: controller)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    outsideFocus.requestFocus();
    await tester.pump();

    await tester.binding.setSurfaceSize(const Size(1200, 700));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus, same(outsideFocus));
  });
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
          title: 'Movie $index',
          type: 'movie',
          duration: const Duration(minutes: 90),
          libraryId: 'movies',
          genres: const ['Drama'],
          addedAt: DateTime.utc(2026, 1, index + 1),
        ),
    ];
    libraryScanStatus = LibraryScanStatus.complete;
    libraryScanCompletedItems = availableMedia.length;
    return true;
  }
}

class _BlockingScanController extends FixtureController {
  final started = Completer<void>();
  final _cancelled = Completer<void>();

  @override
  Future<bool> setLibraries(Set<String> ids) async {
    libraryScanStatus = LibraryScanStatus.scanning;
    busy = true;
    notifyListeners();
    started.complete();
    await _cancelled.future;
    busy = false;
    notifyListeners();
    return false;
  }

  @override
  void cancelLibraryScan() {
    super.cancelLibraryScan();
    if (!_cancelled.isCompleted) _cancelled.complete();
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
