import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets(
    'selection survives search and batch delete receives the reviewed channels',
    (tester) async {
      final controller = _RecordingDirectoryController()
        ..stage = SetupStage.ready
        ..channels = [
          _channel('first', 2, 'First'),
          _channel('second', 7, 'Second'),
          _channel('third', 20, 'Third', generated: true),
        ];
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
      expect(find.text('1 custom · 0 generated'), findsNothing);
      expect(find.text('2 custom · 0 generated'), findsOneWidget);
      await tester.tap(find.text('Delete 2 channels'));
      await tester.pumpAndSettle();

      expect(controller.deleted.map((channel) => channel.id), [
        'first',
        'second',
      ]);
    },
    semanticsEnabled: true,
  );

  testWidgets('reorder previews retained number gaps and saves one order', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController()
      ..stage = SetupStage.ready
      ..channels = [
        _channel('first', 2, 'First'),
        _channel('second', 7, 'Second'),
        _channel('third', 20, 'Third'),
      ];
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

  testWidgets('removed focused row restores focus to a surviving channel', (
    tester,
  ) async {
    final controller = _RecordingDirectoryController()
      ..stage = SetupStage.ready
      ..channels = [
        _channel('first', 1, 'First'),
        _channel('second', 2, 'Second'),
      ];
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
    controller.channels = [controller.channels.last];
    controller.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Open Second');
  });
  for (final batch in [false, true]) {
    testWidgets(
      '${batch ? 'batch' : 'single'} deletion locks mutations and retains retry scope',
      (tester) async {
        final controller = _RecordingDirectoryController()
          ..stage = SetupStage.ready
          ..channels = [
            _channel('first', 2, 'First'),
            _channel('second', 7, 'Second'),
          ]
          ..pendingDelete = Completer<void>();
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
          await tester.tap(find.text('Delete'));
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
      final controller = _RecordingDirectoryController()
        ..stage = SetupStage.ready
        ..channels = [
          _channel('first', 2, 'First'),
          _channel('second', 7, 'Second'),
        ];
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
          expect(find.text('Back to Channels'), findsOneWidget);
          await tester.tap(find.text('Back to Channels'));
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
}) => Channel(
  id: id,
  number: number,
  name: name,
  source: ManualSource([
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
  Completer<void>? pendingDelete;
  Completer<void>? pendingReorder;
  List<Channel> deleted = const [];
  List<Channel> reorderBase = const [];
  List<String> orderedIds = const [];

  @override
  Future<void> deleteChannels({required List<Channel> expectedChannels}) async {
    deleted = List.unmodifiable(expectedChannels);
    await pendingDelete?.future;
    final ids = expectedChannels.map((channel) => channel.id).toSet();
    channels = channels.where((channel) => !ids.contains(channel.id)).toList();
    notifyListeners();
  }

  @override
  Future<void> reorderChannels({
    required List<Channel> expectedLineup,
    required List<String> orderedChannelIds,
  }) async {
    reorderBase = List.unmodifiable(expectedLineup);
    orderedIds = List.unmodifiable(orderedChannelIds);
    await pendingReorder?.future;
  }
}
