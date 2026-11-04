import '../../wallets/model/wallet.dart';

/// The wallet the Jajan form preselects: the last one used, unless it is
/// reserved or gone; else the first ordinary wallet; else the first debt
/// wallet. A reserved wallet can be picked but is never the default (SPEC-v2
/// §14 Q2), so with only reserved wallets there is no default.
Wallet? defaultExpenseWallet(List<Wallet> wallets, int? lastWalletId) {
  for (final wallet in wallets) {
    if (wallet.id == lastWalletId && wallet.kind != WalletKind.reserved) {
      return wallet;
    }
  }
  for (final kind in const [WalletKind.normal, WalletKind.debt]) {
    for (final wallet in wallets) {
      if (wallet.kind == kind) return wallet;
    }
  }
  return null;
}
