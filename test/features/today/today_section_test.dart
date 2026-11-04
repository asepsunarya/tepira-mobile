import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart'
    show goalsRepositoryProvider, kUnrecognizedResponseMessage;
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_row.dart';

import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_today_repository.dart';

/// Pumps the Desa with [today] answering `GET /api/mobile/today`.
Future<void> _pumpDesa(
  WidgetTester tester,
  FakeTodayRepository today, {
  FakeGoalsRepository? goals,
  DateTime? now,
  bool settle = true,
}) async {
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
          goals ??
              FakeGoalsRepository([
                [testGoal(title: 'Dana darurat')],
              ]),
        ),
        clockProvider.overrideWithValue(
          () => now ?? DateTime.utc(2026, 11, 1, 7),
        ),
      ],
      child: MaterialApp.router(
        theme: buildVillageTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

void main() {
  testWidgets('the card sits above the plots, with the month tiles',
      (tester) async {
    await _pumpDesa(tester, FakeTodayRepository.budget());

    expect(find.text('Rp100.000'), findsOneWidget);
    expect(find.text('Rp500.000'), findsOneWidget);
    expect(find.text('Rp50.000'), findsOneWidget);
    expect(find.text('DITABUNG BULAN INI'), findsOneWidget);
    expect(find.text('JAJAN BULAN INI'), findsOneWidget);
    final card = tester.getTopLeft(find.byKey(const Key('safe-today')));
    final plot = tester.getTopLeft(find.byType(GoalRow));
    expect(card.dy, lessThan(plot.dy));
  });

  testWidgets('loading the card does not hold back the plots', (tester) async {
    final today = FakeTodayRepository.budget()..gate = Completer<void>();
    await _pumpDesa(tester, today);

    expect(find.byKey(const Key('safe-today-loading')), findsOneWidget);
    expect(find.byType(GoalRow), findsOneWidget);

    today.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('safe-today')), findsOneWidget);
  });

  testWidgets('an error stays in the card; the plots still show; retry',
      (tester) async {
    final today = FakeTodayRepository([
      const NetworkException(),
      fixtureTodayBudget(),
    ]);
    await _pumpDesa(tester, today);

    expect(find.byKey(const Key('safe-today-error')), findsOneWidget);
    expect(find.text('Koneksi bermasalah. Coba lagi.'), findsOneWidget);
    expect(find.text('Dana darurat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('safe-today-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('safe-today')), findsOneWidget);
    expect(today.calls, 2);
  });

  testWidgets('an unknown state is a card error, never an "ok" card',
      (tester) async {
    await _pumpDesa(
      tester,
      FakeTodayRepository([
        const ServerException(message: kUnrecognizedResponseMessage),
      ]),
    );

    expect(find.byKey(const Key('safe-today')), findsNothing);
    expect(find.text(kUnrecognizedResponseMessage), findsOneWidget);
    expect(find.byType(GoalRow), findsOneWidget);
  });

  testWidgets('the card shows even when the plots fail', (tester) async {
    await _pumpDesa(
      tester,
      FakeTodayRepository.budget(),
      goals: FakeGoalsRepository([const ServerException()]),
    );

    expect(find.byKey(const Key('safe-today')), findsOneWidget);
    expect(find.text('Balai Desa sedang tutup'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the card too', (tester) async {
    final today = FakeTodayRepository([
      fixtureTodayBudget(),
      fixtureTodayWallet(),
    ]);
    await _pumpDesa(tester, today);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(today.calls, 2);
    expect(find.text('Rp201.833'), findsOneWidget);
  });

  testWidgets('reloads at 00:00 WIB', (tester) async {
    final today = FakeTodayRepository.budget();
    // 23:59 WIB on 1 Nov.
    await _pumpDesa(tester, today, now: DateTime.utc(2026, 11, 1, 16, 59));

    await tester.pump(const Duration(seconds: 59));
    expect(today.calls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(today.calls, 2);
  });

  testWidgets('reloads when the app comes back to the foreground',
      (tester) async {
    final today = FakeTodayRepository.budget();
    await _pumpDesa(tester, today);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(today.calls, 1);

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(today.calls, 2);
  });
}
