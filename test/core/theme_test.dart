import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_progress.dart';

void main() {
  test('exposes the village palette as a theme extension', () {
    final theme = buildVillageTheme();

    expect(theme.extension<VillageColors>(), VillageColors.light);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, VillageColors.light.langit);
  });

  test('uses bundled Nunito weights for every text style', () {
    final styles = buildVillageTheme().textTheme;
    final all = [
      styles.displayLarge,
      styles.headlineMedium,
      styles.titleMedium,
      styles.bodyMedium,
      styles.labelSmall,
    ];

    for (final style in all) {
      expect(style!.fontFamily, startsWith('Nunito'));
      expect(style.fontWeight!.value, greaterThanOrEqualTo(700));
    }
  });

  testWidgets('GoalProgress picks up the theme progress colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVillageTheme(),
        home: const Scaffold(body: GoalProgress(saved: 1, target: 4)),
      ),
    );

    final context = tester.element(find.byType(LinearProgressIndicator));
    final progressTheme = ProgressIndicatorTheme.of(context);
    expect(progressTheme.color, VillageColors.light.pink);
    expect(progressTheme.linearTrackColor, VillageColors.light.track);
  });
}
