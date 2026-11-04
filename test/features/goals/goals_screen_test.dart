import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_row.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';

import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_today_repository.dart';

final _threeGoals = [
  testGoal(id: 1, title: 'Dana darurat', saved: 3450000, target: 10000000),
  testGoal(id: 2, title: 'Liburan ke Bali', saved: 1200000, target: 5000000),
  testGoal(id: 3, title: 'Laptop baru', saved: 8750000, target: 12000000),
];

/// Pumps the Desa screen at `/` with stub pages for the routes it opens.
Future<void> _pumpDesa(
  WidgetTester tester,
  FakeGoalsRepository repository, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const GoalsScreen(userName: 'Asep'),
      ),
      for (final path in [
        GoalRoutes.create,
        GoalRoutes.detailPattern,
        GoalRoutes.record,
        kSettingsPath,
      ])
        GoRoute(
          path: path,
          builder: (context, state) => Text('page ${state.uri}'),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
        goalsRepositoryProvider.overrideWithValue(repository),
      ],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  // The skeleton pulses forever, so a loading screen never settles.
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

void main() {
  testWidgets('shows the skeleton while the goals load', (tester) async {
    final repository = FakeGoalsRepository([_threeGoals])
      ..listGate = Completer<void>();
    await _pumpDesa(tester, repository, settle: false);

    expect(find.bySemanticsLabel('Memuat desa'), findsOneWidget);
    expect(find.byType(GoalRow), findsNothing);

    repository.listGate!.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Memuat desa'), findsNothing);
    expect(find.byType(GoalRow), findsNWidgets(3));
  });

  testWidgets('lists three goals with stage, rupiah amounts and percent',
      (tester) async {
    await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

    expect(find.text('Asep'), findsOneWidget);
    expect(find.text('3 kavling sedang dibangun'), findsOneWidget);
    expect(find.byType(GoalRow), findsNWidgets(3));
    expect(find.text('Dana darurat'), findsOneWidget);
    expect(find.text('Dinding'), findsOneWidget);
    expect(find.text('Rp3.450.000 dari Rp10.000.000 · 34%'), findsOneWidget);
    expect(find.text('Fondasi'), findsOneWidget);
    expect(find.text('Rp1.200.000 dari Rp5.000.000 · 24%'), findsOneWidget);
    expect(find.text('Atap'), findsOneWidget);
    expect(find.text('Rp8.750.000 dari Rp12.000.000 · 72%'), findsOneWidget);
  });

  testWidgets('never shows 100% before the target is reached', (tester) async {
    await _pumpDesa(
      tester,
      FakeGoalsRepository([
        [
          testGoal(id: 1, title: 'Hampir', saved: 9996, target: 10000),
          testGoal(id: 2, title: 'Rampung', saved: 10000, target: 10000),
        ],
      ]),
    );

    expect(find.text('Rp9.996 dari Rp10.000 · 99%'), findsOneWidget);
    expect(find.text('Atap'), findsOneWidget);
    expect(find.text('Rp10.000 dari Rp10.000 · 100%'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(find.text('1 kavling sedang dibangun'), findsOneWidget);
  });

  testWidgets('shows the empty village when there are no goals',
      (tester) async {
    await _pumpDesa(tester, FakeGoalsRepository([<Never>[]]));

    expect(find.text('Desamu masih sepi'), findsOneWidget);
    expect(find.text('Belum ada kavling'), findsOneWidget);
    expect(find.byType(GoalRow), findsNothing);
  });

  testWidgets('"Muat ulang" on the empty village loads again', (tester) async {
    final repository = FakeGoalsRepository([
      <Never>[],
      _threeGoals,
    ]);
    await _pumpDesa(tester, repository);

    await tester.tap(find.text('Sudah punya data di tepira.id? Muat ulang'));
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    expect(find.byType(GoalRow), findsNWidgets(3));
  });

  testWidgets('pull to refresh asks the repository again', (tester) async {
    final repository = FakeGoalsRepository([
      _threeGoals,
      [_threeGoals.first],
    ]);
    await _pumpDesa(tester, repository);
    expect(find.byType(GoalRow), findsNWidgets(3));

    await tester.fling(find.text('Dana darurat'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    expect(find.byType(GoalRow), findsOneWidget);
  });

  testWidgets('pull to refresh also works on the empty village',
      (tester) async {
    final repository = FakeGoalsRepository([<Never>[]]);
    await _pumpDesa(tester, repository);

    await tester.fling(
      find.text('Desamu masih sepi'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
  });

  group('errors', () {
    for (final (error, title, message) in [
      (
        const NetworkException(),
        'Desa sedang offline',
        'Koneksi bermasalah. Coba lagi.',
      ),
      (
        const ServerException(statusCode: 500),
        'Balai Desa sedang tutup',
        'Server sedang bermasalah. Coba lagi nanti.',
      ),
      (
        const ForbiddenException(),
        'Desa ini terkunci',
        'Kamu tidak punya akses ke data ini.',
      ),
    ]) {
      testWidgets('${error.runtimeType} shows "$title"', (tester) async {
        await _pumpDesa(tester, FakeGoalsRepository([error]));

        expect(find.text(title), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Coba lagi'), findsOneWidget);
        expect(find.byType(GoalRow), findsNothing);
      });
    }

    testWidgets('an unexpected error shows a generic message', (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([const FormatException()]));

      expect(find.text('Desa belum bisa dimuat'), findsOneWidget);
      expect(find.text('Ada yang tidak beres. Coba lagi.'), findsOneWidget);
    });

    testWidgets('"Coba lagi" shows the skeleton, then the goals',
        (tester) async {
      final repository = FakeGoalsRepository([
        const NetworkException(),
        _threeGoals,
      ]);
      await _pumpDesa(tester, repository);

      repository.listGate = Completer<void>();
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      expect(find.bySemanticsLabel('Memuat desa'), findsOneWidget);

      repository.listGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.listCalls, 2);
      expect(find.text('Desa sedang offline'), findsNothing);
      expect(find.byType(GoalRow), findsNWidgets(3));
    });

    testWidgets('a failed refresh replaces the list with the error',
        (tester) async {
      final repository = FakeGoalsRepository([
        _threeGoals,
        const NetworkException(),
      ]);
      await _pumpDesa(tester, repository);

      await tester.fling(find.text('Dana darurat'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Desa sedang offline'), findsOneWidget);
      expect(find.byType(GoalRow), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets('a goal row opens /goal/:id', (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

      await tester.tap(find.text('Liburan ke Bali'));
      await tester.pumpAndSettle();

      expect(find.text('page /goal/2'), findsOneWidget);
    });

    testWidgets('"Bangun kavling" opens /goal/new', (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

      await tester.tap(find.byKey(const Key('build-plot')));
      await tester.pumpAndSettle();

      expect(find.text('page /goal/new'), findsOneWidget);
    });

    testWidgets('"Bangun kavling" on the empty village opens /goal/new',
        (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([<Never>[]]));

      await tester.tap(find.byKey(const Key('build-first-plot')));
      await tester.pumpAndSettle();

      expect(find.text('page /goal/new'), findsOneWidget);
    });

    testWidgets('"Catat" in the dock opens the Jajan tab', (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

      await tester.tap(find.byKey(const Key('record')));
      await tester.pumpAndSettle();

      expect(find.text('page /record?tab=jajan'), findsOneWidget);
    });

    testWidgets('the HUD avatar opens /settings', (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();

      expect(find.text('page /settings'), findsOneWidget);
    });

    testWidgets('the HUD avatar is a 44px button named Pengaturan',
        (tester) async {
      await _pumpDesa(tester, FakeGoalsRepository([_threeGoals]));

      final avatar = find.byKey(const Key('open-settings'));
      expect(tester.getSize(avatar), const Size(44, 44));
      expect(
        tester.getSemantics(avatar),
        matchesSemantics(
          label: 'Pengaturan',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    });

    testWidgets('back from a pushed page returns to the same list',
        (tester) async {
      final repository = FakeGoalsRepository([_threeGoals]);
      await _pumpDesa(tester, repository);

      await tester.tap(find.byKey(const Key('record')));
      await tester.pumpAndSettle();
      final router =
          GoRouter.of(tester.element(find.text('page /record?tab=jajan')));
      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(GoalRow), findsNWidgets(3));
      expect(repository.listCalls, 1);
    });
  });
}
