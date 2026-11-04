import 'dart:async';

import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import 'fake_today_repository.dart';

/// Contract §6: 18.000 from BCA (id 3), `deduped: false`.
ExpenseCreated fixtureExpenseCreated() =>
    expenseCreatedFromJson(readFixture('mobile_expense_created'));

/// Contract §6: the same body again, `deduped: true`.
ExpenseCreated fixtureExpenseDeduped() =>
    expenseCreatedFromJson(readFixture('mobile_expense_deduped'));

/// [ExpensesRepository] whose writes answer from the given result lists in
/// order (the last one repeats). An [Exception] entry is thrown instead of
/// returned. Every call is recorded.
class FakeExpensesRepository implements ExpensesRepository {
  FakeExpensesRepository({
    this.createResults = const [],
    this.listResults = const [],
    this.updateResults = const [],
    this.deleteResults = const [],
  });

  final List<Object> createResults;
  final List<Object> listResults;
  final List<Object> updateResults;
  final List<Object> deleteResults;

  /// When set, [create] waits for it before answering.
  Completer<void>? createGate;

  final List<NewExpense> created = [];
  final List<WibMonth?> listed = [];
  final List<(int, Map<String, Object?>)> updated = [];
  final List<int> deleted = [];

  static T _pick<T>(List<Object> results, int call) {
    final result = results[call < results.length ? call : results.length - 1];
    if (result is Exception) throw result;
    return result as T;
  }

  @override
  Future<ExpenseCreated> create(NewExpense expense) async {
    final call = created.length;
    created.add(expense);
    await createGate?.future;
    return _pick<ExpenseCreated>(createResults, call);
  }

  @override
  Future<ExpenseList> list({WibMonth? month}) async {
    final call = listed.length;
    listed.add(month);
    return _pick<ExpenseList>(listResults, call);
  }

  @override
  Future<ExpenseUpdated> update(int id, ExpensePatch patch) async {
    final call = updated.length;
    updated.add((id, patch.toJson()));
    return _pick<ExpenseUpdated>(updateResults, call);
  }

  @override
  Future<ExpenseDeleted> delete(int id) async {
    final call = deleted.length;
    deleted.add(id);
    return _pick<ExpenseDeleted>(deleteResults, call);
  }
}
