import '../../../core/wib.dart';

/// `budget.status`: whether this WIB month has an allocation, and whether
/// spending passed it (the server's `computeMonthSummary`).
enum BudgetStatus { noBudget, withinBudget, overBudget }

/// `safeToday.basis`: where the safe-to-spend number comes from (SPEC-v2
/// §3.4). [budget] spreads what is left of the month's budget over the days
/// left; [wallet] spreads Uang bebas over [SafeToday.days] (30) days because
/// no budget is set.
enum SafeTodayBasis { budget, wallet }

/// `safeToday.state`, which decides how the Desa card reads (SPEC-v2 §4
/// `today`).
enum SafeTodayState {
  /// Within today's allowance.
  ok,

  /// Today's spending passed the allowance; `remaining` is negative.
  overToday,

  /// The month's budget is spent; `remaining` is negative and the card must
  /// never say "aman".
  overMonth,
}

/// `period` of `GET /api/mobile/today`: the current WIB month.
class TodayPeriod {
  const TodayPeriod({
    required this.month,
    required this.daysInMonth,
    required this.daysLeft,
  });

  final WibMonth month;
  final int daysInMonth;

  /// Days to the end of the month, today included (1..31).
  final int daysLeft;
}

/// `budget` of `GET /api/mobile/today`.
class TodayBudget {
  const TodayBudget({
    required this.status,
    required this.limit,
    required this.spent,
    required this.remaining,
  });

  final BudgetStatus status;

  /// Null when [status] is [BudgetStatus.noBudget].
  final int? limit;

  /// Every expense dated in the month, reserved wallets included.
  final int spent;

  /// Null when [status] is [BudgetStatus.noBudget]; negative when over.
  final int? remaining;
}

/// `safeToday`: the number on the "Aman dipakai hari ini" card. The client
/// shows it as sent and never recomputes it (SPEC-v2 §7).
class SafeToday {
  const SafeToday({
    required this.basis,
    required this.state,
    required this.days,
    required this.allowance,
    required this.spentToday,
    required this.remaining,
  });

  final SafeTodayBasis basis;
  final SafeTodayState state;

  /// Days the money is spread over: days left in the month on the budget
  /// basis, 30 on the wallet basis.
  final int days;

  /// Today's allowance, never below 0.
  final int allowance;
  final int spentToday;

  /// What is still safe to spend today; negative when over.
  final int remaining;
}

/// `GET /api/mobile/today`, and the `today` every expense write returns
/// (SPEC-v2 §3.4). All days and months are WIB. Money is int rupiah.
class TodaySummary {
  const TodaySummary({
    required this.asOf,
    required this.date,
    required this.period,
    required this.spentToday,
    required this.spentMonth,
    required this.savedThisMonth,
    required this.budget,
    required this.safeToday,
    required this.walletsFree,
    required this.walletsReserved,
  });

  /// Server time of the answer; null in the `today` of a write answer.
  final DateTime? asOf;

  /// Today in WIB, as a UTC midnight `DateTime` (like [wibDate]).
  final DateTime date;
  final TodayPeriod period;

  /// `spent.today`: every expense dated today.
  final int spentToday;

  /// `spent.month`: "Jajan bulan ini".
  final int spentMonth;

  /// Deposits dated this month: "Ditabung bulan ini".
  final int savedThisMonth;
  final TodayBudget budget;
  final SafeToday safeToday;

  /// `wallets.free`: Uang bebas.
  final int walletsFree;

  /// `wallets.reserved`: Dana dicadangkan.
  final int walletsReserved;
}
