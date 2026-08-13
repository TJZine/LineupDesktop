import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('management pages use their available width for compact layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          child: SizedBox(
            width: 800,
            height: 700,
            child: LineupPage(
              title: 'Constrained page',
              actions: TextButton(
                onPressed: () {},
                child: const Text('Action'),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Action')).dy,
      greaterThan(tester.getTopLeft(find.text('Constrained page')).dy),
    );
  });

  testWidgets('successful channel deletion clears a prior failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _DeleteFixtureController()
      ..stage = SetupStage.ready
      ..channels = [_channel];
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();

    await _confirmDelete(tester);
    expect(
      find.text(
        'The channel could not be deleted. No lineup changes were saved.',
      ),
      findsOneWidget,
    );
    expect(controller.channels, hasLength(1));
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<IconButton>()
          ?.tooltip,
      'Delete Newsroom',
    );

    await _confirmDelete(tester);
    expect(controller.channels, isEmpty);
    expect(
      find.text(
        'The channel could not be deleted. No lineup changes were saved.',
      ),
      findsNothing,
    );
  });

  testWidgets('manual channels hide the inapplicable watched-items control', (
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
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create channel'));
    await tester.pumpAndSettle();

    expect(find.text('Include watched items'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Hand-picked'));
    await tester.pumpAndSettle();
    expect(find.text('Include watched items'), findsNothing);

    await tester.tap(find.text('Entire library'));
    await tester.pumpAndSettle();
    expect(find.text('Include watched items'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('settings dropdowns stay disabled until persistence completes', (
    tester,
  ) async {
    final controller = _SettingsFixtureController()..stage = SetupStage.ready;
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 hours').last);
    await tester.pump();

    expect(
      tester
          .widgetList<DropdownButton<dynamic>>(find.byType(DropdownButton))
          .every((dropdown) => dropdown.onChanged == null),
      isTrue,
    );

    controller.failUpdate();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This setting could not be saved. Your previous value remains.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<DropdownButton<dynamic>>(find.byType(DropdownButton))
          .every((dropdown) => dropdown.onChanged != null),
      isTrue,
    );
  });

  testWidgets('PIN dialog leaves autofocus with its keyboard owner', (
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

    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FilledButton>(),
      isNull,
    );
  });

  testWidgets('Channel Setup footer uses its available width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
      tester.getTopLeft(find.text('Configure channels')).dy,
      greaterThan(tester.getTopLeft(find.text('Select All')).dy),
    );
  });
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Delete Newsroom'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete channel'));
  await tester.pumpAndSettle();
}

class _DeleteFixtureController extends FixtureController {
  bool failNextDelete = true;

  @override
  Future<void> deleteChannel(String id) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw StateError('synthetic delete failure');
    }
    await super.deleteChannel(id);
  }
}

class _SettingsFixtureController extends FixtureController {
  final _update = Completer<void>();

  @override
  Future<void> updateSettings(LineupSettings value) => _update.future;

  void failUpdate() =>
      _update.completeError(StateError('synthetic save failure'));
}

class _ProfileFixtureController extends FixtureController {
  @override
  Future<void> selectProfile(PlexHomeUser selected, {String? pin}) async {}
}

final _channel = Channel(
  id: 'newsroom',
  number: 7,
  name: 'Newsroom',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 7,
);
