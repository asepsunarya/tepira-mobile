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
/// When [listAnswerAfterCreate] is set, [create] makes it the [listAnswer]
/// (the create was stored although its answer is lost).
class _Repo implements GoalsRepository {
  _Repo({required this.createAnswer, Object? listAnswer})
      : listAnswer = listAnswer ?? <Goal>[];

  Object createAnswer;
  Object listAnswer;
  Completer<void>? createGate;
  Completer<void>? listGate;
  Object? listAnswerAfterCreate;
  int createCalls = 0;
  int listCalls = 0;

  /// [listCalls] when [create] was last called.
  int listCallsAtCreate = 0;

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
    listCallsAtCreate = listCalls;
    final after = listAnswerAfterCreate;
    if (after != null) listAnswer = after;
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

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  DateTime Function()? clock,
  bool viaDesa = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: viaDesa ? '/' : GoalRoutes.create,
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
        clockProvider.overrideWithValue(clock ?? () => _now),
      ],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  if (!viaDesa) return;
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
      ('422', const ApiException('Target tidak valid.', statusCode: 422)),
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
        'new goals (not in the snapshot) match whatever their createdAt '
        'says against the phone clock: newest wins', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = [
        _goal(50, ago: const Duration(hours: 1)),
        // Server clock far ahead of the phone.
        _goal(51, ago: -const Duration(hours: 1)),
      ];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 51'), findsOneWidget);
      expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
    });

    testWidgets(
      'an identical goal listed before this submit, however recent, is never '
      'recovered as the new one',
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
      'explicit retry while the list still cannot be loaded does not create '
      '(no blind duplicate)',
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

  group('snapshot of known goals (re-test of the fix)', () {
    testWidgets(
        'Desa list failed before submit: the pre-fetched snapshot excludes '
        'an old identical goal', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: const NetworkException(),
      );
      await _pump(tester, repo);
      repo.listAnswer = [_goal(100, ago: const Duration(hours: 1))];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 100'), findsNothing);
      expect(_uncertain, findsOneWidget);
    });

    testWidgets(
        'Desa list failed before submit: with the pre-fetched snapshot the '
        'goal this attempt stored is still recovered', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: const NetworkException(),
      );
      await _pump(tester, repo);
      repo
        ..listAnswer = <Goal>[]
        ..listAnswerAfterCreate = [_goal(101, ago: const Duration(seconds: 3))];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 101'), findsOneWidget);
      expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
    });

    testWidgets(
      'Desa list failed before submit: an identical goal created minutes '
      'earlier is excluded by the pre-fetched snapshot, never recovered',
      (tester) async {
        // goalsProvider has no value at submit (Desa list errored), so the
        // screen loads the list itself before creating; the goal from two
        // minutes earlier is in that snapshot and is not taken for this
        // attempt's goal.
        final repo = _Repo(
          createAnswer: const NetworkException(),
          listAnswer: const NetworkException(),
        );
        await _pump(tester, repo);
        repo.listAnswer = [_goal(102, ago: const Duration(minutes: 2))];

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(repo.listCallsAtCreate, greaterThan(0), reason: 'pre-fetch');
        expect(find.text('kavling 102'), findsNothing);
        expect(_uncertain, findsOneWidget);
      },
    );

    testWidgets(
        'goal from the first timed-out attempt shows up only on a retry '
        '8 minutes later: found, no second create', (tester) async {
      var now = _now;
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, clock: () => now);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(_uncertain, findsOneWidget);

      now = _now.add(const Duration(minutes: 8));
      repo.listAnswer = [_goal(110, ago: -const Duration(seconds: 1))];
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('kavling 110'), findsOneWidget);
    });

    testWidgets(
        'second attempt also times out; the goal from the FIRST attempt is '
        'then found (snapshot from before the first attempt)', (tester) async {
      var now = _now;
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, clock: () => now);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      // 25 minutes later: the pre-create check still sees nothing, the
      // second create times out, and then the first attempt's goal appears.
      now = _now.add(const Duration(minutes: 25));
      repo.createGate = Completer();
      await _tap(tester, 'uncertain-retry');
      await tester.pump();
      expect(repo.createCalls, 2, reason: 'pre-create check saw nothing');
      repo.listAnswer = [_goal(111)]; // createdAt == first attempt start
      repo.createGate!.complete();
      await tester.pumpAndSettle();

      expect(repo.createCalls, 2);
      expect(find.text('kavling 111'), findsOneWidget);
    });

    for (final (name, offset) in <(String, Duration)>[
      ('a day before the first attempt', -const Duration(days: 1)),
      ('11 min before the first attempt', -const Duration(minutes: 11)),
      ('between attempts', const Duration(minutes: 15)),
      ('11 min after the retry', const Duration(minutes: 41)),
      ('a day after the retry', const Duration(days: 1, minutes: 30)),
    ]) {
      testWidgets(
          'no time window: a new goal is found on a retry 30 min later, '
          'createdAt $name', (tester) async {
        var now = _now;
        final repo = _Repo(createAnswer: const NetworkException());
        await _pump(tester, repo, clock: () => now);

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        now = _now.add(const Duration(minutes: 30));
        repo.listAnswer = [
          testGoal(
            id: 120,
            title: 'Kamera mirrorless',
            target: 9000000,
            createdAt: _now.add(offset),
          ),
        ];
        await _tap(tester, 'uncertain-retry');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1);
        expect(find.text('kavling 120'), findsOneWidget);
      });
    }

    testWidgets(
        'list check fails after the failed create: uncertain notice only; '
        'retry with list still down shows the check-failed message and does '
        'not create; once the list loads the stored goal is opened',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = const NetworkException();

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(_uncertain, findsOneWidget);
      expect(_submitError, findsNothing);
      expect(find.text(kNewGoalCheckFailedMessage), findsNothing);

      repo.createAnswer = _goal(130);
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(_uncertain, findsOneWidget);
      expect(
        tester.widget<Text>(_submitError).data,
        kNewGoalCheckFailedMessage,
      );
      expect(find.text('Patok kavling'), findsOneWidget);

      // Main submit button takes the same path.
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(
        tester.widget<Text>(_submitError).data,
        kNewGoalCheckFailedMessage,
      );

      repo.listAnswer = [_goal(131, ago: const Duration(seconds: 2))];
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(find.text('kavling 131'), findsOneWidget);
    });

    testWidgets(
        'check-failed message clears and a create happens once the list loads '
        'empty', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      repo.listAnswer = const ServerException(statusCode: 503);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(find.text(kNewGoalCheckFailedMessage), findsOneWidget);

      repo
        ..listAnswer = <Goal>[]
        ..createAnswer = _goal(140);
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 2);
      expect(find.text('kavling 140'), findsOneWidget);
    });

    testWidgets(
        'a goal known before submit stays excluded on later retries, even '
        'when a new identical goal also appears', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: [_goal(150, ago: const Duration(minutes: 1))],
      );
      await _pump(tester, repo);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(find.text('kavling 150'), findsNothing);

      repo.listAnswer = [
        _goal(150, ago: const Duration(minutes: 1)),
        _goal(151, ago: -const Duration(seconds: 1)),
      ];
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(find.text('kavling 151'), findsOneWidget);
    });

    for (final (name, skew) in <(String, Duration)>[
      ('ahead of', const Duration(minutes: 15)),
      ('behind', -const Duration(minutes: 15)),
    ]) {
      testWidgets(
          'phone clock 15 min $name the server: the stored goal is recovered '
          'on retry and no duplicate is created', (tester) async {
        // The first create times out but was stored with the server's
        // createdAt (_now). The snapshot (empty list) proves it is new, so
        // the phone clock is irrelevant.
        final repo = _Repo(createAnswer: const NetworkException());
        await _pump(tester, repo, clock: () => _now.add(skew));

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();
        expect(_uncertain, findsOneWidget);

        repo
          ..listAnswer = [_goal(160)]
          ..createAnswer = _goal(161);
        await _tap(tester, 'uncertain-retry');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1, reason: 'second create = duplicate goal');
        expect(find.text('kavling 160'), findsOneWidget);
      });

      testWidgets(
          'phone clock 15 min $name the server: a goal stored by the failed '
          'create is recovered right away', (tester) async {
        final repo = _Repo(createAnswer: const NetworkException());
        await _pump(tester, repo, clock: () => _now.add(skew));
        repo.listAnswerAfterCreate = [_goal(162)];

        await _fill(tester);
        await _tap(tester, 'submit');
        await tester.pumpAndSettle();

        expect(repo.createCalls, 1);
        expect(find.text('kavling 162'), findsOneWidget);
      });
    }
  });

  group('no goals list loaded before submit', () {
    testWidgets(
        'opened directly: the list is pre-fetched before creating and an old '
        'identical goal is never adopted', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: [_goal(200, ago: const Duration(minutes: 2))],
      );
      await _pump(tester, repo, viaDesa: false);
      expect(repo.listCalls, 0, reason: 'nothing watched the list yet');

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(repo.listCallsAtCreate, 1, reason: 'pre-fetch before create');
      expect(find.text('kavling 200'), findsNothing);
      expect(_uncertain, findsOneWidget);

      // A retry still does not take it for this screen's goal.
      repo.listAnswer = [
        _goal(200, ago: const Duration(minutes: 2)),
        _goal(201),
      ];
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(find.text('kavling 201'), findsOneWidget);
    });

    testWidgets(
        'pre-fetch fails and the create fails: uncertain notice, nothing '
        'adopted, and a retry never creates blindly', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: const NetworkException(),
      );
      await _pump(tester, repo, viaDesa: false);
      // The create was stored; afterwards the list loads and shows it.
      repo.listAnswerAfterCreate = [_goal(210)];

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(repo.listCallsAtCreate, 1, reason: 'pre-fetch attempted');
      expect(find.text('kavling 210'), findsNothing);
      expect(find.text(kNewGoalRecoveredMessage), findsNothing);
      expect(_uncertain, findsOneWidget);

      // Retry: an identical goal exists but may be older than this screen.
      repo.createAnswer = _goal(211);
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(find.text('kavling 210'), findsNothing);
      expect(tester.widget<Text>(_submitError).data, kNewGoalAmbiguousMessage);
      expect(_uncertain, findsOneWidget);

      // Retry with the list down: still no create.
      repo.listAnswer = const NetworkException();
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(
        tester.widget<Text>(_submitError).data,
        kNewGoalCheckFailedMessage,
      );
    });

    testWidgets(
        'pre-fetch fails, retry list has no identical goal: creates once, '
        'and that list is the snapshot if the retry is lost too',
        (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: const NetworkException(),
      );
      await _pump(tester, repo, viaDesa: false);

      await _fill(tester);
      await _tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(_uncertain, findsOneWidget);

      repo
        ..listAnswer = [testGoal(id: 220, title: 'Lain')]
        ..listAnswerAfterCreate = [
          testGoal(id: 220, title: 'Lain'),
          _goal(221),
        ];
      await _tap(tester, 'uncertain-retry');
      await tester.pumpAndSettle();

      expect(repo.createCalls, 2);
      expect(find.text('kavling 221'), findsOneWidget);
      expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
    });
  });
}
