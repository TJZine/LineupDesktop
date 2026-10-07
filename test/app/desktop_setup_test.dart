import 'dart:async';

import 'dart:ui' show CheckedState;

import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';
import '../support/golden_test_support.dart';

void main() {
  for (final partial in [false, true]) {
    testWidgets(
      'Playlists ${partial ? 'partial' : 'unavailable'} supports retry',
      (tester) async {
        final controller = _SetupController(
          playlistUnavailable: !partial,
          playlistFailures: partial ? {'one', 'two'} : {},
          playlists: partial ? [_workingPlaylist] : [],
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller);
        await _advanceToConfigure(tester);
        await tester.ensureVisible(find.text('Playlists'));
        expect(
          find.text(
            partial
                ? '2 playlists unavailable · Retry'
                : 'Playlists unavailable · Retry',
          ),
          findsOneWidget,
        );
        final tile = find.widgetWithText(CheckboxListTile, 'Playlists');
        expect(
          find.descendant(
            of: tile,
            matching: find.text(partial ? '1 channel' : '0 channels'),
          ),
          findsOneWidget,
        );
        final retry = find.byKey(const ValueKey('retry-discovery-playlists'));
        expect(
          tester
              .getTopLeft(
                find.descendant(
                  of: retry,
                  matching: find.byIcon(Icons.refresh),
                ),
              )
              .dx,
          closeTo(
            tester
                .getTopLeft(
                  find.text('Create channels from your Plex playlists.'),
                )
                .dx,
            0.01,
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('retry-discovery-playlists')),
        );
        await tester.pumpAndSettle();
        expect(controller.rowRetryIds, {'movies', 'shows', 'archive'});
        expect(
          find.byKey(const ValueKey('retry-discovery-playlists')),
          findsNothing,
        );
      },
    );
  }
  for (final unavailable in [false, true]) {
    testWidgets(
      'Collections ${unavailable ? 'unavailable' : 'partial'} supports retry',
      (tester) async {
        final controller = _SetupController(
          collectionUnavailable: unavailable ? {'movies'} : {},
          media: unavailable ? _media : _partialMedia,
          collectionFailures: unavailable
              ? {}
              : {
                  'movies': {'Failed collection'},
                },
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller);
        await _advanceToConfigure(tester);
        await tester.ensureVisible(find.text('Collections'));
        expect(
          find.text(
            unavailable
                ? 'Collections unavailable in 1 library · Retry'
                : '1 collection unavailable · Retry',
          ),
          findsOneWidget,
        );
        final tile = find.widgetWithText(CheckboxListTile, 'Collections');
        expect(
          find.descendant(
            of: tile,
            matching: find.text(unavailable ? '0 channels' : '1 channel'),
          ),
          findsOneWidget,
        );
        final retry = find.byKey(const ValueKey('retry-discovery-collections'));
        expect(
          tester
              .getTopLeft(
                find.descendant(
                  of: retry,
                  matching: find.byIcon(Icons.refresh),
                ),
              )
              .dx,
          closeTo(
            tester
                .getTopLeft(
                  find.text(
                    'Create channels from collections in each selected library.',
                  ),
                )
                .dx,
            0.01,
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('retry-discovery-collections')),
        );
        await tester.pumpAndSettle();
        expect(controller.rowRetryIds, {'movies'});
        expect(
          find.byKey(const ValueKey('retry-discovery-collections')),
          findsNothing,
        );
      },
    );
  }
  testWidgets('append review reports existing sources skipped', (tester) async {
    final existing = materializeChannelPlan(
      proposals: buildChannelProposals(
        libraries: _libraries,
        items: _media,
        strategies: {BuilderStrategy.genres},
        minimumItems: 5,
      ),
      existing: [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels;
    final controller = _SetupController(channels: existing);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);
    await tester.tap(find.text('Add as new channels'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Keep your existing lineup and add channels whose sources are not already in it.',
      ),
      findsOneWidget,
    );
    expect(find.text('3 already in your lineup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-to-configure')));
    await tester.pumpAndSettle();
    for (final strategy in BuilderStrategy.values.where(
      (strategy) => strategy != BuilderStrategy.genres,
    )) {
      final tile = find.widgetWithText(
        CheckboxListTile,
        builderStrategyLabels[strategy]!,
      );
      final label = find.descendant(
        of: tile,
        matching: find.text(builderStrategyLabels[strategy]!),
      );
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('review-channels')));
    await tester.pumpAndSettle();
    expect(find.text('3 already in your lineup'), findsOneWidget);
    expect(find.text('Your lineup is already up to date'), findsOneWidget);
  });
  testWidgets(
    'default keep preserves a missing generated source when applying',
    (tester) async {
      final controller = _SetupController(channels: [_missingChannel]);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToReview(tester);
      await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
      await tester.pumpAndSettle();
      expect(controller.channels, contains(_missingChannel));
      expect(controller.applyCalls, 1);
    },
  );
  testWidgets('missing source defaults to keep and explicit remove applies', (
    tester,
  ) async {
    final controller = _SetupController(channels: [_missingChannel]);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);
    final choice = find.byKey(const ValueKey('missing-source-choice-missing'));
    await tester.ensureVisible(choice);
    expect(find.text('Source not found'), findsOneWidget);
    expect(tester.widget<LineupSegmentedControl<bool>>(choice).selected, {
      false,
    });
    await tester.tap(
      find.descendant(of: choice, matching: find.text('Remove')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<LineupSegmentedControl<bool>>(choice).selected, {
      true,
    });
    await tester.tap(
      find.byKey(const ValueKey('channel-setup-replace-confirmation')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(
      controller.channels.any((channel) => channel.id == 'missing'),
      isFalse,
    );
  });
  testWidgets(
    'collection failure excludes unmatched channel from missing source review',
    (tester) async {
      final controller = _SetupController(
        channels: [_missingChannel],
        collectionFailures: {
          'movies': {'Retired collection'},
        },
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToReview(tester);
      expect(find.text('Source not found'), findsNothing);
    },
  );
  testWidgets(
    'playlist and nested dependency failures never appear as missing sources',
    (tester) async {
      for (final unavailable in [false, true]) {
        final channel = Channel(
          id: 'missing-playlist',
          number: 90,
          name: 'Unavailable playlist',
          source: const MixedSource(
            sources: [
              PlaylistSource('failed'),
              LibrarySource(
                libraryId: 'movies',
                libraryType: PlexLibraryType.movie,
                filters: {
                  LibraryFilter.collection: ['Retired collection'],
                },
              ),
            ],
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026),
          shuffleSeed: 90,
          builderKey: 'missing-playlist',
        );
        final controller = _SetupController(
          channels: [channel],
          playlistUnavailable: unavailable,
          playlistFailures: unavailable ? {} : {'failed'},
        );
        await _pump(tester, controller);
        await _advanceToReview(tester);
        expect(find.text('Source not found'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets('missing sources remain reviewable with no new proposals', (
    tester,
  ) async {
    final controller = _SetupController(channels: [_missingChannel]);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToConfigure(tester);
    for (final strategy in BuilderStrategy.values) {
      final tile = find.widgetWithText(
        CheckboxListTile,
        builderStrategyLabels[strategy]!,
      );
      final label = find.descendant(
        of: tile,
        matching: find.text(builderStrategyLabels[strategy]!),
      );
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('review-channels')));
    await tester.pumpAndSettle();
    expect(find.text('Source not found'), findsOneWidget);
  });
  testWidgets(
    '1366 canvas keeps setup stages reachable after interpolation retirement',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: UpstreamChannelSetupView(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await _advanceToConfigure(tester);
      for (final section in [1, 2, 0]) {
        await tester.tap(find.byKey(ValueKey('configure-section-$section')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(
        find.byKey(const ValueKey('channel-configuration')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-channels')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('apply-reviewed-lineup')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('setup bar and actions remain reachable with enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    expect(find.byType(LineupTopBar), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('scan-selected-libraries')),
    );
    await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
    await tester.pumpAndSettle();
    expect(find.text('Shape your lineup'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('review-channels')));
    await tester.tap(find.byKey(const ValueKey('review-channels')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('apply-reviewed-lineup')),
    );
    expect(
      find.byKey(const ValueKey('apply-reviewed-lineup')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library selection is tri-state and mixed scans continue ready rows',
    (tester) async {
      final controller = _SetupController(mixedScan: true);
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      expect(
        find.byKey(const ValueKey('select-all-libraries')),
        findsOneWidget,
      );
      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Select all')).dx,
        closeTo(tester.getTopLeft(find.text('Movies').first).dx, .1),
      );
      await tester.tap(find.text('Shows'));
      await tester.pump();
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('select-all-libraries')),
            )
            .value,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 of 2 libraries is ready'), findsOneWidget);
      expect(find.text('Ready · 6 items checked'), findsOneWidget);
      expect(find.text('Couldn’t scan · Try again.'), findsOneWidget);
      expect(find.text('Retry failed scans'), findsOneWidget);
      expect(find.text("Won't be used"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('retry-library-archive')));
      await tester.pumpAndSettle();
      expect(controller.rowRetryIds, {'archive'});
      expect(controller.rowRetryInventory, {'movies', 'archive'});
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue-ready-libraries')),
        findsOneWidget,
      );
      await tester.tap(find.text('Movies').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('continue-ready-libraries')),
        findsNothing,
      );
      expect(find.text('Retry failed scans'), findsOneWidget);
      await tester.tap(find.text('Movies').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('continue-ready-libraries')));
      await tester.pumpAndSettle();
      expect(controller.committedIds, {'movies'});
      expect(find.byKey(const ValueKey('configure-section-0')), findsOneWidget);
    },
  );

  testWidgets('cancelled scan keeps the selected libraries editable', (
    tester,
  ) async {
    final controller = _SetupController(blockScan: true);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
    await controller.scanStarted.future;
    await tester.pump();
    expect(find.text('Cancel scan'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('select-all-libraries')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.text('Cancel scan'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('continue-ready-libraries')),
      findsNothing,
    );
    expect(find.text('3 of 3 selected'), findsOneWidget);
    expect(find.textContaining('Cancelled', skipOffstage: false), findsWidgets);
    expect(
      find.byKey(const ValueKey('scan-selected-libraries')),
      findsOneWidget,
    );
  });

  testWidgets('configure exposes the three approved sections and defaults', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToConfigure(tester);

    expect(find.byKey(const ValueKey('configure-section-0')), findsOneWidget);
    expect(find.text('200 generated channels'), findsNothing);
    final grouping = find.byKey(const ValueKey('source-grouping-genres'));
    final genres = find.widgetWithText(CheckboxListTile, 'Genres');
    await tester.ensureVisible(grouping);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<bool>>(grouping).value, isFalse);
    await tester.tap(grouping);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Combine matching genres').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<bool>>(grouping).value, isTrue);

    await tester.ensureVisible(genres);
    await tester.pumpAndSettle();
    await tester.tap(genres);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<bool>>(grouping).onChanged, isNull);
    expect(tester.widget<DropdownButton<bool>>(grouping).value, isTrue);
    await tester.tap(genres);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<bool>>(grouping).onChanged, isNotNull);
    expect(tester.widget<DropdownButton<bool>>(grouping).value, isTrue);

    await tester.ensureVisible(grouping);
    await tester.pumpAndSettle();
    await tester.tap(grouping);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Separate by library').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<bool>>(grouping).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('configure-section-1')));
    await tester.pumpAndSettle();
    expect(find.text('Playback order'), findsNWidgets(2));
    final semantics = tester.ensureSemantics();
    try {
      final shuffle = find.byKey(const ValueKey('setup-playback-shuffle'));
      final inOrder = find.byKey(const ValueKey('setup-playback-sequential'));
      final miniMarathons = find.byKey(const ValueKey('setup-playback-block'));
      for (final card in [shuffle, inOrder, miniMarathons]) {
        expect(
          tester
              .getSemantics(card)
              .getSemanticsData()
              .flagsCollection
              .isInMutuallyExclusiveGroup,
          isTrue,
        );
      }
      final selectedPaint = _cardPaint(tester, shuffle);
      expect((selectedPaint.decoration as BoxDecoration).border!.top.width, 1);
      expect(selectedPaint.foregroundDecoration, isNull);
      tester.widget<RawRadio<PlaybackMode>>(shuffle).focusNode.requestFocus();
      await tester.pump();
      expect(_cardPaint(tester, shuffle).foregroundDecoration, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final focusedPaint = _cardPaint(tester, inOrder);
      expect(
        (focusedPaint.foregroundDecoration as BoxDecoration).border!.top.width,
        3,
      );
      expect((focusedPaint.decoration as BoxDecoration).border!.top.width, 1);
      expect(
        tester
            .getSemantics(inOrder)
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      expect(
        tester
            .getSemantics(shuffle)
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      expect(
        tester.widget<RawRadio<PlaybackMode>>(inOrder).focusNode.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Include specials'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(shuffle)
            .getSemanticsData()
            .flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );
      expect(find.text('Include specials'), findsNothing);
    } finally {
      semantics.dispose();
    }
    expect(find.text('Additional channel versions'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Additional channel versions'),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('configure-section-2')));
    await tester.pumpAndSettle();
    expect(find.text('Lineup rules'), findsOneWidget);
    expect(find.text('Maximum generated channels'), findsOneWidget);
    expect(find.text('Minimum programs per channel'), findsOneWidget);
    expect(
      find.text('Take one channel from each source, then repeat.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('configuration-allocation-summary')),
        matching: find.text('6'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Choose more sources or lower the minimum programs per channel.',
      ),
      findsNothing,
    );
    final minimum = find.byKey(const ValueKey('rules-minimum'));
    await tester.ensureVisible(minimum);
    await tester.pumpAndSettle();
    await tester.tap(minimum);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Choose more sources or lower the minimum programs per channel.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('configuration-allocation-summary')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
          .onPressed,
      isNull,
    );
    await tester.tap(minimum);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('configuration-allocation-summary')),
        matching: find.text('6'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Choose more sources or lower the minimum programs per channel.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'Mini-marathon options share a row without hiding versions at desktop size',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, controller);
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
      await _openPlaybackControls(tester);
      await tester.tap(find.byKey(const ValueKey('setup-playback-block')));
      await tester.pumpAndSettle();
      double? normalSpecialsWidth;
      for (final textScale in [1.0, 1.5]) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pumpAndSettle();
        final field = tester.getRect(_setupField<int>('Episodes per block'));
        final specials = tester.getRect(
          find.widgetWithText(CheckboxMenuButton, 'Include specials'),
        );
        expect(specials.left, greaterThan(field.right));
        expect(
          specials.center.dy,
          inInclusiveRange(field.top - 28 * textScale, field.bottom),
        );
        if (textScale == 1) {
          normalSpecialsWidth = specials.width;
        } else {
          expect(specials.width, greaterThan(normalSpecialsWidth!));
        }
        if (textScale == 1) {
          expect(
            find.text('Additional channel versions').hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.getRect(find.text('Additional channel versions')).bottom,
            lessThan(
              tester
                  .getTopLeft(find.byKey(const ValueKey('review-channels')))
                  .dy,
            ),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'empty sources stay selectable and disabled sources are not truncation',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToConfigure(tester);
      final playlists = find.ancestor(
        of: find.text('Playlists'),
        matching: find.byType(CheckboxListTile),
      );
      expect(
        find.descendant(
          of: playlists,
          matching: find.text('None in your libraries'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<CheckboxListTile>(playlists).onChanged, isNotNull);
      await tester.tap(playlists);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(playlists).value, isFalse);
      await tester.tap(playlists);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(playlists).value, isTrue);
      final recent = find.ancestor(
        of: find.text(builderStrategyLabels[BuilderStrategy.recentlyAdded]!),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(recent);
      expect(
        find.descendant(of: recent, matching: find.text('3 channels')),
        findsOneWidget,
      );
      await tester.tap(recent);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: recent, matching: find.textContaining('included')),
        findsNothing,
      );
    },
  );

  testWidgets('stale replacement resets the contained removal confirmation', (
    tester,
  ) async {
    final controller = _SetupController(
      staleOnce: true,
      channels: [_generated('retired', 40, builderKey: 'retired')],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);
    await tester.tap(find.text('Replace generated channels').last);
    await tester.pumpAndSettle();
    final confirmation = find.byKey(
      const ValueKey('channel-setup-replace-confirmation'),
    );
    await tester.ensureVisible(confirmation);
    await tester.tap(
      find.descendant(of: confirmation, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(controller.applyCalls, 1);
    expect(tester.widget<CheckboxListTile>(confirmation).value, isFalse);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('apply-reviewed-lineup')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byType(LineupSegmentedControl<ChannelBuildMode>),
      findsOneWidget,
    );
  });

  testWidgets(
    'creating shows actual planned count without divider or duplicate apply',
    (tester) async {
      final controller = _SetupController()..applyGate = Completer<void>();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToReview(tester);
      expect(find.text('+ Added'), findsWidgets);
      expect(find.text('＋ Added'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
      await tester.pump();
      expect(find.text('Creating 6 channels'), findsOneWidget);
      expect(
        tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
        isFalse,
      );
      expect(find.byKey(const ValueKey('apply-reviewed-lineup')), findsNothing);
      expect(controller.applyCalls, 1);
      controller.applyGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('✓ Review'), findsOneWidget);
      expect(
        tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
        isFalse,
      );
    },
  );

  testWidgets(
    'existing review defaults to update and add and clears confirmation',
    (tester) async {
      final controller = _SetupController(
        channels: [_generated('retired', 40, builderKey: 'retired')],
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToReview(tester);

      expect(find.text('Update and add'), findsOneWidget);
      expect(
        find.byType(LineupSegmentedControl<ChannelBuildMode>),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('review-build-method'))).dy,
        lessThan(tester.getTopLeft(find.text('Changes in this review')).dy),
      );
      expect(find.text('Changes in this review'), findsOneWidget);
      await tester.tap(find.text('Replace generated channels').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('channel-setup-replace-confirmation')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('apply-reviewed-lineup')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('channel-setup-replace-confirmation')),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('channel-setup-replace-confirmation')),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('channel-setup-replace-confirmation')),
            )
            .value,
        isTrue,
      );
      await tester.ensureVisible(find.text('Add as new channels').last);
      await tester.tap(find.text('Add as new channels').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('channel-setup-replace-confirmation')),
        findsNothing,
      );
    },
  );

  testWidgets('review distinguishes exhausted numbers from generation limit', (
    tester,
  ) async {
    final controller = _SetupController(
      channels: [
        for (var number = 1; number <= 1000; number++)
          _generated(
            'occupied-$number',
            number,
            builderKey: 'occupied-$number',
          ),
      ],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);

    expect(find.textContaining('Channel numbers exhausted'), findsOneWidget);
    expect(find.textContaining('Channel limit reached'), findsNothing);
    expect(controller.applyCalls, 0);
  });

  testWidgets(
    'source reorder keeps keyboard focus through the first boundary',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToConfigure(tester);
      await tester.tap(find.byKey(const ValueKey('configure-section-2')));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('source-order-recentlyAdded'));
      await tester.drag(
        find.byKey(const ValueKey('channel-configuration')),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final earlier = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Move earlier',
        ),
      );
      tester.widget<IconButton>(earlier).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(earlier).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(earlier).onPressed, isNull);
      final later = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Move later',
        ),
      );
      expect(tester.widget<IconButton>(later).focusNode!.hasFocus, isTrue);
      expect(
        tester.getTopLeft(row).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('source-order-playlists')))
              .dy,
        ),
      );
    },
  );

  testWidgets('specials clears when additional Mini-marathons are disabled', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToConfigure(tester);
    await tester.tap(find.byKey(const ValueKey('configure-section-1')));
    await tester.pumpAndSettle();
    final extras = find.widgetWithText(
      SwitchListTile,
      'Additional channel versions',
    );
    await tester.ensureVisible(extras);
    await tester.pumpAndSettle();
    await tester.tap(extras);
    await tester.pumpAndSettle();
    final variant = find.byType(DropdownButtonFormField<PlaybackMode?>);
    await tester.ensureVisible(variant);
    await tester.pumpAndSettle();
    await tester.tap(variant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mini-marathons').last);
    await tester.pumpAndSettle();
    final specials = find.widgetWithText(
      CheckboxMenuButton,
      'Include specials',
    );
    await tester.ensureVisible(specials);
    await tester.pumpAndSettle();
    await tester.tap(specials);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxMenuButton>(specials).value, isTrue);
    await tester.ensureVisible(extras);
    await tester.pumpAndSettle();
    await tester.tap(extras);
    await tester.pump();
    expect(specials, findsNothing);
    await tester.tap(extras);
    await tester.pump();
    expect(tester.widget<CheckboxMenuButton>(specials).value, isFalse);
  });

  testWidgets('playback mode transition clears ineligible copies permanently', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _openPlaybackControls(tester);

    final extras = find.widgetWithText(
      SwitchListTile,
      'Additional channel versions',
    );
    await tester.ensureVisible(extras);
    await tester.pumpAndSettle();
    await tester.tap(extras);
    await tester.pumpAndSettle();

    final copies = _setupField<int>('Alternate schedules');
    await tester.ensureVisible(copies);
    await tester.pumpAndSettle();
    await tester.tap(copies);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<int>>(copies).initialValue, 2);
    expect(find.textContaining('extra version'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('setup-playback-sequential')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-playback-sequential')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            _setupField<int>('Alternate schedules'),
          )
          .initialValue,
      0,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            _setupField<int>('Alternate schedules'),
          )
          .onChanged,
      isNull,
    );
    expect(
      find.text('Alternate schedules aren’t available with In order.'),
      findsOneWidget,
    );
    expect(find.textContaining('extra version'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('setup-playback-shuffle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-playback-shuffle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            _setupField<int>('Alternate schedules'),
          )
          .initialValue,
      0,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            _setupField<int>('Alternate schedules'),
          )
          .onChanged,
      isNotNull,
    );
    expect(find.textContaining('extra version'), findsNothing);
  });

  testWidgets(
    'valid variants survive mode changes and duplicates are cleared',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _openPlaybackControls(tester);

      final extras = find.widgetWithText(
        SwitchListTile,
        'Additional channel versions',
      );
      await tester.ensureVisible(extras);
      await tester.pumpAndSettle();
      await tester.tap(extras);
      await tester.pumpAndSettle();

      final variant = _setupField<PlaybackMode?>('Different playback mode');
      await tester.ensureVisible(variant);
      await tester.pumpAndSettle();
      await tester.tap(variant);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shuffle').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The duplicate extra version was removed because it matches your main playback order.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<PlaybackMode?>>(
              _setupField<PlaybackMode?>('Different playback mode'),
            )
            .initialValue,
        isNull,
      );

      await tester.ensureVisible(
        _setupField<PlaybackMode?>('Different playback mode'),
      );
      await tester.pumpAndSettle();
      await tester.tap(_setupField<PlaybackMode?>('Different playback mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mini-marathons').last);
      await tester.pumpAndSettle();
      final extraBlock = _setupField<int>('Extra block size');
      await tester.ensureVisible(extraBlock);
      await tester.pumpAndSettle();
      await tester.tap(extraBlock);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();

      final inOrder = find.byKey(const ValueKey('setup-playback-sequential'));
      await tester.ensureVisible(inOrder);
      await tester.pumpAndSettle();
      await tester.tap(inOrder);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<PlaybackMode?>>(
              _setupField<PlaybackMode?>('Different playback mode'),
            )
            .initialValue,
        PlaybackMode.block,
      );

      final mainMiniMarathons = find.byKey(
        const ValueKey('setup-playback-block'),
      );
      await tester.ensureVisible(mainMiniMarathons);
      await tester.pumpAndSettle();
      await tester.tap(mainMiniMarathons);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<PlaybackMode?>>(
              _setupField<PlaybackMode?>('Different playback mode'),
            )
            .initialValue,
        PlaybackMode.block,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              _setupField<int>('Extra block size'),
            )
            .initialValue,
        4,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'\d+ originals \+ \d+ extra versions')
                  .hasMatch(widget.data ?? ''),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('disabling extras removes allocation but preserves originals', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _openPlaybackControls(tester);

    final extras = find.widgetWithText(
      SwitchListTile,
      'Additional channel versions',
    );
    await tester.ensureVisible(extras);
    await tester.pumpAndSettle();
    await tester.tap(extras);
    await tester.pumpAndSettle();
    final variant = _setupField<PlaybackMode?>('Different playback mode');
    await tester.ensureVisible(variant);
    await tester.pumpAndSettle();
    await tester.tap(variant);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mini-marathons').last);
    await tester.pumpAndSettle();

    final enabledSummary = tester
        .widget<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                RegExp(r'\d+ originals \+ \d+ extra versions')
                    .hasMatch(widget.data ?? ''),
          ),
        )
        .data!;
    final originalCount = RegExp(r'(\d+) originals')
        .firstMatch(enabledSummary)!
        .group(1);
    expect(find.textContaining('extra version'), findsOneWidget);

    await tester.ensureVisible(extras);
    await tester.pumpAndSettle();
    await tester.tap(extras);
    await tester.pumpAndSettle();
    expect(find.textContaining('extra version'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('configuration-allocation-summary')),
        matching: find.text(originalCount!),
      ),
      findsOneWidget,
    );
    expect(find.text('No additional versions'), findsOneWidget);
  });

  testWidgets('stale apply refreshes review and requires another apply', (
    tester,
  ) async {
    final controller = _SetupController(staleOnce: true);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);

    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your lineup changed. Review the updated changes before applying.',
      ),
      findsOneWidget,
    );
    expect(controller.applyCalls, 1);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(controller.applyCalls, 2);
    expect(find.text('Your lineup is ready'), findsOneWidget);
  });

  testWidgets('unchanged generated lineup opens without saving', (
    tester,
  ) async {
    final existing = materializeChannelPlan(
      proposals: buildChannelProposals(
        libraries: _libraries,
        items: _media,
        playlists: const [],
        minimumItems: 5,
        maximumChannels: null,
      ),
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels;
    final controller = _SetupController(channels: existing);
    addTearDown(controller.dispose);
    var viewed = 0;
    await _pump(tester, controller, onView: () => viewed++);
    await _advanceToReview(tester);

    expect(find.text('Your lineup is already up to date'), findsOneWidget);
    expect(find.text('No changes needed.'), findsOneWidget);
    expect(find.text('View lineup'), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-reviewed-lineup')), findsNothing);
    await tester.tap(find.text('View lineup'));
    expect(viewed, 1);
    expect(controller.applyCalls, 0);
  });

  testWidgets('failed apply keeps the committed lineup and review choices', (
    tester,
  ) async {
    final original = [_generated('retired', 40, builderKey: 'retired')];
    final controller = _SetupController(channels: original, failApply: true);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);

    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t update your lineup'), findsOneWidget);
    expect(
      tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
      isTrue,
    );
    expect(find.text('Your existing lineup hasn’t changed.'), findsOneWidget);
    expect(find.text('Your setup choices are still here.'), findsOneWidget);
    expect(find.text('The lineup could not be saved.'), findsOneWidget);
    expect(controller.channels, same(original));

    await tester.tap(find.text('Back to review'));
    await tester.pumpAndSettle();
    expect(find.text('Review your lineup'), findsOneWidget);
    expect(find.text('Update and add'), findsOneWidget);
  });

  testWidgets('review search reports and clears an empty result', (
    tester,
  ) async {
    final controller = _SetupController(
      channels: [_generated('retired', 40, builderKey: 'retired')],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToReview(tester);

    await tester.enterText(
      find.byKey(const ValueKey('channel-setup-review-search')),
      'not a channel',
    );
    await tester.pump();
    expect(find.text('No matching channels'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear search'));
    await tester.pump();
    expect(find.text('No matching channels'), findsNothing);
    expect(
      find.byKey(const ValueKey('channel-setup-review-roster')),
      findsOneWidget,
    );
  });

  testWidgets(
    'successful build reports committed total and retains both actions',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      var viewed = 0;
      var added = 0;
      await _pump(
        tester,
        controller,
        onView: () => viewed++,
        onAdd: () => added++,
      );
      await _advanceToReview(tester);
      await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
      await tester.pumpAndSettle();

      expect(find.text('Your lineup is ready'), findsOneWidget);
      expect(
        tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
        isFalse,
      );
      for (final label in ['✓ Libraries', '✓ Configure', '✓ Review']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('in your lineup'), findsOneWidget);
      await tester.tap(find.text('Add a custom channel'));
      await tester.tap(find.text('View lineup'));
      expect(added, 1);
      expect(viewed, 1);
    },
  );
  testWidgets(
    'Remove updates final count, removed summary, and channel table label',
    (tester) async {
      await tester.runAsync(loadPinnedTestFonts);
      final controller = _SetupController(channels: [_missingChannel]);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
      await _advanceToReview(tester);
      expect(find.text('7 final'), findsOneWidget);
      expect(find.text('0 Removed'), findsOneWidget);
      final search = find.byKey(const ValueKey('channel-setup-review-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Retired collection');
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('review-channel-missing'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('channel-setup-review-roster')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.descendant(of: row, matching: find.text('Unchanged')),
        findsOneWidget,
      );
      final choice = find.byKey(
        const ValueKey('missing-source-choice-missing'),
      );
      await tester.ensureVisible(choice);
      await tester.tap(
        find.descendant(of: choice, matching: find.text('Remove')),
      );
      await tester.pumpAndSettle();
      expect(find.text('6 final'), findsOneWidget);
      expect(find.text('1 Removed'), findsOneWidget);
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('channel-setup-review-roster')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.descendant(of: row, matching: find.text('Removed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Unchanged')),
        findsNothing,
      );
    },
  );
}

Container _cardPaint(WidgetTester tester, Finder card) =>
    tester.widget<Container>(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.constraints?.minHeight == 152,
        ),
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  _SetupController controller, {
  VoidCallback? onView,
  VoidCallback? onAdd,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          LineupCanvas.builder(context, LineupFocusScope(child: child!)),
      theme: LineupTheme.forName(LineupThemeName.emberSteel),
      home: UpstreamChannelSetupView(
        controller: controller,
        onViewLineup: onView,
        onAddCustomChannel: onAdd,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _advanceToConfigure(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
  await tester.pumpAndSettle();
  expect(find.text('Shape your lineup'), findsOneWidget);
}

Future<void> _advanceToReview(WidgetTester tester) async {
  await _advanceToConfigure(tester);
  final list = find.byKey(const ValueKey('channel-configuration'));
  await tester.drag(list, const Offset(0, -3000));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('review-channels')));
  await tester.pumpAndSettle();
}

Future<void> _openPlaybackControls(WidgetTester tester) async {
  await _advanceToConfigure(tester);
  await tester.tap(find.byKey(const ValueKey('configure-section-1')));
  await tester.pumpAndSettle();
}

Finder _setupField<T>(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is LineupField && widget.label == label,
  ),
  matching: find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<T>,
  ),
);

class _SetupController extends FixtureController {
  _SetupController({
    this.mixedScan = false,
    this.blockScan = false,
    this.staleOnce = false,
    this.failApply = false,
    this.playlistUnavailable = false,
    this.playlistFailures = const {},
    this.collectionUnavailable = const {},
    this.collectionFailures = const {},
    List<Channel> channels = const [],
    List<PlexMediaItem>? media,
    List<PlexPlaylist> playlists = const [],
  }) {
    libraries = _libraries;
    this.channels = channels;
    _fixtureMedia = media ?? _media;
    availableMedia = _fixtureMedia;
    availablePlaylists = playlists;
  }

  late final List<PlexMediaItem> _fixtureMedia;

  bool playlistUnavailable;
  Set<String> playlistFailures;
  Set<String> collectionUnavailable;
  Map<String, Set<String>> collectionFailures;
  @override
  bool get playlistCatalogUnavailable => playlistUnavailable;
  @override
  Set<String> get failedPlaylistIds => playlistFailures;
  @override
  Set<String> get unavailableCollectionLibraryIds => collectionUnavailable;
  @override
  Map<String, Set<String>> get failedCollectionTitles => collectionFailures;
  final bool mixedScan;
  final bool blockScan;
  final bool staleOnce;
  final bool failApply;
  final scanStarted = Completer<void>();
  final _cancelled = Completer<void>();
  Map<String, LibraryScanFact> facts = const {};
  Set<String> ready = const {};
  Set<String> retry = const {};
  Set<String> committedIds = const {};
  int applyCalls = 0;
  Completer<void>? applyGate;
  Set<String>? rowRetryIds;
  Set<String>? rowRetryInventory;

  @override
  Future<bool> retryLibraryScan(Set<String> ids, Set<String> retryIds) {
    playlistUnavailable = false;
    playlistFailures = {};
    collectionUnavailable = {};
    collectionFailures = {};
    rowRetryInventory = Set.of(ids);
    rowRetryIds = Set.of(retryIds);
    return scanLibraries(ids, retryFailedOnly: true);
  }

  @override
  Map<String, LibraryScanFact> get libraryScanFacts => facts;
  @override
  Set<String> get libraryScanReadyIds => ready;
  @override
  Set<String> get libraryScanRetryIds => retry;

  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    if (blockScan) {
      libraryScanStatus = LibraryScanStatus.scanning;
      ready = {ids.first};
      facts = {
        for (final id in ids)
          id: LibraryScanFact(
            status: id == ids.first
                ? LibraryScanStatus.complete
                : LibraryScanStatus.scanning,
          ),
      };
      notifyListeners();
      if (!scanStarted.isCompleted) scanStarted.complete();
      await _cancelled.future;
      return false;
    }
    if (mixedScan) {
      ready = const {'movies'};
      retry = const {'archive'};
      facts = const {
        'movies': LibraryScanFact(
          status: LibraryScanStatus.complete,
          completedPages: 1,
          completedItems: 6,
          totalItems: 6,
        ),
        'archive': LibraryScanFact(
          status: LibraryScanStatus.transientFailure,
          completedPages: 1,
          completedItems: 2,
          totalItems: 6,
        ),
      };
      libraryScanStatus = LibraryScanStatus.transientFailure;
    } else {
      ready = Set.unmodifiable(ids);
      retry = const {};
      facts = {
        for (final id in ids)
          id: const LibraryScanFact(
            status: LibraryScanStatus.complete,
            completedPages: 1,
            completedItems: 6,
            totalItems: 6,
          ),
      };
      libraryScanStatus = LibraryScanStatus.complete;
    }
    notifyListeners();
    return true;
  }

  @override
  void cancelLibraryScan() {
    libraryScanStatus = LibraryScanStatus.cancelled;
    facts = {
      for (final entry in facts.entries)
        entry.key: entry.value.status == LibraryScanStatus.complete
            ? entry.value
            : const LibraryScanFact(status: LibraryScanStatus.cancelled),
    };
    notifyListeners();
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  Future<bool> commitLibraryScan(Set<String> readyIds) async {
    committedIds = Set.unmodifiable(readyIds);
    selectedLibraryIds = committedIds;
    availableMedia = _fixtureMedia
        .where((item) => readyIds.contains(item.libraryId))
        .toList();
    return true;
  }

  @override
  Future<ChannelPlanApplyResult> applyReviewedChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    required List<Channel> expectedBase,
    Set<String> removeChannelIds = const {},
  }) async {
    applyCalls++;
    if (applyGate != null) await applyGate!.future;
    if (failApply) throw StateError('synthetic apply failure');
    if (staleOnce && applyCalls == 1) return ChannelPlanApplyResult.stale;
    channels = composeChannelPlan(
      existing: channels
          .where((channel) => !removeChannelIds.contains(channel.id))
          .toList(),
      planned: planned,
      mode: mode,
    );
    return ChannelPlanApplyResult.applied;
  }
}

const _libraries = [
  PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
  PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
  PlexLibrary(
    id: 'archive',
    title: 'Long Form Archive',
    type: PlexLibraryType.movie,
  ),
];

final _media = [
  for (final library in const ['movies', 'shows', 'archive'])
    for (var index = 0; index < 6; index++)
      PlexMediaItem(
        id: '$library-$index',
        title: '$library $index',
        type: library == 'shows' ? 'episode' : 'movie',
        duration: const Duration(minutes: 30),
        libraryId: library,
        parts: [PlexMediaPart(path: '/parts/$library/$index')],
        genres: const ['Drama'],
        grandparentRatingKey: library == 'shows' ? 'show-$index' : null,
        grandparentTitle: library == 'shows' ? 'Show $index' : null,
      ),
];

Channel _generated(String id, int number, {required String builderKey}) =>
    Channel(
      id: id,
      number: number,
      name: id,
      source: const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
      ),
      playbackMode: PlaybackMode.shuffle,
      anchor: DateTime.utc(2026),
      shuffleSeed: number,
      builderKey: builderKey,
    );

final _missingChannel = Channel(
  id: 'missing',
  number: 90,
  name: 'Retired collection',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
    filters: {
      LibraryFilter.collection: ['Retired collection'],
    },
  ),
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 90,
  builderKey: 'retired-collection',
);

final _workingPlaylist = PlexPlaylist(
  id: 'working',
  title: 'Working playlist',
  items: _media.where((item) => item.libraryId == 'movies').toList(),
);
final _partialMedia = [
  ..._media,
  for (var index = 0; index < 5; index++)
    PlexMediaItem(
      id: 'member-$index',
      title: 'Collection member $index',
      type: 'movie',
      duration: const Duration(minutes: 30),
      libraryId: 'movies',
      collections: const ['Working collection'],
      parts: [PlexMediaPart(path: '/parts/member/$index')],
    ),
];
