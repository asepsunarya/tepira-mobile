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

  testWidgets('exposes one progress-bar node labelled only with the percent',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const GoalProgress(saved: 250000, target: 1000000));

    // The caption must not be merged into (or duplicate) the label.
    expect(find.bySemanticsLabel(RegExp('dari target')), findsNothing);
    final node = tester.getSemantics(find.bySemanticsLabel('Progres 25%'));
    expect(node.label, 'Progres 25%');
    expect(node.value, contains('25'));
    handle.dispose();
  });

  for (final (saved, target, percent) in [
    (0, 1000000, 0),
    (1500000, 1000000, 100),
    (50000, 0, 0),
    (1, 3, 33),
  ]) {
    testWidgets('semantics label is "Progres $percent%" for $saved/$target',
        (tester) async {
      await _pump(tester, GoalProgress(saved: saved, target: target));

      expect(find.bySemanticsLabel('Progres $percent%'), findsOneWidget);
    });
  }

  testWidgets('caps at 100% when saved exceeds the target', (tester) async {
    await _pump(tester, const GoalProgress(saved: 1500000, target: 1000000));

    expect(find.text('100% dari target'), findsOneWidget);
  });

  testWidgets('shows 0% when the target is zero', (tester) async {
    await _pump(tester, const GoalProgress(saved: 50000, target: 0));

    expect(find.text('0% dari target'), findsOneWidget);
  });
}
