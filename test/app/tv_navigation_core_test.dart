import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/channel_setup/review_step.dart';
import 'package:lineup_desktop/app/channels_view.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/focus_ink.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
  var backgrounds = 0;
  late FocusNode outside;
  const platform = MethodChannel('lineup/platform');
  setUp(() {
    outside = FocusNode(debugLabel: 'Outside Android shell');
    backgrounds = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'moveTaskToBack') backgrounds++;
          return true;
        });
  });
  tearDown(() {
    outside.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });

  void androidTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        FocusManager.instance.applyFocusChangesIfNeeded();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> back(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.handlePopRoute();
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> strand(WidgetTester tester) async {
    outside.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(outside));
  }

  for (final textScale in [1.0, 1.15, 1.3]) {
    for (final largeFocus in [false, true]) {
      for (final railEnd in [false, true]) {
        androidTest(
          'Configure real remote ${railEnd ? 'rail end Down' : 'entry Right'} '
          'keeps actionable focus text=$textScale large=$largeFocus',
          (tester) async {
            tester.view
              ..physicalSize = const Size(1920, 1080)
              ..devicePixelRatio = 2;
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final f = await _setup(libraryCount: 8);
            addTearDown(f.controller.dispose);
            await _pump(tester, f.controller, outside, largeFocus: largeFocus);
            Future<void> key(LogicalKeyboardKey key) async {
              await tester.sendKeyEvent(key);
              await tester.pumpAndSettle();
            }

            // Actual Libraries entry and scan, without forcing focus or Tab.
            for (
              var i = 0;
              i < 30 &&
                  !identical(
                    FocusManager.instance.primaryFocus?.context
                        ?.findAncestorWidgetOfExactType<FilledButton>(),
                    _scanButton(tester),
                  );
              i++
            ) {
              await key(LogicalKeyboardKey.arrowDown);
            }
            expect(
              FocusManager.instance.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<FilledButton>(),
              same(_scanButton(tester)),
            );
            await key(LogicalKeyboardKey.select);
            final saves = f.store.calls;
            expect(find.text('Shape your lineup'), findsOneWidget);
            void rail(int index) {
              final label = find
                  .descendant(
                    of: find.byKey(ValueKey('configure-section-$index')),
                    matching: find.byType(Text),
                  )
                  .first;
              expect(Focus.of(tester.element(label)).hasPrimaryFocus, isTrue);
            }

            rail(0);
            if (railEnd) {
              await key(LogicalKeyboardKey.arrowDown);
              rail(1);
              await key(LogicalKeyboardKey.arrowDown);
              rail(2);
              await key(LogicalKeyboardKey.arrowDown);
            } else {
              await key(LogicalKeyboardKey.arrowRight);
            }
            final primary = FocusManager.instance.primaryFocus!;
            final tile = primary.context!
                .findAncestorWidgetOfExactType<CheckboxListTile>();
            expect(
              tile,
              isNotNull,
              reason: 'Primary focus: $primary; rect: ${primary.rect}',
            );
            final control = find.byWidget(tile!);
            final ink = find
                .ancestor(of: control, matching: find.byType(LineupFocusInk))
                .first;
            expect(tester.widget<LineupFocusInk>(ink).focused, isTrue);
            final bounds = primary.rect;
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.top, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(960));
            expect(bounds.bottom, lessThanOrEqualTo(540));
            final title = find
                .descendant(of: control, matching: find.byType(Text))
                .first;
            final label = tester.widget<Text>(title).data!;
            final before = tile.value!;
            await key(LogicalKeyboardKey.select);
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.widgetWithText(CheckboxListTile, label),
                  )
                  .value,
              !before,
            );
            // Restore the draft before walking to its enabled Review action.
            await key(LogicalKeyboardKey.select);
            expect(
              tester
                  .widget<CheckboxListTile>(
                    find.widgetWithText(CheckboxListTile, label),
                  )
                  .value,
              before,
            );
            // Repeat Down remains among actionable descendants, never the router.
            await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
            for (var i = 0; i < 3; i++) {
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
              await tester.pumpAndSettle();
            }
            await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
            final listener = Focus.of(
              tester.element(
                find.descendant(
                  of: find.byType(UpstreamChannelSetupView),
                  matching: find.byType(Scaffold),
                ),
              ),
            );
            expect(FocusManager.instance.primaryFocus, isNot(same(listener)));
            final review = find.byKey(const ValueKey('review-channels'));
            final backToLibraries = find.widgetWithText(
              TextButton,
              'Back to libraries',
            );
            bool footerFocused() {
              final context = FocusManager.instance.primaryFocus?.context;
              final button =
                  context?.findAncestorWidgetOfExactType<FilledButton>() ??
                  context?.findAncestorWidgetOfExactType<TextButton>();
              return identical(button, tester.widget(review)) ||
                  identical(button, tester.widget(backToLibraries));
            }

            for (var i = 0; i < 30 && !footerFocused(); i++) {
              await key(LogicalKeyboardKey.arrowDown);
            }
            expect(footerFocused(), isTrue);
            if (!identical(
              FocusManager.instance.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<FilledButton>(),
              tester.widget(review),
            )) {
              await key(LogicalKeyboardKey.arrowRight);
            }
            expect(
              FocusManager.instance.primaryFocus?.context
                  ?.findAncestorWidgetOfExactType<FilledButton>(),
              same(tester.widget(review)),
            );
            await key(LogicalKeyboardKey.select);
            expect(
              find.byKey(const ValueKey('channel-setup-review-search')),
              findsOneWidget,
            );
            // The non-focusable ancestor must still receive descendant Back.
            await key(LogicalKeyboardKey.escape);
            rail(0);
            await key(LogicalKeyboardKey.escape);
            expect(
              find.byKey(const ValueKey('library-selection-list')),
              findsOneWidget,
            );
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'Setup libraries entry',
            );
            expect(f.store.calls, saves);
            expect(backgrounds, 0);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  for (final stage in [
    SetupStage.welcome,
    SetupStage.profiles,
    SetupStage.servers,
    SetupStage.channelSetup,
  ]) {
    androidTest('idle first-run $stage is a true root after stranded focus', (
      tester,
    ) async {
      final fixture = UiFixture(
        profile: profileFor(true),
        scenario: LineupScenario(stage: stage),
      );
      await tester.pumpWidget(
        Focus(focusNode: outside, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      await strand(tester);
      await back(tester);
      expect(backgrounds, 1);
      expect(fixture.controller.stage, stage);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final failed in [false, true]) {
    androidTest(
      '${failed ? 'error recovery' : 'stopped'} Player utility return uses current surface predicate',
      (tester) async {
        final native = FixturePlayer.preloaded()
          ..emit(
            const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
          );
        final fixture = UiFixture(
          profile: profileFor(true),
          player: native,
          scenario: const LineupScenario(stage: SetupStage.ready),
        );
        await tester.pumpWidget(
          Focus(focusNode: outside, child: fixture.build()),
        );
        await tester.pumpAndSettle();
        await openDestination(tester, 'Player');
        final player = tester
            .widget<PlayerView>(find.byType(PlayerView))
            .controller;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsView), findsOneWidget);
        if (failed) {
          native.emit(
            const PlayerStatus(
              state: PlayerState.error,
              message: 'Synthetic failure',
              recoverable: true,
            ),
          );
        } else {
          await player.stop();
        }
        await tester.pumpAndSettle();
        expect(player.hasPlaybackIntent, isFalse);
        expect(player.error, failed ? isNotNull : isNull);
        final stops = native.stops;
        await back(tester, settle: !failed);
        expect(find.byType(PlayerView), failed ? findsOneWidget : findsNothing);
        if (failed) {
          expect(player.overlay.name, 'error');
          await back(tester, settle: !failed);
          expect(find.byType(PlayerView), findsOneWidget);
          expect(player.overlay.name, 'none');
          await back(tester, settle: !failed);
        }
        expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
        expect(backgrounds, 0);
        await back(tester, settle: !failed);
        expect(backgrounds, 1);
        expect(native.stops, stops);
        expect(native.loads, isEmpty);
        expect(fixture.controller.fixtureStore.savedStates, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  androidTest(
    'real Applying with stranded focus never backgrounds or starts a second save',
    (tester) async {
      final f = await _setup();
      await _pump(tester, f.controller, outside);
      _scanButton(tester).onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
          .onPressed!();
      await tester.pumpAndSettle();
      f.store.block();
      final saves = f.store.calls;
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('apply-reviewed-lineup')),
          )
          .onPressed!();
      await f.store.started.future;
      await tester.pump();
      await strand(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounds, 0);
      expect(f.store.calls, saves + 1);
      expect(find.text('Creating your lineup…'), findsOneWidget);
      f.store.release();
      await tester.pumpAndSettle();
      expect(f.store.calls, saves + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  androidTest(
    'stranded Channels manual picker unwinds locally before dirty guard and watch parent',
    (tester) async {
      final fixture = UiFixture(
        profile: profileFor(true),
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            Channel(
              id: 'manual',
              number: 1,
              name: 'Manual',
              source: const ManualSource([
                ChannelItem(
                  id: 'existing',
                  title: 'Existing',
                  duration: Duration(minutes: 30),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime.utc(2026),
              shuffleSeed: 1,
            ),
          ],
          availableMedia: [
            PlexMediaItem(
              id: 'new',
              title: 'New item',
              type: 'movie',
              libraryId: 'movies',
              duration: const Duration(minutes: 30),
              parts: [PlexMediaPart(path: '/synthetic/new')],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        Focus(focusNode: outside, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      await tester.tap(find.byKey(const ValueKey('channel-row-manual')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('studio-name')),
        findsOneWidget,
        reason: 'row consumer opened Studio',
      );
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Kept manual draft',
      );
      await tester.tap(find.byKey(const Key('studio-manual-browse-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('studio-result-new')));
      await tester.pump();
      await tester.tap(find.text('Show selected'));
      await tester.pumpAndSettle();
      await strand(tester);
      await back(tester);
      expect(find.text('Back to results'), findsNothing);
      expect(find.text('Show selected'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
      await strand(tester);
      await back(tester);
      expect(find.text('Show selected'), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
      await strand(tester);
      await back(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('studio-name')))
            .controller!
            .text,
        'Kept manual draft',
      );
      expect(backgrounds, 0);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
      expect(fixture.player.loads, isEmpty);
      expect(fixture.player.stops, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final action in ['Open guide', 'Add a custom channel']) {
    androidTest('completion $action rebases a prior Player origin to Home', (
      tester,
    ) async {
      final f = await _setup();
      f.controller.completeChannelSetup();
      final native = FixturePlayer()
        ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
      await _pump(tester, f.controller, outside, player: native);
      await openDestination(tester, 'Player');
      await f.controller.enterChannelSetup();
      await tester.pumpAndSettle();
      _scanButton(tester).onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
          .onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('apply-reviewed-lineup')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      final saves = f.store.calls;
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(f.controller.stage, SetupStage.ready);
      expect(find.byType(UpstreamChannelSetupView), findsNothing);
      if (action == 'Add a custom channel') {
        expect(find.byType(ChannelsView), findsOneWidget);
        expect(find.byKey(const Key('studio-name')), findsOneWidget);
        await back(tester);
        expect(find.byType(ChannelsView), findsOneWidget);
        await back(tester);
      } else {
        expect(find.byType(GuideView), findsOneWidget);
      }
      expect(find.byType(PlayerView), findsNothing);
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      expect(backgrounds, 0);
      await back(tester);
      expect(backgrounds, 1);
      expect(native.loads, isEmpty);
      expect(native.stops, 0);
      expect(f.store.calls, saves);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    });
  }

  androidTest('first TV completion opens Guide through terminal Back', (
    tester,
  ) async {
    final f = await _setup();
    final native = FixturePlayer();
    await _pump(tester, f.controller, outside, player: native);
    _scanButton(tester).onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('apply-reviewed-lineup')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    final saves = f.store.calls;
    expect(find.text('Open guide'), findsOneWidget);
    await back(tester);
    expect(f.controller.stage, SetupStage.ready);
    expect(find.byType(GuideView), findsOneWidget);
    expect(backgrounds, 0);
    expect(f.store.calls, saves);
    expect(native.loads, isEmpty);
    expect(native.stops, 0);
    await back(tester);
    expect(backgrounds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    f.controller.dispose();
  });

  androidTest('first TV completion primary opens Guide without saving', (
    tester,
  ) async {
    final f = await _setup();
    final native = FixturePlayer();
    await _pump(tester, f.controller, outside, player: native);
    _scanButton(tester).onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('apply-reviewed-lineup')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    final saves = f.store.calls;
    expect(find.text('Open guide'), findsOneWidget);
    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();
    expect(f.controller.stage, SetupStage.ready);
    expect(find.byType(GuideView), findsOneWidget);
    expect(backgrounds, 0);
    expect(f.store.calls, saves);
    expect(native.loads, isEmpty);
    expect(native.stops, 0);
    await back(tester);
    expect(backgrounds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    f.controller.dispose();
  });

  androidTest('TV no-change Review opens Guide without saving', (tester) async {
    final f = await _setup();
    final native = FixturePlayer();
    await _pump(tester, f.controller, outside, player: native);
    _scanButton(tester).onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('apply-reviewed-lineup')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();

    await f.controller.enterChannelSetup();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('continue-ready-libraries')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-channels')));
    await tester.pumpAndSettle();

    final saves = f.store.calls;
    expect(find.text('Your lineup is already up to date'), findsOneWidget);
    expect(find.text('Open guide'), findsOneWidget);
    expect(find.text('View lineup'), findsNothing);
    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();
    expect(f.controller.stage, SetupStage.ready);
    expect(find.byType(GuideView), findsOneWidget);
    expect(f.store.calls, saves);
    expect(native.loads, isEmpty);
    expect(native.stops, 0);
    expect(backgrounds, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    f.controller.dispose();
  });

  androidTest(
    'TV no-change Review Back preserves Configure state then Open guide exits once',
    (tester) async {
      final f = await _setup();
      final native = FixturePlayer();
      await _pump(tester, f.controller, outside, player: native);
      _scanButton(tester).onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
          .onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('apply-reviewed-lineup')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();

      await f.controller.enterChannelSetup();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('continue-ready-libraries')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-channels')));
      await tester.pumpAndSettle();

      final saves = f.store.calls;
      expect(find.text('Your lineup is already up to date'), findsOneWidget);
      final search = find.byKey(const ValueKey('channel-setup-review-search'));
      await tester.enterText(search, 'channel');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final filter = find.ancestor(
        of: find.textContaining(RegExp(r'^[0-9]+ Unchanged$')),
        matching: find.byType(TextButton),
      );
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final before = tester.widget<SetupReviewStep>(
        find.byType(SetupReviewStep),
      );
      expect(before.initialSearch, 'channel');
      expect(before.initialFilter, SetupReviewFilter.unchanged);
      await back(tester);
      expect(find.text('Shape your lineup'), findsOneWidget);
      expect(find.byType(GuideView), findsNothing);
      expect(backgrounds, 0);
      expect(f.store.calls, saves);
      // Review again through the real Configure action. Mode, projection and
      // consent remain the same; neither Back nor region navigation saves.
      await tester.tap(find.byKey(const ValueKey('review-channels')));
      await tester.pumpAndSettle();
      final after = tester.widget<SetupReviewStep>(
        find.byType(SetupReviewStep),
      );
      expect(after.review.mode, before.review.mode);
      expect(after.initialSearch, before.initialSearch);
      expect(after.initialFilter, before.initialFilter);
      expect(after.removalConfirmed, before.removalConfirmed);
      expect(find.text('Open guide'), findsOneWidget);
      expect(find.text('View lineup'), findsNothing);
      expect(f.store.calls, saves);
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();
      expect(f.controller.stage, SetupStage.ready);
      expect(find.byType(GuideView), findsOneWidget);
      expect(f.store.calls, saves);
      expect(native.loads, isEmpty);
      expect(native.stops, 0);
      await back(tester);
      expect(backgrounds, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  androidTest('TV regeneration terminal Back opens Guide without saving', (
    tester,
  ) async {
    final f = await _setup();
    f.controller.completeChannelSetup();
    final native = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    await _pump(tester, f.controller, outside, player: native);
    await openDestination(tester, 'Player');
    await f.controller.enterChannelSetup();
    await tester.pumpAndSettle();
    _scanButton(tester).onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('apply-reviewed-lineup')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    final saves = f.store.calls;
    expect(find.text('Open guide'), findsOneWidget);
    await back(tester);
    expect(f.controller.stage, SetupStage.ready);
    expect(find.byType(GuideView), findsOneWidget);
    expect(backgrounds, 0);
    expect(f.store.calls, saves);
    expect(native.loads, isEmpty);
    expect(native.stops, 0);
    await back(tester);
    expect(backgrounds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    f.controller.dispose();
  });

  androidTest('stranded Channels returns Home and Home backgrounds once', (
    tester,
  ) async {
    final fixture = UiFixture(
      profile: profileFor(true),
      scenario: const LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(Focus(focusNode: outside, child: fixture.build()));
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    await strand(tester);
    await back(tester);
    expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
    expect(backgrounds, 0);
    await strand(tester);
    await back(tester);
    expect(backgrounds, 1);
    expect(fixture.player.loads, isEmpty);
    expect(fixture.player.stops, 0);
    expect(fixture.controller.fixtureStore.savedStates, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  androidTest(
    'Browse survives Channels Settings Diagnostics and Licenses detours',
    (tester) async {
      final fixture = UiFixture(
        profile: profileFor(true),
        player: FixturePlayer()
          ..emit(
            const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
          ),
        scenario: const LineupScenario(stage: SetupStage.ready),
      );
      await tester.pumpWidget(
        Focus(focusNode: outside, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Player');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      await openDestination(tester, 'Settings');
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open Licenses'));
      await tester.tap(find.text('Open Licenses'));
      await tester.pumpAndSettle();
      await strand(tester);
      await back(tester);
      expect(find.text('Open Licenses'), findsOneWidget);
      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('Open Diagnostics'), findsOneWidget);
      await back(tester);
      expect(find.byType(ChannelsView), findsOneWidget);
      final focus = FocusManager.instance.primaryFocus!;
      expect(focus.context?.mounted, isTrue);
      expect(
        focus.context?.findAncestorWidgetOfExactType<ChannelsView>(),
        isNotNull,
      );
      await back(tester);
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      await back(tester);
      expect(find.byType(PlayerView), findsOneWidget);
      await back(tester);
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      await back(tester);
      expect(backgrounds, 1);
      expect(fixture.player.loads, isEmpty);
      expect(fixture.player.stops, 0);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final key in [
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.backspace,
  ]) {
    androidTest(
      'held $key makes one transition; empty editing Backspace stays local',
      (tester) async {
        final fixture = UiFixture(
          profile: profileFor(true),
          scenario: const LineupScenario(stage: SetupStage.ready),
        );
        await tester.pumpWidget(
          Focus(focusNode: outside, child: fixture.build()),
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const Key('guide-channel-search'));
        await tester.tap(search);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(backgrounds, 0);
        expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
        await openDestination(tester, 'Channels');
        await tester.sendKeyDownEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
        await tester.sendKeyRepeatEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        expect(backgrounds, 0);
        await tester.sendKeyEvent(key, physicalKey: PhysicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(backgrounds, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  androidTest('dirty Studio denial and stranded Back retain route and draft', (
    tester,
  ) async {
    final fixture = UiFixture(
      profile: profileFor(true),
      scenario: const LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(Focus(focusNode: outside, child: fixture.build()));
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('Create a custom channel'));
    await tester.pumpAndSettle();
    final name = find.byKey(const Key('studio-name'));
    await tester.enterText(name, 'Kept draft');
    await openDestination(tester, 'Settings');
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsNothing);
    expect(tester.widget<TextFormField>(name).controller!.text, 'Kept draft');
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    await strand(tester);
    await back(tester);
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
    await strand(tester);
    await back(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(backgrounds, 0);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelsView), findsOneWidget);
    await back(tester);
    expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
    expect(fixture.controller.fixtureStore.savedStates, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  androidTest('stranded Player Sleep and drawer unwind before Home', (
    tester,
  ) async {
    final fixture = UiFixture(
      profile: profileFor(true),
      player: FixturePlayer()
        ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready')),
      scenario: const LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(Focus(focusNode: outside, child: fixture.build()));
    await tester.pumpAndSettle();
    await openDestination(tester, 'Player');
    final player = tester
        .widget<PlayerView>(find.byType(PlayerView))
        .controller;
    player.showOsd();
    player.showSleepTimer();
    await tester.pumpAndSettle();
    await strand(tester);
    await back(tester);
    expect(player.sleepPickerOpen, isFalse);
    expect(player.overlay.name, 'osd');
    player.showTracks(PlayerTrackType.subtitle);
    await tester.pumpAndSettle();
    await strand(tester);
    await back(tester);
    expect(player.overlay.name, 'osd');
    await back(tester);
    expect(player.overlay.name, 'none');
    await back(tester);
    expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
    expect(backgrounds, 0);
    await back(tester);
    expect(backgrounds, 1);
    expect(fixture.player.loads, isEmpty);
    expect(fixture.player.stops, 0);
    expect(fixture.controller.fixtureStore.savedStates, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  androidTest(
    'scope retirement while dirty guard awaits cannot commit proposed Settings',
    (tester) async {
      final fixture = UiFixture(
        profile: profileFor(true),
        scenario: const LineupScenario(stage: SetupStage.ready),
      );
      await tester.pumpWidget(
        Focus(focusNode: outside, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      await tester.tap(find.text('Create a custom channel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Obsolete route intent',
      );
      await openDestination(tester, 'Settings');
      expect(find.text('Discard changes?'), findsOneWidget);
      fixture.controller.fixtureActor.replaceConnection(null);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byKey(const Key('studio-name')), findsOneWidget);
      expect(backgrounds, 0, reason: 'modal owns native route request');
      // The denied intent keeps its menu. A fresh Settings action is guarded.
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      fixture.controller.fixtureActor.publishInventory();
      await tester.pump();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byType(ChannelsView), findsOneWidget);
      expect(fixture.controller.fixtureStore.savedStates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  androidTest(
    'stranded submitting PIN stays with current PIN owner and preserves Setup draft',
    (tester) async {
      final f = await _setup();
      await _pump(tester, f.controller, outside);
      final element = tester.element(find.byType(UpstreamChannelSetupView));
      await tester.tap(find.byKey(const ValueKey('library-row-movies')));
      await tester.tap(find.text('Switch server'));
      await tester.pumpAndSettle();
      f.controller.showProfiles();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-card-protected')));
      await tester.pumpAndSettle();
      f.plex.pinGate = Completer<void>();
      final saves = f.store.calls;
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(f.plex.pinCalls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await strand(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
      expect(f.controller.stage, SetupStage.profiles);
      expect(f.plex.pinCalls, 1);
      expect(f.store.calls, saves);
      expect(backgrounds, 0);
      f.plex.pinGate!.complete();
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(f.controller.stage, SetupStage.profiles);
      await back(tester);
      expect(f.controller.stage, SetupStage.servers);
      await back(tester);
      expect(f.controller.stage, SetupStage.channelSetup);
      expect(
        tester.element(find.byType(UpstreamChannelSetupView)),
        same(element),
      );
      expect(_scanButton(tester).onPressed, isNull);
      expect(f.store.calls, saves);
      expect(backgrounds, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  androidTest(
    'same-scope picker cancel retains configured options without saving the excursion',
    (tester) async {
      final f = await _setup();
      await _pump(tester, f.controller, outside);
      final element = tester.element(find.byType(UpstreamChannelSetupView));
      _scanButton(tester).onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('configure-section-2')));
      await tester.pumpAndSettle();
      final minimum = find.byKey(const ValueKey('rules-minimum'));
      await tester.ensureVisible(minimum);
      await tester.tap(minimum);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(minimum).value, 10);
      await back(tester);
      final saves = f.store.calls;
      await tester.tap(find.text('Switch server'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(
        tester.element(find.byType(UpstreamChannelSetupView)),
        same(element),
      );
      expect(f.store.calls, saves);
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('continue-ready-libraries')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(minimum).value, 10);
      expect(backgrounds, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  for (final profiles in [false, true]) {
    androidTest(
      'same-scope ${profiles ? 'profile' : 'server'} cancel restores actionable retained Setup',
      (tester) async {
        final f = await _setup();
        final native = FixturePlayer();
        await _pump(tester, f.controller, outside, player: native);
        final finder = find.byType(UpstreamChannelSetupView);
        final element = tester.element(finder);
        final state = tester.state(finder);
        final row = find.byKey(const ValueKey('library-row-movies'));
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(_scanButton(tester).onPressed, isNull);
        final saves = f.store.calls;
        final loads = native.loads.length;
        final stops = native.stops;
        final switcher = find.byKey(const ValueKey('setup-switch-server'));
        Focus.of(
          tester.element(
            find.descendant(of: switcher, matching: find.text('Switch server')),
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(f.controller.stage, SetupStage.servers);
        expect(find.byType(UpstreamChannelSetupView), findsNothing);
        expect(find.byType(UpstreamOnboardingView), findsOneWidget);
        if (profiles) {
          // Public controller boundary: the optional Profiles excursion.
          f.controller.showProfiles();
          await tester.pumpAndSettle();
          await back(tester);
          expect(f.controller.stage, SetupStage.servers);
        }
        await back(tester);
        expect(f.controller.stage, SetupStage.channelSetup);
        expect(tester.element(finder), same(element));
        expect(tester.state(finder), same(state));
        expect(_scanButton(tester).onPressed, isNull);
        final node = tester.widget<InkWell>(row).focusNode!;
        expect(node.hasPrimaryFocus, isTrue);
        expect(node.canRequestFocus, isTrue);
        expect(node.context?.mounted, isTrue);
        expect(
          tester
              .getRect(row)
              .overlaps(
                Offset.zero &
                    tester.view.physicalSize / tester.view.devicePixelRatio,
              ),
          isTrue,
        );
        final ink = find
            .ancestor(of: row, matching: find.byType(LineupFocusInk))
            .first;
        expect(tester.widget<LineupFocusInk>(ink).focused, isTrue);
        final label = find
            .descendant(of: row, matching: find.text('Movies'))
            .first;
        final roles = LineupTheme.of(tester.element(finder));
        expect(tester.widget<Text>(label).style!.color, roles.onFocus);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(
          _scanButton(tester).onPressed,
          isNotNull,
          reason: 'immediate Select toggles the retained unchecked library',
        );
        expect(node.hasPrimaryFocus, isTrue);
        expect(node.canRequestFocus, isTrue);
        expect(node.context?.mounted, isTrue);
        expect(f.store.calls, saves);
        expect(native.loads.length, loads);
        expect(native.stops, stops);
        expect(backgrounds, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        f.controller.dispose();
      },
    );
  }

  androidTest(
    'empty Libraries return paints recovery and immediate Select reopens picker',
    (tester) async {
      final f = await _setup(empty: true);
      final native = FixturePlayer();
      await _pump(tester, f.controller, outside, player: native);
      final setup = tester.element(find.byType(UpstreamChannelSetupView));
      final saves = f.store.calls;
      final loads = native.loads.length;
      final stops = native.stops;
      final switcher = find.byKey(const ValueKey('setup-switch-server'));
      final node = tester.widget<FilledButton>(switcher).focusNode!;
      expect(node.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(f.controller.stage, SetupStage.servers);
      await back(tester);
      expect(
        tester.element(find.byType(UpstreamChannelSetupView)),
        same(setup),
      );
      expect(node.hasPrimaryFocus, isTrue);
      expect(node.context?.mounted, isTrue);
      expect(node.canRequestFocus, isTrue);
      expect(tester.widget<FilledButton>(switcher).onPressed, isNotNull);
      final roles = LineupTheme.of(tester.element(switcher));
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(of: switcher, matching: find.byType(Material))
                  .first,
            )
            .color,
        roles.focusedSurface,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(f.controller.stage, SetupStage.servers);
      expect(find.byType(UpstreamOnboardingView), findsOneWidget);
      expect(f.store.calls, saves);
      expect(native.loads.length, loads);
      expect(native.stops, stops);
      expect(backgrounds, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  androidTest(
    'unrendered picker round trip preserves the current Setup focus',
    (tester) async {
      final f = await _setup();
      await _pump(tester, f.controller, outside);
      final switcher = find.byKey(const ValueKey('setup-switch-server'));
      final label = find.descendant(
        of: switcher,
        matching: find.text('Switch server'),
      );
      final node = Focus.of(tester.element(label));
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(node.hasPrimaryFocus, isTrue);
      f.controller.showServers();
      f.controller.cancelServerSelection();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(node));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(f.controller.stage, SetupStage.servers);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );

  for (final modal in [false, true]) {
    androidTest(
      'pending Setup resume yields to ${modal ? 'modal' : 'new picker'} owner',
      (tester) async {
        final f = await _setup();
        await _pump(tester, f.controller, outside);
        await tester.tap(find.text('Switch server'));
        await tester.pumpAndSettle();
        // Public controller boundary, deliberately before the resume frame.
        f.controller.cancelServerSelection();
        final dialogFocus = FocusNode(debugLabel: 'Superseding dialog');
        if (modal) {
          unawaited(
            showDialog<void>(
              context: tester.element(find.byType(LineupShell)),
              builder: (context) => AlertDialog(
                actions: [
                  TextButton(
                    focusNode: dialogFocus,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Dialog owner'),
                  ),
                ],
              ),
            ),
          );
        } else {
          f.controller.showServers();
        }
        await tester.pumpAndSettle();
        final owner = FocusManager.instance.primaryFocus;
        expect(owner, isNotNull);
        expect(owner!.context?.mounted, isTrue);
        expect(owner.canRequestFocus, isTrue);
        if (modal) {
          expect(owner, same(dialogFocus));
        } else {
          expect(
            owner.context
                ?.findAncestorWidgetOfExactType<UpstreamOnboardingView>(),
            isNotNull,
          );
        }
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(owner));
        expect(
          owner.context
              ?.findAncestorWidgetOfExactType<UpstreamChannelSetupView>(),
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        dialogFocus.dispose();
        f.controller.dispose();
      },
    );
  }

  for (final fail in [true, false]) {
    androidTest(
      'real same-ID server save ${fail ? 'failure retains' : 'success retires'} suspended Setup',
      (tester) async {
        final f = await _setup();
        await _pump(tester, f.controller, outside);
        final finder = find.byType(UpstreamChannelSetupView);
        final element = tester.element(finder);
        await tester.tap(find.byKey(const ValueKey('library-row-movies')));
        await tester.tap(find.text('Switch server'));
        await tester.pumpAndSettle();
        final saves = f.store.calls;
        final generation = f.controller.contentGeneration;
        f.store.block(fail: fail);
        final selection = f.controller.selectServer(f.controller.server!);
        await f.store.started.future;
        await tester.pump();
        await strand(tester);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(backgrounds, 0);
        expect(f.controller.stage, SetupStage.servers);
        expect(f.store.calls, saves + 1);
        f.store.release();
        await selection;
        await tester.pumpAndSettle();
        if (fail) {
          expect(f.controller.contentGeneration, generation);
          await back(tester);
          expect(tester.element(finder), same(element));
          expect(_scanButton(tester).onPressed, isNull);
          final row = find.byKey(const ValueKey('library-row-movies'));
          expect(
            tester.widget<InkWell>(row).focusNode!.hasPrimaryFocus,
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(_scanButton(tester).onPressed, isNotNull);
        } else {
          expect(f.controller.contentGeneration, greaterThan(generation));
          expect(f.controller.stage, SetupStage.channelSetup);
          expect(tester.element(finder), isNot(same(element)));
          expect(_scanButton(tester).onPressed, isNotNull);
        }
        expect(f.store.calls, saves + 1);
        expect(backgrounds, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        f.controller.dispose();
      },
    );
  }

  androidTest(
    'real held library commit and Applying consume focused and stranded Back exactly once',
    (tester) async {
      final f = await _setup();
      await _pump(tester, f.controller, outside);
      final element = tester.element(find.byType(UpstreamChannelSetupView));
      f.store.block();
      final saves = f.store.calls;
      _scanButton(tester).onPressed!();
      await f.store.started.future;
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await strand(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounds, 0);
      expect(f.store.calls, saves + 1);
      f.store.release();
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(UpstreamChannelSetupView)),
        same(element),
      );
      expect(find.text('Shape your lineup'), findsOneWidget);
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
          .onPressed!();
      await tester.pumpAndSettle();
      f.store.block();
      final applySaves = f.store.calls;
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('apply-reviewed-lineup')),
          )
          .onPressed!();
      await f.store.started.future;
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await strand(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounds, 0);
      expect(find.text('Creating your lineup…'), findsOneWidget);
      expect(f.store.calls, applySaves + 1);
      f.store.release();
      await tester.pumpAndSettle();
      await back(tester);
      expect(f.controller.stage, SetupStage.ready);
      expect(find.byType(GuideView), findsOneWidget);
      expect(backgrounds, 0);
      expect(f.store.calls, applySaves + 1);
      await back(tester);
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      expect(backgrounds, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      f.controller.dispose();
    },
  );
}

FilledButton _scanButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('scan-selected-libraries')),
);

Future<void> _pump(
  WidgetTester tester,
  LineupController controller,
  FocusNode outside, {
  FixturePlayer? player,
  bool largeFocus = false,
}) async {
  await tester.pumpWidget(
    DeviceProfileScope(
      profile: profileFor(true),
      child: Focus(
        focusNode: outside,
        child: MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            largeFocusIndicators: largeFocus,
            formFactor: profileFor(true).formFactor,
          ),
          builder: LineupCanvas.builder,
          home: LineupShell(
            player: player ?? FixturePlayer(),
            controller: controller,
            profile: profileFor(true),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<({LineupController controller, _Store store, _Plex plex})> _setup({
  bool empty = false,
  int libraryCount = 1,
}) async {
  final store = _Store();
  final plex = _Plex(empty: empty, libraryCount: libraryCount);
  final controller = LineupController(
    store: store,
    credentials: MemoryCredentialStore(accountToken: 'synthetic-token'),
    plex: plex,
  );
  await controller.initialize();
  expect(controller.stage, SetupStage.channelSetup);
  return (controller: controller, store: store, plex: plex);
}

class _Store extends MemoryAppStore {
  _Store()
    : super(
        initial: const PersistedState(
          profileId: 'owner',
          selectedServerByProfile: {'owner': 'server'},
        ),
      );
  int calls = 0;
  Completer<void>? gate;
  Completer<void> started = Completer<void>();
  bool failure = false;
  void block({bool fail = false}) {
    gate = Completer<void>();
    started = Completer<void>();
    failure = fail;
  }

  void release() => gate!.complete();
  @override
  Future<void> save(PersistedState value) async {
    calls++;
    if (gate case final held?) {
      started.complete();
      await held.future;
      gate = null;
      if (failure) throw StateError('synthetic save failure');
    }
    await super.save(value);
  }
}

final _server = PlexServer(
  id: 'server',
  name: 'Synthetic server',
  connections: [
    PlexConnection(
      uri: Uri.parse('https://synthetic.invalid'),
      local: true,
      relay: false,
    ),
  ],
);

class _Plex extends PlexClient {
  _Plex({this.empty = false, this.libraryCount = 1})
    : super(
        clientIdentifier: 'lineup-navigation-test-client',
        httpClient: testPlexHttpClient(),
      );
  final bool empty;
  final int libraryCount;
  Completer<void>? pinGate;
  int pinCalls = 0;
  @override
  Future<String> switchHomeUser(String token, String id, String? pin) async {
    pinCalls++;
    if (pinGate case final gate?) await gate.future;
    throw const PlexException('pin-invalid', 'Synthetic PIN failure.');
  }

  @override
  Future<PlexAccount> account(String token) async => const PlexAccount(
    id: 'owner',
    name: 'Owner',
    email: 'owner@example.invalid',
  );
  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => const [
    PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
    PlexHomeUser(id: 'other', name: 'Other', protected: false),
    PlexHomeUser(id: 'protected', name: 'Protected', protected: true),
  ];
  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    PlexServerAccess(server: _server, token: 'synthetic-pms-token'),
  ];
  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async => server.connections.single;
  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async => empty
      ? const []
      : [
          for (var i = 0; i < libraryCount; i++)
            PlexLibrary(
              id: i == 0 ? 'movies' : 'movies-$i',
              title: i == 0 ? 'Movies' : 'Movies $i',
              type: PlexLibraryType.movie,
            ),
        ];
  @override
  Future<PlexLibraryScan> scanLibrary(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress progress) onProgress,
    void Function(PlexLibraryScanPhase phase)? onPhase,
    Future<void>? cancelled,
  }) async => PlexLibraryScan(
    items: [
      for (var i = 0; i < 5; i++)
        PlexMediaItem(
          id: 'movie-$i',
          title: 'Movie $i',
          type: 'movie',
          libraryId: 'movies',
          duration: const Duration(minutes: 30),
          parts: [PlexMediaPart(path: '/synthetic/movie-$i')],
        ),
    ],
  );
  @override
  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress)? onProgress,
  }) async => const PlexPlaylistCatalog(playlists: [], failedIds: {});
}
