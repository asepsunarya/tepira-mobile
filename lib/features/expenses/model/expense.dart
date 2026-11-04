import '../../../core/wib.dart';
import '../../today/model/today_summary.dart';
import '../../wallets/model/wallet.dart';

/// One expense ("jajan") from `/api/mobile/expenses*` (SPEC-v2 §3.5).
/// Money is int rupiah.
class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.note,
    required this.source,
    required this.date,
    required this.createdAt,
    required this.walletId,
    required this.walletName,
    required this.placeName,
  });

  final int id;
  final int amount;

  /// A category label (`lib/core/categories.dart`), or null for none.
  final String? category;
  final String? note;

  /// `gaji` or `bonus` as stored; kept as sent so one odd web row cannot
  /// break a whole list.
  final String source;

  /// The instant the expense counts for; group it by [wibDate].
  final DateTime date;
  final DateTime createdAt;

  /// Null for an orphan row whose wallet was deleted on the web.
  final int? walletId;
  final String? walletName;

  /// Always null from the app; the web may set it.
  final String? placeName;
}

/// `GET /api/mobile/expenses?year=&month=`: one WIB month, newest first.
class ExpenseList {
  const ExpenseList({
    required this.asOf,
    required this.period,
    required this.total,
    required this.count,
    required this.more,
    required this.expenses,
  });

  final DateTime asOf;
  final WibMonth period;

  /// Sum and number of every expense in the month, not only those sent.
  final int total;
  final int count;

  /// True when the server left rows out (it sends at most 500).
  final bool more;
  final List<Expense> expenses;
}

/// What every expense write answers besides the expense: the wallets whose
/// balance moved and the new Desa summary, so the app updates Dompet and
/// Desa without reloading them (SPEC-v2 §3).
sealed class ExpenseWriteResult {
  const ExpenseWriteResult({required this.today});

  final TodaySummary today;

  /// Wallets after the write, in id order.
  List<Wallet> get wallets;
}

/// `POST /api/mobile/expenses`, 201 (new row) or 200 (dedupe).
class ExpenseCreated extends ExpenseWriteResult {
  const ExpenseCreated({
    required this.deduped,
    required this.expense,
    required this.wallet,
    required super.today,
  });

  /// True when the same expense was already stored in the last 120 s: the
  /// server returned that row and wrote nothing. Still a success.
  final bool deduped;
  final Expense expense;

  /// Null only when the wallet vanished meanwhile.
  final Wallet? wallet;

  @override
  List<Wallet> get wallets => [if (wallet case final wallet?) wallet];
}

/// `PATCH /api/mobile/expenses/{id}`.
class ExpenseUpdated extends ExpenseWriteResult {
  const ExpenseUpdated({
    required this.expense,
    required this.wallets,
    required super.today,
  });

  final Expense expense;

  /// One or two wallets (old and new when the wallet changed).
  @override
  final List<Wallet> wallets;
}

/// `DELETE /api/mobile/expenses/{id}`.
class ExpenseDeleted extends ExpenseWriteResult {
  const ExpenseDeleted({
    required this.id,
    required this.amount,
    required this.wallet,
    required super.today,
  });

  final int id;
  final int amount;

  /// The wallet that got the amount back; null for an orphan row.
  final Wallet? wallet;

  @override
  List<Wallet> get wallets => [if (wallet case final wallet?) wallet];
}
