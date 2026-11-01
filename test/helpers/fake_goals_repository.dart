import 'dart:async';

import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';

/// A goal for widget tests; only the fields the list shows matter.
Goal testGoal({
  int id = 1,
  String title = 'Dana darurat',
  int target = 10000000,
  int saved = 3450000,
}) {
  return Goal(
    id: id,
    title: title,
    description: null,
    target: target,
    saved: saved,
    percent: target == 0 ? 0 : saved * 100 / target,
    remaining: target - saved < 0 ? 0 : target - saved,
    deadline: null,
    daysLeft: null,
    perMonthNeeded: null,
    createdAt: DateTime.utc(2026, 11),
    lastContribution: null,
    contributionCount: 0,
  );
}

/// [GoalsRepository] whose [list] answers from [listResults] in order (the
/// last one repeats). An [Exception] entry is thrown instead of returned.
class FakeGoalsRepository implements GoalsRepository {
  FakeGoalsRepository(this.listResults);

  final List<Object> listResults;

  /// When set, [list] waits for it before answering.
  Completer<void>? listGate;

  /// Per-call gates, keyed by the zero-based index of the [list] call; a
  /// gated call waits for its completer before answering.
  final Map<int, Completer<void>> listCallGates = {};

  int listCalls = 0;

  @override
  Future<List<Goal>> list() async {
    final result = listResults[
        listCalls < listResults.length ? listCalls : listResults.length - 1];
    final callGate = listCallGates[listCalls];
    listCalls++;
    await listGate?.future;
    await callGate?.future;
    if (result is Exception) throw result;
    return result as List<Goal>;
  }

  @override
  Future<GoalDetail> detail(int id) => throw UnimplementedError();

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) =>
      throw UnimplementedError();
}
