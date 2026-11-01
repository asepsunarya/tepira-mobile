import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_progress.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('shows 25% when a quarter of the target is saved',
      (tester) async {
    await _pump(tester, const GoalProgress(saved: 250000, target: 1000000));

    expect(find.text('25% dari target'), findsOneWidget);
    expect(find.bySemanticsLabel('Progres 25%'), findsOneWidget);
  });

  testWidgets('caps at 100% when saved exceeds the target', (tester) async {
    await _pump(tester, const GoalProgress(saved: 1500000, target: 1000000));

    expect(find.text('100% dari target'), findsOneWidget);
  });

  testWidgets('shows 0% when the target is zero', (tester) async {
    await _pump(tester, const GoalProgress(saved: 50000, target: 0));

    expect(find.text('0% dari target'), findsOneWidget);
  });
}
