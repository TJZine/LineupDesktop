import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

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

  testWidgets(
    'reorder uses the directory number label and compact move action',
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
        final controller = _RecordingDirectoryController()
          ..stage = SetupStage.ready
          ..channels = [
            _channel('first', 2, 'First', source: const PlaylistSource('P')),
            _channel('second', 7, 'Second', source: const PlaylistSource('P')),
          ];
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
    final controller = _RecordingDirectoryController()
      ..stage = SetupStage.ready
      ..channels = [_channel('long', 42, longName, generated: true)];
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
