import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/today/today_dto.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';

import '../../helpers/fake_today_repository.dart';

Map<String, Object?> _with(
  Map<String, Object?> json,
  String object,
  String key,
  Object? value,
) {
  final copy = Map<String, Object?>.of(json);
  copy[object] = {...(json[object] as Map<String, Object?>), key: value};
  return copy;
}

void main() {
  group('budget basis (contract §5)', () {
    final today = todaySummaryFromJson(readFixture('mobile_today_budget'));

    test('reads every field', () {
      expect(today.asOf, DateTime.utc(2026, 11, 1, 7));
      expect(today.date, DateTime.utc(2026, 11, 1));
      expect(today.period.month, WibMonth(2026, 11));
      expect(today.period.daysInMonth, 30);
      expect(today.period.daysLeft, 30);
      expect(today.spentToday, 50000);
      expect(today.spentMonth, 50000);
      expect(today.savedThisMonth, 500000);
      expect(today.budget.status, BudgetStatus.withinBudget);
      expect(today.budget.limit, 4500000);
      expect(today.budget.spent, 50000);
      expect(today.budget.remaining, 4450000);
      expect(today.safeToday.basis, SafeTodayBasis.budget);
      expect(today.safeToday.state, SafeTodayState.ok);
      expect(today.safeToday.days, 30);
      expect(today.safeToday.allowance, 150000);
      expect(today.safeToday.spentToday, 50000);
      expect(today.safeToday.remaining, 100000);
      expect(today.walletsFree, 7070000);
      expect(today.walletsReserved, 3000000);
    });
  });

  test('wallet basis: NO_BUDGET with null limit and remaining', () {
    final today = todaySummaryFromJson(readFixture('mobile_today_wallet'));

    expect(today.budget.status, BudgetStatus.noBudget);
    expect(today.budget.limit, isNull);
    expect(today.budget.remaining, isNull);
    expect(today.safeToday.basis, SafeTodayBasis.wallet);
    expect(today.safeToday.allowance, 236833);
    expect(today.safeToday.spentToday, 35000);
    expect(today.safeToday.remaining, 201833);
  });

  test('over_today and over_month map to their states; remaining negative', () {
    final base = readFixture('mobile_today_budget');
    final overToday = todaySummaryFromJson(
      _with(
        _with(base, 'safeToday', 'state', 'over_today'),
        'safeToday',
        'remaining',
        -20000,
      ),
    );
    final overMonth = todaySummaryFromJson(
      _with(
        _with(base, 'safeToday', 'state', 'over_month'),
        'budget',
        'status',
        'OVER_BUDGET',
      ),
    );

    expect(overToday.safeToday.state, SafeTodayState.overToday);
    expect(overToday.safeToday.remaining, -20000);
    expect(overMonth.safeToday.state, SafeTodayState.overMonth);
    expect(overMonth.budget.status, BudgetStatus.overBudget);
  });

  test('the today of a write answer has no asOf', () {
    final json =
        readFixture('mobile_expense_created')['today']! as Map<String, Object?>;

    final today = todaySummaryFromJson(json);

    expect(today.asOf, isNull);
    expect(today.safeToday.remaining, 82000);
  });

  group('rejects', () {
    final base = readFixture('mobile_today_budget');

    for (final (name, json) in [
      ('an unknown state', _with(base, 'safeToday', 'state', 'aman')),
      ('an unknown basis', _with(base, 'safeToday', 'basis', 'gaji')),
      ('an unknown budget status', _with(base, 'budget', 'status', 'X')),
      (
        'OVER_BUDGET with state ok',
        _with(base, 'budget', 'status', 'OVER_BUDGET'),
      ),
      (
        'OVER_BUDGET with state over_today',
        _with(
          _with(base, 'safeToday', 'state', 'over_today'),
          'budget',
          'status',
          'OVER_BUDGET',
        ),
      ),
      (
        'a missing nullable limit',
        {
          ...base,
          'budget': {...(base['budget'] as Map)}..remove('limit'),
        }
      ),
      ('a fractional remaining', _with(base, 'safeToday', 'remaining', 1.5)),
      ('an impossible date', {...base, 'date': '2026-02-30'}),
      ('a timestamp as date', {...base, 'date': '2026-11-01T00:00:00.000Z'}),
    ]) {
      test(name, () {
        expect(() => todaySummaryFromJson(json), throwsFormatException);
      });
    }
  });
}
