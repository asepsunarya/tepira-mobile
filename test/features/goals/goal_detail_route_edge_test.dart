import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_detail_screen.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_today_repository.dart';

/// Independent edge cases for how the real router turns `/goal/:id` into a
/// goal id (T8, 578adf7). The id comes from `GoalRoutes.parseId`: positive
/// int32 decimal digits only, as the server accepts nothing else.
void main() {
  Future<(ProviderContainer, FakeGoalsRepository)> pumpApp(
    WidgetTester tester, {
    List<Object>? detailResults,
  }) async {
    final goals = FakeGoalsRepository(
      [
        [testGoal()],
      ],
      detailResults: detailResults ??
          [GoalDetail(goal: testGoal(id: 12), contributions: const [])],
    );
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(restoredUser: testUser),
        ),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
        goalsRepositoryProvider.overrideWithValue(goals),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TepiraApp(),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pumpAndSettle();
    return (container, goals);
  }

  int? shownId(WidgetTester tester) =>
      tester.widget<GoalDetailScreen>(find.byType(GoalDetailScreen)).goalId;

  for (final path in [
    '/goal/12abc',
    '/goal/1.5',
    '/goal/1e3',
    '/goal/%20',
    // Beyond int64: int.tryParse gives null.
    '/goal/99999999999999999999',
    // Not decimal digits, or not positive: the server would 404 these.
    '/goal/0x0C',
    '/goal/-3',
    '/goal/+12',
    '/goal/0',
    '/goal/000',
    // Above the int32 maximum, which is the largest id the server accepts.
    '/goal/2147483648',
    '/goal/3000000000',
  ]) {
    testWidgets('$path shows the missing goal without a request',
        (tester) async {
      final (container, goals) = await pumpApp(tester);

      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();

      expect(shownId(tester), isNull);
      expect(find.text('Kavling tidak ditemukan'), findsOneWidget);
      expect(goals.detailIds, isEmpty);
    });
  }

  testWidgets('/goal/012 (leading zeros) opens goal 12', (tester) async {
    final (container, goals) = await pumpApp(tester);

    container.read(routerProvider).go('/goal/012');
    await tester.pumpAndSettle();

    expect(shownId(tester), 12);
    expect(goals.detailIds, [12]);
  });

  testWidgets('/goal/2147483647 (int32 maximum) opens that goal',
      (tester) async {
    final (container, goals) = await pumpApp(
      tester,
      detailResults: [
        GoalDetail(goal: testGoal(id: 2147483647), contributions: const []),
      ],
    );

    container.read(routerProvider).go('/goal/2147483647');
    await tester.pumpAndSettle();

    expect(shownId(tester), 2147483647);
    expect(goals.detailIds, [2147483647]);
  });
}
