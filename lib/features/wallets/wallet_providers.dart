import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/wallets/wallets_repository.dart';
import 'model/wallet.dart';

/// The signed-in user's wallets and totals for the Dompet screen, in server
/// order. Disposed when no screen watches it, so the next visit (or the next
/// user) loads a fresh list.
class WalletsNotifier extends AutoDisposeAsyncNotifier<WalletList> {
  @override
  Future<WalletList> build() => ref.watch(walletsRepositoryProvider).list();

  /// Reloads the list. Keeps showing the current wallets while loading; a
  /// failure replaces them with the error, which stays in the state rather
  /// than being thrown at the caller.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Already exposed as AsyncError in the state.
    }
  }

  /// Puts a create or update answer into the list without reloading: the
  /// written wallet replaces the one with its id, or is appended (the server
  /// gives a new wallet the last `sortOrder`), and the totals become the
  /// server's new ones. Without a loaded list it reloads instead.
  void applyWrite(WalletWrite write) {
    final current = state.valueOrNull;
    if (current == null || state.hasError) {
      ref.invalidateSelf();
      return;
    }
    final wallets = [...current.wallets];
    final index = wallets.indexWhere((w) => w.id == write.wallet.id);
    if (index < 0) {
      wallets.add(write.wallet);
    } else {
      wallets[index] = write.wallet;
    }
    state = AsyncData(
      WalletList(
        asOf: current.asOf,
        period: current.period,
        wallets: List.unmodifiable(wallets),
        totals: write.totals,
      ),
    );
  }

  /// Puts the wallets an expense write returned into the list without
  /// reloading. Expense answers carry no wallet totals, only the server's
  /// new [free] and [reserved] (its `today.wallets`); the debts total moves
  /// by the change in the returned debt wallets, and the assets total is
  /// what keeps `free = assets - reserved - debts` true. A wallet the list
  /// does not hold, a wallet whose debt flag changed (its type was edited on
  /// the web), or a list that is not loaded, means the list is stale, so it
  /// reloads instead. The derived totals are kept only when they equal
  /// [summarizeWallets] (the app's copy of the backend rule) over the local
  /// list; otherwise the list reloads.
  void applyExpenseWrite(
    List<Wallet> written, {
    required int free,
    required int reserved,
  }) {
    // SPEC-v2 §9 (Never): client-side wallet totals are not the source of
    // truth. [free] and [reserved] come from the server's answer. The totals
    // derived here are kept only when they equal summarizeWallets (the
    // app's copy of the backend rule) over the local list; on any mismatch,
    // or a stale list, the list reloads from the server instead.
    final current = state.valueOrNull;
    if (current == null || state.hasError) {
      ref.invalidateSelf();
      return;
    }
    final wallets = [...current.wallets];
    var debts = current.totals.debts;
    for (final wallet in written) {
      final index = wallets.indexWhere((w) => w.id == wallet.id);
      if (index < 0 || wallets[index].isDebt != wallet.isDebt) {
        ref.invalidateSelf();
        return;
      }
      if (wallet.isDebt) {
        debts -= wallet.displayBalance - wallets[index].displayBalance;
      }
      wallets[index] = wallet;
    }
    final totals = WalletTotals(
      assets: free + reserved + debts,
      debts: debts,
      reserved: reserved,
      netWorth: free + reserved,
      free: free,
    );
    if (totals != summarizeWallets(wallets)) {
      ref.invalidateSelf();
      return;
    }
    final loading = state.isLoading;
    state = AsyncData(
      WalletList(
        asOf: current.asOf,
        period: current.period,
        wallets: List.unmodifiable(wallets),
        totals: totals,
      ),
    );
    // A reload in flight may have read the list before this write; restart
    // it so its stale answer cannot replace the newer numbers.
    if (loading) ref.invalidateSelf();
  }
}

/// The backend's `summarizeWallets` (SPEC-v2 §2) over [wallets]: debts are
/// the absolute display balances of debt wallets, assets and reserved sum
/// the non-debt ones, and `free = assets - debts - reserved`.
WalletTotals summarizeWallets(Iterable<Wallet> wallets) {
  var assets = 0;
  var debts = 0;
  var reserved = 0;
  for (final wallet in wallets) {
    if (wallet.isDebt) {
      debts += wallet.displayBalance.abs();
    } else {
      assets += wallet.displayBalance;
      if (wallet.isReserved) reserved += wallet.displayBalance;
    }
  }
  final netWorth = assets - debts;
  return WalletTotals(
    assets: assets,
    debts: debts,
    reserved: reserved,
    netWorth: netWorth,
    free: netWorth - reserved,
  );
}

final walletsProvider =
    AsyncNotifierProvider.autoDispose<WalletsNotifier, WalletList>(
  WalletsNotifier.new,
);
