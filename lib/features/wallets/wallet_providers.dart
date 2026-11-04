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
}

final walletsProvider =
    AsyncNotifierProvider.autoDispose<WalletsNotifier, WalletList>(
  WalletsNotifier.new,
);
