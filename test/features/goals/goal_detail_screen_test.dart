import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goal_dto.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_detail_screen.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/widgets/stage_illustration.dart';

import '../../helpers/fake_goals_repository.dart';

/// `test/fixtures/mobile_goal_detail.json`: goal 12, Rp6.200.000 of
/// Rp15.000.000 (41%), four deposits, one without a note.
GoalDetail _fixtureDetail() {
  final body = jsonDecode(
    File('test/fixtures/mobile_goal_detail.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return goalDetailFromJson(body['goal']! as Map<String, Object?>);
}

/// A goal with every nullable field null and no deposits.
GoalDetail _bareDetail({int saved = 0, int target = 5000000}) => GoalDetail(
      goal: testGoal(id: 12, title: 'Sepeda', saved: saved, target: target),
      contributions: const [],
    );

/// Pumps `/goal/<id>` with stub pages for `/` and the Setor route.
Future<void> _pumpDetail(
  WidgetTester tester,
  FakeGoalsRepository repository, {
  int? goalId = 12,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('desa')),
      GoRoute(
        path: '/start',
        builder: (context, state) => GoalDetailScreen(goalId: goalId),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => Text('page ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  // The loading spinner never settles.
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

BuildStage _shownStage(WidgetTester tester) =>
    tester.widget<StageIllustration>(find.byType(StageIllustration)).stage;

/// Texts of the history rows in screen order, via their semantics labels.
List<String> _historyLabels(WidgetTester tester) {
  final rows = find.bySemanticsLabel(RegExp(r'^\d+ \w+ \d{4}, '));
  return [
    for (var i = 0; i < rows.evaluate().length; i++)
      tester.getSemantics(rows.at(i)).label,
  ];
}

void main() {
  testWidgets('shows a loader while the goal loads', (tester) async {
    final repository =
        FakeGoalsRepository([], detailResults: [_fixtureDetail()])
          ..detailGate = Completer<void>();
    await _pumpDetail(tester, repository, settle: false);

    expect(find.bySemanticsLabel('Memuat kavling'), findsOneWidget);
    expect(find.byKey(const Key('deposit')), findsNothing);

    repository.detailGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Laptop kerja'), findsOneWidget);
    expect(repository.detailIds, [12]);
  });

  testWidgets('shows the fixture goal: stage, amounts, percent and deadline',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDetail(
      tester,
      FakeGoalsRepository([], detailResults: [_fixtureDetail()]),
    );

    expect(_shownStage(tester), BuildStage.dinding);
    expect(find.bySemanticsLabel('Tahap dinding'), findsOneWidget);
    expect(find.text('Laptop kerja'), findsOneWidget);
    expect(find.text('Ganti laptop lama sebelum proyek baru'), findsOneWidget);
    expect(find.text('Target 30 Apr 2027 · 180 hari lagi'), findsOneWidget);
    // floor(6.2M * 100 / 15M) = 41; the server sends 41.3.
    expect(find.text('41%'), findsOneWidget);
    expect(find.bySemanticsLabel('Terkumpul: Rp6.200.000'), findsOneWidget);
    expect(find.bySemanticsLabel('Sisa: Rp8.800.000'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Kejar deadline: Rp1.466.667/bulan'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Target: Rp15.000.000'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('lists deposits newest first; a missing note reads Setoran',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final fixture = _fixtureDetail();
    // Server order is newest first; feed it reversed to prove the sort.
    final shuffled = GoalDetail(
      goal: fixture.goal,
      contributions: fixture.contributions.reversed.toList(),
    );
    await _pumpDetail(
      tester,
      FakeGoalsRepository([], detailResults: [shuffled]),
    );
    await tester.scrollUntilVisible(find.text('Gaji Juni'), 100);

    expect(
      find.bySemanticsLabel('Setoran terakhir, 4 setoran'),
      findsOneWidget,
    );
    expect(_historyLabels(tester), [
      '28 Okt 2026, Sisa jajan Oktober, +Rp1.200.000',
      '25 Sep 2026, Bonus proyek, +Rp1.500.000',
      '26 Agu 2026, Setoran, +Rp1.500.000',
      '25 Jun 2026, Gaji Juni, +Rp2.000.000',
    ]);
    expect(find.byKey(const Key('empty-history')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a goal without deadline, description or deposits',
      (tester) async {
    await _pumpDetail(
      tester,
      FakeGoalsRepository([], detailResults: [_bareDetail()]),
    );

    expect(_shownStage(tester), BuildStage.lahan);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Tanpa tenggat'), findsNWidgets(2));
    expect(find.byKey(const Key('empty-history')), findsOneWidget);
    expect(find.textContaining('Belum ada setoran'), findsOneWidget);
  });

  testWidgets('a reached goal says so instead of a monthly amount',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpDetail(
      tester,
      FakeGoalsRepository(
        [],
        detailResults: [_bareDetail(saved: 5000000, target: 5000000)],
      ),
    );

    expect(_shownStage(tester), BuildStage.selesai);
    expect(find.text('100%'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Kejar deadline: Sudah tercapai'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a passed deadline reads "tenggat habis"', (tester) async {
    final goal = _fixtureDetail().goal;
    final overdue = GoalDetail(
      goal: Goal(
        id: goal.id,
        title: goal.title,
        description: null,
        target: goal.target,
        saved: goal.saved,
        percent: goal.percent,
        remaining: goal.remaining,
        deadline: DateTime.utc(2026, 10, 1),
        daysLeft: 0,
        perMonthNeeded: goal.remaining,
        createdAt: goal.createdAt,
        lastContribution: goal.lastContribution,
        contributionCount: goal.contributionCount,
      ),
      contributions: const [],
    );
    await _pumpDetail(
      tester,
      FakeGoalsRepository([], detailResults: [overdue]),
    );

    expect(find.text('Target 1 Okt 2026 · tenggat habis'), findsOneWidget);
  });

  group('stage follows the displayed percent', () {
    for (final (saved, percent, stage) in [
      (0, '0%', BuildStage.lahan),
      (1, '0%', BuildStage.fondasi),
      (2999, '29%', BuildStage.fondasi),
      (3000, '30%', BuildStage.dinding),
      (7000, '70%', BuildStage.atap),
      // The server would round this to 100.0; the screen must not.
      (9996, '99%', BuildStage.atap),
      (10000, '100%', BuildStage.selesai),
    ]) {
      testWidgets('Rp$saved of Rp10.000 is $percent, ${stage.name}',
          (tester) async {
        await _pumpDetail(
          tester,
          FakeGoalsRepository(
            [],
            detailResults: [_bareDetail(saved: saved, target: 10000)],
          ),
        );

        expect(find.text(percent), findsOneWidget);
        expect(_shownStage(tester), stage);
      });
    }
  });

  testWidgets('Setor opens the Setor page for this goal', (tester) async {
    await _pumpDetail(
      tester,
      FakeGoalsRepository([], detailResults: [_fixtureDetail()]),
    );

    await tester.tap(find.byKey(const Key('deposit')));
    await tester.pumpAndSettle();

    expect(find.text('page /record?goal=12'), findsOneWidget);
  });

  testWidgets('a 404 shows a friendly missing-goal message', (tester) async {
    final repository =
        FakeGoalsRepository([], detailResults: [const NotFoundException()]);
    await _pumpDetail(tester, repository);

    expect(find.text('Kavling tidak ditemukan'), findsOneWidget);
    expect(
      find.text('Kavling ini sudah tidak ada atau bukan milikmu.'),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsNothing);
    expect(find.byKey(const Key('deposit')), findsNothing);

    await tester.tap(find.text('Kembali ke desa'));
    await tester.pumpAndSettle();
    expect(find.text('desa'), findsOneWidget);
  });

  testWidgets('a non-numeric route id shows the missing goal without a call',
      (tester) async {
    final repository = FakeGoalsRepository([], detailResults: [_bareDetail()]);
    await _pumpDetail(tester, repository, goalId: null);

    expect(find.text('Kavling tidak ditemukan'), findsOneWidget);
    expect(repository.detailIds, isEmpty);
  });

  testWidgets('a network error can be retried', (tester) async {
    final repository = FakeGoalsRepository(
      [],
      detailResults: [const NetworkException(), _fixtureDetail()],
    );
    await _pumpDetail(tester, repository);

    expect(find.text('Desa sedang offline'), findsOneWidget);
    expect(find.byKey(const Key('deposit')), findsNothing);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Laptop kerja'), findsOneWidget);
    expect(repository.detailIds, [12, 12]);
  });

  testWidgets('pull to refresh reloads the goal', (tester) async {
    final fixture = _fixtureDetail();
    final repository = FakeGoalsRepository(
      [],
      detailResults: [_bareDetail(saved: 1000000), fixture],
    );
    await _pumpDetail(tester, repository);
    expect(find.text('Sepeda'), findsOneWidget);

    await tester.fling(find.text('Sepeda'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repository.detailIds, [12, 12]);
    expect(find.text('Laptop kerja'), findsOneWidget);
  });
}
