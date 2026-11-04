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

/// Contract §6: November 2026, three expenses on 1 November WIB (one of
/// them at 06:40 WIB, still 31 October in UTC), 50.000 in total.
ExpenseList fixtureExpenseList() =>
    expenseListFromJson(readFixture('mobile_expenses'));

/// An expense with test defaults: 25.000 "nasi padang" from BCA (id 3).
Expense testExpense({
  int id = 501,
  int amount = 25000,
  String? category = 'Makan harian',
  String? note = 'nasi padang',
  String source = 'gaji',
  required DateTime date,
  int? walletId = 3,
  String? walletName = 'BCA',
}) {
  return Expense(
    id: id,
    amount: amount,
    category: category,
    note: note,
    source: source,
    date: date,
    createdAt: date,
    walletId: walletId,
    walletName: walletName,
    placeName: null,
  );
}

/// A month list of [expenses] (newest first) with the server's [total] and
/// [count]; both default to the sum and number of [expenses].
ExpenseList testExpenseList(
  WibMonth period,
  List<Expense> expenses, {
  int? total,
  int? count,
  bool more = false,
}) {
  return ExpenseList(
    asOf: DateTime.utc(2026, 11, 1, 7),
    period: period,
    total: total ?? expenses.fold(0, (sum, e) => sum + e.amount),
    count: count ?? expenses.length,
    more: more,
    expenses: expenses,
  );
}

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

  /// When set, [list] waits for it before answering.
  Completer<void>? listGate;

  /// When set, [update] waits for it before answering.
  Completer<void>? updateGate;

  /// When set, [delete] waits for it before answering.
  Completer<void>? deleteGate;

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
    await listGate?.future;
    return _pick<ExpenseList>(listResults, call);
  }

  @override
  Future<ExpenseUpdated> update(int id, ExpensePatch patch) async {
    final call = updated.length;
    updated.add((id, patch.toJson()));
    await updateGate?.future;
    return _pick<ExpenseUpdated>(updateResults, call);
  }

  @override
  Future<ExpenseDeleted> delete(int id) async {
    final call = deleted.length;
    deleted.add(id);
    await deleteGate?.future;
    return _pick<ExpenseDeleted>(deleteResults, call);
  }
}
