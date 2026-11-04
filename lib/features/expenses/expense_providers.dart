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

  /// Creates [expense]. A dedupe answer is returned like a new row.
  ///
  /// When the server aborted the transaction (500 `server_error` with a
  /// short `Retry-After`), nothing was written, so the same body is sent
  /// once more after the wait; the server's 120 s dedupe keeps that from
  /// storing it twice. Every other error (502/503/504 with an unknown
  /// outcome, 429, a long or missing `Retry-After`) is surfaced unsent.
  Future<ExpenseCreated> create(NewExpense expense) async {
    ExpenseCreated result;
    try {
      result = await _repository.create(expense);
    } on ServerException catch (error) {
      final wait = retryWaitOf(error);
      if (wait == null) rethrow;
      await Future<void>.delayed(wait);
      result = await _repository.create(expense);
    }
    applyWriteResult(result);
    return result;
  }

  Future<ExpenseUpdated> update(int id, ExpensePatch patch) async {
    final result = await _repository.update(id, patch);
    applyWriteResult(result);
    return result;
  }

  Future<ExpenseDeleted> delete(int id) async {
    final result = await _repository.delete(id);
    applyWriteResult(result);
    return result;
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

/// The wait before resending a create that failed with [error], or null
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
}

final historyProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryNotifier, ExpenseList, WibMonth>(HistoryNotifier.new);
