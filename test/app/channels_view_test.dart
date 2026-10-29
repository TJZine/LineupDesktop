import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channels_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/focus_ink.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final androidTv in [true, false]) {
    testWidgets(
      'bulk-selected channel rows show checked state on the checkbox only (TV: $androidTv)',
      (tester) async {
        await tester.pumpWidget(
          UiFixture(
            androidTv: androidTv,
            scenario: LineupScenario(
              stage: SetupStage.ready,
              channels: [
                _channel('first', 1, 'First'),
                _channel('second', 2, 'Second'),
              ],
            ),
          ).build(),
        );
        await tester.pumpAndSettle();
        await openDestination(tester, 'Channels');
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('channel-row-first'));
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<Checkbox>(
                find.descendant(of: row, matching: find.byType(Checkbox)),
              )
              .value,
          isTrue,
        );
        final roles = LineupTheme.of(tester.element(row));
        final surface =
            tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.ancestor(
                              of: row,
                              matching: find.byType(LineupRowSurface),
                            ),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect(surface.color, isNot(roles.selectedSurface));
        expect((surface.border! as Border).left.color, Colors.transparent);
      },
    );
  }

  testWidgets('Channels Back unwinds local layers before background fallback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const platform = MethodChannel('lineup/platform');
    var backgrounded = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          expect(call.method, 'moveTaskToBack');
          backgrounded++;
          return true;
        });
    try {
      await tester.pumpWidget(
        UiFixture(
          androidTv: true,
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: [_channel('back', 2, 'Back channel')],
          ),
        ).build(),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      final channelsState = tester.state<ChannelsViewState>(
        find.byType(ChannelsView),
      );

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(channelsState.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
      expect(backgrounded, 0);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('channel-row-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 selected'));
      await tester.pumpAndSettle();
      expect(find.text('Selected channels'), findsOneWidget);
      expect(channelsState.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Selected channels'), findsNothing);
      expect(find.byKey(const Key('channels-search')), findsOneWidget);
      expect(backgrounded, 0);

      expect(channelsState.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
      expect(backgrounded, 0);

      await tester.tap(find.text('Reorder channels'));
      await tester.pumpAndSettle();
      expect(channelsState.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Reorder channels'), findsOneWidget);
      expect(backgrounded, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backgrounded, 0);
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backgrounded, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'selected-only Back restores search focus for an empty filtered projection',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const platform = MethodChannel('lineup/platform');
      var backgrounded = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            expect(call.method, 'moveTaskToBack');
            backgrounded++;
            return true;
          });
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 1, 'First'),
            _channel('second', 2, 'Second'),
          ],
        ),
      );
      addTearDown(controller.dispose);
      try {
        await tester.pumpWidget(
          UiFixture(controller: controller, androidTv: true).build(),
        );
        await tester.pumpAndSettle();
        await openDestination(tester, 'Channels');
        final channelsState = tester.state<ChannelsViewState>(
          find.byType(ChannelsView),
        );

        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('channel-row-first')));
        await tester.pumpAndSettle();
        final search = find.byKey(const Key('channels-search'));
        await tester.enterText(search, 'no matching channel');
        await tester.pumpAndSettle();
        final selectedSummary = find.text('1 selected · 1 outside this view');
        await tester.tap(selectedSummary);
        await tester.pumpAndSettle();
        expect(find.text('Selected channels'), findsOneWidget);
        expect(find.byKey(const ValueKey('channel-row-first')), findsOneWidget);

        final rowFocus = tester
            .widgetList<Focus>(find.byType(Focus))
            .map((widget) => widget.focusNode)
            .whereType<FocusNode>()
            .firstWhere((node) => node.debugLabel == 'Open First');
        rowFocus.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(rowFocus));
        await tester.sendKeyEvent(
          LogicalKeyboardKey.goBack,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();

        expect(find.text('Selected channels'), findsNothing);
        expect(
          tester.widget<TextField>(search).controller!.text,
          'no matching channel',
        );
        expect(find.text('1 selected · 1 outside this view'), findsOneWidget);
        final searchFocus = tester
            .widgetList<Focus>(find.byType(Focus))
            .map((widget) => widget.focusNode)
            .whereType<FocusNode>()
            .firstWhere((node) => node.debugLabel == 'Search channels');
        expect(FocusManager.instance.primaryFocus, same(searchFocus));
        expect(searchFocus.context, isNotNull);
        expect(searchFocus.parent, isNotNull);
        expect(searchFocus.canRequestFocus, isTrue);
        expect(backgrounded, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'TV text field editor',
        );
        await tester.enterText(search, '');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(find.text('Cancel'), findsOneWidget);
        expect(backgrounded, 0);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.goBack,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        expect(backgrounded, 0);

        searchFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(find.text('Cancel'), findsOneWidget);
        expect(backgrounded, 0);

        expect(channelsState.handleBack(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Select'), findsOneWidget);
        expect(backgrounded, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      'TV deletion dialog reads every selected name before cancel or confirm (large focus $large)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final previousHighlight = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        final semantics = tester.ensureSemantics();
        tester.view
          ..physicalSize = const Size(1920, 1080)
          ..devicePixelRatio = 2;
        try {
          final channels = [
            for (var i = 0; i < 40; i++)
              _channel(
                'selected-$i',
                i + 100,
                'Selected channel $i with a name that wraps clearly in the review list',
              ),
          ];
          final controller = _RecordingDirectoryController(
            scenario: LineupScenario(
              stage: SetupStage.ready,
              channels: channels,
              settings: LineupSettings(largeFocusIndicators: large),
            ),
          );
          await tester.pumpWidget(
            UiFixture(controller: controller, androidTv: true).build(),
          );
          await tester.pumpAndSettle();
          // Establish selection through existing controls. Reading and the dialog's
          // actions below use remote keys only, without requestFocus/ensureVisible.
          await openDestination(tester, 'Channels');
          await tester.tap(find.text('Select'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Select all matching'));
          await tester.pumpAndSettle();
          Future<void> openDelete() async {
            await tester.tap(find.text('Delete selected'));
            await tester.pumpAndSettle();
          }

          Future<void> key(LogicalKeyboardKey key) async {
            await tester.sendKeyEvent(key);
            await tester.pumpAndSettle();
          }

          bool focusedIn(Finder finder) {
            final target = tester.element(finder);
            final primary =
                FocusManager.instance.primaryFocus?.context as Element?;
            var inside = identical(target, primary);
            primary?.visitAncestorElements((e) {
              inside |= identical(e, target);
              return !inside;
            });
            return inside;
          }

          await openDelete();
          final dialog = find.byType(Dialog);
          final cancel = find.descendant(
            of: dialog,
            matching: find.widgetWithText(TextButton, 'Cancel'),
          );
          expect(focusedIn(cancel), isTrue);
          final list = find.descendant(
            of: dialog,
            matching: find.byType(ListView),
          );
          final originalState = tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          );
          final scroll = tester.widget<ListView>(list).controller!;
          expect(scroll.position.maxScrollExtent, greaterThan(0));
          await key(LogicalKeyboardKey.arrowUp);
          await key(LogicalKeyboardKey.arrowDown);
          expect(scroll.offset, greaterThan(0));
          await key(LogicalKeyboardKey.arrowUp);
          expect(scroll.offset, 0);
          final firstRow = find.byKey(
            const ValueKey('delete-dialog-row-selected-0'),
          );
          final frame = find.ancestor(
            of: list,
            matching: find.byType(LineupFocusFrame),
          );
          expect(frame, findsOneWidget);
          expect(tester.widget<LineupFocusFrame>(frame).focused, isTrue);
          final frameBox = tester.renderObject<RenderBox>(frame);
          final clearance = large ? 6.0 : 0.0;
          final safeViewport = Rect.fromPoints(
            frameBox.localToGlobal(Offset(clearance, clearance)),
            frameBox.localToGlobal(
              Offset(
                frameBox.size.width - clearance,
                frameBox.size.height - clearance,
              ),
            ),
          );
          expect(tester.getRect(list), safeViewport);
          final viewportWidget = tester.widget<ShrinkWrappingViewport>(
            find.descendant(
              of: list,
              matching: find.byType(ShrinkWrappingViewport),
            ),
          );
          expect(viewportWidget.clipBehavior, Clip.hardEdge);
          final surface = find
              .ancestor(of: list, matching: find.byType(DecoratedBox))
              .first;
          final roles = LineupTheme.of(tester.element(dialog));
          expect(
            (tester.widget<DecoratedBox>(surface).decoration as BoxDecoration)
                .color,
            roles.focusedSurface,
          );
          expect(
            tester
                .widget<Text>(
                  find.descendant(
                    of: firstRow,
                    matching: find.text(channels.first.name),
                  ),
                )
                .style
                ?.color,
            roles.onFocus,
          );
          expect(
            find.bySemanticsLabel(RegExp('Selected channels for deletion')),
            findsOneWidget,
          );
          void expectReaderContentClear(Channel channel) {
            final row = find.byKey(ValueKey('delete-dialog-row-${channel.id}'));
            final frameBox = tester.renderObject<RenderBox>(frame);
            // The shared large indicator paints two 3cu strokes inside its
            // outer region. Its scroll clip and text must clear that paint.
            final clearance = large ? 6.0 : 0.0;
            final safe = Rect.fromPoints(
              frameBox.localToGlobal(Offset(clearance, clearance)),
              frameBox.localToGlobal(
                Offset(
                  frameBox.size.width - clearance,
                  frameBox.size.height - clearance,
                ),
              ),
            );
            for (final label in ['${channel.number}', channel.name]) {
              final text = find.descendant(of: row, matching: find.text(label));
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: text, matching: find.byType(RichText)),
              );
              final boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              );
              expect(boxes, isNotEmpty);
              for (final box in boxes) {
                final rect = Rect.fromPoints(
                  paragraph.localToGlobal(box.toRect().topLeft),
                  paragraph.localToGlobal(box.toRect().bottomRight),
                );
                expect(
                  rect.left,
                  greaterThanOrEqualTo(safe.left - .25),
                  reason: label,
                );
                expect(
                  rect.right,
                  lessThanOrEqualTo(safe.right + .25),
                  reason: label,
                );
                expect(
                  rect.top,
                  greaterThanOrEqualTo(safe.top - .25),
                  reason: label,
                );
                expect(
                  rect.bottom,
                  lessThanOrEqualTo(safe.bottom + .25),
                  reason: label,
                );
              }
            }
          }

          expectReaderContentClear(channels.first);
          final seen = <String>{};
          for (var i = 0; i < 150; i++) {
            final viewport = tester.getRect(list);
            for (final channel in channels) {
              final row = find.byKey(
                ValueKey('delete-dialog-row-${channel.id}'),
              );
              if (row.evaluate().isNotEmpty) {
                final rect = tester.getRect(row);
                if (rect.top >= viewport.top &&
                    rect.bottom <= viewport.bottom) {
                  expectReaderContentClear(channel);
                  seen.add(channel.id);
                }
              }
            }
            if (scroll.offset >= scroll.position.maxScrollExtent) break;
            await key(LogicalKeyboardKey.arrowDown);
          }
          expect(seen, channels.map((c) => c.id).toSet());
          // At the end the same arrow resumes ordinary action traversal. Reading
          // does not authorize or invoke deletion, and Cancel retains its result.
          await key(LogicalKeyboardKey.arrowDown);
          expect(focusedIn(cancel), isTrue);
          expect(
            tester.state<ScrollableState>(
              find.descendant(of: list, matching: find.byType(Scrollable)),
            ),
            same(originalState),
          );
          expect(tester.widget<LineupFocusFrame>(frame).focused, isFalse);
          await key(LogicalKeyboardKey.arrowRight);
          expect(
            focusedIn(
              find.widgetWithText(
                LineupDestructiveButton,
                'Delete 40 channels',
              ),
            ),
            isTrue,
          );
          await key(LogicalKeyboardKey.arrowLeft);
          await key(LogicalKeyboardKey.select);
          expect(find.byType(Dialog), findsNothing);
          expect(controller.deleted, isEmpty);
          await openDelete();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(controller.deleted, isEmpty);
          await openDelete();
          await key(LogicalKeyboardKey.arrowRight);
          await key(LogicalKeyboardKey.select);
          expect(
            controller.deleted.map((c) => c.id),
            channels.map((c) => c.id),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          semantics.dispose();
          FocusManager.instance.highlightStrategy = previousHighlight;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('directory exposes search, management actions and channel rows', (
    tester,
  ) async {
    final fixture = UiFixture(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [_channel('first', 2, 'First')],
      ),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await openDestination(tester, 'Channels');
    await tester.pumpAndSettle();

    void outsideTextField(SemanticsNode node) {
      SemanticsNode? ancestor = node;
      while (ancestor != null) {
        expect(
          ancestor.getSemanticsData().flagsCollection.isTextField,
          isFalse,
          reason: 'Directory controls must not be children of a text field',
        );
        ancestor = ancestor.parent;
      }
    }

    final search = tester.getSemantics(
      find.byKey(const Key('channels-search')),
    );
    expect(search.label, contains('Search channels'));
    expect(search.getSemanticsData().flagsCollection.isTextField, isTrue);
    for (final label in [
      'Generate lineup',
      'Add a custom channel',
      'Select',
      'Reorder channels',
    ]) {
      final node = tester.getSemantics(find.text(label).first);
      expect(node.getSemanticsData().label, contains(label));
      outsideTextField(node);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    for (final label in ['All', 'Custom', 'Generated']) {
      final node = tester.getSemantics(find.text(label).first);
      expect(node.getSemanticsData().label, label);
      outsideTextField(node);
    }
    final row = tester.getSemantics(find.text('First'));
    expect(row.label, contains('First'));
    outsideTextField(row);
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final actions = tester.getSemantics(find.byTooltip('Actions for First'));
    expect(actions.label, 'Actions for First');
    outsideTextField(actions);
    expect(actions.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(actions.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: true);
  testWidgets(
    'selection survives search and batch delete receives the reviewed channels',
    (tester) async {
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 2, 'First'),
            _channel('second', 7, 'Second'),
            _channel('third', 20, 'Third', generated: true),
          ],
        ),
      );
      final fixture = UiFixture(controller: controller);
      await tester.pumpWidget(fixture.build());
      await tester.pump();
      await openDestination(tester, 'Channels');

      await tester.tap(find.text('Select'));
      await tester.pump();
      expect(
        tester
            .getSemantics(
              find.descendant(
                of: find.byKey(const ValueKey('channel-row-first')),
                matching: find.byType(Checkbox),
              ),
            )
            .label,
        contains('Select First'),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('channel-row-first')),
          matching: find.text('First'),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('channels-search')),
        'Second',
      );
      await tester.pumpAndSettle();
      final secondRow = find.byKey(const ValueKey('channel-row-second'));
      await tester.ensureVisible(secondRow);
      await tester.tap(secondRow);
      await tester.pump();
      expect(find.text('2 selected · 1 outside this view'), findsOneWidget);

      await tester.tap(find.text('2 selected · 1 outside this view'));
      await tester.pump();
      expect(find.text('Selected channels'), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byKey(const Key('channels-search')), findsNothing);
      expect(find.byKey(const ValueKey('channel-row-first')), findsOneWidget);
      expect(find.byKey(const ValueKey('channel-row-second')), findsOneWidget);
      await tester.tap(find.text('Delete selected'));
      await tester.pumpAndSettle();
      final confirmation = find.byType(Dialog);
      for (final name in ['First', 'Second']) {
        expect(
          find.descendant(of: confirmation, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: confirmation, matching: find.text('Third')),
        findsNothing,
      );
      await tester.tap(find.text('Delete 2 channels'));
      await tester.pumpAndSettle();

      expect(controller.deleted.map((channel) => channel.id), [
        'first',
        'second',
      ]);
    },
    semanticsEnabled: true,
  );

  testWidgets(
    'TV move search enters navigation and restores it after IME hide and Done',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final visibility = ValueNotifier<bool?>(false);
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      try {
        final controller = _RecordingDirectoryController(
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: [
              _channel('first', 2, 'First'),
              _channel('second', 7, 'Second'),
              _channel('third', 20, 'Third'),
            ],
          ),
        );
        await tester.pumpWidget(
          LineupBootstrap(
            controller: controller,
            player: FixturePlayer(),
            androidTv: true,
            keyboardVisibility: visibility,
          ),
        );
        await tester.pumpAndSettle();
        await openDestination(tester, 'Channels');
        await tester.tap(find.text('Reorder channels'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move to…').first);
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final field = find.descendant(
          of: dialog,
          matching: find.byType(TextField),
        );
        EditableText editor() => tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        bool focusedIn(Finder finder) {
          final target = tester.element(finder);
          final primary =
              FocusManager.instance.primaryFocus?.context as Element?;
          var inside = identical(target, primary);
          primary?.visitAncestorElements((e) {
            inside |= identical(e, target);
            return !inside;
          });
          return inside;
        }

        expect(editor().focusNode.hasFocus, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Move channel search',
        );
        expect(tester.testTextInput.isVisible, isFalse);
        await key(LogicalKeyboardKey.select);
        expect(editor().focusNode.hasFocus, isTrue);
        await tester.enterText(field, 'Third');
        await tester.pumpAndSettle();
        expect(find.text('20 · Third'), findsOneWidget);
        expect(find.text('7 · Second'), findsNothing);
        // Observed native shown->hidden restores navigation before any arrow.
        visibility.value = true;
        await tester.pump();
        visibility.value = false;
        await tester.pumpAndSettle();
        expect(editor().focusNode.hasFocus, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Move channel search',
        );
        await key(LogicalKeyboardKey.select);
        expect(editor().focusNode.hasFocus, isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(editor().focusNode.hasFocus, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Move channel search',
        );
        await key(LogicalKeyboardKey.arrowDown);
        expect(focusedIn(find.widgetWithText(TextButton, 'Before')), isTrue);
        await key(LogicalKeyboardKey.arrowRight);
        expect(focusedIn(find.widgetWithText(TextButton, 'After')), isTrue);
        await key(LogicalKeyboardKey.select);
        expect(dialog, findsNothing);
        // Reopening retains the same navigation-only entry. Back and Cancel
        // dismiss without adding another reorder operation.
        await tester.tap(find.text('Move to…').first);
        await tester.pumpAndSettle();
        expect(editor().focusNode.hasFocus, isFalse);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        await tester.tap(find.text('Move to…').first);
        await tester.pumpAndSettle();
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.arrowDown);
        expect(
          focusedIn(
            find.descendant(
              of: dialog,
              matching: find.widgetWithText(TextButton, 'Cancel'),
            ),
          ),
          isTrue,
        );
        await key(LogicalKeyboardKey.select);
        expect(dialog, findsNothing);
        await tester.tap(find.text('Save order'));
        await tester.pumpAndSettle();
        expect(controller.orderedIds, ['second', 'third', 'first']);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        visibility.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('desktop move search keeps autofocus editing', (tester) async {
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [
          _channel('first', 2, 'First'),
          _channel('second', 7, 'Second'),
        ],
      ),
    );
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('Reorder channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…').first);
    await tester.pumpAndSettle();
    final editor = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.orderedIds, isEmpty);
  });

  testWidgets('reorder previews retained number gaps and saves one order', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [
          _channel('first', 2, 'First'),
          _channel('second', 7, 'Second'),
          _channel('third', 20, 'Third'),
        ],
      ),
    );
    controller.pendingReorder = Completer<void>();
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await openDestination(tester, 'Channels');

    await tester.tap(find.text('Reorder channels'));
    await tester.pump();
    await tester.tap(find.byTooltip('Move First down'));
    await tester.pump();
    expect(find.text('7 → 2'), findsOneWidget);
    expect(find.text('2 → 7'), findsOneWidget);
    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ReorderableDragStartListener>(
            find.byType(ReorderableDragStartListener),
          )
          .every((handle) => !handle.enabled),
      isTrue,
    );
    controller.pendingReorder!.complete();
    await tester.pumpAndSettle();

    expect(controller.reorderBase.map((channel) => channel.id), [
      'first',
      'second',
      'third',
    ]);
    expect(controller.orderedIds, ['second', 'first', 'third']);
  });

  testWidgets(
    'reorder uses the directory number label and compact move action',
    (tester) async {
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 2, 'First'),
            _channel('second', 7, 'Second'),
          ],
        ),
      );
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');

      await tester.tap(find.text('Reorder channels'));
      await tester.pump();

      expect(find.text('No.'), findsOneWidget);
      expect(find.text('Number'), findsNothing);
      expect(find.text('Move to…'), findsNWidgets(2));
      final firstUp = find.ancestor(
        of: find.byTooltip('Move First up'),
        matching: find.byType(IconButton),
      );
      final firstDown = find.ancestor(
        of: find.byTooltip('Move First down'),
        matching: find.byType(IconButton),
      );
      final secondDown = find.ancestor(
        of: find.byTooltip('Move Second down'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(firstUp).onPressed, isNull);
      expect(tester.widget<IconButton>(firstDown).onPressed, isNotNull);
      expect(tester.widget<IconButton>(secondDown).onPressed, isNull);
    },
  );

  for (final (size, textScale) in [
    (const Size(1280, 720), 1.0),
    (const Size(1920, 1080), 1.0),
    (const Size(1920, 1080), 1.5),
  ]) {
    testWidgets(
      'reorder action row stays single-line at ${size.width}x${size.height} text $textScale',
      (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = _RecordingDirectoryController(
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: [
              _channel('first', 2, 'First', source: const PlaylistSource('P')),
              _channel(
                'second',
                7,
                'Second',
                source: const PlaylistSource('P'),
              ),
            ],
          ),
        );
        await tester.pumpWidget(UiFixture(controller: controller).build());
        await tester.pumpAndSettle();
        await openDestination(tester, 'Channels');
        await tester.tap(find.text('Reorder channels'));
        await tester.pump();

        final row = find.byKey(const ValueKey('reorder-first'));
        final move = find
            .descendant(of: row, matching: find.text('Move to…'))
            .first;
        final moveButton = find
            .ancestor(of: move, matching: find.byType(TextButton))
            .first;
        final upButton = find.ancestor(
          of: find.byTooltip('Move First up'),
          matching: find.byType(IconButton),
        );
        final downButton = find.ancestor(
          of: find.byTooltip('Move First down'),
          matching: find.byType(IconButton),
        );
        final rowSize = tester.getSize(row);
        final moveTop = tester.getTopLeft(moveButton).dy;
        expect(tester.getTopLeft(upButton).dy, closeTo(moveTop, 0.5));
        expect(tester.getTopLeft(downButton).dy, closeTo(moveTop, 0.5));
        expect(rowSize.height, lessThanOrEqualTo(80));
        expect(tester.getSize(moveButton).width, lessThanOrEqualTo(248));
      },
    );
  }

  testWidgets('row actions use themed menu rows and baseline delete rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const longName =
        'A very long channel name that wraps across multiple lines in the deletion confirmation';
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [_channel('long', 42, longName, generated: true)],
      ),
    );
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');

    final actionButton = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('PopupMenuButton'),
    );
    await tester.ensureVisible(actionButton);
    await tester.tap(actionButton);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate as custom'), findsOneWidget);
    expect(find.text('Delete…'), findsOneWidget);
    expect(find.byType(LineupDropdownMenuRow), findsNWidgets(2));
    final menu = tester.widget<Widget>(actionButton) as dynamic;
    // PopupMenuButton's private state is intentionally inspected for layout.
    // ignore: avoid_dynamic_calls
    expect(menu.menuPadding, EdgeInsets.zero);

    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    final dialogRow = find.byKey(const ValueKey('delete-dialog-row-long'));
    final row = tester.renderObject<RenderFlex>(dialogRow);
    expect(row.crossAxisAlignment, CrossAxisAlignment.baseline);
    expect(row.textBaseline, TextBaseline.alphabetic);
    expect(
      tester
          .getSize(
            find.descendant(of: dialogRow, matching: find.text(longName)),
          )
          .height,
      greaterThan(40),
    );
    await tester.tap(find.text('Cancel'));
  });

  for (final (label, batch, deletedName, expectedFocus) in [
    ('batch middle', true, 'Third', 'Open Fourth'),
    ('single end', false, 'Fourth', 'Open Third'),
  ]) {
    testWidgets('$label deletion restores the ordered adjacent survivor', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 1, 'First'),
            _channel('second', 2, 'Second'),
            _channel('third', 3, 'Third'),
            _channel('fourth', 4, 'Fourth'),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');

      if (batch) {
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        final row = find.text(deletedName);
        await tester.scrollUntilVisible(
          row,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(
          find.byKey(ValueKey('channel-row-${deletedName.toLowerCase()}')),
        );
        await tester.pumpAndSettle();
        final deleteFinder = find.widgetWithText(
          OutlinedButton,
          'Delete selected',
        );
        final deleteButton = tester.widget<OutlinedButton>(deleteFinder);
        final deleteFocus = Focus.of(
          tester.element(find.text('Delete selected')),
        );
        deleteFocus.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(deleteFocus));
        deleteButton.onPressed!();
      } else {
        final actions = find.byTooltip('Actions for $deletedName');
        await tester.scrollUntilVisible(
          actions,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(actions);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete…'));
      }
      await tester.pumpAndSettle();

      final confirmFinder = find.widgetWithText(
        FilledButton,
        batch ? 'Delete 1 channel' : 'Delete channel',
      );
      final confirm = tester.widget<FilledButton>(confirmFinder);
      final confirmFocus = Focus.of(
        tester.element(
          find.text(batch ? 'Delete 1 channel' : 'Delete channel'),
        ),
      );
      confirmFocus.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(confirmFocus));
      confirm.onPressed!();
      await tester.pumpAndSettle();

      expect(controller.deleted.single.name, deletedName);
      expect(FocusManager.instance.primaryFocus?.debugLabel, expectedFocus);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('channel'), findsWidgets);
    });
  }

  testWidgets(
    'filtered middle deletion restores the nearest visible survivor',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 1, 'First'),
            _channel('second', 2, 'Second'),
            _channel('third', 3, 'Third'),
            _channel('fourth', 4, 'Fourth'),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      final third = find.text('Third');
      await tester.scrollUntilVisible(
        third,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('channel-row-third')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('channels-search'));
      await tester.enterText(search, 'Fourth');
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 selected · 1 outside this view'));
      await tester.pumpAndSettle();
      final deleteFinder = find.widgetWithText(
        OutlinedButton,
        'Delete selected',
      );
      final deleteButton = tester.widget<OutlinedButton>(deleteFinder);
      final deleteFocus = Focus.of(
        tester.element(find.text('Delete selected')),
      );
      deleteFocus.requestFocus();
      await tester.pump();
      deleteButton.onPressed!();
      await tester.pumpAndSettle();
      final confirmFinder = find.widgetWithText(
        FilledButton,
        'Delete 1 channel',
      );
      final confirm = tester.widget<FilledButton>(confirmFinder);
      final confirmFocus = Focus.of(
        tester.element(find.text('Delete 1 channel')),
      );
      confirmFocus.requestFocus();
      await tester.pump();
      confirm.onPressed!();
      await tester.pumpAndSettle();

      expect(controller.channels.map((channel) => channel.name), [
        'First',
        'Second',
        'Fourth',
      ]);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Fourth');
      expect(tester.widget<TextField>(search).controller!.text, 'Fourth');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('Fourth'), findsWidgets);
    },
  );

  testWidgets('Back during delayed deletion preserves conflict scope', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [
          _channel('first', 1, 'First'),
          _channel('second', 2, 'Second'),
        ],
      ),
    )..pendingDelete = Completer<void>();
    controller.deleteFailure = const ChannelStateConflictException();
    addTearDown(controller.dispose);
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    final channelsState = tester.state<ChannelsViewState>(
      find.byType(ChannelsView),
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete 1 channel'));
    await tester.pump();
    expect(controller.deleteCalls, 1);
    expect(controller.deleteRequests.single.map((channel) => channel.id), [
      'first',
    ]);

    expect(channelsState.handleBack(), isTrue);
    expect(controller.deleteCalls, 1);
    expect(await channelsState.requestLeave(), isFalse);
    expect(controller.deleteCalls, 1);
    expect(controller.deleted.map((channel) => channel.id), ['first']);
    expect(controller.channels, hasLength(2));

    controller.pendingDelete!.complete();
    await tester.pumpAndSettle();
    expect(controller.deleteCalls, 1);
    expect(find.textContaining('changed'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(controller.deleted.map((channel) => channel.id), ['first']);
  });

  testWidgets('Back during delayed reorder preserves the conflict preview', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [
          _channel('first', 1, 'First'),
          _channel('second', 2, 'Second'),
        ],
      ),
    )..pendingReorder = Completer<void>();
    controller.reorderFailure = const ChannelStateConflictException();
    addTearDown(controller.dispose);
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    final channelsState = tester.state<ChannelsViewState>(
      find.byType(ChannelsView),
    );
    await tester.tap(find.text('Reorder channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Second up'));
    await tester.pump();
    await tester.tap(find.text('Save order'));
    await tester.pump();
    expect(controller.reorderCalls, 1);
    expect(controller.reorderRequests.single, ['second', 'first']);

    expect(channelsState.handleBack(), isTrue);
    expect(controller.reorderCalls, 1);
    expect(await channelsState.requestLeave(), isFalse);
    expect(controller.reorderCalls, 1);
    expect(controller.orderedIds, ['second', 'first']);
    expect(controller.channels.map((channel) => channel.number), [1, 2]);

    controller.pendingReorder!.complete();
    await tester.pumpAndSettle();
    expect(controller.reorderCalls, 1);
    expect(find.textContaining('lineup changed'), findsOneWidget);
    expect(find.text('Reorder channels'), findsOneWidget);
    expect(controller.orderedIds, ['second', 'first']);
  });

  testWidgets('removed focused row restores focus to a surviving channel', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [
          _channel('first', 1, 'First'),
          _channel('second', 2, 'Second'),
        ],
      ),
    );
    final fixture = UiFixture(controller: controller);
    await tester.pumpWidget(fixture.build());
    await tester.pump();
    await openDestination(tester, 'Channels');

    final firstFocus = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((widget) => widget.focusNode)
        .whereType<FocusNode>()
        .firstWhere((node) => node.debugLabel == 'Open First');
    firstFocus.requestFocus();
    await tester.pump();
    controller.fixtureActor.replaceChannels([controller.channels.last]);
    controller.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Second');
  });
  for (final batch in [false, true]) {
    testWidgets(
      '${batch ? 'batch' : 'single'} deletion locks mutations and retains retry scope',
      (tester) async {
        final controller = _RecordingDirectoryController(
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: [
              _channel('first', 2, 'First'),
              _channel('second', 7, 'Second'),
            ],
          ),
        )..pendingDelete = Completer<void>();
        await tester.pumpWidget(UiFixture(controller: controller).build());
        await tester.pumpAndSettle();
        await openDestination(tester, 'Channels');
        if (batch) {
          await tester.tap(find.text('Select'));
          await tester.pump();
          await tester.tap(find.text('First'));
          await tester.pump();
          await tester.tap(find.text('Delete selected'));
        } else {
          await tester.tap(find.byTooltip('Actions for First'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete…'));
        }
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(batch ? 'Delete 1 channel' : 'Delete channel'),
        );
        await tester.pumpAndSettle();
        for (final label
            in batch
                ? [
                    'Select all matching',
                    'Clear selection',
                    'Cancel',
                    'Deleting…',
                  ]
                : [
                    'Generate lineup',
                    'Add a custom channel',
                    'Select',
                    'Reorder channels',
                  ]) {
          final button = find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate(
                  (widget) => widget is ButtonStyleButton,
                ),
              )
              .first;
          expect(
            tester.widget<ButtonStyleButton>(button).onPressed,
            isNull,
            reason: label,
          );
        }
        controller.pendingDelete!.completeError(
          StateError('synthetic save failure'),
        );
        await tester.pumpAndSettle();
        expect(controller.channels, hasLength(2));
        expect(controller.deleted.map((channel) => channel.id), ['first']);
        if (batch) expect(find.text('1 selected'), findsOneWidget);
        expect(find.textContaining('could not be deleted'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'batch deletion restores an actionable surviving row or empty action',
    (tester) async {
      final controller = _RecordingDirectoryController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            _channel('first', 2, 'First'),
            _channel('second', 7, 'Second'),
          ],
        ),
      );
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      for (final name in ['First', 'Second']) {
        await tester.tap(find.text('Select'));
        await tester.pump();
        await tester.tap(find.text(name));
        await tester.pump();
        await tester.tap(find.text('Delete selected'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete 1 channel'));
        await tester.pumpAndSettle();
        if (name == 'First') {
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Second');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('‹ Channels'), findsOneWidget);
          await tester.tap(find.text('‹ Channels'));
          await tester.pumpAndSettle();
        } else {
          expect(find.text('Generate lineup'), findsOneWidget);
          expect(find.text('Add a custom channel'), findsNothing);
          expect(
            Focus.of(tester.element(find.text('Generate lineup'))).hasFocus,
            isTrue,
          );
        }
      }
    },
  );
}

Channel _channel(
  String id,
  int number,
  String name, {
  bool generated = false,
  ContentSource? source,
}) => Channel(
  id: id,
  number: number,
  name: name,
  source:
      source ??
      ManualSource([
        ChannelItem(
          id: '$id-program',
          title: '$name program',
          duration: const Duration(minutes: 30),
        ),
      ]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: number,
  builderKey: generated ? 'generated:$id' : null,
);

class _RecordingDirectoryController extends FixtureController {
  _RecordingDirectoryController({super.scenario});

  Completer<void>? pendingDelete;
  Completer<void>? pendingReorder;
  Object? deleteFailure;
  Object? reorderFailure;
  int deleteCalls = 0;
  int reorderCalls = 0;
  final deleteRequests = <List<Channel>>[];
  final reorderRequests = <List<String>>[];
  List<Channel> deleted = const [];
  List<Channel> reorderBase = const [];
  List<String> orderedIds = const [];

  @override
  Future<void> deleteChannels({required List<Channel> expectedChannels}) async {
    deleteCalls++;
    deleteRequests.add(List.unmodifiable(expectedChannels));
    deleted = List.unmodifiable(expectedChannels);
    await pendingDelete?.future;
    if (deleteFailure case final failure?) {
      deleteFailure = null;
      // The fixture injects arbitrary failures to exercise propagation.
      // ignore: only_throw_errors
      throw failure;
    }
    final ids = expectedChannels.map((channel) => channel.id).toSet();
    fixtureActor.replaceChannels(
      channels.where((channel) => !ids.contains(channel.id)).toList(),
    );
    notifyListeners();
  }

  @override
  Future<void> reorderChannels({
    required List<Channel> expectedLineup,
    required List<String> orderedChannelIds,
  }) async {
    reorderCalls++;
    reorderRequests.add(List.unmodifiable(orderedChannelIds));
    reorderBase = List.unmodifiable(expectedLineup);
    orderedIds = List.unmodifiable(orderedChannelIds);
    await pendingReorder?.future;
    if (reorderFailure case final failure?) {
      reorderFailure = null;
      // The fixture injects arbitrary failures to exercise propagation.
      // ignore: only_throw_errors
      throw failure;
    }
  }
}
