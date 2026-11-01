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
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/goals/goal_providers.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';

import '../../helpers/fake_goals_repository.dart';

/// [FakeGoalsRepository] that records [contribute] calls. The call with
/// index i throws `contributeErrors[i]` when that entry is not null.
class _ContributeRepository extends FakeGoalsRepository {
  _ContributeRepository({
    super.detailResults,
    this.contributeErrors = const [],
  }) : super([_goals]);

  final List<Exception?> contributeErrors;
  final List<(int, int, String?)> contributions = [];

  /// When set, [contribute] waits for it before answering.
  Completer<void>? contributeGate;

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) async {
    final call = contributions.length;
    contributions.add((goalId, amount, note));
    await contributeGate?.future;
    final error =
        call < contributeErrors.length ? contributeErrors[call] : null;
    if (error != null) throw error;
  }
}

final List<Goal> _goals = [
  testGoal(id: 1, title: 'Dana darurat'),
  testGoal(id: 2, title: 'Sepeda', saved: 0),
];

GoalDetail _detail(List<Contribution> contributions) => GoalDetail(
      goal: testGoal(id: 1, title: 'Dana darurat'),
      contributions: contributions,
    );

final Contribution _justStored = Contribution(
  id: 41,
  amount: 20000,
  note: 'gajian',
  date: DateTime.utc(2026, 11, 1, 7),
);

/// Pumps the Desa stub at `/`, then pushes [location] on top of it unless
/// [direct] is set, in which case [location] is the first page.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _ContributeRepository repository, {
  String location = '/record?goal=1',
  bool direct = false,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: direct ? location : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('desa')),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) =>
            Scaffold(body: Text('kavling ${state.uri}')),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => ContributeScreen(
          goalParam: state.uri.queryParameters[GoalRoutes.recordGoalParam],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  if (!direct) unawaited(router.push(location));
  await tester.pumpAndSettle();
  return container;
}

String _amountShown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('amount'))).data!;

String _ctaLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('submit')),
        matching: find.byType(Text),
      ),
    )
    .data!;

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key('key-$key')));
  await tester.pump();
}

void main() {
  testWidgets('?goal= preselects that goal from the list', (tester) async {
    await _pump(tester, _ContributeRepository(), location: '/record?goal=2');

    expect(find.text('Sepeda'), findsOneWidget);
    expect(find.text('Kavling dari tautan tidak ditemukan.'), findsNothing);
  });

  for (final raw in ['abc', '0x02', '+2', '-1', '0', '99', '']) {
    testWidgets('?goal=$raw selects nothing and says so', (tester) async {
      final repository = _ContributeRepository();
      await _pump(tester, repository, location: '/record?goal=$raw');
      await tester.tap(find.byKey(const Key('chip-20000')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Pilih kavling'), findsOneWidget);
      expect(find.text('Kavling dari tautan tidak ditemukan.'), findsOneWidget);
      expect(_ctaLabel(tester), 'Pilih kavling dulu');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(repository.contributions, isEmpty);
    });
  }

  testWidgets('without ?goal= the user picks a goal from the sheet',
      (tester) async {
    await _pump(tester, _ContributeRepository(), location: '/record');

    expect(find.text('Pilih kavling'), findsOneWidget);
    expect(find.text('Kavling dari tautan tidak ditemukan.'), findsNothing);

    await tester.tap(find.byKey(const Key('goal-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-2')));
    await tester.pumpAndSettle();

    expect(find.text('Sepeda'), findsOneWidget);
    expect(find.text('Pilih kavling'), findsNothing);
  });

  testWidgets('amount 0 is rejected', (tester) async {
    final repository = _ContributeRepository();
    await _pump(tester, repository);
    await _tapKey(tester, '0');
    await _tapKey(tester, '000');

    expect(_amountShown(tester), 'Rp0');
    expect(_ctaLabel(tester), 'Isi nominal dulu');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(repository.contributions, isEmpty);
  });

  testWidgets('chips set the amount and the keypad edits it', (tester) async {
    await _pump(tester, _ContributeRepository());

    for (final (chip, shown) in [
      (10000, 'Rp10.000'),
      (20000, 'Rp20.000'),
      (50000, 'Rp50.000'),
      (100000, 'Rp100.000'),
    ]) {
      await tester.tap(find.byKey(Key('chip-$chip')));
      await tester.pump();
      expect(_amountShown(tester), shown);
    }

    await _tapKey(tester, '⌫');
    expect(_amountShown(tester), 'Rp10.000');
    await _tapKey(tester, '5');
    expect(_amountShown(tester), 'Rp100.005');
    expect(_ctaLabel(tester), 'Setor Rp100.005');
  });

  testWidgets(
      'success deposits once, reloads detail and list, pops with a snackbar',
      (tester) async {
    final repository = _ContributeRepository(
      detailResults: [
        _detail(const []),
        _detail([_justStored]),
      ],
    );
    final container = await _pump(tester, repository);
    // The Kavling screen below keeps its detail alive.
    container.listen(goalDetailProvider(1), (_, __) {});
    await tester.pumpAndSettle();
    final listCalls = repository.listCalls;
    final detailCalls = repository.detailIds.length;

    await tester.tap(find.byKey(const Key('chip-20000')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('note')), '  gajian  ');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repository.contributions, [(1, 20000, 'gajian')]);
    expect(repository.detailIds.length, detailCalls + 1);
    expect(repository.listCalls, greaterThan(listCalls));
    expect(
      container.read(goalDetailProvider(1)).value!.contributions,
      [_justStored],
    );
    expect(find.text('desa'), findsOneWidget);
    expect(find.byType(ContributeScreen), findsNothing);
    expect(
      find.text('Setoran Rp20.000 masuk ke Dana darurat.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty note is sent as no note', (tester) async {
    final repository = _ContributeRepository();
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('chip-10000')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('note')), '   ');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repository.contributions, [(1, 10000, null)]);
  });

  testWidgets('opened directly, success lands on the Kavling', (tester) async {
    await _pump(tester, _ContributeRepository(), direct: true);

    await tester.tap(find.byKey(const Key('chip-10000')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('kavling /goal/1'), findsOneWidget);
  });

  testWidgets('a double tap deposits once', (tester) async {
    final repository = _ContributeRepository()
      ..contributeGate = Completer<void>();
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('chip-20000')));
    await tester.pump();
    await tester.pump();

    // Both taps land before a frame rebuilds the button.
    await tester.tap(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(_ctaLabel(tester), 'Menyimpan…');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(repository.contributions, hasLength(1));
    repository.contributeGate!.complete();
    await tester.pumpAndSettle();
    expect(repository.contributions, hasLength(1));
  });

  testWidgets(
      'a network failure reloads the goal and waits for the user to retry',
      (tester) async {
    final repository = _ContributeRepository(
      detailResults: [
        _detail([_justStored]),
      ],
      contributeErrors: [const NetworkException()],
    );
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('chip-20000')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('note')), 'gajian');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repository.contributions, hasLength(1));
    expect(repository.detailIds, [1]);
    expect(find.byKey(const Key('uncertain-deposit')), findsOneWidget);
    expect(find.byKey(const Key('latest-41')), findsOneWidget);
    expect(find.textContaining('+Rp20.000 · gajian'), findsOneWidget);
    expect(find.byType(ContributeScreen), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    expect(repository.contributions, hasLength(1));

    expect(_ctaLabel(tester), 'Setor Rp20.000 lagi');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(repository.contributions, [
      (1, 20000, 'gajian'),
      (1, 20000, 'gajian'),
    ]);
    expect(find.text('desa'), findsOneWidget);
  });

  testWidgets('a failed reload after a network failure can be repeated',
      (tester) async {
    final repository = _ContributeRepository(
      detailResults: [
        const NetworkException(),
        _detail([_justStored]),
      ],
      contributeErrors: [const NetworkException()],
    );
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('chip-20000')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat setoran belum bisa dimuat.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reload-latest')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('latest-41')), findsOneWidget);
    expect(repository.contributions, hasLength(1));
  });

  testWidgets('a rejected deposit shows the message and allows a retry',
      (tester) async {
    final repository = _ContributeRepository(
      contributeErrors: [const ServerException()],
    );
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('chip-20000')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Server sedang bermasalah. Coba lagi nanti.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('uncertain-deposit')), findsNothing);
    expect(repository.detailIds, isEmpty);
    expect(_ctaLabel(tester), 'Setor Rp20.000');
  });
}
