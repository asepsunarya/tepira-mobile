// Independent edge tests for the 00:00 WIB re-check (fix round on PR #22):
// the cap, its reset at the next midnight, errors and disposal.
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
import 'package:tepira_mobile/features/today/widgets/safe_today_card.dart';

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

/// Runs pending microtasks and frames without moving the fake clock, so
/// the 60 s re-check timers do not drift (pumpAndSettle advances time).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  group('00:00 WIB re-check cap', () {
    testWidgets(
        'exactly kTodayMaxRechecks re-checks, then none until the next '
        '00:00, where the count starts over', (tester) async {
      expect(kTodayMaxRechecks, 15);
      expect(kTodayRecheckDelay, const Duration(seconds: 60));
      // The server never leaves 30 Nov.
      final today = FakeTodayRepository([
        testToday(date: DateTime.utc(2026, 11, 30)),
      ]);
      final clock = _Clock(DateTime.utc(2026, 11, 30, 16, 59, 30));
      await _pumpDesa(tester, today, clock);
      expect(today.calls, 1);

      // 1 Dec 00:00 WIB: the midnight reload.
      clock.now = DateTime.utc(2026, 11, 30, 17);
      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(today.calls, 2);

      // Re-check i at 00:0i, each exactly 60 s apart, never early.
      for (var i = 1; i <= kTodayMaxRechecks; i++) {
        clock.now = clock.now.add(const Duration(seconds: 59));
        await tester.pump(const Duration(seconds: 59));
        await _flush(tester);
        expect(today.calls, 1 + i, reason: 'early re-check $i');
        clock.now = clock.now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await _flush(tester);
        expect(today.calls, 2 + i, reason: 're-check $i');
      }
      expect(today.calls, 2 + kTodayMaxRechecks);

      // No 16th re-check, a minute or many hours later.
      clock.now = clock.now.add(kTodayRecheckDelay);
      await tester.pump(kTodayRecheckDelay);
      await _flush(tester);
      expect(today.calls, 2 + kTodayMaxRechecks, reason: '16th re-check');
      clock.now = DateTime.utc(2026, 12, 1, 16, 59);
      await tester.pump(const Duration(hours: 23, minutes: 43));
      await _flush(tester);
      expect(today.calls, 2 + kTodayMaxRechecks);

      // 2 Dec 00:00 WIB: a new midnight reload and a fresh re-check budget.
      clock.now = DateTime.utc(2026, 12, 1, 17);
      await tester.pump(const Duration(minutes: 1));
      await _flush(tester);
      expect(today.calls, 3 + kTodayMaxRechecks);
      for (var i = 1; i <= kTodayMaxRechecks + 3; i++) {
        clock.now = clock.now.add(kTodayRecheckDelay);
        await tester.pump(kTodayRecheckDelay);
        await _flush(tester);
      }
      expect(today.calls, 3 + 2 * kTodayMaxRechecks);
    });

    testWidgets('a matching date on the last allowed re-check stops there',
        (tester) async {
      final today = FakeTodayRepository([
        testToday(date: DateTime.utc(2026, 11, 30)),
        for (var i = 0; i < kTodayMaxRechecks; i++)
          testToday(date: DateTime.utc(2026, 11, 30)),
        testToday(date: DateTime.utc(2026, 12), remaining: 7),
      ]);
      final clock = _Clock(DateTime.utc(2026, 11, 30, 16, 59, 30));
      await _pumpDesa(tester, today, clock);

      clock.now = DateTime.utc(2026, 11, 30, 17);
      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      for (var i = 0; i < kTodayMaxRechecks + 5; i++) {
        clock.now = clock.now.add(kTodayRecheckDelay);
        await tester.pump(kTodayRecheckDelay);
        await _flush(tester);
      }

      expect(today.calls, 2 + kTodayMaxRechecks);
      expect(find.text('Rp7'), findsOneWidget);
    });

    testWidgets('a failed re-check does not start a fast retry loop',
        (tester) async {
      final today = FakeTodayRepository([
        testToday(date: DateTime.utc(2026, 11, 30)),
        testToday(date: DateTime.utc(2026, 11, 30)),
        const NetworkException(),
      ]);
      final clock = _Clock(DateTime.utc(2026, 11, 30, 16, 59, 30));
      await _pumpDesa(tester, today, clock);

      clock.now = DateTime.utc(2026, 11, 30, 17);
      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(today.calls, 2);
      clock.now = clock.now.add(kTodayRecheckDelay);
      await tester.pump(kTodayRecheckDelay);
      await _flush(tester);
      expect(today.calls, 3);

      clock.now = clock.now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      await _flush(tester);
      expect(today.calls, 3);
    });

    testWidgets('leaving the Desa during re-checks stops them', (tester) async {
      final today = FakeTodayRepository([
        testToday(date: DateTime.utc(2026, 11, 30)),
      ]);
      final clock = _Clock(DateTime.utc(2026, 11, 30, 16, 59, 30));
      await _pumpDesa(tester, today, clock);
      clock.now = DateTime.utc(2026, 11, 30, 17);
      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      clock.now = clock.now.add(kTodayRecheckDelay);
      await tester.pump(kTodayRecheckDelay);
      await _flush(tester);
      expect(today.calls, 3);

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 5; i++) {
        clock.now = clock.now.add(kTodayRecheckDelay);
        await tester.pump(kTodayRecheckDelay);
      }
      expect(today.calls, 3);
    });
  });
}
