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
  _CreatingRepository({this.createResult}) : super([<Goal>[]]);

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
        builder: (context, state) =>
            Text('kavling ${state.pathParameters['id']}'),
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

    testWidgets('a lost connection asks to retry, and retry works',
        (tester) async {
      final repository =
          _CreatingRepository(createResult: const NetworkException());
      await _pumpNewGoal(tester, repository);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(kNewGoalNetworkMessage), findsOneWidget);

      repository.createResult = null;
      await _tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(2));
      expect(find.text('kavling 16'), findsOneWidget);
    });

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
}
