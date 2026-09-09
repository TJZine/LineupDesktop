import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
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

      expect(find.textContaining('1 library is ready'), findsOneWidget);
      expect(find.text('Ready · 6/6 items · 1 page'), findsOneWidget);
      expect(find.text('Scan failed · 2/6 items · 1 page'), findsOneWidget);
      expect(find.text('Retry 1 failed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue-ready-libraries')),
        findsOneWidget,
      );
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
    await tester.tap(find.text('Cancel scan'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byKey(const ValueKey('configure-section-1')));
    await tester.pumpAndSettle();
    expect(find.text('Playback order'), findsNWidgets(2));
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
    expect(find.text('Lineup rules'), findsNWidgets(2));
    expect(find.text('Maximum generated channels'), findsOneWidget);
    expect(find.text('Minimum programs per channel'), findsOneWidget);
    expect(find.textContaining('one eligible original'), findsOneWidget);
  });

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
      expect(find.text('Changes in this review'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-build-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace generated channels').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('channel-setup-replace-confirmation')),
        findsOneWidget,
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
      await tester.tap(find.byKey(const ValueKey('review-build-method')));
      await tester.pumpAndSettle();
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
    await tester.tap(extras);
    await tester.pumpAndSettle();

    final copies = _setupField<int>('Alternate schedules');
    await tester.ensureVisible(copies);
    await tester.tap(copies);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<int>>(copies).initialValue, 2);
    expect(find.textContaining('extra version'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(RadioListTile<PlaybackMode>, 'In order'),
    );
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

    await tester.tap(
      find.widgetWithText(RadioListTile<PlaybackMode>, 'Shuffle'),
    );
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
      await tester.tap(extras);
      await tester.pumpAndSettle();

      final variant = _setupField<PlaybackMode?>('Different playback mode');
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

      await tester.tap(_setupField<PlaybackMode?>('Different playback mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mini-marathons').last);
      await tester.pumpAndSettle();
      final extraBlock = _setupField<int>('Extra block size');
      await tester.tap(extraBlock);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();

      final inOrder = find.widgetWithText(
        RadioListTile<PlaybackMode>,
        'In order',
      );
      await tester.ensureVisible(inOrder);
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

      final mainMiniMarathons = find.widgetWithText(
        RadioListTile<PlaybackMode>,
        'Mini-marathons',
      );
      await tester.ensureVisible(mainMiniMarathons);
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
    await tester.tap(extras);
    await tester.pumpAndSettle();
    final variant = _setupField<PlaybackMode?>('Different playback mode');
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
    await tester.tap(extras);
    await tester.pumpAndSettle();
    expect(find.textContaining('extra version'), findsNothing);
    expect(find.textContaining('$originalCount generated'), findsOneWidget);
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
      expect(find.textContaining('in your lineup'), findsOneWidget);
      await tester.tap(find.text('Add a custom channel'));
      await tester.tap(find.text('View lineup'));
      expect(added, 1);
      expect(viewed, 1);
    },
  );
}

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
  expect(find.text('Configure channels'), findsOneWidget);
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

Finder _setupField<T>(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField && widget.decoration.labelText == label,
);

class _SetupController extends FixtureController {
  _SetupController({
    this.mixedScan = false,
    this.blockScan = false,
    this.staleOnce = false,
    this.failApply = false,
    List<Channel> channels = const [],
  }) {
    libraries = _libraries;
    this.channels = channels;
    availableMedia = _media;
  }

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
      facts = {
        for (final id in ids)
          id: const LibraryScanFact(status: LibraryScanStatus.scanning),
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
        entry.key: const LibraryScanFact(status: LibraryScanStatus.cancelled),
    };
    notifyListeners();
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  Future<bool> commitLibraryScan(Set<String> readyIds) async {
    committedIds = Set.unmodifiable(readyIds);
    selectedLibraryIds = committedIds;
    availableMedia = _media
        .where((item) => readyIds.contains(item.libraryId))
        .toList();
    return true;
  }

  @override
  Future<ChannelPlanApplyResult> applyReviewedChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    required List<Channel> expectedBase,
  }) async {
    applyCalls++;
    if (failApply) throw StateError('synthetic apply failure');
    if (staleOnce && applyCalls == 1) return ChannelPlanApplyResult.stale;
    channels = composeChannelPlan(
      existing: channels,
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
