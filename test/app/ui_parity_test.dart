import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('shell keeps the deliberate destination inventory and focus', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
    await tester.tap(find.text('Guide').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
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
      if (target.$2 == 'Diagnostics') {
        await tester.tap(find.byTooltip('Open Lineup menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diagnostics').last);
      } else if (target.$2 != 'Channels') {
        await tester.tap(find.byIcon(target.$1));
      }
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, target.$2);
      if (target.$2 == 'Channels') {
        final rail = find.byType(NavigationRail);
        final selectedLabel = find.descendant(
          of: rail,
          matching: find.text('Channels'),
        );
        expect(tester.widget<NavigationRail>(rail).selectedIndex, 1);
        expect(tester.widget<NavigationRail>(rail).extended, isTrue);
        expect(selectedLabel, findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Generate lineup'),
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
      expect(find.text('Generate lineup'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'Channels at $size');
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

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Remote quality'), findsNothing);
      expect(find.text('HDR tone mapping'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'Settings at $size');
      expect(find.byType(NavigationRail), findsNothing);
      final categoryRailSize = tester.getSize(
        find.byKey(const Key('settings-category-rail')),
      );
      if (size.width < LineupLayout.compact) {
        expect(categoryRailSize.width, size.width);
      } else {
        expect(
          categoryRailSize.width,
          size.width * 0.24 > 320 ? 320 : size.width * 0.24,
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
      await tester.tap(find.byTooltip('Open Lineup menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnostics').last);
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
    final setupContent = tester.getRect(
      find.byKey(const ValueKey('channel-setup-content')),
    );
    final setupShell = tester.getRect(
      find.byKey(const ValueKey('channel-setup-shell')),
    );
    expect(setupShell.width, setupContent.width - 56);
    expect(setupShell.center.dx, setupContent.center.dx);
    expect(setupShell.left, greaterThan(0));
    expect(tester.takeException(), isNull);

    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(find.text('Channel Setup'))),
      const Size(1920, 1080),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('channel-setup-shell')))
          .center
          .dx,
      960,
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
      tester.getSize(find.byKey(const Key('settings-category-rail'))).width,
      320,
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
    await tester.tap(find.text('New channel'));
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
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad4);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad5);
    await tester.pumpAndSettle();
    expect(controller.pin, '1345');
  });

  testWidgets('PIN and Audio Setup scale from 800x600 through 4K', (
    tester,
  ) async {
    const profile = PlexHomeUser(id: 'child', name: 'Child', protected: true);
    final controller = _ProfileFixtureController()
      ..stage = SetupStage.profiles
      ..profiles = const [profile];
    final fixture = UiFixture(controller: controller);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in [
      const Size(800, 600),
      const Size(1280, 720),
      const Size(1600, 900),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Child'));
      await tester.pumpAndSettle();

      final sheet = tester.getRect(
        find.byKey(const Key('profile-pin-surface')),
      );
      expect(sheet.width, lessThanOrEqualTo(520));
      expect(sheet.bottom, size.height);
      final digitButton = tester.widget<FilledButton>(
        find
            .descendant(
              of: find.byKey(const Key('profile-pin-surface')),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      final background = digitButton.style?.backgroundColor;
      expect(
        background?.resolve(const {}),
        isNot(background?.resolve(const {WidgetState.pressed})),
      );
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byKey(const Key('profile-pin-surface')),
                    matching: find.byType(FilledButton),
                  )
                  .first,
            )
            .shortestSide,
        greaterThanOrEqualTo(72),
      );
      expect(find.byTooltip('Backspace'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.bySemanticsLabel('Backspace'), findsOneWidget);
      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'PIN viewport $size');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      controller.stage = SetupStage.audio;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Audio viewport $size');
      controller.stage = SetupStage.profiles;
    }
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
        PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
        PlexHomeUser(id: 'family', name: 'Family', protected: true),
        PlexHomeUser(id: 'kids', name: 'Kids', protected: false),
        PlexHomeUser(id: 'movies', name: 'Movie Night', protected: false),
        PlexHomeUser(id: 'sports', name: 'Sports', protected: false),
        PlexHomeUser(id: 'weekend', name: 'Weekend', protected: false),
        PlexHomeUser(id: 'visitor', name: 'Visitor', protected: false),
        PlexHomeUser(id: 'parents', name: 'Parents', protected: true),
      ];
    final fixture = UiFixture(controller: controller);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [
      const Size(800, 600),
      const Size(1280, 720),
      const Size(1600, 900),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final cards = find.byType(LineupSelectionCard);
      expect(cards, findsNWidgets(9));
      final cardElements = cards.evaluate();
      expect(
        cardElements.map(
          (element) => (element.renderObject! as RenderBox).size.width,
        ),
        everyElement(140),
      );
      final tops = cardElements
          .map(
            (element) => (element.renderObject! as RenderBox)
                .localToGlobal(Offset.zero)
                .dy,
          )
          .toList();
      expect(
        tops.where((top) => (top - tops.first).abs() < 1),
        hasLength(size.width == 800 ? 4 : 7),
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Parents'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }

    await tester.binding.setSurfaceSize(null);
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(find.text("Who's watching?"))),
      const Size(1920, 1080),
    );
    expect(find.byType(LineupSelectionCard), findsNWidgets(9));
    expect(tester.takeException(), isNull, reason: 'physical 4K at DPR2');

    controller.profiles = controller.profiles.take(8).toList();
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(find.byType(LineupSelectionCard), findsNWidgets(8));
    expect(tester.takeException(), isNull, reason: 'eight-profile population');
  });

  testWidgets('server hierarchy stays reachable across desktop sizes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final server = PlexServer(
      id: 'server',
      name:
          'A deliberately long synthetic server name that must remain readable',
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
    const backupServer = PlexServer(
      id: 'backup-server',
      name: 'Backup Server',
      connections: [],
    );
    final controller = FixtureController()
      ..stage = SetupStage.servers
      ..servers = [server, backupServer]
      ..server = server
      ..connection = PlexConnection(
        uri: Uri.parse('https://selected.synthetic.invalid'),
        local: true,
        relay: false,
        latency: const Duration(milliseconds: 100),
      );

    final fixture = UiFixture(controller: controller);
    for (final size in [
      const Size(800, 600),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'server viewport $size');
    }

    expect(find.bySemanticsLabel(RegExp('Owned server')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Direct local available')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Direct remote available')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Relay available')), findsOneWidget);
    final reconnectSemantics = tester
        .getSemantics(find.widgetWithText(FilledButton, 'Reconnect'))
        .getSemanticsData();
    expect(reconnectSemantics.label, 'Reconnect to ${server.name}');
    expect(reconnectSemantics.flagsCollection.isButton, isTrue);
    expect(reconnectSemantics.hasAction(SemanticsAction.focus), isTrue);
    expect(reconnectSemantics.hasAction(SemanticsAction.tap), isTrue);
    final connectSemantics = tester
        .getSemantics(find.widgetWithText(FilledButton, 'Connect'))
        .getSemanticsData();
    expect(connectSemantics.label, 'Connect to Backup Server');
    expect(connectSemantics.hasAction(SemanticsAction.tap), isTrue);
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
    final shell = tester.getRect(
      find.byKey(const ValueKey('channel-setup-shell')),
    );
    expect(find.text('Configure channels'), findsOneWidget);
    expect(shell.left, greaterThan(0));
    expect(shell.right, lessThan(800));
    expect(shell.top, greaterThan(0));
    expect(shell.bottom, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Channel Setup keeps its footer reachable at 1080p', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
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

    final action = find.widgetWithText(FilledButton, 'Configure channels');
    final shell = tester.getRect(
      find.byKey(const ValueKey('channel-setup-shell')),
    );
    expect(action, findsOneWidget);
    expect(shell.width, lessThan(1920));
    expect(shell.center.dx, 960);
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(1080));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Channel Setup Review keeps staged chrome at compact sizes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final (:size, :textScale) in const [
      (size: Size(800, 600), textScale: 1.0),
      (size: Size(800, 1200), textScale: 1.0),
      (size: Size(1280, 720), textScale: 1.0),
      (size: Size(800, 1200), textScale: 2.0),
    ]) {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      final controller = _SetupFixtureController()
        ..stage = SetupStage.channelSetup
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: UpstreamChannelSetupView(
            key: ValueKey((size, textScale)),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configure channels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build Channels'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pumpAndSettle();

      final header = find.text('Channel Setup');
      final review = find.text('Review expected changes');
      final footer = find.widgetWithText(FilledButton, 'Confirm & Replace');
      expect(header, findsOneWidget);
      expect(review, findsOneWidget);
      expect(footer, findsOneWidget);
      expect(
        tester.getBottomLeft(header).dy,
        lessThan(tester.getTopLeft(review).dy),
      );
      expect(tester.getBottomRight(footer).dy, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    }
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
      ]
      ..channels = [_channel()];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select Plex libraries'), findsOneWidget);
    expect(find.text('Count available after scan'), findsOneWidget);
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    expect(find.text('Configure the lineup'), findsOneWidget);
    expect(find.text('Content Sources'), findsWidgets);
    expect(find.text('Guide Order'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Playlists: No matches.*Genres: 1')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Playlists'));
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('Playlists: Off.*Genres: 1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review expected changes'), findsOneWidget);
    expect(find.text('Confirm & Replace'), findsOneWidget);
    expect(find.bySemanticsLabel('Create: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Update: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Unchanged: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Generated removed: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Custom kept: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Final: 3'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Channel composition. Create: 2, Update: 0, Unchanged: 1, Generated removed: 0.',
      ),
      findsOneWidget,
    );
    expect(find.text('Remove 0 generated channels'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm & Replace'),
          )
          .onPressed,
      isNotNull,
    );
    final firstPlanned = tester.getTopLeft(find.text('Movies Recently Added'));
    final secondPlanned = tester.getTopLeft(find.text('Drama'));
    final protectedCustom = tester.getTopLeft(find.text('Newsroom'));
    expect(firstPlanned.dy, lessThan(secondPlanned.dy));
    expect(secondPlanned.dy, lessThan(protectedCustom.dy));
  });

  testWidgets('Channel Setup protects actual generated removals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SetupFixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..channels = [
        _channel(),
        Channel(
          id: 'retired-generated',
          number: 42,
          name: 'Retro Detectives',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026),
          shuffleSeed: 42,
          builderKey: 'synthetic:retired-generated',
        ),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Confirm & Replace');
    expect(find.text('Remove 1 generated channel'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.text('Remove 1 generated channel'));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      controller.channels.where((channel) => channel.id == 'retired-generated'),
      isEmpty,
    );
    expect(
      controller.channels.where((channel) => channel.id == 'newsroom'),
      hasLength(1),
    );
  });

  testWidgets('Channel Setup merge review matches the applied channel sets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _SetupFixtureController()
      ..stage = SetupStage.channelSetup
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ];
    await controller.setLibraries(const {'movies'});
    final generated = materializeChannelPlan(
      proposals: buildChannelProposals(
        libraries: controller.libraries,
        items: controller.availableMedia,
      ),
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels;
    controller.channels = [
      generated.first,
      Channel(
        id: generated.last.id,
        number: generated.last.number,
        name: 'Old generated name',
        source: generated.last.source,
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2025),
        shuffleSeed: generated.last.shuffleSeed,
        builderKey: generated.last.builderKey,
      ),
      Channel(
        id: 'custom',
        number: 42,
        name: 'Custom',
        source: const ManualSource([]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 42,
      ),
    ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: UpstreamChannelSetupView(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh generated channels'));
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Create: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Update: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Unchanged: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Generated removed: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Custom kept: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Final: 3'), findsOneWidget);
    expect(find.textContaining('UPDATED'), findsOneWidget);
    expect(find.textContaining('RETAINED'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Channel composition.*Update: 1')),
      findsOneWidget,
    );
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
        ..scanFacts = {
          'movies': LibraryScanFact(
            status: status,
            completedPages: 3,
            completedItems: 50,
            totalItems: 100,
          ),
        }
        ..error = error;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: UpstreamChannelSetupView(
            key: ValueKey(status),
            controller: controller,
          ),
        ),
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
    expect(find.text('Scanning'), findsOneWidget);
    expect(find.text('50/100 items · 3 pages'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Movies.*Scanning', dotAll: true)),
      findsOneWidget,
    );
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
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
      await tester.pump();
      expect(
        find.text(switch (state.$1) {
          LibraryScanStatus.empty => 'Empty',
          LibraryScanStatus.unsupported => 'Unsupported',
          _ => 'Cancelled',
        }),
        findsOneWidget,
      );
      expect(find.text('50/100 items · 3 pages'), findsOneWidget);
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
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('50/100 items · 3 pages'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('50/100 items · 3 pages'), findsOneWidget);
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
  Future<bool> selectProfile(PlexHomeUser selected, {String? pin}) async {
    this.pin = pin;
    return true;
  }
}

class _SetupFixtureController extends FixtureController {
  Map<String, LibraryScanFact> scanFacts = const {};

  @override
  Map<String, LibraryScanFact> get libraryScanFacts => scanFacts;

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
          parts: [PlexMediaPart(path: '/parts/movie-$index')],
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
