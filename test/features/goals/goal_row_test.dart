import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_row.dart';

import '../../core/widgets/village_test_app.dart';
import '../../helpers/fake_goals_repository.dart';

void main() {
  testWidgets('one row per stage matches the golden', (tester) async {
    tester.view.physicalSize = const Size(390, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpVillage(
      tester,
      SizedBox(
        width: 358,
        child: Column(
          children: [
            for (final (title, saved) in [
              ('Liburan Lombok', 0),
              ('Liburan ke Bali', 1200000),
              ('Dana darurat', 4200000),
              ('Laptop baru', 8750000),
              ('Sepeda lipat', 12000000),
            ]) ...[
              GoalRow(
                goal: testGoal(title: title, saved: saved, target: 12000000),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );

    await expectLater(
      find.byKey(goldenKey),
      matchesGoldenFile('goldens/goal_row.png'),
    );
  });

  testWidgets('reads as one button with title, stage, amounts and percent',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpVillage(
      tester,
      GoalRow(
        goal: testGoal(title: 'Dana darurat', saved: 3450000),
        onTap: () {},
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Dana darurat, tahap Dinding, Rp3.450.000 dari Rp10.000.000, 34%',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
