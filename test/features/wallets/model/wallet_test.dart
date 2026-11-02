import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_input.dart';

const _bca = Wallet(
  id: 3,
  name: 'BCA',
  type: 'bank',
  balance: 8250000,
  displayBalance: 8250000,
  isDebt: false,
  isReserved: false,
  description: 'Gaji',
  sortOrder: 0,
  spentThisMonth: 385000,
);

WalletEdit _edit({
  String name = 'BCA',
  String type = 'bank',
  int balance = 8250000,
  bool isReserved = false,
  String? description = 'Gaji',
}) =>
    WalletEdit(
      name: name,
      type: type,
      balance: balance,
      isReserved: isReserved,
      description: description,
    );

void main() {
  group('WalletKind (three kinds)', () {
    test('debt when isDebt', () {
      expect(WalletKind.of(isDebt: true, isReserved: false), WalletKind.debt);
    });

    test('reserved when isReserved and not debt', () {
      expect(
        WalletKind.of(isDebt: false, isReserved: true),
        WalletKind.reserved,
      );
    });

    test('debt wins when both flags are set (as summarizeWallets)', () {
      expect(WalletKind.of(isDebt: true, isReserved: true), WalletKind.debt);
    });

    test('normal otherwise', () {
      expect(
        WalletKind.of(isDebt: false, isReserved: false),
        WalletKind.normal,
      );
      expect(_bca.kind, WalletKind.normal);
    });
  });

  test('wallet types match the API list; credit and paylater are debt', () {
    expect(kWalletTypes, [
      'bank',
      'e-wallet',
      'cash',
      'investment',
      'credit',
      'paylater',
      'other',
    ]);
    expect(kDebtWalletTypes, {'credit', 'paylater'});
  });

  group('NewWallet.toJson', () {
    test('sends every field, trimmed, blank description as null', () {
      expect(
        const NewWallet(
          name: '  GoPay ',
          type: 'e-wallet',
          balance: 150000,
          description: '   ',
        ).toJson(),
        {
          'name': 'GoPay',
          'type': 'e-wallet',
          'balance': 150000,
          'isDebt': false,
          'isReserved': false,
          'description': null,
        },
      );
    });

    test('reserved wallet with a description', () {
      final json = const NewWallet(
        name: 'Tabungan Kurban',
        type: 'bank',
        isReserved: true,
        description: ' Kurban 2027 ',
      ).toJson();

      expect(json['isReserved'], isTrue);
      expect(json['balance'], 0);
      expect(json['description'], 'Kurban 2027');
    });
  });

  group('WalletPatch.between sends only what changed', () {
    test('nothing changed -> empty', () {
      final patch = WalletPatch.between(_bca, _edit());

      expect(patch.isEmpty, isTrue);
      expect(patch.toJson(), isEmpty);
    });

    test('only the name -> {name}; balance is never resent', () {
      expect(
        WalletPatch.between(_bca, _edit(name: ' BCA Utama ')).toJson(),
        {'name': 'BCA Utama'},
      );
    });

    test('whitespace around an unchanged name is not a change', () {
      expect(WalletPatch.between(_bca, _edit(name: ' BCA ')).isEmpty, isTrue);
    });

    test('balance correction -> {balance}', () {
      expect(
        WalletPatch.between(_bca, _edit(balance: 8000000)).toJson(),
        {'balance': 8000000},
      );
    });

    test('cleared description -> {description: null}', () {
      final json = WalletPatch.between(_bca, _edit(description: '  ')).toJson();

      expect(json, {'description': null});
      expect(json.containsKey('description'), isTrue);
    });

    test('type and reserved flag', () {
      expect(
        WalletPatch.between(
          _bca,
          _edit(type: 'investment', isReserved: true),
        ).toJson(),
        {'type': 'investment', 'isReserved': true},
      );
    });

    test('never sends isDebt', () {
      final json = WalletPatch.between(
        _bca,
        _edit(name: 'x', type: 'cash', balance: 1, isReserved: true),
      ).toJson();

      expect(json.containsKey('isDebt'), isFalse);
    });
  });
}
