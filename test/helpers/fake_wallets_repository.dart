import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tepira_mobile/data/wallets/wallet_dto.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_input.dart';

/// The `GET /api/mobile/wallets` fixture (contract §2): BCA, Tabungan Kurban
/// (reserved), Kartu Kredit (debt) and Tunai.
WalletList fixtureWalletList() => walletListFromJson(
      jsonDecode(File('test/fixtures/mobile_wallets.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// A wallet for widget tests.
Wallet testWallet({
  int id = 1,
  String name = 'BCA',
  String type = 'bank',
  int balance = 8250000,
  int? displayBalance,
  bool isDebt = false,
  bool isReserved = false,
  String? description,
  int sortOrder = 0,
  int spentThisMonth = 0,
}) {
  return Wallet(
    id: id,
    name: name,
    type: type,
    balance: balance,
    displayBalance: displayBalance ?? (isDebt ? -balance.abs() : balance),
    isDebt: isDebt,
    isReserved: isReserved,
    description: description,
    sortOrder: sortOrder,
    spentThisMonth: spentThisMonth,
  );
}

const testTotals = WalletTotals(
  assets: 0,
  debts: 0,
  reserved: 0,
  netWorth: 0,
  free: 0,
);

/// A list answer holding [wallets] and [totals].
WalletList testWalletList(
  List<Wallet> wallets, {
  WalletTotals totals = testTotals,
}) {
  return WalletList(
    asOf: DateTime.utc(2026, 11, 1, 7),
    period: fixtureWalletList().period,
    wallets: wallets,
    totals: totals,
  );
}

/// [WalletsRepository] whose methods answer from the given result lists, in
/// order (the last one repeats). An [Exception] entry is thrown instead of
/// returned. Every call is recorded.
class FakeWalletsRepository implements WalletsRepository {
  FakeWalletsRepository(
    this.listResults, {
    this.createResults = const [],
    this.updateResults = const [],
  });

  final List<Object> listResults;
  final List<Object> createResults;
  final List<Object> updateResults;

  /// When set, [list] waits for it before answering.
  Completer<void>? listGate;

  /// When set, [create] and [update] wait for it before answering.
  Completer<void>? writeGate;

  int listCalls = 0;
  final List<NewWallet> created = [];
  final List<(int, Map<String, Object?>)> updated = [];

  static T _pick<T>(List<Object> results, int call) {
    final result = results[call < results.length ? call : results.length - 1];
    if (result is Exception) throw result;
    return result as T;
  }

  @override
  Future<WalletList> list() async {
    final call = listCalls++;
    await listGate?.future;
    return _pick<WalletList>(listResults, call);
  }

  @override
  Future<WalletWrite> create(NewWallet wallet) async {
    final call = created.length;
    created.add(wallet);
    await writeGate?.future;
    return _pick<WalletWrite>(createResults, call);
  }

  @override
  Future<WalletWrite> update(int id, WalletPatch patch) async {
    final call = updated.length;
    updated.add((id, patch.toJson()));
    await writeGate?.future;
    return _pick<WalletWrite>(updateResults, call);
  }
}
