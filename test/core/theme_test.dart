import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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

  test('every Material text style is lifted to a bundled weight', () {
    final t = buildVillageTheme().textTheme;
    final all = {
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };

    for (final MapEntry(:key, :value) in all.entries) {
      expect(value, isNotNull, reason: key);
      expect(value!.fontFamily, startsWith('Nunito'), reason: key);
      expect(
        [FontWeight.w700, FontWeight.w800, FontWeight.w900],
        contains(value.fontWeight),
        reason: key,
      );
    }
  });

  testWidgets(
    'theme fonts load from assets with runtime fetching disabled',
    (tester) async {
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
      buildVillageTheme();
      for (final w in [FontWeight.w700, FontWeight.w800, FontWeight.w900]) {
        villageText(fontSize: 14, fontWeight: w);
      }

      // A weight missing from assets/fonts would need a network fetch, which
      // is disabled; in flutter_test that surfaces as a hang, hence the timeout.
      await tester.runAsync(GoogleFonts.pendingFonts);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('villageText rejects weights that are not bundled', () {
    expect(
      () => villageText(fontSize: 14, fontWeight: FontWeight.w400),
      throwsAssertionError,
    );
  });

  test('VillageColors.lerp hits both ends', () {
    const a = VillageColors.light;
    final b = a.copyWith(pink: const Color(0xFF000000));

    expect(a.lerp(b, 0).pink, a.pink);
    expect(a.lerp(b, 1).pink, const Color(0xFF000000));
    expect(a.lerp(null, 0.5), a);
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
