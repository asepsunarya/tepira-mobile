import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tepira_mobile/data/today/today_dto.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';

/// The JSON of fixture [name] (`test/fixtures/<name>.json`).
Map<String, Object?> readFixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// Contract §5, budget basis: 100.000 safe today, 50.000 spent this month,
/// 500.000 saved.
TodaySummary fixtureTodayBudget() =>
    todaySummaryFromJson(readFixture('mobile_today_budget'));

/// Contract §5, wallet basis (no budget this month).
TodaySummary fixtureTodayWallet() =>
    todaySummaryFromJson(readFixture('mobile_today_wallet'));

/// The budget fixture with `safeToday` and `budget` replaced, for card
/// states the fixtures do not cover.
TodaySummary testToday({
  SafeTodayBasis basis = SafeTodayBasis.budget,
  SafeTodayState state = SafeTodayState.ok,
  int allowance = 150000,
  int remaining = 100000,
  int days = 30,
  BudgetStatus? status,
  int spentMonth = 50000,
  int savedThisMonth = 500000,
  DateTime? date,
}) {
  final base = fixtureTodayBudget();
  final budgetStatus = status ??
      switch ((basis, state)) {
        (SafeTodayBasis.wallet, _) => BudgetStatus.noBudget,
        (_, SafeTodayState.overMonth) => BudgetStatus.overBudget,
        _ => BudgetStatus.withinBudget,
      };
  final noBudget = budgetStatus == BudgetStatus.noBudget;
  return TodaySummary(
    asOf: base.asOf,
    date: date ?? base.date,
    period: base.period,
    spentToday: base.spentToday,
    spentMonth: spentMonth,
    savedThisMonth: savedThisMonth,
    budget: TodayBudget(
      status: budgetStatus,
      limit: noBudget ? null : 4500000,
      spent: spentMonth,
      remaining: noBudget ? null : 4500000 - spentMonth,
    ),
    safeToday: SafeToday(
      basis: basis,
      state: state,
      days: days,
      allowance: allowance,
      spentToday: base.safeToday.spentToday,
      remaining: remaining,
    ),
    walletsFree: base.walletsFree,
    walletsReserved: base.walletsReserved,
  );
}

/// [TodayRepository] answering from [results] in order (the last repeats).
/// An [Exception] entry is thrown instead of returned.
class FakeTodayRepository implements TodayRepository {
  FakeTodayRepository(this.results);

  /// A repository that always answers [fixtureTodayBudget].
  factory FakeTodayRepository.budget() =>
      FakeTodayRepository([fixtureTodayBudget()]);

  final List<Object> results;

  /// When set, [get] waits for it before answering.
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<TodaySummary> get() async {
    final call = calls++;
    await gate?.future;
    final result = results[call < results.length ? call : results.length - 1];
    if (result is Exception) throw result;
    return result as TodaySummary;
  }
}
