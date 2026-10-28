import 'dart:io';
import 'dart:ui' as ui;

import '../support/committed_state_matchers.dart';

import 'dart:async';

import 'dart:ui' show CheckedState;
import 'dart:ui' show PointerDeviceKind;

import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderImage, RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';
import '../support/golden_test_support.dart';

void main() {
  const reviewEvidence = String.fromEnvironment('REVIEW_EVIDENCE');
  for (final scale in [1.0, 1.3]) {
    testWidgets('R1 full production Review hint render at TV $scale', (
      tester,
    ) async {
      await tester.runAsync(loadPinnedTestFonts);
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await _pump(tester, controller, isTv: true, reviewRenderScale: scale);
      await _advanceToReview(tester);
      // Asset decoding runs outside the fake test clock. pumpAndSettle alone
      // can finish before the header Image receives its first decoded frame.
      final logo = find.descendant(
        of: find.byType(LineupTopBar),
        matching: find.byType(Image),
      );
      expect(logo, findsOneWidget);
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(logo).image,
          tester.element(logo),
        ),
      );
      await tester.pumpAndSettle();
      final logoRender = tester.renderObject<RenderImage>(
        find.descendant(of: logo, matching: find.byType(RawImage)),
      );
      expect(
        logoRender.image,
        isNotNull,
        reason: 'Capture requires the actual decoded brand mark, not its slot',
      );
      expect(logoRender.image!.width, greaterThan(0));
      expect(logoRender.image!.height, greaterThan(0));
      expect(tester.getRect(logo).isEmpty, isFalse);
      final row = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'review-channel-',
                ),
          )
          .first;
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(Text)).first,
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
      final hint = find.byKey(const ValueKey('review-footer-hint'));
      expect(hint, findsOneWidget);
      expect(
        find.text('Press right on any channel to jump here'),
        findsOneWidget,
      );
      final paragraph = tester.renderObject<RenderParagraph>(hint);
      expect(
        paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: paragraph.text.toPlainText().length,
              ),
            )
            .map((box) => box.top)
            .toSet()
            .length,
        1,
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('review-page-raster')),
      );
      await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 2);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$reviewEvidence/review-full-tv-$scale${scale == 1.3 ? '-large' : ''}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        raster.dispose();
      });
    }, skip: reviewEvidence.isEmpty);
  }

  testWidgets(
    'R1 real controller saves and review choices stay unchanged across region keys',
    (tester) async {
      final fixture = await _createBoundarySetup();
      addTearDown(fixture.controller.dispose);
      await _pump(tester, fixture.controller, isTv: true);
      await _advanceToReview(tester);
      final search = find.byKey(const ValueKey('channel-setup-review-search'));
      await tester.enterText(search, 'Recently');
      await tester.pumpAndSettle();
      final row = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'review-channel-',
                ),
          )
          .first;
      await tester.ensureVisible(row);
      final node = Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(Text)).first,
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      final saves = fixture.store.saveCalls;
      final channels = fixture.controller.channels;
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          Focus.of(tester.element(find.text('Create lineup'))).hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(node.hasPrimaryFocus, isTrue);
      }
      expect(fixture.store.saveCalls, saves);
      expect(fixture.controller.channels, channels);
      expect(tester.widget<TextField>(search).controller!.text, 'Recently');
      expect(find.text('Review your first lineup'), findsOneWidget);
      debugPrint(
        'R1 real controller navigation saveDelta=${fixture.store.saveCalls - saves} query=retained lineup=unchanged',
      );
    },
  );

  testWidgets('NAV-I2 Applying Back is claimed without duplicate apply', (
    tester,
  ) async {
    final controller = _SetupController()..applyGate = Completer<void>();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await tester.pumpAndSettle();
    await _advanceToReview(tester);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pump();

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    expect(controller.applyCalls, 1);
    expect(find.text('Creating your lineup…'), findsOneWidget);
    controller.applyGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('NAV-I2 completed Back invokes the visible primary once', (
    tester,
  ) async {
    var viewCalls = 0;
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true, onView: () => viewCalls++);
    await _advanceToReview(tester);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    expect(viewCalls, 1);
  });

  testWidgets('NAV-I2 scanning Back cancels the real scan once', (
    tester,
  ) async {
    final controller = _SetupController(blockScan: true);
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
    await controller.scanStarted.future;

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
    expect(
      find.byKey(const ValueKey('library-selection-list')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('NAV-I2 library commit Back is claimed while persistence waits', (
    tester,
  ) async {
    final controller = _SetupController()..commitGate = Completer<void>();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
    await tester.pump();
    expect(controller.commitCalls, 1);

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    expect(
      find.byKey(const ValueKey('library-selection-list')),
      findsOneWidget,
    );
    controller.commitGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Shape your lineup'), findsOneWidget);
  });

  testWidgets('NAV-I2 desktop picker ignores non-Back navigation keys', (
    tester,
  ) async {
    final controller = _SetupController(
      scenario: const LineupScenario(channelSetupCanCancel: true),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _advanceToConfigure(tester);

    final navigation = tester
        .widgetList<Focus>(find.byType(Focus))
        .firstWhere(
          (focus) => focus.onKeyEvent != null && focus.focusNode == null,
        );
    expect(navigation.onKeyEvent, isNotNull);
    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );

    for (final key in [
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyX,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(find.text('Shape your lineup'), findsOneWidget);
    expect(state.handleBack(), isTrue);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('library-selection-list')),
      findsOneWidget,
    );
  });

  testWidgets('NAV-I2 TV Libraries chooses the enabled recovery target', (
    tester,
  ) async {
    final controller = _SetupController(
      scenario: const LineupScenario(libraries: []),
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await tester.pumpAndSettle();
    final switchServer = find.byKey(const ValueKey('setup-switch-server'));
    final switchButton = tester.widget<FilledButton>(switchServer);
    expect(switchButton.onPressed, isNotNull);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Setup libraries entry',
    );

    controller.fixtureActor.present(const LineupPresentation(busy: true));
    await _pump(tester, controller, isTv: true);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(switchServer).focusNode, isNull);
  });

  testWidgets('NAV-I2 TV scan Cancel autofocus is not a desktop policy', (
    tester,
  ) async {
    for (final tv in [true, false]) {
      final controller = _SetupController(blockScan: true);
      addTearDown(controller.dispose);
      await _pump(tester, controller, isTv: tv);
      await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
      await controller.scanStarted.future;
      await tester.pump();
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel scan'),
      );
      expect(cancel.autofocus, tv);
      controller.cancelLibraryScan();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('NAV-I2 Libraries and Review expose their first TV focus', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await tester.pumpAndSettle();

    _expectLibraryEntryPaint(tester);

    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('scan-selected-libraries')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
        .onPressed!();
    await tester.pumpAndSettle();
    final searchFocus = tester
        .widgetList<Focus>(find.byType(Focus))
        .firstWhere(
          (focus) => focus.focusNode?.debugLabel == 'Setup review search',
        )
        .focusNode!;
    expect(searchFocus.hasPrimaryFocus, isTrue);
    final search = find.byKey(const ValueKey('channel-setup-review-search'));
    final searchInk = find.ancestor(
      of: search,
      matching: find.byType(LineupFocusInk),
    );
    expect(searchInk, findsOneWidget);
    expect(tester.widget<LineupFocusInk>(searchInk).focused, isTrue);
    final searchRoles = LineupTheme.of(
      tester.element(find.byType(UpstreamChannelSetupView)),
    );
    expect(tester.widget<TextField>(search).style!.color, searchRoles.onFocus);
    expect(
      Theme.of(tester.element(search)).inputDecorationTheme.fillColor,
      searchRoles.focusedSurface,
    );

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(state.handleBack(), isTrue);
    await tester.pumpAndSettle();
    _expectLibraryEntryPaint(tester);
  });

  for (final isTv in [true, false]) {
    testWidgets(
      'library Select all is one target covering its checkbox (TV: $isTv)',
      (tester) async {
        final controller = _SetupController();
        addTearDown(controller.dispose);
        await _pump(tester, controller, isTv: isTv);
        await tester.pumpAndSettle();

        final selectAll = find.widgetWithText(TextButton, 'Select all');
        final checkbox = find.byKey(const ValueKey('select-all-libraries'));
        expect(
          find.descendant(of: selectAll, matching: checkbox),
          findsOneWidget,
        );
        final buttonRect = tester.getRect(selectAll);
        expect(
          buttonRect.expandToInclude(tester.getRect(checkbox)),
          buttonRect,
        );
        final checkboxElement = tester.element(checkbox);
        bool insideCheckbox(FocusNode node) {
          final context = node.context;
          if (context == null) return false;
          if (identical(context, checkboxElement)) return true;
          var inside = false;
          context.visitAncestorElements((element) {
            inside = identical(element, checkboxElement);
            return !inside;
          });
          return inside;
        }

        expect(
          FocusManager.instance.rootScope.traversalDescendants.where(
            insideCheckbox,
          ),
          isEmpty,
        );

        final semantics = tester.ensureSemantics();
        var data = tester.getSemantics(selectAll).getSemanticsData();
        expect(data.label, 'Select all');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isChecked, CheckedState.isTrue);
        await tester.tap(find.text('Shows'));
        await tester.pump();
        expect(tester.widget<Checkbox>(checkbox).value, isNull);
        data = tester.getSemantics(selectAll).getSemanticsData();
        expect(data.label, 'Select all');
        expect(data.flagsCollection.isChecked, CheckedState.mixed);
        semantics.dispose();

        if (isTv) {
          final node = tester.widget<TextButton>(selectAll).focusNode!;
          expect(node.hasPrimaryFocus, isTrue);
          final roles = LineupTheme.of(tester.element(selectAll));
          final fill = find
              .descendant(of: selectAll, matching: find.byType(Material))
              .first;
          expect(tester.widget<Material>(fill).color, roles.focusedSurface);
          expect(
            tester.getRect(fill).expandToInclude(tester.getRect(checkbox)),
            tester.getRect(fill),
          );
        }
      },
    );
  }

  testWidgets(
    'TV checked library rows show checked state on the checkbox only',
    (tester) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      await _pump(tester, controller, isTv: true);
      await tester.pumpAndSettle();
      final roles = LineupTheme.of(
        tester.element(find.byType(UpstreamChannelSetupView)),
      );
      final row = find.byKey(const ValueKey('library-row-movies'));
      BoxDecoration surface() =>
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

      expect(
        tester
            .widget<Checkbox>(
              find.descendant(of: row, matching: find.byType(Checkbox)),
            )
            .value,
        isTrue,
      );
      expect(surface().color, isNot(roles.selectedSurface));
      expect(surface().color, isNot(roles.focusedSurface));
      expect((surface().border! as Border).left.color, Colors.transparent);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final rowContent = find
          .descendant(of: row, matching: find.byType(Padding))
          .first;
      expect(Focus.of(tester.element(rowContent)).hasPrimaryFocus, isTrue);
      expect(surface().color, roles.focusedSurface);
      expect((surface().border! as Border).left.color, Colors.transparent);
    },
  );

  testWidgets('library row checkbox, name, and type share a vertical center', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('library-row-shows'));
    final checkbox = tester.getCenter(
      find.descendant(of: row, matching: find.byType(Checkbox)),
    );
    final name = tester.getCenter(
      find.descendant(of: row, matching: find.text('Shows')),
    );
    final type = tester.getCenter(
      find.descendant(of: row, matching: find.text('TV Shows')),
    );
    expect(name.dy, closeTo(checkbox.dy, 1));
    expect(type.dy, closeTo(checkbox.dy, 1));
    expect(type.dx, greaterThan(name.dx));
  });

  testWidgets('NAV-I2 review entry yields to a modal opened before its frame', (
    tester,
  ) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await _advanceToConfigure(tester);

    final reviewButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('review-channels')),
    );
    reviewButton.onPressed!();
    final modalFocus = FocusNode(debugLabel: 'NAV-I2 modal owner');
    addTearDown(modalFocus.dispose);
    final dialog = showDialog<void>(
      context: tester.element(find.byType(UpstreamChannelSetupView)),
      builder: (context) => AlertDialog(
        title: const Text('Modal owner'),
        actions: [
          TextButton(
            focusNode: modalFocus,
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(modalFocus.hasPrimaryFocus, isTrue);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('Setup review search'),
    );
    Navigator.of(tester.element(find.text('Modal owner'))).pop();
    await dialog;
    await tester.pumpAndSettle();
  });

  testWidgets(
    'NAV-I2 Libraries restores visible focus after scan cancellation',
    (tester) async {
      final controller = _SetupController(blockScan: true);
      addTearDown(controller.dispose);
      await _pump(tester, controller, isTv: true);
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('scan-selected-libraries')),
          )
          .onPressed!();
      await controller.scanStarted.future;
      await tester.pump();
      expect(
        tester
            .state<UpstreamChannelSetupViewState>(
              find.byType(UpstreamChannelSetupView),
            )
            .handleBack(),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
      _expectLibraryEntryPaint(tester);
    },
  );

  for (final entry in ['Libraries', 'Review']) {
    testWidgets('NAV-I2 pending $entry entry preserves visible Support focus', (
      tester,
    ) async {
      final controller = _SetupController();
      addTearDown(controller.dispose);
      final hostKey = GlobalKey<_RetainedSetupHostState>();
      await _pumpRetainedSetup(tester, controller, hostKey);
      await _advanceToConfigure(tester);

      if (entry == 'Review') {
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
            .onPressed!();
      } else {
        tester
            .state<UpstreamChannelSetupViewState>(
              find.byType(UpstreamChannelSetupView),
            )
            .handleBack();
      }
      hostKey.currentState!.hide();
      FocusManager.instance.applyFocusChangesIfNeeded();
      expect(
        FocusManager.instance.primaryFocus,
        same(hostKey.currentState!.supportFocus),
      );
      await tester.pumpAndSettle();
      expect(hostKey.currentState!.supportFocus.hasPrimaryFocus, isTrue);
      expect(find.text('Support owner'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus,
        same(hostKey.currentState!.supportFocus),
      );
    });
  }

  testWidgets('NAV-I2 real scan Back rejects a late successful IO result', (
    tester,
  ) async {
    final fixture = await _createBoundarySetup();
    addTearDown(fixture.controller.dispose);
    fixture.plex.scanGate = Completer<PlexLibraryScan>();
    final saves = fixture.store.saveCalls;
    await _pump(tester, fixture.controller, isTv: true);
    await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
    await fixture.plex.scanStarted.future;

    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isFalse);
    expect(fixture.controller.libraryScanStatus, LibraryScanStatus.cancelled);
    fixture.plex.scanGate!.complete(
      PlexLibraryScan(items: [_boundaryMediaItem]),
    );
    await tester.pumpAndSettle();

    expect(fixture.controller.stage, SetupStage.channelSetup);
    expect(fixture.controller.selectedLibraryIds, isEmpty);
    expect(find.text('Choose libraries'), findsOneWidget);
    expect(fixture.store.saveCalls, saves);
  });

  testWidgets('NAV-I2 scan failure restores visible focus and retry advances', (
    tester,
  ) async {
    final fixture = await _createBoundarySetup();
    addTearDown(fixture.controller.dispose);
    fixture.plex.scanGate = Completer<PlexLibraryScan>();
    final saves = fixture.store.saveCalls;
    await _pump(tester, fixture.controller, isTv: true);
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('scan-selected-libraries')),
        )
        .onPressed!();
    await fixture.plex.scanStarted.future;
    await tester.pump();
    fixture.plex.scanGate!.completeError(
      const PlexException('server-unreachable', 'Synthetic scan failure.'),
    );
    await tester.pumpAndSettle();
    expect(
      fixture.controller.libraryScanStatus,
      LibraryScanStatus.transientFailure,
    );
    expect(fixture.store.saveCalls, saves);
    _expectSingleLibraryEntryPaint(tester);
    fixture.plex.scanGate = null;
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('retry-failed-libraries')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Shape your lineup'), findsOneWidget);
    expect(fixture.store.saveCalls, saves + 1);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'NAV-I2 real library persistence Back is claimed before ${fail ? 'failure' : 'success'}',
      (tester) async {
        final fixture = await _createBoundarySetup();
        addTearDown(fixture.controller.dispose);
        fixture.store.blockNext(fail: fail);
        final saves = fixture.store.saveCalls;
        await _pump(tester, fixture.controller, isTv: true);
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('scan-selected-libraries')),
            )
            .onPressed!();
        await fixture.store.saveStarted.future;
        await tester.pump();
        expect(
          tester
              .widget<InkWell>(find.byKey(const ValueKey('library-row-movies')))
              .focusNode,
          isNull,
        );

        final state = tester.state<UpstreamChannelSetupViewState>(
          find.byType(UpstreamChannelSetupView),
        );
        expect(state.handleBack(), isTrue);
        expect(state.handleBack(), isTrue);
        expect(fixture.controller.canSwitchServer, isFalse);
        expect(fixture.store.saveCalls, saves + 1);
        fixture.store.releaseBlockedSave();
        await tester.pumpAndSettle();

        expect(fixture.controller.canSwitchServer, isTrue);
        expect(fixture.store.saveCalls, saves + 1);
        if (fail) {
          expect(fixture.controller.selectedLibraryIds, isEmpty);
          expect(fixture.controller.stage, SetupStage.channelSetup);
          expect(
            find.byKey(const ValueKey('library-selection-list')),
            findsOneWidget,
          );
          _expectSingleLibraryEntryPaint(tester);
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('continue-ready-libraries')),
              )
              .onPressed!();
          await tester.pumpAndSettle();
          expect(find.text('Shape your lineup'), findsOneWidget);
          expect(fixture.store.saveCalls, saves + 2);
        } else {
          expect(fixture.controller.selectedLibraryIds, {'movies'});
          expect(fixture.store.state.selectedLibraryIdsByProfileServer, {
            'owner': {
              'server': ['movies'],
            },
          });
          expect(find.text('Shape your lineup'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('NAV-I2 actual Applying save claims repeated Back until commit', (
    tester,
  ) async {
    final fixture = await _createBoundarySetup();
    addTearDown(fixture.controller.dispose);
    var completions = 0;
    await _pump(
      tester,
      fixture.controller,
      isTv: true,
      onView: () => completions++,
    );
    await _advanceToReview(tester);
    final saves = fixture.store.saveCalls;
    fixture.store.blockNext(fail: false);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await fixture.store.saveStarted.future;
    await tester.pump();
    final state = tester.state<UpstreamChannelSetupViewState>(
      find.byType(UpstreamChannelSetupView),
    );
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    await tester.pump();
    expect(find.text('Creating your lineup…'), findsOneWidget);
    expect(fixture.controller.channels, isEmpty);
    expect(completions, 0);
    expect(fixture.store.saveCalls, saves + 1);
    fixture.store.releaseBlockedSave();
    await tester.pumpAndSettle();
    expect(fixture.controller.channels, isNotEmpty);
    expect(fixture.store.saveCalls, saves + 1);
    expect(completions, 0);
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    expect(completions, 1);
    expect(fixture.store.saveCalls, saves + 1);
  });

  testWidgets('NAV-I2 Configure Back returns to Libraries', (tester) async {
    final controller = _SetupController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, isTv: true);
    await _advanceToConfigure(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('library-selection-list')),
      findsOneWidget,
      reason: 'Configure Back should return to Libraries',
    );
  });

  testWidgets('NAV-I2 Review and Failed Back return to their owners', (
    tester,
  ) async {
    final reviewController = _SetupController();
    addTearDown(reviewController.dispose);
    await _pump(tester, reviewController, isTv: true);
    await _advanceToReview(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Shape your lineup'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final failedController = _SetupController(failApply: true);
    addTearDown(failedController.dispose);
    await _pump(tester, failedController, isTv: true);
    await _advanceToReview(tester);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t create your lineup'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Review your first lineup'), findsOneWidget);
  });

  for (final tv in [false, true]) {
    testWidgets(
      'Library explicit footer action labels follow focus ink TV=$tv',
      (tester) async {
        final controller = _SetupController(
          blockScan: true,
          scenario: const LineupScenario(channelSetupCanCancel: true),
        );
        final strategy = FocusManager.instance.highlightStrategy;
        try {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTouch;
          await _pump(tester, controller, isTv: tv);
          Future<void> checkLabel(String label) async {
            final text = find.text(label);
            expect(text, findsOneWidget);
            final element = tester.element(text);
            final originalStyle = tester.widget<Text>(text).style!;
            final originalInk = originalStyle.color;
            final node = Focus.of(element);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
            node.requestFocus();
            await tester.pumpAndSettle();
            expect(node.hasPrimaryFocus, isTrue);
            final richText = tester.widget<RichText>(
              find.descendant(of: text, matching: find.byType(RichText)),
            );
            expect(
              richText.text.style?.color,
              tv
                  ? LineupTheme.of(tester.element(text)).primaryText
                  : originalInk,
            );
            expect(
              tester.widget<Text>(text).style!.fontSize,
              originalStyle.fontSize,
            );
            expect(tester.element(text), same(element));
            node.unfocus();
            await tester.pumpAndSettle();
            expect(tester.widget<Text>(text).style!.color, originalInk);
          }

          await checkLabel('Switch server');
          await checkLabel('Cancel');
          await tester.tap(
            find.byKey(const ValueKey('scan-selected-libraries')),
          );
          await tester.pump();
          await checkLabel('Cancel scan');
          controller.cancelLibraryScan();
          await tester.pumpAndSettle();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          FocusManager.instance.highlightStrategy = strategy;
        }
      },
    );
  }
  testWidgets(
    'TV conditional variant selection preserves its trigger element and focus',
    (tester) async {
      final controller = _SetupController();
      try {
        await tester.runAsync(loadPinnedTestFonts);
        await _pump(tester, controller, isTv: true);
        await _openPlaybackControls(tester);
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(
          true,
        );
        await tester.pumpAndSettle();
        final field = _setupField<PlaybackMode?>('Different playback mode');
        await tester.ensureVisible(field);
        final element = tester.element(field);
        final node = tester
            .widget<Focus>(
              find.descendant(
                of: field,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Focus &&
                      widget.focusNode?.debugLabel ==
                          'DropdownButton<PlaybackMode?>',
                ),
              ),
            )
            .focusNode!;
        node.requestFocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        node.requestFocus();
        await tester.pumpAndSettle();
        expect(
          node.hasPrimaryFocus,
          isTrue,
          reason: 'The actual variant trigger owns the key',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.byType(LineupDropdownMenuRow), findsWidgets);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<PlaybackMode?>>(field)
              .initialValue,
          PlaybackMode.block,
        );
        expect(tester.element(field), same(element));
        expect(node.hasFocus, isTrue);
        expect(find.text('Extra block size'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.reset();
      }
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets('semantic failure leaves keep focused contrast: $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final tv = platform == TargetPlatform.android;
      final controller = _SetupController(mixedScan: true);
      try {
        await _pump(tester, controller, isTv: tv);
        await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
        await tester.pumpAndSettle();
        final status = find.text('Couldn’t scan · Try again.');
        expect(status, findsOneWidget);
        final element = tester.element(status);
        final baseError = Theme.of(element).colorScheme.error;
        Color? ink(Finder text) => tester
            .widget<RichText>(
              find.descendant(of: text, matching: find.byType(RichText)),
            )
            .text
            .style
            ?.color;
        expect(ink(status), baseError);
        final row = find.byKey(const ValueKey('library-row-archive'));
        await tester.ensureVisible(row);
        final rowFocus = Focus.of(tester.element(status));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        rowFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(ink(status), tv ? const Color(0xFF090806) : baseError);
        final retry = find.byKey(const ValueKey('retry-library-archive'));
        final retryLeaf = find.descendant(
          of: retry,
          matching: find.text('Retry'),
        );
        Focus.of(tester.element(retryLeaf)).requestFocus();
        await tester.pumpAndSettle();
        expect(ink(status), tv ? const Color(0xFF090806) : baseError);
        expect(tester.element(status), same(element));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(ink(status), baseError);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
    testWidgets('Removed review leaf keeps focused contrast: $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final tv = platform == TargetPlatform.android;
      final controller = _SetupController(channels: [_missingChannel]);
      try {
        await tester.runAsync(loadPinnedTestFonts);
        await _pump(tester, controller, isTv: tv);
        tester.view.physicalSize = const Size(1920, 1080);
        await tester.pumpAndSettle();
        await _advanceToReview(tester);
        final search = find.byKey(
          const ValueKey('channel-setup-review-search'),
        );
        await tester.ensureVisible(search);
        await tester.enterText(search, 'Retired collection');
        await tester.pumpAndSettle();
        final choice = find.byKey(
          const ValueKey('missing-source-choice-missing'),
        );
        await tester.scrollUntilVisible(
          choice,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('channel-setup-review-roster')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        // Removal interaction has its own coverage below. Initialize this paint
        // case through the existing choice callback, without depending on its
        // position in the separate missing-source scroll region.
        tester.widget<LineupSegmentedControl<bool>>(choice).onSelectionChanged!(
          {true},
        );
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
        await tester.pumpAndSettle();
        final removed = find.descendant(
          of: row,
          matching: find.text('Removed'),
        );
        final element = tester.element(removed);
        final baseError = Theme.of(element).colorScheme.error;
        Color? ink() => tester
            .widget<RichText>(
              find.descendant(of: removed, matching: find.byType(RichText)),
            )
            .text
            .style
            ?.color;
        expect(ink(), baseError);
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          Focus.of(element).requestFocus();
          await tester.pumpAndSettle();
          expect(ink(), const Color(0xFF090806));
          expect(
            (const Color(0xFFE9DCC3).computeLuminance() + .05) /
                (ink()!.computeLuminance() + .05),
            greaterThan(4.5),
          );
        }
        expect(tester.element(removed), same(element));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(ink(), baseError);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      'limit dropdown trigger and menu use legible focus ink: $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final controller = _SetupController();
        final tv = platform == TargetPlatform.android;
        final focusStrategy = FocusManager.instance.highlightStrategy;
        if (tv) {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTouch;
        }
        try {
          await tester.runAsync(loadPinnedTestFonts);
          await _pump(tester, controller, isTv: tv);
          await _advanceToConfigure(tester);
          await tester.tap(find.byKey(const ValueKey('configure-section-2')));
          await tester.pumpAndSettle();
          final dropdown = find.byKey(const ValueKey('rules-maximum'));
          await tester.ensureVisible(dropdown);
          await tester.pumpAndSettle();
          final element = tester.element(dropdown);
          final roles = LineupTheme.of(element);
          Finder label() =>
              find.descendant(of: dropdown, matching: find.text('200'));
          Color? ink(Finder text) {
            final widget = tester.widget<Text>(text);
            return DefaultTextStyle.of(tester.element(text)).style
                .merge(widget.style)
                .color;
          }

          expect(ink(label()), roles.primaryText);
          final closedElement = tester.element(label());
          final node = tester
              .widget<InkWell>(
                find.descendant(of: dropdown, matching: find.byType(InkWell)),
              )
              .focusNode!;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          node.requestFocus();
          await tester.pumpAndSettle();
          expect(node.hasPrimaryFocus, isTrue);
          expect(ink(label()), tv ? roles.onFocus : roles.primaryText);
          final icon = find.descendant(
            of: dropdown,
            matching: find.byIcon(Icons.arrow_drop_down),
          );
          expect(
            tester.widget<Icon>(icon).color ??
                IconTheme.of(tester.element(icon)).color,
            tv ? roles.focusSecondaryText : Colors.white70,
          );
          expect(tester.element(label()), same(closedElement));
          expect(tester.element(dropdown), same(element));
          if (!tv) {
            final box = find.ancestor(
              of: dropdown,
              matching: find.byType(LineupDropdownBox),
            );
            expect(tester.getSize(box).width, 110);
          }
          await tester.sendKeyEvent(
            tv ? LogicalKeyboardKey.select : LogicalKeyboardKey.enter,
          );
          await tester.pumpAndSettle();
          final unfocusedMenuLabel = find.text('50').last;
          expect(
            LineupTheme.of(tester.element(unfocusedMenuLabel)).primaryText,
            roles.primaryText,
            reason: 'Field focus ink must not be captured by the popup',
          );
          for (final value in [50, 100, 200, 300, 500, 750, 1000]) {
            final text = find.text('$value').last;
            expect(ink(text), LineupTheme.of(tester.element(text)).primaryText);
          }
          if (tv) {
            final last = tester.element(find.text('1000').last);
            for (var n = 0; n < 4; n++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pumpAndSettle();
            }
            expect(ink(find.text('1000').last), roles.onFocus);
            expect(ink(find.text('200').last), roles.primaryText);
            expect(tester.element(find.text('1000').last), same(last));
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await tester.pumpAndSettle();
            expect(tester.widget<DropdownButton<int>>(dropdown).value, 1000);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          FocusManager.instance.highlightStrategy = focusStrategy;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  for (final textScale in [1.0, 1.3]) {
    testWidgets(
      'TV limit dropdown accounts for all trigger and menu chrome: text=$textScale',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        final controller = _SetupController();
        try {
          await tester.runAsync(loadPinnedTestFonts);
          await _pump(tester, controller, isTv: true);
          await _advanceToConfigure(tester);
          await tester.tap(find.byKey(const ValueKey('configure-section-2')));
          await tester.pumpAndSettle();
          void fits(Finder text) {
            final element = tester.element(text);
            final widget = tester.widget<Text>(text);
            final painter = TextPainter(
              text: TextSpan(
                text: widget.data,
                style: DefaultTextStyle.of(element).style.merge(widget.style),
              ),
              textScaler: MediaQuery.textScalerOf(element),
              textDirection: Directionality.of(element),
            )..layout();
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(
              paragraph.size.width + .01,
              greaterThanOrEqualTo(painter.width),
              reason: 'Complete ${widget.data} must fit',
            );
            expect(
              paragraph.size.height,
              lessThanOrEqualTo(painter.height + .01),
              reason: '${widget.data} must stay single line',
            );
            painter.dispose();
          }

          for (final (name, choices) in [
            ('rules-maximum', [50, 100, 200, 300, 500, 750, 1000]),
            ('rules-minimum', [1, 5, 10, 20, 50]),
          ]) {
            final dropdown = find.byKey(ValueKey(name));
            await tester.ensureVisible(dropdown);
            await tester.pumpAndSettle();
            for (final value in choices) {
              await tester.tap(dropdown);
              await tester.pumpAndSettle();
              for (final option in choices) {
                fits(find.text('$option').last);
              }
              await tester.tap(find.text('$value').last);
              await tester.pumpAndSettle();
              fits(
                find.descendant(of: dropdown, matching: find.text('$value')),
              );
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  testWidgets(
    'TV playback cards leave the radio group vertically using remote keys',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      final controller = _SetupController();
      try {
        await tester.runAsync(loadPinnedTestFonts);
        await _pump(tester, controller, isTv: true);
        await _advanceToConfigure(tester);
        final section = find.byKey(const ValueKey('configure-section-1'));
        await tester.tap(section);
        await tester.pumpAndSettle();
        final label = find.descendant(
          of: section,
          matching: find.text('Playback order'),
        );
        // Fixture entry only. All subsequent movement is remote-only.
        Focus.of(tester.element(label)).requestFocus();
        await tester.pumpAndSettle();
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        bool inRadio() =>
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<RawRadio<PlaybackMode>>() !=
            null;
        await key(LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Setup playback shuffle',
        );
        await key(LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Setup playback sequential',
        );
        await key(LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Setup playback block',
        );
        await key(LogicalKeyboardKey.select);
        expect(find.text('Include specials'), findsOneWidget);
        await key(LogicalKeyboardKey.arrowDown);
        expect(inRadio(), isFalse, reason: 'Down must leave the radio group');
        await key(LogicalKeyboardKey.arrowDown);
        expect(inRadio(), isFalse);
        expect(
          Focus.of(tester.element(find.text('Back to libraries')))
              .hasPrimaryFocus,
          isTrue,
        );
        await key(LogicalKeyboardKey.select);
        expect(
          find.byKey(const ValueKey('library-selection-list')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.reset();
        FocusManager.instance.highlightStrategy = strategy;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      'playback card tracks actual focus independently of toggleable highlight: $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        final tv = platform == TargetPlatform.android;
        final controller = _SetupController();
        try {
          await _pump(tester, controller, isTv: tv);
          await _advanceToConfigure(tester);
          await tester.tap(find.byKey(const ValueKey('configure-section-1')));
          await tester.pumpAndSettle();
          final shuffle = find.byKey(const ValueKey('setup-playback-shuffle'));
          final sequential = find.byKey(
            const ValueKey('setup-playback-sequential'),
          );
          final element = tester.element(sequential);
          final radio = tester.widget<RawRadio<PlaybackMode>>(sequential);
          final roles = LineupTheme.of(tester.element(shuffle));
          final selectedNode = tester
              .widget<RawRadio<PlaybackMode>>(shuffle)
              .focusNode;
          // Enter through the section's real focus target, then move with D-pad.
          selectedNode.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(radio.focusNode.hasPrimaryFocus, isTrue);
          expect(
            (tester.state(sequential) as ToggleableStateMixin).states.contains(
              WidgetState.focused,
            ),
            isFalse,
          );
          final paint = _cardPaint(tester, sequential);
          expect(
            (paint.decoration as BoxDecoration).color,
            tv ? roles.focusedSurface : roles.elevatedSurface,
          );
          final title = tester.widget<Text>(
            find.descendant(of: sequential, matching: find.text('In order')),
          );
          expect(title.style!.color, tv ? roles.onFocus : roles.primaryText);
          expect(paint.foregroundDecoration, isNull);
          expect(tester.element(sequential), same(element));
          // Selection can change separately; moving back must repaint focus,
          // even while the selected sequential card remains selected.
          selectedNode.requestFocus();
          await tester.pumpAndSettle();
          expect(selectedNode.hasPrimaryFocus, isTrue);
          expect(
            (_cardPaint(tester, sequential).decoration as BoxDecoration).color,
            roles.elevatedSurface,
          );
          expect(
            (_cardPaint(tester, shuffle).decoration as BoxDecoration).color,
            tv ? roles.focusedSurface : roles.primarySurface,
          );
          final focused = FocusManager.instance.primaryFocus;
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 0));
          await mouse.moveTo(const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(
            (_cardPaint(tester, shuffle).decoration as BoxDecoration).color,
            roles.primarySurface,
          );
          expect(FocusManager.instance.primaryFocus, same(focused));
          expect(tester.element(sequential), same(element));
          await mouse.removePointer();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          FocusManager.instance.highlightStrategy = strategy;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'source-order row retains focus and hover backgrounds: $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final tv = platform == TargetPlatform.android;
        final controller = _SetupController();
        try {
          await _pump(tester, controller, isTv: tv);
          await _advanceToConfigure(tester);
          await tester.tap(find.byKey(const ValueKey('configure-section-2')));
          await tester.pumpAndSettle();
          final row = find.byKey(const ValueKey('source-order-recentlyAdded'));
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          final action = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Move later',
            ),
          );
          final focus = tester.widget<IconButton>(action).focusNode!;
          final roles = LineupTheme.of(tester.element(row));
          Color? background() =>
              (tester.widget<DecoratedBox>(row).decoration as BoxDecoration)
                  .color;
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(background(), Colors.transparent);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(
            background(),
            tv ? roles.focusedSurface : roles.primarySurface,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(0, 0));
          await mouse.moveTo(const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(background(), Colors.transparent);
          expect(focus.hasPrimaryFocus, isTrue);
          await mouse.moveTo(tester.getCenter(row));
          await tester.pumpAndSettle();
          expect(background(), roles.primarySurface);
          expect(focus.hasPrimaryFocus, isTrue);
          await mouse.removePointer();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  for (final tv in [false, true]) {
    testWidgets(
      'Configure entry gives TV first rail focus without an extra key TV=$tv',
      (tester) async {
        final controller = _SetupController();
        try {
          await tester.runAsync(loadPinnedTestFonts);
          await _pump(tester, controller, isTv: tv);
          await tester.pumpAndSettle();
          Future<void> activate(Finder button) async {
            final label = find
                .descendant(of: button, matching: find.byType(Text))
                .first;
            for (
              var i = 0;
              i < 80 && !Focus.of(tester.element(label)).hasFocus;
              i++
            ) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
            }
            expect(Focus.of(tester.element(label)).hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await tester.pumpAndSettle();
          }

          void expectEntry() {
            final rail = find.byKey(const ValueKey('configure-section-0'));
            final label = find.descendant(
              of: rail,
              matching: find.text('Channel sources'),
            );
            expect(Focus.of(tester.element(label)).hasPrimaryFocus, tv);
            if (tv) {
              final button = tester.widget<TextButton>(
                find.descendant(of: rail, matching: find.byType(TextButton)),
              );
              expect(
                button.style!.backgroundColor!.resolve({WidgetState.focused}),
                LineupTheme.of(tester.element(rail)).focusedSurface,
              );
            }
          }

          await activate(find.byKey(const ValueKey('scan-selected-libraries')));
          expectEntry();
          await activate(find.byKey(const ValueKey('review-channels')));
          expect(find.text('Back to configure'), findsOneWidget);
          await activate(find.widgetWithText(TextButton, 'Back to configure'));
          expectEntry();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
        }
      },
    );
  }
  for (final existing in [false, true]) {
    testWidgets(
      'TV Setup has a fixed footer and an initially complete Review row existing=$existing',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await tester.runAsync(loadPinnedTestFonts);
          final controller = _SetupController(
            channels: existing ? [_missingChannel] : [],
          );
          addTearDown(controller.dispose);
          await _pump(tester, controller, isTv: true);
          await _advanceToConfigure(tester);
          final configuration = find.byKey(
            const ValueKey('channel-configuration'),
          );
          expect(
            find.ancestor(of: configuration, matching: find.byType(Scrollable)),
            findsNothing,
          );
          final reviewButton = find.byKey(const ValueKey('review-channels'));
          final footerBounds = tester.getRect(reviewButton);
          expect(
            footerBounds.bottom,
            inInclusiveRange(540 - 48 * .5, 540 - 24 * .5),
          );
          await tester.drag(configuration, const Offset(0, -3000));
          await tester.pumpAndSettle();
          expect(tester.getRect(reviewButton), footerBounds);
          await tester.tap(reviewButton);
          await tester.pumpAndSettle();
          final roster = find.byKey(
            const ValueKey('channel-setup-review-roster'),
          );
          final row = find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> &&
                    (widget.key as ValueKey<String>).value.startsWith(
                      'review-channel-',
                    ),
              )
              .first;
          final viewport = tester.getRect(roster);
          final rowBounds = tester.getRect(row);
          expect(rowBounds.top, greaterThanOrEqualTo(viewport.top));
          expect(rowBounds.bottom, lessThanOrEqualTo(viewport.bottom));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  testWidgets('empty library recovery exposes quiet Sign out', (tester) async {
    final controller = _SetupController(
      scenario: LineupScenario(libraries: const []),
    );
    addTearDown(controller.dispose);
    var signOutCalls = 0;
    Widget buildSetup() => MaterialApp(
      builder: (context, child) =>
          LineupCanvas.builder(context, LineupFocusScope(child: child!)),
      theme: LineupTheme.forName(LineupThemeName.emberSteel),
      home: UpstreamChannelSetupView(
        controller: controller,
        onRequestLogout: () async {
          signOutCalls++;
        },
      ),
    );
    Future<void> pumpSetup() async {
      await tester.pumpWidget(buildSetup());
      await tester.pumpAndSettle();
    }

    await pumpSetup();

    expect(find.text('No movie or show libraries found'), findsOneWidget);
    expect(find.text('Switch server'), findsOneWidget);
    final signOut = find.widgetWithText(TextButton, 'Sign out');
    expect(signOut, findsOneWidget);
    expect(tester.widget<TextButton>(signOut).onPressed, isNotNull);
    controller.fixtureActor.present(LineupPresentation(busy: true));
    controller.notifyListeners();
    await pumpSetup();
    expect(tester.widget<TextButton>(signOut).onPressed, isNull);
    controller.fixtureActor.present(LineupPresentation(busy: false));
    controller.notifyListeners();
    await pumpSetup();
    expect(tester.widget<TextButton>(signOut).onPressed, isNotNull);
    await tester.tap(signOut);
    expect(signOutCalls, 1);
  });
  for (final index in [0, 1, 2]) {
    testWidgets(
      'TV playback card $index escapes upward without changing selection',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final controller = _SetupController();
        try {
          await tester.runAsync(loadPinnedTestFonts);
          await _pump(tester, controller, isTv: true);
          await _advanceToConfigure(tester);
          final section = find.byKey(const ValueKey('configure-section-1'));
          await tester.tap(section);
          await tester.pumpAndSettle();
          Focus.of(
            tester.element(
              find.descendant(
                of: section,
                matching: find.text('Playback order'),
              ),
            ),
          ).requestFocus();
          await tester.pumpAndSettle();
          for (var n = 0; n <= index; n++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
          }
          final cards = [
            for (final mode in PlaybackMode.values)
              find.byKey(ValueKey('setup-playback-${mode.name}')),
          ];
          List<bool> selection() => [
            for (final card in cards)
              (tester.state(card) as ToggleableStateMixin).states.contains(
                WidgetState.selected,
              ),
          ];
          final before = selection();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<RawRadio<PlaybackMode>>(),
            isNull,
          );
          expect(selection(), before);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'Mini-marathon counts exclude specials-only sources until enabled',
    (tester) async {
      final controller = _SetupController(
        media: [
          for (var i = 0; i < 5; i++)
            PlexMediaItem(
              id: 'special-$i',
              title: 'Special',
              type: 'episode',
              duration: const Duration(minutes: 20),
              libraryId: 'shows',
              grandparentRatingKey: 'show',
              seasonNumber: 0,
              episodeNumber: i,
              collections: const ['Collection'],
              parts: [PlexMediaPart(path: '/parts/$i')],
            ),
        ],
      );
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToConfigure(tester);
      final recent = find.widgetWithText(CheckboxListTile, 'Recently Added');
      await tester.ensureVisible(recent);
      await tester.tap(recent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('configure-section-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setup-playback-block')));
      await tester.pumpAndSettle();
      final summary = find.byKey(
        const ValueKey('configuration-allocation-summary'),
      );
      expect(
        find.descendant(of: summary, matching: find.text('0')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Channel limit reached'), findsNothing);

      final specials = find.widgetWithText(
        CheckboxMenuButton,
        'Include specials',
      );
      await tester.ensureVisible(specials);
      await tester.tap(specials);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: summary, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('review-channels')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('configure-section-0')));
      await tester.pumpAndSettle();
      final collections = find.widgetWithText(CheckboxListTile, 'Collections');
      expect(
        find.descendant(of: collections, matching: find.text('1 channel')),
        findsOneWidget,
      );
    },
  );

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
  for (final failure in [null, ...PlexCollectionFailure.values]) {
    final unavailable = failure != null;
    final scale = failure?.isScaleLimit == true;
    testWidgets('Collections $failure supports recovery', (tester) async {
      final controller = _SetupController(
        collectionDiscovery: failure == null ? {} : {'movies': failure},
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
          scale
              ? 'Collection limit exceeded in 1 library · Rescan'
              : unavailable
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
              find.descendant(of: retry, matching: find.byIcon(Icons.refresh)),
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
      expect(controller.collectionDiscoveryFailures, isEmpty);
      expect(
        find.textContaining(
          'Reduce the collection inventory in Plex before rescanning',
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('retry-discovery-collections')),
        findsNothing,
      );
    });
  }
  for (final failure in [
    PlexCollectionFailure.listingLimitExceeded,
    PlexCollectionFailure.memberLimitExceeded,
  ]) {
    testWidgets(
      'Choose libraries explains $failure and preserves saved channels',
      (tester) async {
        final controller = _SetupController(
          collectionDiscovery: {'movies': failure},
          channels: [_missingChannel],
        );
        addTearDown(controller.dispose);
        await _pump(tester, controller);
        await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
        await tester.pumpAndSettle();
        expect(find.text('Review your libraries'), findsOneWidget);
        expect(
          find.textContaining(
            'Reduce the collection inventory in Plex before rescanning',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('100000'), findsOneWidget);
        expect(find.text('Rescan after Plex changes'), findsWidgets);
        expect(controller.channels.single.id, _missingChannel.id);
        expect(
          controller.isGeneratedSourceConfirmedGone(_missingChannel),
          isFalse,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('retry-library-movies')),
        );
        await tester.tap(find.byKey(const ValueKey('retry-library-movies')));
        await tester.pumpAndSettle();
        expect(controller.collectionDiscoveryFailures, isEmpty);
        expect(
          find.textContaining(
            'Reduce the collection inventory in Plex before rescanning',
          ),
          findsNothing,
        );
        expect(find.text('Shape your lineup'), findsOneWidget);
        expect(controller.channels.single.id, _missingChannel.id);
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
      expect(controller.channels, contains(channelValue(_missingChannel)));
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
      final controller = _SetupController(channels: [_missingChannel]);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _advanceToConfigure(tester);
      controller.collectionFailures = {
        'movies': {'Retired collection'},
      };
      await tester.tap(find.byKey(const ValueKey('review-channels')));
      await tester.pumpAndSettle();
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
        final controller = _SetupController(channels: [channel]);
        await _pump(tester, controller);
        await _advanceToConfigure(tester);
        controller.playlistUnavailable = unavailable;
        controller.playlistFailures = unavailable ? {} : {'failed'};
        await tester.tap(find.byKey(const ValueKey('review-channels')));
        await tester.pumpAndSettle();
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

  for (final required in [false, true]) {
    testWidgets(
      'Continue offers only committable sources and footer retry recovers (required=$required)',
      (tester) async {
        final channel = Channel(
          id: 'saved',
          number: 1,
          name: 'Saved',
          source: LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            filters: required
                ? {
                    LibraryFilter.collection: ['Saved'],
                  }
                : {},
          ),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.utc(2026),
          shuffleSeed: 1,
        );
        final c =
            _SetupController(
                channels: [channel],
                collectionFailures: {
                  'movies': {'Saved'},
                },
              )
              ..ready = {'movies', 'shows', 'archive'}
              ..facts = {
                for (final id in ['movies', 'shows', 'archive'])
                  id: const LibraryScanFact(status: LibraryScanStatus.complete),
              }
              ..fixtureActor.reportScan(status: LibraryScanStatus.complete);
        addTearDown(c.dispose);
        await _pump(tester, c);
        expect(
          find.text('Continue with ${required ? 2 : 3} libraries'),
          findsOneWidget,
        );
        expect(find.text('Scan again'), findsOneWidget);
        await tester.tap(find.text('Shows'));
        await tester.tap(find.text('Long Form Archive'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('continue-ready-libraries')),
          required ? findsNothing : findsOneWidget,
        );
        expect(find.text('Scan again'), findsOneWidget);
        if (required) {
          expect(
            find.text(
              'No libraries are ready. Retry failed scans or change your selection.',
            ),
            findsOneWidget,
          );
          expect(find.text("Won't be used"), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('retry-failed-libraries')));
        await tester.pumpAndSettle();
        expect(c.footerRetries, 1);
        expect(c.committedIds, {'movies'});
        expect(find.text('Shape your lineup'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'required playlist failure offers Retry scan with retained library facts',
    (tester) async {
      final c =
          _SetupController(
              playlistFailures: {'saved'},
              channels: [
                Channel(
                  id: 'saved',
                  number: 1,
                  name: 'Saved',
                  source: const PlaylistSource('saved'),
                  playbackMode: PlaybackMode.sequential,
                  anchor: DateTime.utc(2026),
                  shuffleSeed: 1,
                ),
              ],
            )
            ..ready = {'movies', 'shows', 'archive'}
            ..facts = {
              for (final id in ['movies', 'shows', 'archive'])
                id: const LibraryScanFact(status: LibraryScanStatus.complete),
            }
            ..fixtureActor.reportScan(status: LibraryScanStatus.complete);
      addTearDown(c.dispose);
      await _pump(tester, c);
      expect(
        find.byKey(const ValueKey('continue-ready-libraries')),
        findsNothing,
      );
      expect(find.text('Retry scan'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
      await tester.tap(find.text('Retry scan'));
      await tester.pumpAndSettle();
      expect(c.footerRetries, 1);
      expect(find.text('Shape your lineup'), findsOneWidget);
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
      expect(find.text('3 Review'), findsOneWidget);
      expect(find.text('✓ Review'), findsNothing);
      expect(find.text('+ Added'), findsWidgets);
      expect(find.text('＋ Added'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
      await tester.pump();
      expect(find.text('3 Review'), findsOneWidget);
      expect(find.text('✓ Review'), findsNothing);
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

  for (final replace in [false, true]) {
    testWidgets(
      'fast failed apply retains confirmed review choices (replace: $replace)',
      (tester) async {
        final original = [_missingChannel];
        final controller = _SetupController(
          channels: original,
          failApply: true,
        );
        addTearDown(controller.dispose);
        final committedBefore = controller.channels;
        await _pump(tester, controller);
        await _advanceToReview(tester);
        if (replace) {
          await tester.tap(find.text('Replace generated channels'));
        } else {
          final choice = find.byKey(
            const ValueKey('missing-source-choice-missing'),
          );
          await tester.ensureVisible(choice);
          await tester.tap(
            find.descendant(of: choice, matching: find.text('Remove')),
          );
        }
        await tester.pumpAndSettle();
        final confirmation = find.byKey(
          const ValueKey('channel-setup-replace-confirmation'),
        );
        await tester.ensureVisible(confirmation);
        await tester.tap(confirmation);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('apply-reviewed-lineup')));
        await tester.pumpAndSettle();
        expect(find.text('We couldn’t update your lineup'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Back to review'),
              )
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        expect(find.text('3 Review'), findsOneWidget);
        expect(find.text('✓ Review'), findsNothing);
        expect(
          tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
          isTrue,
        );
        expect(
          find.text('Your existing lineup hasn’t changed.'),
          findsOneWidget,
        );
        expect(find.text('Your setup choices are still here.'), findsOneWidget);
        expect(find.text('The lineup could not be saved.'), findsOneWidget);
        expect(controller.channels, same(committedBefore));

        if (replace) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('Back to review'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Review your lineup'), findsOneWidget);
        expect(find.text('Update and add'), findsOneWidget);
        expect(find.text('The lineup could not be saved.'), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(confirmation).value, isTrue);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('apply-reviewed-lineup')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<LineupSegmentedControl<ChannelBuildMode>>(
                find.byKey(const ValueKey('review-build-method')),
              )
              .selected,
          {replace ? ChannelBuildMode.replace : ChannelBuildMode.merge},
        );
        if (!replace) {
          final choice = find.byKey(
            const ValueKey('missing-source-choice-missing'),
          );
          await tester.scrollUntilVisible(
            choice,
            150,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('channel-setup-review-roster')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(tester.widget<LineupSegmentedControl<bool>>(choice).selected, {
            true,
          });
        }
      },
    );
  }

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
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'View lineup'),
            )
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
      expect(
        tester.widget<LineupTopBar>(find.byType(LineupTopBar)).divider,
        isFalse,
      );
      for (final label in ['✓ Libraries', '✓ Configure', '✓ Review']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('in your lineup'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(viewed, 1);
      await tester.tap(find.text('Add a custom channel'));
      await tester.tap(find.text('View lineup'));
      expect(added, 1);
      expect(viewed, 2);
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

void _expectLibraryEntryPaint(WidgetTester tester) {
  final button = find.widgetWithText(TextButton, 'Select all');
  final node = tester.widget<TextButton>(button).focusNode!;
  expect(node.hasPrimaryFocus, isTrue);
  expect(node.canRequestFocus, isTrue);
  expect(node.context?.mounted, isTrue);
  final roles = LineupTheme.of(tester.element(button));
  final material = tester.widget<Material>(
    find.descendant(of: button, matching: find.byType(Material)).first,
  );
  expect(material.color, roles.focusedSurface);
  final label = find.descendant(of: button, matching: find.text('Select all'));
  final rich = tester.widget<RichText>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  expect(rich.text.style?.color, roles.focusSecondaryText);
  expect(
    tester
        .getRect(button)
        .overlaps(
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
        ),
    isTrue,
  );
}

void _expectSingleLibraryEntryPaint(WidgetTester tester) {
  final row = find.byKey(const ValueKey('library-row-movies'));
  final node = tester.widget<InkWell>(row).focusNode!;
  expect(node.hasPrimaryFocus, isTrue);
  expect(node.canRequestFocus, isTrue);
  expect(node.context?.mounted, isTrue);
  expect(
    tester
        .getRect(row)
        .overlaps(
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
        ),
    isTrue,
  );
  final ink = find
      .ancestor(of: row, matching: find.byType(LineupFocusInk))
      .first;
  expect(tester.widget<LineupFocusInk>(ink).focused, isTrue);
  final label = find.descendant(of: row, matching: find.text('Movies')).first;
  final roles = LineupTheme.of(
    tester.element(find.byType(UpstreamChannelSetupView)),
  );
  expect(tester.widget<Text>(label).style!.color, roles.onFocus);
}

Future<void> _pump(
  WidgetTester tester,
  LineupController controller, {
  VoidCallback? onView,
  VoidCallback? onAdd,
  bool isTv = false,
  double? reviewRenderScale,
}) async {
  tester.view
    ..physicalSize = isTv ? const Size(1920, 1080) : const Size(1280, 720)
    ..devicePixelRatio = isTv ? 2 : 1;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => DeviceProfileScope(
        profile: profileFor(isTv),
        child: reviewRenderScale == null
            ? LineupCanvas.builder(context, LineupFocusScope(child: child!))
            : RepaintBoundary(
                key: const ValueKey('review-page-raster'),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(reviewRenderScale),
                    disableAnimations: true,
                  ),
                  child: LineupCanvas.builder(
                    context,
                    LineupFocusScope(child: child!),
                  ),
                ),
              ),
      ),
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        formFactor: profileFor(isTv).formFactor,
        largeFocusIndicators: reviewRenderScale == 1.3,
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => UpstreamChannelSetupView(
          controller: controller,
          onViewLineup: onView,
          onAddCustomChannel: onAdd,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpRetainedSetup(
  WidgetTester tester,
  LineupController controller,
  GlobalKey<_RetainedSetupHostState> hostKey,
) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => DeviceProfileScope(
        profile: profileFor(true),
        child: LineupCanvas.builder(context, LineupFocusScope(child: child!)),
      ),
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        formFactor: profileFor(true).formFactor,
      ),
      home: _RetainedSetupHost(key: hostKey, controller: controller),
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

class _RetainedSetupHost extends StatefulWidget {
  const _RetainedSetupHost({required this.controller, super.key});

  final LineupController controller;

  @override
  State<_RetainedSetupHost> createState() => _RetainedSetupHostState();
}

class _RetainedSetupHostState extends State<_RetainedSetupHost> {
  bool _inactive = false;
  final supportFocus = FocusNode(debugLabel: 'Visible Support owner');

  void hide() {
    setState(() => _inactive = true);
    supportFocus.requestFocus();
  }

  @override
  void dispose() {
    supportFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Offstage(
        offstage: _inactive,
        child: ExcludeFocus(
          excluding: _inactive,
          child: UpstreamChannelSetupView(controller: widget.controller),
        ),
      ),
      Align(
        alignment: Alignment.topRight,
        child: TextButton(
          focusNode: supportFocus,
          onPressed: () {},
          child: const Text('Support owner'),
        ),
      ),
    ],
  );
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

Future<
  ({LineupController controller, _BoundaryStore store, _BoundaryPlex plex})
>
_createBoundarySetup() async {
  final store = _BoundaryStore(
    initial: const PersistedState(
      profileId: 'owner',
      selectedServerByProfile: {'owner': 'server'},
    ),
  );
  final plex = _BoundaryPlex();
  final controller = LineupController(
    store: store,
    credentials: MemoryCredentialStore(accountToken: 'account-token'),
    plex: plex,
  );
  await controller.initialize();
  expect(controller.stage, SetupStage.channelSetup);
  return (controller: controller, store: store, plex: plex);
}

final _boundaryServer = PlexServer(
  id: 'server',
  name: 'Boundary server',
  connections: [
    PlexConnection(
      uri: Uri.parse('https://boundary.invalid'),
      local: true,
      relay: false,
    ),
  ],
);

const _boundaryLibrary = PlexLibrary(
  id: 'movies',
  title: 'Movies',
  type: PlexLibraryType.movie,
);

final _boundaryMediaItem = PlexMediaItem(
  id: 'boundary-movie',
  title: 'Boundary movie',
  type: 'movie',
  duration: const Duration(minutes: 30),
  libraryId: 'movies',
  parts: [PlexMediaPart(path: '/boundary/movie')],
);

class _BoundaryStore extends MemoryAppStore {
  _BoundaryStore({required PersistedState initial}) : super(initial: initial);

  Completer<void> saveStarted = Completer<void>();
  Completer<void>? _saveGate;
  bool _failBlockedSave = false;
  int saveCalls = 0;

  void blockNext({required bool fail}) {
    saveStarted = Completer<void>();
    _saveGate = Completer<void>();
    _failBlockedSave = fail;
  }

  void releaseBlockedSave() => _saveGate!.complete();

  @override
  Future<void> save(PersistedState value) async {
    saveCalls++;
    final gate = _saveGate;
    if (gate != null) {
      saveStarted.complete();
      await gate.future;
      _saveGate = null;
      final fail = _failBlockedSave;
      _failBlockedSave = false;
      if (fail) throw StateError('synthetic boundary save failure');
    }
    await super.save(value);
  }
}

class _BoundaryPlex extends PlexClient {
  _BoundaryPlex()
    : super(
        clientIdentifier: 'lineup-desktop-boundary-client',
        httpClient: testPlexHttpClient(),
      );

  Completer<PlexLibraryScan>? scanGate;
  final scanStarted = Completer<void>();

  @override
  Future<PlexAccount> account(String token) async => const PlexAccount(
    id: 'owner',
    name: 'Owner',
    email: 'owner@example.invalid',
  );

  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => const [
    PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
  ];

  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    PlexServerAccess(server: _boundaryServer, token: 'pms-token'),
  ];

  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async => server.connections.single;

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async => const [
    _boundaryLibrary,
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
  }) async {
    onPhase?.call(PlexLibraryScanPhase.items);
    if (!scanStarted.isCompleted) scanStarted.complete();
    final gate = scanGate;
    if (gate != null) return gate.future;
    return PlexLibraryScan(
      items: [
        for (var index = 0; index < 5; index++)
          PlexMediaItem(
            id: 'movie-$index',
            title: 'Movie $index',
            type: 'movie',
            libraryId: 'movies',
            duration: const Duration(minutes: 30),
            parts: [PlexMediaPart(path: '/synthetic/movie-$index')],
          ),
      ],
    );
  }

  @override
  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress)? onProgress,
  }) async => const PlexPlaylistCatalog(playlists: [], failedIds: {});
}

class _SetupController extends FixtureController {
  _SetupController({
    LineupScenario? scenario,
    this.mixedScan = false,
    this.blockScan = false,
    this.staleOnce = false,
    this.failApply = false,
    this.playlistUnavailable = false,
    this.playlistFailures = const {},
    this.collectionDiscovery = const {},
    this.collectionFailures = const {},
    List<Channel> channels = const [],
    List<PlexMediaItem>? media,
    List<PlexPlaylist> playlists = const [],
  }) : super(
         scenario: (scenario ?? const LineupScenario()).withDefaults(
           LineupScenario(
             libraries: _libraries,
             channels: channels,
             availableMedia: media ?? _media,
             availablePlaylists: playlists,
           ),
         ),
       ) {
    _fixtureMedia = media ?? _media;
  }

  late final List<PlexMediaItem> _fixtureMedia;

  bool playlistUnavailable;
  Set<String> playlistFailures;
  Map<String, PlexCollectionFailure> collectionDiscovery;
  Map<String, Set<String>> collectionFailures;
  @override
  bool get playlistCatalogUnavailable => playlistUnavailable;
  @override
  Set<String> get failedPlaylistIds => playlistFailures;
  @override
  Map<String, PlexCollectionFailure> get collectionDiscoveryFailures =>
      collectionDiscovery;
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
  int commitCalls = 0;
  int footerRetries = 0;
  Completer<void>? applyGate;
  Completer<void>? commitGate;
  Set<String>? rowRetryIds;
  Set<String>? rowRetryInventory;

  @override
  Future<bool> retryLibraryScan(Set<String> ids, Set<String> retryIds) {
    playlistUnavailable = false;
    playlistFailures = {};
    collectionDiscovery = {};
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
  Set<String> get libraryScanRetryIds => {
    ...retry,
    ...collectionDiscovery.keys.where(facts.containsKey),
    ...collectionFailures.keys.where(facts.containsKey),
  };

  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    if (retryFailedOnly) {
      footerRetries++;
      collectionDiscovery = {};
      collectionFailures = {};
      playlistUnavailable = false;
      playlistFailures = {};
    }
    if (blockScan) {
      fixtureActor.reportScan(status: LibraryScanStatus.scanning);
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
      fixtureActor.reportScan(status: LibraryScanStatus.transientFailure);
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
      fixtureActor.reportScan(status: LibraryScanStatus.complete);
    }
    notifyListeners();
    return true;
  }

  @override
  void cancelLibraryScan() {
    ready = const {};
    fixtureActor.reportScan(status: LibraryScanStatus.cancelled);
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
    commitCalls++;
    if (commitGate != null) await commitGate!.future;
    committedIds = Set.unmodifiable(readyIds);
    fixtureActor.publishInventory(selectedLibraryIds: committedIds);
    fixtureActor.publishInventory(
      media: _fixtureMedia
          .where((item) => readyIds.contains(item.libraryId))
          .toList(),
    );
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
    fixtureActor.replaceChannels(
      composeChannelPlan(
        existing: channels
            .where((channel) => !removeChannelIds.contains(channel.id))
            .toList(),
        planned: planned,
        mode: mode,
      ),
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
