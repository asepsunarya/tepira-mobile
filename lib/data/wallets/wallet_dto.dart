/// Parses wallet JSON from `/api/mobile/wallets*` (SPEC-v2 §3.1 to 3.3).
library;

import '../../features/wallets/model/wallet.dart';
import '../json_fields.dart';

/// One wallet item (list, create, update, and the wallets an expense write
/// returns).
Wallet walletFromJson(Map<String, Object?> json) {
  return Wallet(
    id: requiredField<int>(json, 'id'),
    name: requiredField<String>(json, 'name'),
    type: requiredField<String>(json, 'type'),
    balance: requiredField<int>(json, 'balance'),
    displayBalance: requiredField<int>(json, 'displayBalance'),
    isDebt: requiredField<bool>(json, 'isDebt'),
    isReserved: requiredField<bool>(json, 'isReserved'),
    description: nullableField<String>(json, 'description'),
    sortOrder: requiredField<int>(json, 'sortOrder'),
    spentThisMonth: requiredField<int>(json, 'spentThisMonth'),
  );
}

WalletTotals walletTotalsFromJson(Map<String, Object?> json) {
  return WalletTotals(
    assets: requiredField<int>(json, 'assets'),
    debts: requiredField<int>(json, 'debts'),
    reserved: requiredField<int>(json, 'reserved'),
    netWorth: requiredField<int>(json, 'netWorth'),
    free: requiredField<int>(json, 'free'),
  );
}

/// The body of `GET /api/mobile/wallets`.
WalletList walletListFromJson(Map<String, Object?> json) {
  return WalletList(
    asOf: instantField(json, 'asOf'),
    period: periodField(json, 'period'),
    wallets: listField(json, 'wallets', walletFromJson),
    totals: walletTotalsFromJson(objectField(json, 'totals')),
  );
}

/// The body of `POST /api/mobile/wallets` and `PATCH /api/mobile/wallets/{id}`.
WalletWrite walletWriteFromJson(Map<String, Object?> json) {
  return WalletWrite(
    wallet: walletFromJson(objectField(json, 'wallet')),
    totals: walletTotalsFromJson(objectField(json, 'totals')),
  );
}
