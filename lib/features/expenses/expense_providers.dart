import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/wib.dart';
import '../../data/expenses/expenses_repository.dart';
import '../today/today_providers.dart';
import '../wallets/wallet_providers.dart';
import 'model/expense.dart';
import 'model/expense_input.dart';

/// Writes expenses through [ExpensesRepository] and puts each answer's
/// wallets and `today` into [walletsProvider] and [todayProvider], so Dompet
/// and Desa show the server's new numbers without reloading (SPEC-v2 §7).
class ExpenseWriter {
  ExpenseWriter(this._ref);

  final Ref _ref;

  ExpensesRepository get _repository => _ref.read(expensesRepositoryProvider);

  /// Creates [expense]. A dedupe answer is returned like a new row. The
  /// row is put into the loaded Riwayat month it belongs to.
  Future<ExpenseCreated> create(NewExpense expense) async {
    final result = await _sendResendingAborted(
      () => _repository.create(expense),
    );
    applyWriteResult(result);
    _history(WibMonth.of(result.expense.date))?.upsert(result.expense);
    return result;
  }

  /// Sends [patch] for expense [id], which the Riwayat shows in
  /// [listedIn]. The answer's row replaces the listed one; when its new day
  /// falls in another month it moves there. Throws [NotFoundException] when
  /// the expense is gone, after reloading [listedIn].
  Future<ExpenseUpdated> update(
    int id,
    ExpensePatch patch, {
    WibMonth? listedIn,
  }) async {
    final ExpenseUpdated result;
    try {
      result = await _sendResendingAborted(
        () => _repository.update(id, patch),
      );
    } on NotFoundException {
      _history(listedIn)?.refresh();
      rethrow;
    }
    applyWriteResult(result);
    final month = WibMonth.of(result.expense.date);
    if (listedIn != null && listedIn != month) _history(listedIn)?.remove(id);
    _history(month)?.upsert(result.expense);
    return result;
  }

  /// Deletes expense [id], which the Riwayat shows in [listedIn], and drops
  /// it from that month. Throws [NotFoundException] when it is already
  /// gone, after reloading [listedIn].
  Future<ExpenseDeleted> delete(int id, {WibMonth? listedIn}) async {
    final ExpenseDeleted result;
    try {
      result = await _sendResendingAborted(() => _repository.delete(id));
    } on NotFoundException {
      _history(listedIn)?.refresh();
      rethrow;
    }
    applyWriteResult(result);
    _history(listedIn)?.remove(id);
    return result;
  }

  /// Runs [send] once more when the server aborted the transaction (500
  /// `server_error` with a short `Retry-After`): nothing was written, so
  /// the same request is safe to repeat after the wait. A create is also
  /// covered by the server's 120 s dedupe, an update sets absolute values,
  /// and a delete of a row already gone answers 404. Every other error
  /// (502/503/504 with an unknown outcome, 429, a long or missing
  /// `Retry-After`) is surfaced unsent.
  Future<T> _sendResendingAborted<T>(Future<T> Function() send) async {
    try {
      return await send();
    } on ServerException catch (error) {
      final wait = retryWaitOf(error);
      if (wait == null) rethrow;
      await Future<void>.delayed(wait);
      return send();
    }
  }

  /// The Riwayat month [month] when a screen has it loaded or loading.
  HistoryNotifier? _history(WibMonth? month) {
    if (month == null || !_ref.exists(historyProvider(month))) return null;
    return _ref.read(historyProvider(month).notifier);
  }

  /// Replaces the written wallets in the loaded wallet list and shows the
  /// answer's `today`. Providers nobody watches are left alone: they load
  /// fresh data when next opened.
  void applyWriteResult(ExpenseWriteResult result) {
    if (_ref.exists(walletsProvider)) {
      _ref.read(walletsProvider.notifier).applyExpenseWrite(
            result.wallets,
            free: result.today.walletsFree,
            reserved: result.today.walletsReserved,
          );
    }
    if (_ref.exists(todayProvider)) {
      _ref.read(todayProvider.notifier).applySummary(result.today);
    }
  }
}

/// Longest `Retry-After` the expense writer waits out before resending.
const Duration kMaxExpenseResendWait = Duration(seconds: 5);

/// The wait before resending a write that failed with [error], or null
/// when it must not be resent: only a 500 `server_error` with a
/// `Retry-After` of at most [kMaxExpenseResendWait] is a safe resend.
Duration? retryWaitOf(ServerException error) {
  final wait = error.retryAfter;
  if (error.statusCode != 500 || error.code != 'server_error') return null;
  if (wait == null || wait > kMaxExpenseResendWait) return null;
  return wait;
}

final expenseWriterProvider = Provider<ExpenseWriter>(ExpenseWriter.new);

/// One WIB month of expenses for the Riwayat screen (`GET
/// /api/mobile/expenses?year=&month=`), newest first. Disposed when no
/// screen shows the month, so the next visit loads it fresh.
class HistoryNotifier
    extends AutoDisposeFamilyAsyncNotifier<ExpenseList, WibMonth> {
  @override
  Future<ExpenseList> build(WibMonth month) =>
      ref.watch(expensesRepositoryProvider).list(month: month);

  /// Reloads the month. A failure lands in the state as an error, not at
  /// the caller.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Already exposed as AsyncError in the state.
    }
  }

  /// Puts [expense], from a write answer, into the month: it replaces the
  /// row with its id, or is added, and the month's total and count move by
  /// exactly that row's change, so they stay the server's numbers without a
  /// reload. Without a loaded month it reloads instead; a reload in flight
  /// may have read the month before the write, so it is restarted.
  void upsert(Expense expense) {
    final current = _loaded();
    if (current == null) return;
    final expenses = [...current.expenses];
    final index = expenses.indexWhere((e) => e.id == expense.id);
    var total = current.total + expense.amount;
    var count = current.count;
    if (index < 0) {
      expenses.add(expense);
      count += 1;
    } else {
      total -= expenses[index].amount;
      expenses[index] = expense;
    }
    expenses.sort(_newestFirst);
    _show(current, expenses, total: total, count: count);
  }

  /// Drops the row with [id], when listed, and its amount from the total.
  void remove(int id) {
    final current = _loaded();
    if (current == null) return;
    final index = current.expenses.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final removed = current.expenses[index];
    _show(
      current,
      [...current.expenses]..removeAt(index),
      total: current.total - removed.amount,
      count: current.count - 1,
    );
  }

  /// The loaded month, or null after asking for a reload because there is
  /// none to update.
  ExpenseList? _loaded() {
    final current = state.valueOrNull;
    if (current == null || state.hasError) {
      ref.invalidateSelf();
      return null;
    }
    return current;
  }

  void _show(
    ExpenseList current,
    List<Expense> expenses, {
    required int total,
    required int count,
  }) {
    final loading = state.isLoading;
    state = AsyncData(
      ExpenseList(
        asOf: current.asOf,
        period: current.period,
        total: total,
        count: count,
        more: current.more,
        expenses: List.unmodifiable(expenses),
      ),
    );
    if (loading) ref.invalidateSelf();
  }

  /// The server's order: `date desc, id desc`.
  static int _newestFirst(Expense a, Expense b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }
}

final historyProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryNotifier, ExpenseList, WibMonth>(HistoryNotifier.new);
