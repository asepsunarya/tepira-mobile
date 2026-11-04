import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_form_rules.dart';

import '../../../helpers/fake_wallets_repository.dart';

void main() {
  group('walletNameError', () {
    test('empty or blank name -> the server message', () {
      expect(walletNameError(''), kWalletNameError);
      expect(walletNameError('   '), kWalletNameError);
    });

    test('60 characters after trimming pass; 61 fail', () {
      expect(walletNameError('  ${'a' * 60}  '), isNull);
      expect(walletNameError('a' * 61), kWalletNameError);
    });

    test('a control character fails', () {
      expect(walletNameError('BCA\u0007'), kWalletNameError);
      expect(walletNameError('BC\nA'), kWalletNameError);
    });

    test('length counts code points, as the server: one emoji is one', () {
      expect(walletNameError('😀' * 60), isNull);
      expect(walletNameError('😀' * 61), kWalletNameError);
    });

    test('C1 controls (U+0080 to U+009F) pass, as on the server', () {
      expect(walletNameError('BCA\u0085\u009F'), isNull);
    });

    test('a lone surrogate fails (not well-formed)', () {
      expect(walletNameError('BCA \uD83D'), kWalletNameError);
    });

    test('an ordinary name passes', () {
      expect(walletNameError('Kartu kredit BCA'), isNull);
    });
  });

  group('walletDescriptionError', () {
    test('blank and up to 200 characters pass', () {
      expect(walletDescriptionError(''), isNull);
      expect(walletDescriptionError(' ${'x' * 200} '), isNull);
    });

    test('201 characters fail', () {
      expect(walletDescriptionError('x' * 201), kWalletDescriptionError);
    });

    test('length counts code points: 200 emoji pass, 201 fail', () {
      expect(walletDescriptionError('😀' * 200), isNull);
      expect(walletDescriptionError('😀' * 201), kWalletDescriptionError);
    });

    test('a NUL character fails with the server message', () {
      const withNul = 'Kurban\u00002027';
      expect(walletDescriptionError(withNul), kWalletDescriptionError);
    });

    test('a lone surrogate fails; other controls pass, as on the server', () {
      expect(walletDescriptionError('x\uDE00'), kWalletDescriptionError);
      expect(walletDescriptionError('baris 1\nbaris 2\t\u0007'), isNull);
    });
  });

  group('parseWalletBalance', () {
    test('blank is 0; grouped digits and a sign parse', () {
      expect(parseWalletBalance(''), 0);
      expect(parseWalletBalance('1.500.000'), 1500000);
      expect(parseWalletBalance('-25.000'), -25000);
    });

    test('int32 bounds', () {
      expect(parseWalletBalance('2.147.483.647'), 2147483647);
      expect(parseWalletBalance('-2.147.483.648'), -2147483648);
      expect(parseWalletBalance('2.147.483.648'), isNull);
      expect(parseWalletBalance('99999999999'), isNull);
    });

    test('anything else is not a whole number', () {
      expect(parseWalletBalance('1,5'), isNull);
      expect(parseWalletBalance('--1'), isNull);
      expect(parseWalletBalance('1-'), isNull);
    });
  });

  group('walletBalanceError', () {
    test('a new debt wallet must not owe a negative amount', () {
      expect(
        walletBalanceError('-1', isDebt: true),
        kWalletDebtNegativeError,
      );
      expect(walletBalanceError('1.000', isDebt: true), isNull);
    });

    test('an asset may be negative (overdraft)', () {
      expect(walletBalanceError('-50.000', isDebt: false), isNull);
    });

    test('an unchanged negative debt balance passes on edit', () {
      final legacy = testWallet(
        type: 'credit',
        balance: -300000,
        displayBalance: -300000,
        isDebt: true,
      );
      expect(
        walletBalanceError('-300.000', isDebt: true, original: legacy),
        isNull,
      );
      expect(
        walletBalanceError('-200.000', isDebt: true, original: legacy),
        kWalletDebtNegativeError,
      );
    });

    test('out of range -> the integer message', () {
      expect(
        walletBalanceError('9.999.999.999', isDebt: false),
        kWalletBalanceError,
      );
    });
  });

  group('walletTypeChoices', () {
    test('a new wallet may take every type', () {
      expect(walletTypeChoices(null), [
        'bank',
        'e-wallet',
        'cash',
        'investment',
        'credit',
        'paylater',
        'other',
      ]);
    });

    test('an asset keeps to asset types', () {
      expect(
        walletTypeChoices(testWallet(type: 'bank')),
        ['bank', 'e-wallet', 'cash', 'investment', 'other'],
      );
    });

    test('a debt wallet may take any type; it stays debt', () {
      expect(
        walletTypeChoices(testWallet(type: 'credit', isDebt: true)),
        kWalletTypes,
      );
    });

    test('a debt wallet of an asset type keeps that type selectable', () {
      expect(
        walletTypeChoices(testWallet(type: 'other', isDebt: true)),
        contains('other'),
      );
    });

    test('an unknown stored type stays selectable', () {
      expect(
        walletTypeChoices(testWallet(type: 'kripto')),
        ['bank', 'e-wallet', 'cash', 'investment', 'other', 'kripto'],
      );
    });
  });

  test('walletIsDebt follows the type on create and the stored flag on edit',
      () {
    expect(walletIsDebt('credit', null), isTrue);
    expect(walletIsDebt('paylater', null), isTrue);
    expect(walletIsDebt('bank', null), isFalse);
    final legacyDebt = testWallet(type: 'other', isDebt: true);
    expect(walletIsDebt('other', legacyDebt), isTrue);
  });
}
