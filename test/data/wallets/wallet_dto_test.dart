import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/wallets/wallet_dto.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';

Map<String, Object?> _fixture() =>
    jsonDecode(File('test/fixtures/mobile_wallets.json').readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> _firstWallet() =>
    ((_fixture()['wallets'] as List).first as Map).cast<String, Object?>();

void main() {
  group('walletListFromJson (mobile_wallets.json)', () {
    test('parses wallets in server order with every field', () {
      final list = walletListFromJson(_fixture());

      expect(list.asOf, DateTime.utc(2026, 11, 1, 7));
      expect(list.period, WibMonth(2026, 11));
      expect(list.wallets.map((w) => w.id), [3, 7, 9]);
      expect(
        list.wallets.first,
        const Wallet(
          id: 3,
          name: 'BCA',
          type: 'bank',
          balance: 8250000,
          displayBalance: 8250000,
          isDebt: false,
          isReserved: false,
          description: null,
          sortOrder: 0,
          spentThisMonth: 385000,
        ),
      );
    });

    test('a debt wallet keeps a negative displayBalance', () {
      final debt = walletListFromJson(_fixture()).wallets.last;

      expect(debt.isDebt, isTrue);
      expect(debt.balance, 1200000);
      expect(debt.displayBalance, -1200000);
      expect(debt.kind, WalletKind.debt);
    });

    test('a reserved wallet keeps its description', () {
      final reserved = walletListFromJson(_fixture()).wallets[1];

      expect(reserved.kind, WalletKind.reserved);
      expect(reserved.description, 'Kurban 2027');
    });

    test('parses totals', () {
      expect(
        walletListFromJson(_fixture()).totals,
        const WalletTotals(
          assets: 11250000,
          debts: 1200000,
          reserved: 3000000,
          netWorth: 10050000,
          free: 7050000,
        ),
      );
    });

    test('an empty wallet list is valid', () {
      final json = _fixture()..['wallets'] = <Object?>[];

      expect(walletListFromJson(json).wallets, isEmpty);
    });
  });

  group('walletFromJson is strict', () {
    test('a missing nullable field throws', () {
      final json = _firstWallet()..remove('description');

      expect(() => walletFromJson(json), throwsFormatException);
    });

    for (final (key, value) in [
      ('id', '3'),
      ('balance', 1.5),
      ('displayBalance', null),
      ('isDebt', 'false'),
      ('isReserved', null),
      ('spentThisMonth', null),
      ('description', 3),
    ]) {
      test('"$key": ${jsonEncode(value)} throws', () {
        final json = _firstWallet()..[key] = value;

        expect(() => walletFromJson(json), throwsFormatException);
      });
    }
  });

  test('a period with month 13 throws', () {
    final json = _fixture()..['period'] = {'year': 2026, 'month': 13};

    expect(() => walletListFromJson(json), throwsFormatException);
  });

  test('walletWriteFromJson reads wallet and totals', () {
    final fixture = _fixture();
    final write = walletWriteFromJson({
      'ok': true,
      'wallet': _firstWallet(),
      'totals': fixture['totals'],
    });

    expect(write.wallet.id, 3);
    expect(write.totals.free, 7050000);
  });

  test('walletWriteFromJson without totals throws', () {
    expect(
      () => walletWriteFromJson({'ok': true, 'wallet': _firstWallet()}),
      throwsFormatException,
    );
  });
}
