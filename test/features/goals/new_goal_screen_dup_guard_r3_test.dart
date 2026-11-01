// Round-3 re-test of the NewGoalScreen duplicate-goal guard: the snapshot
// uses the Desa goals list only when it holds settled data, otherwise it
// loads its own list. Edge cases around the Desa provider's state.
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
/// [Exception], awaited when a [Future]) and whose [create] answers [createAnswer]. [onCreate] runs
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
    if (answer is Future<List<Goal>>) return answer;
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
  group('snapshot source', () {
    testWidgets(
        'Desa first load still pending (AsyncLoading, no value): the screen '
        'loads its own list; an older identical goal is not adopted',
        (tester) async {
      final firstLoad = Completer<List<Goal>>();
      final repo = _Repo(
        createAnswer: const NetworkException(),
        listAnswer: firstLoad.future,
      );
      final container = await _pump(tester, repo);
      final state = container.read(goalsProvider);
      expect(state.isLoading, isTrue);
      expect(state.hasValue, isFalse);
      expect(repo.listCalls, 1);

      repo.listAnswer = [_goal(600, ago: const Duration(minutes: 5))];
      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [2], reason: 'own snapshot load');
      expect(repo.createCalls, 1);
      expect(find.text('kavling 600'), findsNothing);
      expect(find.text(kNewGoalRecoveredMessage), findsNothing);
      expect(_uncertain, findsOneWidget);

      firstLoad.complete(<Goal>[]);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'Desa refresh failed, then a later refresh succeeded (settled '
        'AsyncData again): the Desa list is reused without a load',
        (tester) async {
      final repo = _Repo(createAnswer: const NetworkException());
      final container = await _pump(tester, repo);
      repo.listAnswer = const NetworkException();
      await container.read(goalsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(container.read(goalsProvider).hasError, isTrue);

      repo.listAnswer = [_goal(610, ago: const Duration(minutes: 5))];
      await container.read(goalsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      final state = container.read(goalsProvider);
      expect(state, isA<AsyncData<List<Goal>>>());
      expect(state.isLoading || state.hasError, isFalse);
      final listsBefore = repo.listCalls;

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [listsBefore], reason: 'Desa reused');
      expect(
        find.text('kavling 610'),
        findsNothing,
        reason: '610 is in the snapshot',
      );
      expect(_uncertain, findsOneWidget);
    });

    testWidgets(
        'goalsProvider never read (ref.exists false): the snapshot loads the '
        'list itself and does not create goalsProvider', (tester) async {
      final repo = _Repo(createAnswer: _goal(620));
      final container = await _pump(tester, repo, viaDesa: false);
      expect(container.exists(goalsProvider), isFalse);

      await _fill(tester);
      await _tap(tester, 'submit');

      expect(repo.listCallsAtCreate, [1]);
      expect(repo.listCalls, 1, reason: 'no second (provider) load');
      expect(container.exists(goalsProvider), isFalse);
      expect(find.text('kavling 620'), findsOneWidget);
    });
  });

  group('fallback list() fails during the snapshot', () {
    for (final (name, makeDesaUnsettled) in <(
      String,
      Future<void> Function(ProviderContainer, _Repo, WidgetTester)
    )>[
      (
        'Desa refresh failed',
        (container, repo, tester) async {
          repo.listAnswer = const NetworkException();
          await container.read(goalsProvider.notifier).refresh();
          await tester.pumpAndSettle();
        },
      ),
      (
        'Desa refresh in flight',
        (container, repo, tester) async {
          repo.listAnswer = Completer<List<Goal>>().future;
          unawaited(container.read(goalsProvider.notifier).refresh());
          await tester.pump();
        },
      ),
    ]) {
      testWidgets(
          '$name: no snapshot, so a lost create never adopts an identical '
          'goal and the uncertain notice is shown', (tester) async {
        final repo = _Repo(createAnswer: const NetworkException());
        final container = await _pump(tester, repo);
        await makeDesaUnsettled(container, repo, tester);
        final state = container.read(goalsProvider);
        expect(state.isLoading || state.hasError, isTrue);

        repo.listAnswer = const NetworkException();
        // The lost create was in fact stored; the check after it sees it.
        repo.onCreate = () => repo.listAnswer = [_goal(630)];
        await _fill(tester);
        await _tap(tester, 'submit');

        expect(repo.createCalls, 1);
        expect(find.text('kavling 630'), findsNothing);
        expect(find.text(kNewGoalRecoveredMessage), findsNothing);
        expect(_uncertain, findsOneWidget);

        // Explicit retry: goal 630 exists and cannot be told apart from an
        // earlier one, so nothing is created and the ambiguity is reported.
        repo.onCreate = null;
        await _tap(tester, 'uncertain-retry');
        expect(repo.createCalls, 1, reason: 'no duplicate');
        expect(_errorText(tester), kNewGoalAmbiguousMessage);
      });
    }
  });
}
