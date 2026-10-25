import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/app/channel_setup/review_step.dart';
import 'package:lineup_desktop/app/setup_review.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';

import '../support/ui_fixture.dart';
import '../support/golden_test_support.dart';

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
const _select = LogicalKeyboardKey.select;
const _back = LogicalKeyboardKey.goBack;

Future<void> _keys(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    if (key == _back) {
      // Models the normalized native boundary; actual key/callback ownership
      // is verified by the Android input probe, not by widget simulation.
      await tester.binding.handlePopRoute();
    } else {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
  }
}

void _tvTest(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _focusedVisible(WidgetTester tester, Finder control) {
  final primary = FocusManager.instance.primaryFocus!;
  expect(
    primary.context!.findAncestorWidgetOfExactType<OutlinedButton>(),
    same(tester.widget<OutlinedButton>(control)),
  );
  final rect = tester.getRect(control);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(540));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(960));
}

bool _hasFocusIn(WidgetTester tester, Finder control) {
  final target = tester.element(control);
  final primary = FocusManager.instance.primaryFocus!.context! as Element;
  var inside = identical(target, primary);
  primary.visitAncestorElements((element) {
    inside |= identical(target, element);
    return !inside;
  });
  return inside;
}

void _focusedIn(WidgetTester tester, Finder control) => expect(
  _hasFocusIn(tester, control),
  isTrue,
  reason: 'Focus must be within $control',
);

var _backgroundRequests = 0;
void main() {
  const platform = MethodChannel('lineup/platform');
  setUp(() {
    _backgroundRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'watchKeyboardVisibility' ||
              call.method == 'unwatchKeyboardVisibility') {
            return false;
          }
          expect(call.method, 'moveTaskToBack');
          _backgroundRequests++;
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );
  for (final theme in LineupThemeName.values) {
    for (final textScale in [1.0, 1.15, 1.3]) {
      _tvTest(
        'PIN is initially complete and stationary: ${theme.name} text=$textScale',
        (tester) async {
          await tester.runAsync(loadPinnedTestFonts);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final pending = Completer<void>();
          final fixture = UiFixture(
            androidTv: true,
            controller: _RejectedPinController(
              name: 'A deliberately long profile name with a second line and an ellipsis',
              pending: pending,
              rejectionMessage: textScale > 1
                  ? 'The profile could not be selected. Check your connection and try again.'
                  : 'That Plex Home PIN was not accepted.',
              settings: LineupSettings(
                theme: theme,
                largeFocusIndicators: true,
                reduceMotion: textScale > 1,
              ),
            ),
          );
          await tester.pumpWidget(fixture.build());
          await tester.pumpAndSettle();
          await _keys(tester, [_select]);
          Rect drawn(Finder finder) => Rect.fromPoints(
            tester.getTopLeft(finder),
            tester.getBottomRight(finder),
          );
          void expectComplete() {
            final controls = [
              for (var digit = 0; digit <= 9; digit++)
                find.widgetWithText(OutlinedButton, '$digit'),
              find.byTooltip('Backspace'),
              find.widgetWithText(TextButton, 'Cancel'),
              find.byKey(const Key('profile-pin-progress')),
              find.byKey(const Key('profile-pin-status')),
            ];
            for (final control in controls) {
              final bounds = drawn(control)
                  .inflate(2); // Includes the 3cu large-focus outer stroke.
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.top, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(960));
              expect(bounds.bottom, lessThanOrEqualTo(540));
            }
            for (final element in find.byType(Scrollable).evaluate()) {
              expect(
                (element as StatefulElement).state is ScrollableState,
                isTrue,
              );
              expect(((element).state as ScrollableState).position.pixels, 0);
            }
            expect(tester.takeException(), isNull);
          }

          expectComplete(); // Before the first arrow or scroll.
          _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
          await _keys(tester, [_select, _select, _select]);
          await tester.sendKeyEvent(_select);
          await tester.pump();
          expect(find.bySemanticsLabel('Checking PIN'), findsOneWidget);
          expectComplete();
          pending.complete();
          await tester.pumpAndSettle();
          expect(
            find.text(
              textScale > 1
                  ? 'The profile could not be selected. Check your connection and try again.'
                  : 'Incorrect PIN. Try again.',
            ),
            findsOneWidget,
          );
          expectComplete();
          _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
        },
      );
    }
  }
  _tvTest(
    'protected PIN remote walk reaches every bottom key, error, Cancel and Back',
    (tester) async {
      final fixture = UiFixture(
        controller: _RejectedPinController(),
        androidTv: true,
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await _keys(tester, [_select]);
      Finder digit(String value) => find.widgetWithText(OutlinedButton, value);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_select, _select, _select, _select]);
      expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_select, _right]);
      _focusedVisible(tester, digit('2'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('3'));
      await _keys(tester, [_down]);
      _focusedVisible(tester, digit('6'));
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('5'));
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('4'));
      await _keys(tester, [_down]);
      _focusedVisible(tester, digit('7'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('8'));
      await _keys(tester, [_right]);
      _focusedVisible(tester, digit('9'));
      await _keys(tester, [_down]);
      final delete = find.descendant(
        of: find.byTooltip('Backspace'),
        matching: find.byType(OutlinedButton),
      );
      _focusedVisible(tester, delete);
      await _keys(tester, [_left]);
      _focusedVisible(tester, digit('0'));
      await _keys(tester, [_right, _select]);
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('profile-pin-progress')))
            .properties
            .label,
        '0 of 4 digits entered',
      );
      await _keys(tester, [_left, _down]);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TextButton>(),
        same(tester.widget<TextButton>(cancel)),
      );
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(540));
      await _keys(tester, [_select]);
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      await _keys(tester, [_select]);
      _focusedVisible(tester, digit('1'));
      await _keys(tester, [_back]);
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(_backgroundRequests, 0);
    },
  );

  _tvTest(
    'current protected profile PIN consumes normalized Back without backgrounding',
    (tester) async {
      final fixture = UiFixture(
        controller: _RejectedPinController(current: true),
        androidTv: true,
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await _keys(tester, [_select]);
      _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.controller.profileSelectionCanCancel, isTrue);
      expect(_backgroundRequests, 0);
      await _keys(tester, [_select]);
      _focusedVisible(tester, find.widgetWithText(OutlinedButton, '1'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.controller.profileSelectionCanCancel, isTrue);
      expect(_backgroundRequests, 0);
    },
  );
  _tvTest(
    'Channels search uses closed navigation focus and explicit Select editing',
    (tester) async {
      final fixture = UiFixture(
        androidTv: true,
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            Channel(
              id: 'fixture',
              number: 1,
              name: 'Fixture channel',
              source: const ManualSource([
                ChannelItem(
                  id: 'program',
                  title: 'Fixture program',
                  duration: Duration(minutes: 30),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime.utc(2026),
              shuffleSeed: 1,
            ),
          ],
        ),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await _keys(tester, [LogicalKeyboardKey.contextMenu, _down, _select]);
      expect(find.byKey(const Key('channels-search')), findsOneWidget);
      await _keys(tester, [_down, _left, _left, _left, _left]);
      final activation = tester.widget<LineupTextFieldActivation>(
        find.byType(LineupTextFieldActivation),
      );
      expect(
        activation.focusNode!.hasPrimaryFocus,
        isTrue,
        reason: 'primary=${FocusManager.instance.primaryFocus}',
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await _keys(tester, [_select]);
      expect(tester.testTextInput.isVisible, isTrue);
      await _keys(tester, [_back]);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(activation.focusNode!.hasPrimaryFocus, isTrue);
      await _keys(tester, [_select]);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(activation.focusNode!.hasPrimaryFocus, isTrue);
      await _keys(tester, [_down]);
      expect(activation.focusNode!.hasPrimaryFocus, isFalse);
    },
  );
  _tvTest('library rows toggle once and scroll in visual order', (
    tester,
  ) async {
    final fixture = UiFixture(
      androidTv: true,
      scenario: LineupScenario(
        stage: SetupStage.channelSetup,
        libraries: [
          for (var i = 1; i <= 8; i++)
            PlexLibrary(
              id: 'library-$i',
              title: 'Library $i',
              type: PlexLibraryType.movie,
            ),
        ],
        selectedLibraryIds: const {},
      ),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    final libraryFooter = find.byKey(const ValueKey('setup-switch-server'));
    final footerBounds = tester.getRect(libraryFooter);
    expect(footerBounds.bottom, inInclusiveRange(540 - 48 * .5, 540 - 24 * .5));
    _focusedIn(tester, find.widgetWithText(TextButton, 'Select all'));
    await _keys(tester, [_select]);
    expect(find.text('0 of 8 selected'), findsOneWidget);
    for (var i = 1; i <= 8; i++) {
      await _keys(tester, [_down]);
      final row = find.byKey(ValueKey('library-row-library-$i'));
      _focusedIn(tester, row);
      expect(tester.getRect(row).bottom, lessThanOrEqualTo(540));
      await _keys(tester, [_select]);
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(of: row, matching: find.byType(Checkbox)),
            )
            .value,
        isTrue,
      );
      expect(find.text('$i of 8 selected'), findsOneWidget);
    }
    await _keys(tester, [_down]);
    _focusedIn(tester, find.byKey(const ValueKey('setup-switch-server')));
    expect(tester.getRect(libraryFooter), footerBounds);
    for (var i = 8; i >= 1; i--) {
      await _keys(tester, [_up]);
      _focusedIn(tester, find.byKey(ValueKey('library-row-library-$i')));
    }
    await _keys(tester, [_up]);
    _focusedIn(tester, find.widgetWithText(TextButton, 'Select all'));
  });
  for (final existing in [false, true]) {
    _tvTest(
      'Review search and readonly rows follow remote reading order (existing: $existing)',
      (tester) async {
        final channels = [
          for (var i = 1; i <= 12; i++) _reviewChannel(i, generated: true),
        ];
        final review = SetupReview(
          base: existing
              ? [
                  _reviewChannel(1, name: 'Before', generated: true),
                  _reviewChannel(99, generated: true),
                ]
              : const [],
          plan: (
            channels: channels,
            allocatedOriginals: channels.length,
            excludedOriginals: 0,
            allocatedExtras: 0,
            excludedExtras: 0,
            numberLimitExcluded: 0,
            existingSkipped: 0,
            unmatchedGenerated: const [],
            eligibleOriginalsByStrategy: const {},
            allocatedOriginalsByStrategy: const {},
            allocatedChannelsByStrategy: const {},
            truncated: false,
          ),
          mode: ChannelBuildMode.replace,
          removeSourceIds: existing ? const {'review-99'} : const {},
          strategyBySource: const {},
        );
        var applyCalls = 0;
        bool? consent;
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              androidTv: true,
            ),
            home: Scaffold(
              body: SafeArea(
                child: LineupFocusScope(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SetupReviewStep(
                      review: review,
                      notice: null,
                      removalConfirmed: false,
                      sourceOrder: const [],
                      sourceLabel: (_) => 'Manual',
                      initialFilter: SetupReviewFilter.all,
                      initialSearch: '',
                      onFilterChanged: (_) {},
                      onSearchChanged: (_) {},
                      isGeneratedSourceConfirmedGone: (_) => false,
                      onBack: () {},
                      onModeChanged: (_) {},
                      onRemovalChanged: (_, _) {},
                      onRemovalConfirmationChanged: (value) => consent = value,
                      onApply: () => applyCalls++,
                      onViewLineup: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final firstRow = find.byKey(const ValueKey('review-channel-review-1'));
        final roster = find.byKey(
          const ValueKey('channel-setup-review-roster'),
        );
        final footer = find.byKey(const ValueKey('back-to-configure'));
        final footerBounds = tester.getRect(footer);
        final firstBounds = tester.getRect(firstRow);
        final rosterBounds = tester.getRect(roster);
        expect(firstBounds.top, greaterThanOrEqualTo(rosterBounds.top));
        expect(firstBounds.bottom, lessThanOrEqualTo(rosterBounds.bottom));
        expect(footerBounds.bottom, lessThanOrEqualTo(540));
        expect(
          find.ancestor(of: roster, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final search = find.byType(LineupTextFieldActivation);
        for (var step = 0; step < 12 && !_hasFocusIn(tester, search); step++) {
          await _keys(tester, [_down]);
        }
        _focusedIn(tester, search);
        expect(tester.testTextInput.isVisible, isFalse);
        await _keys(tester, [_select]);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        if (existing) {
          await _keys(tester, [_down]);
          _focusedIn(tester, find.byKey(const ValueKey('review-show-all')));
        }
        for (var i = 1; i <= channels.length; i++) {
          await _keys(tester, [_down]);
          final row = find.byKey(ValueKey('review-channel-review-$i'));
          _focusedIn(tester, row);
          if (existing && i == 1) {
            await _keys(tester, [_select]);
            expect(
              find.text('Name: Before → Review channel 1'),
              findsOneWidget,
            );
            await _keys(tester, [_select]);
          }
          final rect = tester.getRect(row);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(540));
        }
        if (existing) {
          await _keys(tester, [_down]);
          _focusedIn(
            tester,
            find.byKey(const ValueKey('review-channel-review-99')),
          );
          await _keys(tester, [_down]);
          _focusedIn(
            tester,
            find.byKey(const ValueKey('channel-setup-replace-confirmation')),
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('apply-reviewed-lineup')),
                )
                .onPressed,
            isNull,
          );
          await _keys(tester, [_select]);
          expect(consent, isTrue);
        }
        await _keys(tester, [_down]);
        _focusedIn(tester, find.byKey(const ValueKey('back-to-configure')));
        expect(tester.getRect(footer), footerBounds);
        if (existing) {
          await _keys(tester, [_up]);
          _focusedIn(
            tester,
            find.byKey(const ValueKey('channel-setup-replace-confirmation')),
          );
          await _keys(tester, [_up]);
          _focusedIn(
            tester,
            find.byKey(const ValueKey('review-channel-review-99')),
          );
        }
        for (var i = channels.length; i >= 1; i--) {
          await _keys(tester, [_up]);
          _focusedIn(tester, find.byKey(ValueKey('review-channel-review-$i')));
        }
        expect(applyCalls, 0);
      },
    );
  }
  _tvTest('library Retry remains between its row and the next library', (
    tester,
  ) async {
    final fixture = UiFixture(
      androidTv: true,
      scenario: const LineupScenario(
        stage: SetupStage.channelSetup,
        libraries: [
          PlexLibrary(
            id: 'failed',
            title: 'Failed library',
            type: PlexLibraryType.movie,
          ),
          PlexLibrary(
            id: 'next',
            title: 'Next library',
            type: PlexLibraryType.show,
          ),
        ],
        selectedLibraryIds: {'failed', 'next'},
        libraryScanStatus: LibraryScanStatus.transientFailure,
        scanFacts: {
          'failed': LibraryScanFact(status: LibraryScanStatus.transientFailure),
        },
      ),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    _focusedIn(tester, find.widgetWithText(TextButton, 'Select all'));
    await _keys(tester, [_down]);
    _focusedIn(tester, find.byKey(const ValueKey('library-row-failed')));
    await _keys(tester, [_down]);
    _focusedIn(tester, find.byKey(const ValueKey('retry-library-failed')));
    await _keys(tester, [_down]);
    _focusedIn(tester, find.byKey(const ValueKey('library-row-next')));
    await _keys(tester, [_up]);
    _focusedIn(tester, find.byKey(const ValueKey('retry-library-failed')));
  });

  _tvTest('Guide search has explicit activation and closed arrow traversal', (
    tester,
  ) async {
    final fixture = UiFixture(
      androidTv: true,
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [_reviewChannel(1)],
      ),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('guide-channel-search'));
    final activation = tester.widget<LineupTextFieldActivation>(
      find.ancestor(
        of: field,
        matching: find.byType(LineupTextFieldActivation),
      ),
    );
    // Grid-to-toolbar access is UX4. Establish toolbar focus, then prove actual
    // arrow arrival/exit and activation using the production Guide controls.
    activation.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await _keys(tester, [_left]);
    expect(activation.focusNode!.hasPrimaryFocus, isFalse);
    await _keys(tester, [_right]);
    expect(activation.focusNode!.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await _keys(tester, [_select]);
    expect(tester.testTextInput.isVisible, isTrue);
    await _keys(tester, [_back]);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(activation.focusNode!.hasPrimaryFocus, isTrue);
    await _keys(tester, [_right]);
    expect(activation.focusNode!.hasPrimaryFocus, isFalse);
  });
}

class _RejectedPinController extends FixtureController {
  _RejectedPinController({
    bool current = false,
    String name = 'Fixture viewer',
    LineupSettings? settings,
    this.pending,
    this.rejectionMessage = 'That Plex Home PIN was not accepted.',
  }) : super(
         scenario: LineupScenario(
           stage: SetupStage.profiles,
           settings: settings,
           profile: current
               ? const PlexHomeUser(
                   id: 'protected',
                   name: 'Fixture viewer',
                   protected: true,
                 )
               : null,
           profileSelectionOrigin: current ? SetupStage.ready : null,
           profiles: [
             PlexHomeUser(id: 'protected', name: name, protected: true),
           ],
         ),
       );
  final Completer<void>? pending;
  final String rejectionMessage;
  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    await pending?.future;
    fixtureActor.present(LineupPresentation(error: (rejectionMessage,)));
    notifyListeners();
    return false;
  }
}

Channel _reviewChannel(int i, {String? name, bool generated = false}) =>
    Channel(
      id: 'review-$i',
      number: i,
      name: name ?? 'Review channel $i',
      source: generated
          ? const LibrarySource(
              libraryId: 'movies',
              libraryType: PlexLibraryType.movie,
            )
          : const ManualSource([
              ChannelItem(
                id: 'show',
                title: 'Show',
                duration: Duration(minutes: 30),
              ),
            ]),
      builderKey: generated ? 'generated-$i' : null,
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: 1,
    );
