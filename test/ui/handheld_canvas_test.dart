import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);

void main() {
  const handheldWindows = [
    Size(360, 800),
    Size(412, 915),
    Size(915, 412),
    Size(599, 960),
    Size(600, 960),
    Size(690, 840),
    Size(800, 1280),
    Size(839, 960),
    Size(840, 960),
    Size(960, 600),
    Size(1279, 800),
    Size(1280, 719),
  ];
  test('only the full 1280 by 720 window threshold selects Wide', () {
    for (final size in handheldWindows) {
      expect(LineupCanvas.scaleFor(size, formFactor: FormFactor.handheld), .9);
      expect(
        LineupCanvas.compositionFor(size, formFactor: FormFactor.handheld),
        LineupComposition.handheld,
      );
    }
    for (final size in [
      const Size(1280, 720),
      const Size(1280, 800),
      const Size(1920, 1080),
      const Size(2560, 1440),
    ]) {
      expect(
        LineupCanvas.compositionFor(size, formFactor: FormFactor.handheld),
        LineupComposition.wide,
      );
      expect(
        LineupCanvas.scaleFor(size, formFactor: FormFactor.handheld),
        LineupCanvas.scaleFor(size),
      );
    }
  });

  test(
    'portrait composition is Handheld-only and uses strict 933 canvas units',
    () {
      for (final size in [
        const Size(360, 800),
        const Size(412, 915),
        const Size(600, 960),
        const Size(690, 840),
        const Size(800, 1280),
        const Size(839.69, 600),
      ]) {
        expect(
          LineupCanvas.usesPortraitCompositionFor(
            size,
            formFactor: FormFactor.handheld,
          ),
          isTrue,
          reason: '$size',
        );
      }
      for (final size in [
        const Size(839.7, 600),
        const Size(840, 600),
        const Size(915, 412),
        const Size(960, 600),
        const Size(1279, 800),
        const Size(1280, 719),
        const Size(1280, 720),
        const Size(1280, 800),
      ]) {
        expect(
          LineupCanvas.usesPortraitCompositionFor(
            size,
            formFactor: FormFactor.handheld,
          ),
          isFalse,
          reason: '$size',
        );
      }
      for (final form in [FormFactor.desktop, FormFactor.tv]) {
        expect(
          LineupCanvas.usesPortraitCompositionFor(
            const Size(412, 915),
            formFactor: form,
          ),
          isFalse,
        );
      }
    },
  );

  testWidgets('resize preserves the child state, scaler and converted insets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1280, 800) * 2;
    addTearDown(tester.view.reset);
    const scaler = _SyntheticNonlinearScaler();
    var count = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    late StateSetter update;
    late BuildContext canvasContext;
    final child = StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        canvasContext = context;
        return Column(
          children: [
            Text('$count'),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 100, child: Text('Row $i')),
                ],
              ),
            ),
          ],
        );
      },
    );
    await tester.pumpWidget(
      DeviceProfileScope(
        profile: _handheld,
        child: MaterialApp(
          builder: (context, route) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: scaler,
              padding: const EdgeInsets.only(top: 24),
              viewInsets: const EdgeInsets.only(bottom: 200),
            ),
            child: LineupCanvas(child: route!),
          ),
          home: child,
        ),
      ),
    );
    update(() => count = 7);
    await tester.pump();
    scroll.jumpTo(100);
    await tester.pump();
    final element = tester.element(find.byWidget(child));
    for (final window in [
      const Size(800, 1280),
      const Size(599, 960),
      const Size(1280, 720),
    ]) {
      tester.view.physicalSize = window * 2;
      await tester.pump();
      final scale = LineupCanvas.scaleFor(
        window,
        formFactor: FormFactor.handheld,
      );
      expect(tester.element(find.byWidget(child)), same(element));
      expect(find.text('7'), findsOneWidget);
      expect(scroll.offset, 100);
      expect(LineupCanvas.windowSizeOf(canvasContext), window);
      expect(LineupCanvas.scaleOf(canvasContext), scale);
      expect(MediaQuery.textScalerOf(canvasContext), same(scaler));
      expect(MediaQuery.paddingOf(canvasContext).top, 24 / scale);
      expect(MediaQuery.viewInsetsOf(canvasContext).bottom, 200 / scale);
    }
  });

  for (final window in [
    const Size(412, 915),
    const Size(1280, 800),
    const Size(2560, 1440),
  ]) {
    testWidgets(
      'touch space is at least 48 window dp and disjoint at $window',
      (tester) async {
        tester.view
          ..physicalSize = window
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final taps = [0, 0];
        await tester.pumpWidget(
          DeviceProfileScope(
            profile: _handheld,
            child: MaterialApp(
              builder: LineupCanvas.builder,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 2; i++)
                        LineupTouchTarget(
                          key: ValueKey('target-$i'),
                          onPressed: () => taps[i]++,
                          child: SizedBox(
                            key: ValueKey('visual-$i'),
                            width: 24,
                            height: 24,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final scale = LineupCanvas.scaleFor(
          window,
          formFactor: FormFactor.handheld,
        );
        final first = tester.getRect(find.byKey(const ValueKey('target-0')));
        final second = tester.getRect(find.byKey(const ValueKey('target-1')));
        expect(first.width, greaterThanOrEqualTo(48));
        expect(first.height, greaterThanOrEqualTo(48));
        expect(first.overlaps(second), isFalse);
        expect(
          tester.getRect(find.byKey(const ValueKey('visual-0'))).size,
          Size(24 * scale, 24 * scale),
        );
        await tester.tapAt(first.topLeft + const Offset(1, 1));
        await tester.tapAt(second.bottomRight - const Offset(1, 1));
        expect(taps, [1, 1]);
      },
    );
  }
  for (final window in [const Size(412, 915), const Size(1280, 800)]) {
    testWidgets(
      'owned header/menu/link/arrow primitives have no undersized semantic tap region at $window',
      (tester) async {
        tester.view
          ..physicalSize = window
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        final menuFocus = FocusNode();
        addTearDown(menuFocus.dispose);
        await tester.pumpWidget(
          DeviceProfileScope(
            profile: _handheld,
            child: MaterialApp(
              builder: LineupCanvas.builder,
              home: Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LineupTopBar(
                      menuFocusNode: menuFocus,
                      onOpenMenu: (_, _) {},
                    ),
                    LineupNavigationRow(
                      selected: false,
                      onPressed: () {},
                      child: const Text('Guide'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: LineupInlineLink(
                        onPressed: () {},
                        child: const Text('Back'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: lineupArrowButton(
                        icon: Icons.arrow_upward,
                        tooltip: 'Move up',
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final targets = find.semantics
            .byAction(ui.SemanticsAction.tap)
            .evaluate()
            .where((node) => !node.isInvisible && !node.isMergedIntoParent)
            .toList();
        expect(targets.length, greaterThanOrEqualTo(4));
        for (final node in targets) {
          var rect = node.rect;
          for (
            SemanticsNode? current = node;
            current != null;
            current = current.parent
          ) {
            if (current.transform case final transform?) {
              rect = MatrixUtils.transformRect(transform, rect);
            }
          }
          expect(
            rect.width,
            greaterThanOrEqualTo(48 - 1e-6),
            reason: node.getSemanticsData().label,
          );
          expect(
            rect.height,
            greaterThanOrEqualTo(48 - 1e-6),
            reason: node.getSemanticsData().label,
          );
        }
        semantics.dispose();
      },
    );
  }
}

/// A deliberately synthetic nonlinear scaler tests pass-through only. Device
/// acceptance must collect Android's real curve rather than call this Android.
class _SyntheticNonlinearScaler extends TextScaler {
  const _SyntheticNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize >= 28 ? 1.4 : 2);
  @override
  double get textScaleFactor => 2;
}
