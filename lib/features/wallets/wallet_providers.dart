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
}

final walletsProvider =
    AsyncNotifierProvider.autoDispose<WalletsNotifier, WalletList>(
  WalletsNotifier.new,
);
