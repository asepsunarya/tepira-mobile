import '../../../core/wib.dart';

/// Wallet types the API accepts (SPEC-v2 §3.2), in the order the form lists
/// them.
const List<String> kWalletTypes = [
  'bank',
  'e-wallet',
  'cash',
  'investment',
  'credit',
  'paylater',
  'other',
];

/// Types the server always stores as debt.
const Set<String> kDebtWalletTypes = {'credit', 'paylater'};

/// Which group a wallet is listed under (web: "Saldo & Tabungan", "Dana
/// Dicadangkan", "Kartu Kredit & Cicilan").
enum WalletKind {
  normal,
  reserved,
  debt;

  /// Debt wins over reserved, as in the server's `summarizeWallets`.
  static WalletKind of({required bool isDebt, required bool isReserved}) {
    if (isDebt) return WalletKind.debt;
    if (isReserved) return WalletKind.reserved;
    return WalletKind.normal;
  }
}

/// One wallet from `/api/mobile/wallets` (SPEC-v2 §3.1). Money is int rupiah.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.displayBalance,
    required this.isDebt,
    required this.isReserved,
    required this.description,
    required this.sortOrder,
    required this.spentThisMonth,
  });

  final int id;
  final String name;

  /// One of [kWalletTypes] for wallets the app created; the web may store
  /// other values, so it is kept as sent.
  final String type;

  /// Raw stored balance. For debt it is the amount owed, as the web stored it.
  final int balance;

  /// What the app shows: debt is always negative.
  final int displayBalance;
  final bool isDebt;
  final bool isReserved;
  final String? description;
  final int sortOrder;

  /// Sum of this wallet's expenses in the current WIB month.
  final int spentThisMonth;

  WalletKind get kind => WalletKind.of(isDebt: isDebt, isReserved: isReserved);

  @override
  bool operator ==(Object other) =>
      other is Wallet &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.balance == balance &&
      other.displayBalance == displayBalance &&
      other.isDebt == isDebt &&
      other.isReserved == isReserved &&
      other.description == description &&
      other.sortOrder == sortOrder &&
      other.spentThisMonth == spentThisMonth;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        type,
        balance,
        displayBalance,
        isDebt,
        isReserved,
        description,
        sortOrder,
        spentThisMonth,
      );
}

/// Totals over all the user's wallets (`summarizeWallets` on the server).
class WalletTotals {
  const WalletTotals({
    required this.assets,
    required this.debts,
    required this.reserved,
    required this.netWorth,
    required this.free,
  });

  /// "Total saldo": every non-debt wallet, reserved included.
  final int assets;

  /// Amount owed, positive.
  final int debts;

  /// "Dana dicadangkan".
  final int reserved;
  final int netWorth;

  /// "Uang bebas": assets that are not reserved, minus debts.
  final int free;

  @override
  bool operator ==(Object other) =>
      other is WalletTotals &&
      other.assets == assets &&
      other.debts == debts &&
      other.reserved == reserved &&
      other.netWorth == netWorth &&
      other.free == free;

  @override
  int get hashCode => Object.hash(assets, debts, reserved, netWorth, free);
}

/// `GET /api/mobile/wallets`: wallets in server order, plus totals.
class WalletList {
  const WalletList({
    required this.asOf,
    required this.period,
    required this.wallets,
    required this.totals,
  });

  /// Server time of the answer.
  final DateTime asOf;

  /// The WIB month [Wallet.spentThisMonth] covers.
  final WibMonth period;
  final List<Wallet> wallets;
  final WalletTotals totals;
}

/// A create or update answer: the written wallet and the new totals.
class WalletWrite {
  const WalletWrite({required this.wallet, required this.totals});

  final Wallet wallet;
  final WalletTotals totals;
}
