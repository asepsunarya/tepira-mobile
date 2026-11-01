// Independent edge-case tests for the duplicate-goal guard of NewGoalScreen:
// a create that fails on the network may still have been stored, so the
// screen must look for it before (ever) creating again.
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

final DateTime _now = DateTime.utc(2026, 11, 1, 12);

/// Repository whose [list] answers the current [listAnswer] (thrown when an
/// [Exception]) and whose [create] answers [createAnswer] after [createGate].
class _Repo implements GoalsRepository {
  _Repo({required this.createAnswer, Object? listAnswer})
      : listAnswer = listAnswer ?? <Goal>[];

  Object createAnswer;
  Object listAnswer;
  Completer<void>? createGate;
  Completer<void>? listGate;
  int createCalls = 0;
  int listCalls = 0;

  @override
  Future<List<Goal>> list() async {
    listCalls++;
    final answer = listAnswer;
    await listGate?.future;
    if (answer is Exception) throw answer;
    return answer as List<Goal>;
  }

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) async {
    createCalls++;
    final answer = createAnswer;
    await createGate?.future;
    if (answer is Exception) throw answer;
    return answer as Goal;
  }

  @override
  Future<GoalDetail> detail(int id) => throw UnimplementedError();

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) =>
      throw UnimplementedError();
}

class _Desa extends ConsumerWidget {
  const _Desa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(goalsProvider);
    return const Text('desa');
  }
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
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
            Scaffold(body: Text('kavling ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsRepositoryProvider.overrideWithValue(repo),
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
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('title')), 'Kamera mirrorless');
  await tester.enterText(find.byKey(const Key('target')), '9000000');
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)), warnIfMissed: false);
}

Goal _goal(int id, {int target = 9000000, Duration ago = Duration.zero}) =>
    testGoal(
      id: id,
      title: 'Kamera mirrorless',
      target: target,
      createdAt: _now.subtract(ago),
    );

final Finder _uncertain = find.byKey(const Key('uncertain-create'));
final Finder _submitError = find.byKey(const Key('submitError'));

void main() {
  group('which failures trigger the guard', () {
    for (final (name, error) in <(String, AppException)>[
      ('timeout / no connection', const NetworkException()),
      ('502', const ServerException(statusCode: 502)),
      ('503', const ServerException(statusCode: 503)),
      ('504', const ServerException(statusCode: 504)),
    ]) {
      testWidgets('$name: guard runs (list reloaded, uncertain notice)',
          (tester) async {
        final repo = _Repo(createAnswer: error);
        await _pump(tester, repo);
        final before = repo.listCalls;

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1);
        expect(repo.listCalls, greaterThan(before));
        expect(_uncertain, findsOneWidget);
        expect(_submitError, findsNothing);
      });
    }

    for (final (name, error) in <(String, AppException)>[
      (
        '400 ServerException',
        const ServerException(
          message: 'Nama goal terlalu panjang.',
          code: 'bad_request',
          statusCode: 400,
        ),
      ),
      (
        '400 ApiException',
        const ApiException('Target tidak valid.', statusCode: 400)
      ),
      ('500', const ServerException(statusCode: 500)),
      ('401', const UnauthorizedException()),
    ]) {
      testWidgets('$name: guard does NOT run, definite error shown',
          (tester) async {
        final repo = _Repo(
          createAnswer: error,
          // Even if a same-looking goal exists, a definite failure must not
          // be "recovered" into it.
          listAnswer: [_goal(21)],
        );
        await _pump(tester, repo);
        final before = repo.listCalls;

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1);
        expect(repo.listCalls, before, reason: 'no list check after $name');
        expect(_uncertain, findsNothing);
        expect(find.text('kavling 21'), findsNothing);
        expect(tester.widget<Text>(_submitError).data, error.message);
      });
    }
  });

  group('matching', () {
    testWidgets('match found: opens it with the notice, no second create',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [_goal(21, ago: const Duration(seconds: 5))];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 21'), findsOneWidget);
      expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
    });

    testWidgets('no match: stays with the uncertain notice', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [testGoal(id: 3, title: 'Lain', target: 9000000)];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(_uncertain, findsOneWidget);
      expect(find.byType(NewGoalScreen), findsOneWidget);
    });

    testWidgets(
        'two goals with the same title: the one with the right target wins '
        'even if older', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [
        _goal(30, target: 1000, ago: const Duration(seconds: 1)),
        _goal(31, ago: const Duration(minutes: 1)),
      ];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(find.text('kavling 31'), findsOneWidget);
    });

    testWidgets('two recent goals with same title and target: newest wins',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [
        _goal(40, ago: const Duration(minutes: 4)),
        _goal(41, ago: const Duration(seconds: 2)),
        _goal(42, ago: const Duration(minutes: 2)),
      ];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(find.text('kavling 41'), findsOneWidget);
    });

    testWidgets(
        'same title and target but outside the recency window: '
        'no match', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [
        _goal(50, ago: kNewGoalMatchWindow + const Duration(seconds: 1)),
        // Server clock far ahead also falls outside the window.
        _goal(51, ago: -(kNewGoalMatchWindow + const Duration(minutes: 1))),
      ];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(_uncertain, findsOneWidget);
      expect(find.text('kavling 50'), findsNothing);
      expect(find.text('kavling 51'), findsNothing);
    });

    testWidgets(
      'BUG: an identical goal that already existed before this submit '
      '(within the window) is "recovered" instead of the new attempt',
      (tester) async {
        // The user created "Kamera mirrorless / 9.000.000" two minutes ago,
        // came back and deliberately creates a second identical one; the
        // create times out and was NOT stored. The pre-existing goal (which
        // was already in the list before submit) must not be treated as the
        // one this attempt created.
        final existing = _goal(60, ago: const Duration(minutes: 2));
        final repo = _Repo(
          createAnswer: const NetworkException(),
          listAnswer: [existing],
        );
        await _pump(tester, repo);

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(find.text('kavling 60'), findsNothing);
        expect(_uncertain, findsOneWidget);
      },
    );
  });

  group('list reload failing during the check', () {
    for (final listError in <AppException>[
      const NetworkException(),
      const ServerException(statusCode: 500),
      const UnauthorizedException(),
    ]) {
      testWidgets('${listError.runtimeType}: uncertain notice, no create retry',
          (tester) async {
        final repo = _Repo(createAnswer: const NetworkException());
        await _pump(tester, repo);
        repo.listAnswer = listError;

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1);
        expect(_uncertain, findsOneWidget);
        expect(
          find.text('Patok kavling'),
          findsOneWidget,
          reason: 'not stuck in submitting',
        );
      });
    }

    testWidgets(
      'BUG: explicit retry while the list still cannot be loaded creates '
      'blindly (possible duplicate)',
      (tester) async {
        final repo = _Repo(createAnswer: const NetworkException());
        await _pump(tester, repo);
        repo.listAnswer = const ServerException(statusCode: 500);

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();
        expect(repo.createCalls, 1);

        // The first create was actually stored; the list endpoint is flaky.
        repo.createAnswer = _goal(70);
        await _tap(tester, 'uncertain-retry');
        await tester.pumpAndSettle();

        // The guard could not verify absence, so it must not create again.
        expect(repo.createCalls, 1);
        expect(_uncertain, findsOneWidget);
      },
    );

    testWidgets('slow list check: submit disabled, double tap is ignored',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listGate = Completer();

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pump();
      await _tap(tester, 'submit');
      await tester.pump();
      await _tap(tester, 'submit');
      await tester.pump();

      expect(repo.createCalls, 1);
      expect(find.text('Mematok kavling…'), findsOneWidget);

      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(_uncertain, findsOneWidget);
    });
  });

  group('no auto-retry', () {
    testWidgets('waiting long after the uncertain notice never creates again',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      final listsAfter = repo.listCalls;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(minutes: 1));
      }
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(repo.listCalls, listsAfter, reason: 'no background polling');
    });

    testWidgets('a retry that fails on the network again does not loop',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 2);
      expect(_uncertain, findsOneWidget);
    });
  });

  group('explicit retry', () {
    testWidgets('retry creates exactly once and opens the new goal',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      repo.createAnswer = _goal(80);
      final listsBefore = repo.listCalls;
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 2);
      expect(
        repo.listCalls,
        greaterThan(listsBefore),
        reason: 'retry checks the list before creating',
      );
      expect(find.text('kavling 80'), findsOneWidget);
    });

    testWidgets('double tap on retry while the create is in flight: once',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      repo
        ..createAnswer = _goal(81)
        ..createGate = Completer();
      await _tap(tester, 'uncertain-retry');
      await tester.pump();
      await _tap(tester, 'uncertain-retry');
      await tester.pump();
      await _tap(tester, 'submit');
      await tester.pump();

      expect(repo.createCalls, 2);
      repo.createGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.createCalls, 2);
      expect(find.text('kavling 81'), findsOneWidget);
    });

    testWidgets('double tap on retry during the pre-create list check: once',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      repo
        ..createAnswer = _goal(82)
        ..listGate = Completer();
      await _tap(tester, 'uncertain-retry');
      await tester.pump();
      await _tap(tester, 'uncertain-retry');
      await tester.pump();
      expect(repo.createCalls, 1, reason: 'still checking the list');

      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.createCalls, 2);
      expect(find.text('kavling 82'), findsOneWidget);
    });

    testWidgets('the main submit button also checks before creating again',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      repo
        ..createAnswer = _goal(83)
        ..listAnswer = [_goal(21, ago: const Duration(seconds: 30))];
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 21'), findsOneWidget);
    });
  });

  testWidgets('double tap on the first submit creates once', (tester) async {
    final repo = _Repo(createAnswer: _goal(90))..createGate = Completer();
    await _pump(tester, repo);

    await _fill(tester);
    await _tap(tester, 'submit');
    await _tap(tester, 'submit');
    await tester.pump();
    await _tap(tester, 'submit');
    await tester.pump();

    expect(repo.createCalls, 1);
    repo.createGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(find.text('kavling 90'), findsOneWidget);
  });
}
