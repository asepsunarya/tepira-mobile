/// Parses `GET /api/mobile/today` and the `today` of expense writes
/// (SPEC-v2 §3.4).
library;

import '../../core/wib.dart';
import '../../features/today/model/today_summary.dart';
import '../json_fields.dart';

/// The body of `GET /api/mobile/today` (with `asOf`) or the `today` object
/// of an expense write (without it). An unknown `status`, `basis` or `state`
/// throws [FormatException]: the card must not guess what it means.
TodaySummary todaySummaryFromJson(Map<String, Object?> json) {
  final period = objectField(json, 'period');
  final spent = objectField(json, 'spent');
  final budget = objectField(json, 'budget');
  final safeToday = objectField(json, 'safeToday');
  final wallets = objectField(json, 'wallets');
  return TodaySummary(
    asOf: json.containsKey('asOf') ? instantField(json, 'asOf') : null,
    date: _calendarDate(requiredField<String>(json, 'date')),
    period: TodayPeriod(
      month: periodField(json, 'period'),
      daysInMonth: requiredField<int>(period, 'daysInMonth'),
      daysLeft: requiredField<int>(period, 'daysLeft'),
    ),
    spentToday: requiredField<int>(spent, 'today'),
    spentMonth: requiredField<int>(spent, 'month'),
    savedThisMonth: requiredField<int>(json, 'savedThisMonth'),
    budget: TodayBudget(
      status: _enum(budget, 'status', const {
        'NO_BUDGET': BudgetStatus.noBudget,
        'WITHIN_BUDGET': BudgetStatus.withinBudget,
        'OVER_BUDGET': BudgetStatus.overBudget,
      }),
      limit: nullableField<int>(budget, 'limit'),
      spent: requiredField<int>(budget, 'spent'),
      remaining: nullableField<int>(budget, 'remaining'),
    ),
    safeToday: SafeToday(
      basis: _enum(safeToday, 'basis', const {
        'budget': SafeTodayBasis.budget,
        'wallet': SafeTodayBasis.wallet,
      }),
      state: _enum(safeToday, 'state', const {
        'ok': SafeTodayState.ok,
        'over_today': SafeTodayState.overToday,
        'over_month': SafeTodayState.overMonth,
      }),
      days: requiredField<int>(safeToday, 'days'),
      allowance: requiredField<int>(safeToday, 'allowance'),
      spentToday: requiredField<int>(safeToday, 'spentToday'),
      remaining: requiredField<int>(safeToday, 'remaining'),
    ),
    walletsFree: requiredField<int>(wallets, 'free'),
    walletsReserved: requiredField<int>(wallets, 'reserved'),
  );
}

T _enum<T>(Map<String, Object?> json, String key, Map<String, T> values) {
  final raw = requiredField<String>(json, key);
  final value = values[raw];
  if (value == null) throw FormatException('unknown "$key"', raw);
  return value;
}

final _calendarDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `YYYY-MM-DD` as a UTC midnight `DateTime`, rejecting impossible dates
/// such as `2026-02-30`.
DateTime _calendarDate(String raw) {
  final match = _calendarDay.firstMatch(raw);
  if (match != null) {
    final date = DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    if (wibDayKey(date.subtract(kWibOffset)) == raw) return date;
  }
  throw FormatException('"date" must be YYYY-MM-DD', raw);
}
