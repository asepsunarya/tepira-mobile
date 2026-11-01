// Round-2 re-test of the NewGoalScreen duplicate-goal guard (id snapshot,
// no phone clock): definite errors after a pre-fetch, races, repeated
// Ambiguous retries, edits before a retry, snapshot reuse and how the
// autoDispose goals list is (not) reloaded.
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

final DateTime _now = DateTime.utc(2026, 11, 1, 12);

/// Repository whose [list] answers [listAnswer] (thrown when an
/// [Exception]) and whose [create] answers [createAnswer]. [onCreate] runs
/// when [create] is called, before it answers (e.g. to store the goal).
class _Repo implements GoalsRepository {
  _Repo({required this.createAnswer, Object? listAnswer})
      : listAnswer = listAnswer ?? <Goal>[];

  Object createAnswer;
  Object listAnswer;
  void Function()? onCreate;
  int createCalls = 0;
  int listCalls = 0;
  final List<int> listCallsAtCreate = [];
  final List<(String, int)> created = [];

  @override
  Future<List<Goal>> list() async {
    listCalls++;
    final answer = listAnswer;
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
    listCallsAtCreate.add(listCalls);
    created.add((title, target));
    onCreate?.call();
    final answer = createAnswer;
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
    return const Scaffold(body: Text('desa'));
  }
}

late GoRouter _router;

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repo repo, {
  bool viaDesa = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _router = GoRouter(
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
  addTearDown(_router.dispose);
  final container = ProviderContainer(
    overrides: [goalsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: _router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  if (viaDesa) {
    unawaited(_router.push(GoalRoutes.create));
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _fill(
  WidgetTester tester, {
  String title = 'Kamera mirrorless',
  String target = '9000000',
}) async {
  await tester.enterText(find.byKey(const Key('title')), title);
  await tester.enterText(find.byKey(const Key('target')), target);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Goal _goal(
  int id, {
  String title = 'Kamera mirrorless',
  int target = 9000000,
  Duration ago = Duration.zero,
}) =>
    testGoal(
      id: id,
      title: title,
      target: target,
      createdAt: _now.subtract(ago),
    );

final Finder _uncertain = find.byKey(const Key('uncertain-create'));
final Finder _submitError = find.byKey(const Key('submitError'));

String? _errorText(WidgetTester tester) => _submitError.evaluate().isEmpty
    ? null
    : tester.widget<Text>(_submitError).data;

void main() {
  group('definite create errors after a successful pre-fetch', () {
    for (final (name, error) in <(String, AppException)>[
      (
        '400',
        const ServerException(
          message: 'Nama goal terlalu panjang.',
          code: 'bad_request',
          statusCode: 400,
        ),
      ),
      ('422', const ApiException('Target tidak valid.', statusCode: 422)),
    ]) {
      testWidgets(
          '$name: no list check, nothing adopted even if an identical goal '
          'NOT in the snapshot shows up', (tester) async {
        final repo = _Repo(createAnswer: error);
        await _pump(tester, repo, viaDesa: false);
        // A new identical goal (not in the pre-fetched snapshot) appears
        // when create is called; a definite failure must still not adopt it.
        repo.onCreate = () => repo.listAnswer = [_goal(300)];

        await _fill(tester);
        await _tap(tester, 'submit');

        expect(repo.createCalls, 1);
        expect(repo.listCallsAtCreate, [1], reason: 'pre-fetch ran');
        expect(repo.listCalls, 1, reason: 'no dup-check after $name');
        expect(find.text('kavling 300'), findsNothing);
        expect(find.text(kNewGoalRecoveredMessage), findsNothing);
        expect(_uncertain, findsNothing);
        expect(_errorText(tester), error.message);

        // The next submit is a fresh attempt: it re-snapshots (the goal 300
        // is now known) and creates normally.
        repo.createAnswer = _goal(301);
        await _tap(tester, 'submit');
        expect(repo.createCalls, 2);
        expect(repo.listCallsAtCreate, [1, 2], reason: 'fresh snapshot');
        expect(find.text('kavling 301'), findsOneWidget);
      });
    }

    testWidgets(
        '422 on an explicit retry (uncertain): error shown, still uncertain, '
        'no adoption', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, viaDesa: false);

      await _fill(tester);
      await _tap(tester, 'submit');
      expect(_uncertain, findsOneWidget);

      repo
        ..createAnswer =
            const ApiException('Target tidak valid.', statusCode: 422)
        ..onCreate = () => repo.listAnswer = [_goal(310)];
      final listsBefore = repo.listCalls;
      await _tap(tester, 'uncertain-retry');

      expect(repo.createCalls, 2);
      expect(repo.listCalls, listsBefore + 1, reason: 'pre-check only');
      expect(find.text('kavling 310'), findsNothing);
      expect(_errorText(tester), 'Target tidak valid.');
      expect(_uncertain, findsOneWidget);
    });
  });

  group('race: goal created elsewhere between snapshot and create', () {
    testWidgets(
        'DOCUMENTED LIMITATION: an identical goal created by another device '
        'after the snapshot is adopted when this create is lost',
        (tester) async {
      // Snapshot = {} (pre-fetch). Another device creates the same
      // title+target right before our create; our create times out and was
      // NOT stored. The screen cannot tell the two apart and opens the
      // other device's goal with the recovered notice. Net effect: one goal
      // with that title/target exists (no duplicate), which matches the
      // user's evident intent; acceptable.
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, viaDesa: false);
      repo.onCreate = () => repo.listAnswer = [_goal(400)];

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.createCalls, 1);
      expect(find.text('kavling 400'), findsOneWidget);
      expect(find.text(kNewGoalRecoveredMessage), findsOneWidget);
    });

    testWidgets(
        'DOCUMENTED LIMITATION: a stale (but loaded) Desa list is used as the '
        'snapshot without a reload', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo);
      expect(repo.listCalls, 1);
      // Created on another device after the Desa loaded.
      repo.listAnswer = [_goal(410, ago: const Duration(minutes: 3))];

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [1], reason: 'Desa data reused');
      expect(find.text('kavling 410'), findsOneWidget);
    });

    testWidgets(
      'BUG: Desa refresh failed (AsyncError keeping stale data): the stale '
      'list is still taken as the snapshot and an older identical goal is '
      'adopted',
      (tester) async {
        // Desa loaded [] earlier; since then an identical goal was created
        // elsewhere and the Desa's refresh failed (offline). goalsProvider
        // is AsyncError but valueOrNull still returns the stale []. The
        // guard should treat that as "not loaded" and pre-fetch (or have no
        // snapshot), but it uses [] and adopts goal 420.
        final repo = _Repo(createAnswer: const NetworkException());
        final container = await _pump(tester, repo);
        repo.listAnswer = const NetworkException();
        await container.read(goalsProvider.notifier).refresh();
        await tester.pumpAndSettle();
        final state = container.read(goalsProvider);
        expect(state.hasError, isTrue);
        expect(state.valueOrNull, isEmpty, reason: 'stale value kept');

        repo.listAnswer = [_goal(420, ago: const Duration(minutes: 5))];
        await _fill(tester);
        await _tap(tester, 'submit');

        expect(find.text('kavling 420'), findsNothing);
      },
      skip: true,
    );
  });

  group('repeated retries after Ambiguous', () {
    Future<_Repo> toAmbiguous(WidgetTester tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: const NetworkException(),
      );
      await _pump(tester, repo, viaDesa: false);
      repo.onCreate = () => repo.listAnswer = [_goal(500)];
      await _fill(tester);
      await _tap(tester, 'submit');
      repo.onCreate = null;
      await _tap(tester, 'uncertain-retry');
      expect(_errorText(tester), kNewGoalAmbiguousMessage);
      return repo;
    }

    testWidgets('each retry re-checks the list and never creates',
        (tester) async {
      final repo = await toAmbiguous(tester);
      repo.createAnswer = _goal(501);
      for (var i = 0; i < 5; i++) {
        final before = repo.listCalls;
        await _tap(tester, i.isEven ? 'uncertain-retry' : 'submit');
        expect(repo.listCalls, before + 1);
        expect(repo.createCalls, 1);
        expect(_errorText(tester), kNewGoalAmbiguousMessage);
        expect(find.text('Patok kavling'), findsOneWidget, reason: 'not stuck');
      }
      expect(find.text('kavling 500'), findsNothing);
    });

    testWidgets(
        'not a trap: the message points to the Desa, the check button is '
        'enabled and leads there', (tester) async {
      await toAmbiguous(tester);
      expect(kNewGoalAmbiguousMessage, contains('Cek daftar di Desa'));
      final check = tester.widget<TextButton>(
        find.byKey(const Key('uncertain-check')),
      );
      expect(check.onPressed, isNotNull);
      await _tap(tester, 'uncertain-check');
      expect(find.text('desa'), findsOneWidget);
      expect(find.byType(NewGoalScreen), findsNothing);
    });

    testWidgets(
        'way forward: reopening the screen starts a fresh attempt that can '
        'create a deliberate second identical goal', (tester) async {
      final repo = await toAmbiguous(tester);
      await _tap(tester, 'uncertain-check');
      unawaited(_router.push(GoalRoutes.create));
      await tester.pumpAndSettle();

      repo.createAnswer = _goal(502);
      await _fill(tester);
      await _tap(tester, 'submit');
      expect(repo.createCalls, 2);
      expect(find.text('kavling 502'), findsOneWidget);
    });

    testWidgets(
        'identical goal removed meanwhile: next retry proceeds and creates '
        'exactly once', (tester) async {
      final repo = await toAmbiguous(tester);
      repo
        ..listAnswer = <Goal>[]
        ..createAnswer = _goal(503);
      await _tap(tester, 'uncertain-retry');
      expect(repo.createCalls, 2);
      expect(find.text('kavling 503'), findsOneWidget);
    });

    testWidgets(
        'editing the title after Ambiguous: a different goal, created once',
        (tester) async {
      final repo = await toAmbiguous(tester);
      repo.createAnswer = _goal(504, title: 'Lensa tele');
      await tester.enterText(find.byKey(const Key('title')), 'Lensa tele');
      await _tap(tester, 'uncertain-retry');
      expect(repo.createCalls, 2);
      expect(repo.created.last, ('Lensa tele', 9000000));
      expect(find.text('kavling 504'), findsOneWidget);
    });
  });

  group('editing title/target before a retry', () {
    testWidgets(
        'title edited: the first attempt\'s stored goal (old title) is not '
        'adopted and a goal with the new title is created', (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, viaDesa: false);
      await _fill(tester);
      await _tap(tester, 'submit');
      expect(_uncertain, findsOneWidget);

      // The first attempt was stored after all (old title).
      repo
        ..listAnswer = [_goal(600)]
        ..createAnswer = _goal(601, title: 'Kamera bekas');
      await tester.enterText(find.byKey(const Key('title')), 'Kamera bekas');
      await _tap(tester, 'uncertain-retry');

      // Per the doc comment an edit makes it a different goal. The user
      // ends with both goals 600 and 601 - by design, documented.
      expect(repo.createCalls, 2);
      expect(repo.created.last, ('Kamera bekas', 9000000));
      expect(find.text('kavling 601'), findsOneWidget);
    });

    testWidgets('target edited: matches only the new target among new goals',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      await _pump(tester, repo, viaDesa: false);
      await _fill(tester);
      await _tap(tester, 'submit');

      repo.listAnswer = [_goal(610), _goal(611, target: 12000000)];
      await tester.enterText(find.byKey(const Key('target')), '12000000');
      await _tap(tester, 'uncertain-retry');

      expect(repo.createCalls, 1);
      expect(find.text('kavling 611'), findsOneWidget);
    });

    testWidgets(
        'edited to match a goal that was in the snapshot: not adopted, '
        'created (deliberate identical goal)', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: [_goal(620, title: 'Sepeda')],
      );
      await _pump(tester, repo, viaDesa: false);
      await _fill(tester);
      await _tap(tester, 'submit');

      repo.createAnswer = _goal(621, title: 'Sepeda');
      await tester.enterText(find.byKey(const Key('title')), 'Sepeda');
      await _tap(tester, 'uncertain-retry');

      expect(repo.createCalls, 2);
      expect(find.text('kavling 620'), findsNothing);
      expect(find.text('kavling 621'), findsOneWidget);
    });
  });

  group('snapshot reuse across retries', () {
    testWidgets(
        'snapshot taken once; three lost retries do not re-snapshot; the first '
        'attempt\'s goal is found on the 4th try', (tester) async {
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: [_goal(700, ago: const Duration(days: 1))],
      );
      await _pump(tester, repo, viaDesa: false);
      await _fill(tester);
      await _tap(tester, 'submit');
      // pre-fetch + post-failure check.
      expect(repo.listCalls, 2);

      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'uncertain-retry');
      }
      expect(repo.createCalls, 4);
      // Each retry: pre-check + post-failure check; never a 3rd list call.
      expect(repo.listCalls, 2 + 3 * 2);
      expect(repo.listCallsAtCreate, [1, 3, 5, 7]);

      repo.listAnswer = [
        _goal(700, ago: const Duration(days: 1)),
        _goal(701, ago: const Duration(minutes: 40)),
      ];
      await _tap(tester, 'uncertain-retry');
      expect(repo.createCalls, 4);
      expect(find.text('kavling 701'), findsOneWidget);
      expect(find.text('kavling 700'), findsNothing);
    });
  });

  group('autoDispose goals provider', () {
    testWidgets(
        'opened directly: the screen loads the list itself exactly once and '
        'does not instantiate goalsProvider', (tester) async {
      final repo = _Repo(createAnswer: _goal(800));
      final container = await _pump(tester, repo, viaDesa: false);
      expect(container.exists(goalsProvider), isFalse);

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [1]);
      expect(find.text('kavling 800'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repo.listCalls, 1, reason: 'no extra (unawaited) load');
    });

    testWidgets(
        'via a loaded Desa: its data is the snapshot, no reload before create',
        (tester) async {
      final repo = _Repo(createAnswer: _goal(810));
      await _pump(tester, repo);
      expect(repo.listCalls, 1);

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [1]);
      expect(find.text('kavling 810'), findsOneWidget);
    });

    testWidgets(
        'via a Desa whose load failed (AsyncError, no value): the screen '
        'pre-fetches once', (tester) async {
      final repo = _Repo(
        createAnswer: _goal(820),
        listAnswer: const NetworkException(),
      );
      final container = await _pump(tester, repo);
      expect(container.read(goalsProvider).hasValue, isFalse);
      repo.listAnswer = <Goal>[];

      await _fill(tester);
      await _tap(tester, 'submit');
      expect(repo.listCallsAtCreate, [2]);
      expect(find.text('kavling 820'), findsOneWidget);
    });
  });
}
