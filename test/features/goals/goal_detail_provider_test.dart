import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_providers.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';

import '../../helpers/fake_goals_repository.dart';

GoalDetail _detail({int id = 7, int saved = 1000}) => GoalDetail(
      goal: testGoal(id: id, saved: saved),
      contributions: const [],
    );

ProviderContainer _container(FakeGoalsRepository repository) {
  final container = ProviderContainer(
    overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('loads the detail of the requested goal id', () async {
    final repository = FakeGoalsRepository([], detailResults: [_detail()]);
    final container = _container(repository);
    final sub = container.listen(goalDetailProvider(7), (_, __) {});
    addTearDown(sub.close);

    expect(await container.read(goalDetailProvider(7).future), _detail());
    expect(repository.detailIds, [7]);
  });

  test('exposes a 404 as AsyncError with NotFoundException', () async {
    final repository =
        FakeGoalsRepository([], detailResults: [const NotFoundException()]);
    final container = _container(repository);
    final sub = container.listen(goalDetailProvider(9), (_, __) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(goalDetailProvider(9).future),
      throwsA(isA<NotFoundException>()),
    );
    expect(
      container.read(goalDetailProvider(9)).error,
      isA<NotFoundException>(),
    );
  });

  test('refresh keeps the old detail while loading, then shows the new one',
      () async {
    final repository = FakeGoalsRepository(
      [],
      detailResults: [_detail(saved: 1000), _detail(saved: 5000)],
    );
    final container = _container(repository);
    final sub = container.listen(goalDetailProvider(7), (_, __) {});
    addTearDown(sub.close);
    await container.read(goalDetailProvider(7).future);

    repository.detailGate = Completer<void>();
    final refreshing = container.read(goalDetailProvider(7).notifier).refresh();
    final during = container.read(goalDetailProvider(7));
    expect(during.isLoading, isTrue);
    expect(during.valueOrNull?.goal.saved, 1000);

    repository.detailGate!.complete();
    await refreshing;
    expect(container.read(goalDetailProvider(7)).value?.goal.saved, 5000);
    expect(repository.detailIds, [7, 7]);
  });

  test('refresh does not throw when the reload fails', () async {
    final repository = FakeGoalsRepository(
      [],
      detailResults: [_detail(), const NetworkException()],
    );
    final container = _container(repository);
    final sub = container.listen(goalDetailProvider(7), (_, __) {});
    addTearDown(sub.close);
    await container.read(goalDetailProvider(7).future);

    await container.read(goalDetailProvider(7).notifier).refresh();
    expect(
      container.read(goalDetailProvider(7)).error,
      isA<NetworkException>(),
    );
  });
}
