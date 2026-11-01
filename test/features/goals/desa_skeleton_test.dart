import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/widgets/desa_skeleton.dart';

import '../../core/widgets/village_test_app.dart';

const _caption = 'Si penabung sedang berjalan ke desa…';

/// Pumps the skeleton with reduced motion so the pulse stops and the frame
/// settles.
Future<void> _pumpStill(WidgetTester tester, {Size? size}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = size ?? const Size(390, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpVillage(
    tester,
    SizedBox(
      width: (size?.width ?? 390) - 32,
      height: (size?.height ?? 600) - 32,
      child: const DesaSkeleton(),
    ),
  );
}

void main() {
  testWidgets('shows the SkeletonDesa caption', (tester) async {
    await _pumpStill(tester);
    expect(find.text(_caption), findsOneWidget);
  });

  testWidgets('the caption does not pulse with the bars', (tester) async {
    await _pumpStill(tester);
    // Only fades inside the skeleton count; the route adds its own.
    final skeletonFades = find.descendant(
      of: find.byType(DesaSkeleton),
      matching: find.byType(FadeTransition),
    );
    expect(skeletonFades, findsNWidgets(2));
    expect(
      find.descendant(of: skeletonFades, matching: find.text(_caption)),
      findsNothing,
    );
  });

  testWidgets('reads only as "Memuat desa" to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpStill(tester);
    expect(find.bySemanticsLabel('Memuat desa'), findsOneWidget);
    expect(find.bySemanticsLabel(_caption), findsNothing);
    handle.dispose();
  });

  testWidgets('the caption fits a narrow screen with large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpStill(tester, size: const Size(320, 600));
    expect(find.text(_caption), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('matches the golden', (tester) async {
    await _pumpStill(tester, size: const Size(390, 520));
    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/desa_skeleton.png'),
    );
  });
}
