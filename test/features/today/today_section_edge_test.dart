import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart'
    show goalsRepositoryProvider;
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_row.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';
import 'package:tepira_mobile/features/today/widgets/safe_today_card.dart';

import '../../core/widgets/village_test_app.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_today_repository.dart';

class _Clock {
  _Clock(this.now);
  DateTime now;
}

Future<void> _pumpDesa(
  WidgetTester tester,
  FakeTodayRepository today,
  _Clock clock,
) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const GoalsScreen(userName: 'Asep'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayRepositoryProvider.overrideWithValue(today),
        goalsRepositoryProvider.overrideWithValue(
          FakeGoalsRepository([
            [testGoal(title: 'Dana darurat')],
          ]),
        ),
        clockProvider.overrideWithValue(() => clock.now),
      ],
      child: MaterialApp.router(
        theme: buildVillageTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

/// Every text and the semantics label of the card, lower case.
String _cardWords(WidgetTester tester) {
  final card = find.byKey(const Key('safe-today'));
  final texts = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((t) => t.data ?? '');
  final semantics = tester
      .widgetList<Semantics>(
        find.ancestor(of: card, matching: find.byType(Semantics)),
      )
      .map((s) => s.properties.label ?? '');
  return [...texts, ...semantics].join(' | ').toLowerCase();
}

void main() {
  group('00:00 WIB rollover', () {
    testWidgets('reloads on 1 Dec 00:00 WIB, then waits a full day',
        (tester) async {
      final today = FakeTodayRepository.budget();
      // 30 Nov 23:59:30 WIB.
      final clock = _Clock(DateTime.utc(2026, 11, 30, 16, 59, 30));
      await _pumpDesa(tester, today, clock);
      expect(today.calls, 1);

      clock.now = DateTime.utc(2026, 11, 30, 17);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(today.calls, 2);

      // An hour later (01:00 WIB) no further reload.
      clock.now = DateTime.utc(2026, 11, 30, 18);
      await tester.pump(const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect(today.calls, 2);

      // The next one is 2 Dec 00:00 WIB, 24 h after the first.
      clock.now = DateTime.utc(2026, 12, 1, 17);
      await tester.pump(const Duration(hours: 23));
      await tester.pumpAndSettle();
      expect(today.calls, 3);
    });

    testWidgets('reloads at the year turn (1 Jan 00:00 WIB)', (tester) async {
      final today = FakeTodayRepository.budget();
      final clock = _Clock(DateTime.utc(2026, 12, 31, 16, 58));
      await _pumpDesa(tester, today, clock);

      clock.now = DateTime.utc(2026, 12, 31, 16, 59, 59);
      await tester.pump(const Duration(minutes: 1, seconds: 59));
      expect(today.calls, 1);
      clock.now = DateTime.utc(2026, 12, 31, 17);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(today.calls, 2);
    });

    testWidgets('UTC midnight (07:00 WIB) is not a reload', (tester) async {
      final today = FakeTodayRepository.budget();
      // 1 Nov 06:30 WIB = 31 Oct 23:30Z.
      final clock = _Clock(DateTime.utc(2026, 10, 31, 23, 30));
      await _pumpDesa(tester, today, clock);

      clock.now = DateTime.utc(2026, 11, 1, 0, 30);
      await tester.pump(const Duration(hours: 1));
      await tester.pumpAndSettle();

      expect(today.calls, 1);
    });

    testWidgets('leaving the Desa stops the midnight reload', (tester) async {
      final today = FakeTodayRepository.budget();
      final clock = _Clock(DateTime.utc(2026, 11, 1, 16, 59));
      await _pumpDesa(tester, today, clock);

      await tester.pumpWidget(const SizedBox());
      clock.now = DateTime.utc(2026, 11, 1, 17);
      await tester.pump(const Duration(minutes: 2));

      expect(today.calls, 1);
    });
  });

  group('card error is isolated', () {
    for (final (name, error) in <(String, Exception)>[
      ('rate limited', const RateLimitedException()),
      ('unauthorized-like forbidden', const ForbiddenException()),
      ('a non-AppException', Exception('boom')),
    ]) {
      testWidgets('$name: card error, plots still listed', (tester) async {
        await _pumpDesa(
          tester,
          FakeTodayRepository([error]),
          _Clock(DateTime.utc(2026, 11, 1, 7)),
        );

        expect(find.byKey(const Key('safe-today-error')), findsOneWidget);
        expect(find.byKey(const Key('safe-today')), findsNothing);
        expect(find.byType(GoalRow), findsOneWidget);
        expect(find.text('Dana darurat'), findsOneWidget);
      });
    }

    testWidgets('a failed retry keeps the plots and the error card',
        (tester) async {
      final today = FakeTodayRepository([
        const NetworkException(),
        const ServerException(),
      ]);
      await _pumpDesa(tester, today, _Clock(DateTime.utc(2026, 11, 1, 7)));

      await tester.tap(find.byKey(const Key('safe-today-retry')));
      await tester.pumpAndSettle();

      expect(today.calls, 2);
      expect(find.byKey(const Key('safe-today-error')), findsOneWidget);
      expect(find.byType(GoalRow), findsOneWidget);
    });
  });

  group('over budget never says "aman"', () {
    Future<void> pumpCard(WidgetTester tester, TodaySummary summary) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpVillage(
        tester,
        SizedBox(width: 358, child: SafeTodayCard(summary: summary)),
      );
    }

    for (final basis in SafeTodayBasis.values) {
      for (final remaining in [-1, -120000, -100000000]) {
        testWidgets('over_month, ${basis.name} basis, remaining $remaining',
            (tester) async {
          await pumpCard(
            tester,
            testToday(
              basis: basis,
              state: SafeTodayState.overMonth,
              allowance: 0,
              remaining: remaining,
            ),
          );

          expect(_cardWords(tester), isNot(contains('aman')));
        });
      }
    }

    group(
      'OVER_BUDGET paired with state ok/over_today '
      '(contract-violating input)',
      () {
        for (final state in [SafeTodayState.ok, SafeTodayState.overToday]) {
          testWidgets('state ${state.name} still never says "aman"',
              (tester) async {
            await pumpCard(
              tester,
              testToday(
                state: state,
                status: BudgetStatus.overBudget,
                allowance: 0,
                remaining: state == SafeTodayState.ok ? 5000 : -5000,
              ),
            );

            expect(_cardWords(tester), isNot(contains('aman')));
          });
        }
      },
    );
  });
}
