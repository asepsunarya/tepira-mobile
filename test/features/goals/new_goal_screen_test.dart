import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_providers.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/new_goal_screen.dart';

import '../../helpers/fake_goals_repository.dart';

/// Arguments of one [GoalsRepository.create] call.
typedef _CreateCall = ({
  String title,
  int target,
  String? description,
  DateTime? deadline,
});

/// [FakeGoalsRepository] that records [create] calls and answers with
/// [createResult] (thrown when it is an [Exception]) after [createGate].
class _CreatingRepository extends FakeGoalsRepository {
  _CreatingRepository({this.createResult, List<Object>? listResults})
      : super(listResults ?? [<Goal>[]]);

  Object? createResult;
  Completer<void>? createGate;
  final List<_CreateCall> createCalls = [];

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) async {
    final call = (
      title: title,
      target: target,
      description: description,
      deadline: deadline,
    );
    createCalls.add(call);
    await createGate?.future;
    final result = createResult ?? testGoal(id: 16, title: title);
    if (result is Exception) throw result;
    return result as Goal;
  }
}

/// A Desa stand-in that watches [goalsProvider], so its reloads show in
/// [FakeGoalsRepository.listCalls].
class _Desa extends ConsumerWidget {
  const _Desa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(goalsProvider);
    return const Text('desa');
  }
}

/// The fixed "now" of these tests: three minutes after [testGoal]'s
/// default `createdAt`.
final DateTime _now = DateTime.utc(2026, 11, 1, 0, 3);

/// Pumps the Desa stand-in, then opens `/goal/new` on top of it.
Future<GoRouter> _pumpNewGoal(
  WidgetTester tester,
  _CreatingRepository repository,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _Desa()),
      GoRoute(
        path: GoalRoutes.create,
        builder: (context, state) => const NewGoalScreen(),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        // A Scaffold, so a snackbar shown while navigating here is visible.
        builder: (context, state) => Scaffold(
          body: Text('kavling ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(() => _now),
      ],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  unawaited(router.push(GoalRoutes.create));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _fill(
  WidgetTester tester, {
  String title = 'Kamera mirrorless',
  String target = '9000000',
  String? description,
}) async {
  await tester.enterText(find.byKey(const Key('title')), title);
  await tester.enterText(find.byKey(const Key('target')), target);
  if (description != null) {
    await tester.enterText(find.byKey(const Key('description')), description);
  }
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('submit')));
  await tester.tap(find.byKey(const Key('submit')));
}

/// Picks [month]/[day]/[year] through the date picker's text input mode.
Future<void> _pickDeadline(
  WidgetTester tester, {
  required int year,
  required int month,
  required int day,
}) async {
  await tester.tap(find.byKey(const Key('deadline')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final mm = '$month'.padLeft(2, '0');
  final dd = '$day'.padLeft(2, '0');
  await tester.enterText(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    ),
    '$mm/$dd/$year',
  );
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
}

void main() {
  group('validation', () {
    testWidgets('an empty name is rejected without calling the API',
        (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester, title: '   ');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Nama goal harus diisi.'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('an empty target is rejected', (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester, target: '');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Target harus diisi.'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('a target of 0 is rejected', (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester, target: '0');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Target harus berupa angka bulat lebih dari 0.'),
        findsOneWidget,
      );
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('non-numeric target text is dropped and then required',
        (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester, target: 'abc');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('Target harus diisi.'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('the target field cannot hold a sign or decimals',
        (tester) async {
      await _pumpNewGoal(tester, _CreatingRepository());

      await tester.enterText(find.byKey(const Key('target')), '-5000');
      expect(find.text('5.000'), findsOneWidget);

      // Rupiah has no cents: the decimal part is dropped, not glued on.
      await tester.enterText(find.byKey(const Key('target')), '12,5');
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('the target is grouped by thousands', (tester) async {
      await _pumpNewGoal(tester, _CreatingRepository());

      await tester.enterText(find.byKey(const Key('target')), '1500000');

      expect(find.text('1.500.000'), findsOneWidget);
    });
  });

  group('submit', () {
    testWidgets(
        'calls create once with trimmed fields and the local deadline date',
        (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(
        tester,
        title: '  Kamera mirrorless ',
        target: '9000000',
        description: ' Untuk konten ',
      );
      await _pickDeadline(tester, year: 2027, month: 6, day: 30);
      expect(find.text('30 Jun 2027'), findsOneWidget);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final call = repository.createCalls.single;
      expect(call.title, 'Kamera mirrorless');
      expect(call.target, 9000000);
      expect(call.description, 'Untuk konten');
      expect(call.deadline, DateTime(2027, 6, 30));
      expect(call.deadline!.isUtc, isFalse);
    });

    testWidgets('sends no deadline or description when left empty',
        (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester, title: 'Dana pendidikan', target: '20000000');
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, [
        (
          title: 'Dana pendidikan',
          target: 20000000,
          description: null,
          deadline: null,
        ),
      ]);
    });

    testWidgets('a cleared deadline is not sent', (tester) async {
      final repository = _CreatingRepository();
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _pickDeadline(tester, year: 2027, month: 6, day: 30);
      await tester.tap(find.byKey(const Key('clearDeadline')));
      await tester.pump();
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls.single.deadline, isNull);
    });

    testWidgets('a second tap while saving does not create twice',
        (tester) async {
      final repository = _CreatingRepository()..createGate = Completer();
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')), warnIfMissed: false);
      await tester.pump();

      expect(repository.createCalls, hasLength(1));
      expect(find.text('Mematok kavling…'), findsOneWidget);

      repository.createGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.createCalls, hasLength(1));
    });

    testWidgets(
        'success reloads the goals and replaces the form with the Kavling',
        (tester) async {
      final repository = _CreatingRepository();
      final router = await _pumpNewGoal(tester, repository);
      expect(repository.listCalls, 1);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('kavling 16'), findsOneWidget);
      expect(repository.listCalls, 2);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('desa'), findsOneWidget);
    });
  });

  group('errors', () {
    for (final error in <AppException>[
      const ServerException(
        message: 'Target harus berupa angka bulat lebih dari 0.',
        code: 'bad_request',
        statusCode: 400,
      ),
      const ApiException('Deskripsi maksimal 200 karakter.', statusCode: 400),
    ]) {
      testWidgets('a 400 (${error.runtimeType}) shows the server message',
          (tester) async {
        final repository = _CreatingRepository(createResult: error);
        await _pumpNewGoal(tester, repository);

        await _fill(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(find.byType(NewGoalScreen), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('submitError'))).data,
          error.message,
        );
        expect(repository.listCalls, 1);
      });
    }

    testWidgets('a 500 shows the server message', (tester) async {
      final repository = _CreatingRepository(
        createResult: const ServerException(statusCode: 500),
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Server sedang bermasalah. Coba lagi nanti.'),
        findsOneWidget,
      );
    });
  });

  group('create fails on the network (outcome unknown)', () {
    final lostErrors = <(String, AppException)>[
      ('timeout', const NetworkException()),
      ('502', const ServerException(statusCode: 502)),
      ('503', const ServerException(statusCode: 503)),
      ('504', const ServerException(statusCode: 504)),
    ];

    for (final (name, error) in lostErrors) {
      testWidgets(
        'after $name, a matching goal created just now is opened with a '
        'notice, without retrying',
        (tester) async {
          final repository = _CreatingRepository(
            createResult: error,
            listResults: [
              <Goal>[],
              [
                testGoal(id: 3, title: 'Lain', target: 9000000),
                testGoal(id: 21, title: 'Kamera mirrorless', target: 9000000),
              ],
            ],
          );
          await _pumpNewGoal(tester, repository);

          await _fill(tester);
          await _tapSubmit(tester);
          await tester.pumpAndSettle();

          expect(repository.createCalls, hasLength(1));
          expect(find.text('kavling 21'), findsOneWidget);
          expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
          expect(find.textContaining('belum'), findsNothing);
        },
      );

      testWidgets(
        'after $name without a match, says to check first and does not '
        'retry by itself',
        (tester) async {
          final repository = _CreatingRepository(createResult: error);
          await _pumpNewGoal(tester, repository);

          await _fill(tester);
          await _tapSubmit(tester);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(minutes: 1));
          await tester.pumpAndSettle();

          expect(repository.createCalls, hasLength(1));
          expect(find.byType(NewGoalScreen), findsOneWidget);
          expect(find.text(kNewGoalUncertainTitle), findsOneWidget);
          expect(find.byKey(const Key('uncertain-retry')), findsOneWidget);
          expect(find.byKey(const Key('submitError')), findsNothing);
          expect(find.textContaining('belum dipatok'), findsNothing);
          // The Desa list was reloaded to look for the goal.
          expect(repository.listCalls, greaterThanOrEqualTo(2));
        },
      );
    }

    testWidgets('a same-named goal with another target is not a match', (
      tester,
    ) async {
      final repository = _CreatingRepository(
        createResult: const NetworkException(),
        listResults: [
          <Goal>[],
          [testGoal(id: 21, title: 'Kamera mirrorless', target: 8000000)],
        ],
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(kNewGoalUncertainTitle), findsOneWidget);
      expect(find.text('kavling 21'), findsNothing);
    });

    testWidgets(
        'a goal with the same title and target that was listed before the '
        'submit is not a match', (
      tester,
    ) async {
      final old = testGoal(
        id: 21,
        title: 'Kamera mirrorless',
        target: 9000000,
        createdAt: _now.subtract(const Duration(days: 2)),
      );
      final repository = _CreatingRepository(
        createResult: const NetworkException(),
        listResults: [
          [old],
          [old],
        ],
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(kNewGoalUncertainTitle), findsOneWidget);
      expect(find.text('kavling 21'), findsNothing);
    });

    testWidgets('when the list also fails, says to check first', (
      tester,
    ) async {
      final repository = _CreatingRepository(
        createResult: const NetworkException(),
        listResults: [<Goal>[], const NetworkException()],
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(find.text(kNewGoalUncertainTitle), findsOneWidget);
    });

    testWidgets('the explicit retry creates when the goal is still missing', (
      tester,
    ) async {
      final repository = _CreatingRepository(
        createResult: const NetworkException(),
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(repository.createCalls, hasLength(1));

      repository.createResult = null;
      await tester.ensureVisible(find.byKey(const Key('uncertain-retry')));
      await tester.tap(find.byKey(const Key('uncertain-retry')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(2));
      expect(find.text('kavling 16'), findsOneWidget);
    });

    testWidgets(
      'the explicit retry opens the goal instead when it has appeared '
      'meanwhile',
      (tester) async {
        final repository = _CreatingRepository(
          createResult: const NetworkException(),
          listResults: [
            <Goal>[],
            <Goal>[],
            [testGoal(id: 21, title: 'Kamera mirrorless', target: 9000000)],
          ],
        );
        await _pumpNewGoal(tester, repository);

        await _fill(tester);
        await _tapSubmit(tester);
        await tester.pumpAndSettle();
        expect(find.text(kNewGoalUncertainTitle), findsOneWidget);

        repository.createResult = null;
        await tester.ensureVisible(find.byKey(const Key('uncertain-retry')));
        await tester.tap(find.byKey(const Key('uncertain-retry')));
        await tester.pumpAndSettle();

        expect(repository.createCalls, hasLength(1));
        expect(find.text('kavling 21'), findsOneWidget);
        expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
      },
    );

    testWidgets('"Cek daftar di Desa" goes back to the Desa', (tester) async {
      final repository = _CreatingRepository(
        createResult: const NetworkException(),
      );
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('uncertain-check')));
      await tester.tap(find.byKey(const Key('uncertain-check')));
      await tester.pumpAndSettle();

      expect(find.text('desa'), findsOneWidget);
      expect(repository.createCalls, hasLength(1));
    });
  });
}
