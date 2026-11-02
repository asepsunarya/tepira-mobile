import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';

void main() {
  test('picker lists the 12 design brands, e-wallets first', () {
    expect(kPickerBrands.map((b) => b.name), [
      'GoPay',
      'OVO',
      'DANA',
      'ShopeePay',
      'LinkAja',
      'BCA',
      'Mandiri',
      'BNI',
      'BRI',
      'Jenius',
      'Jago',
      'SeaBank',
    ]);
  });

  test('every brand asset exists', () {
    for (final name in [
      ...kPickerBrands.map((b) => b.name),
      'blu by BCA',
      'BCA Flazz',
      'Mandiri e-money',
      'BNI TapCash',
      'BRI Brizzi',
      'BTN',
      'Flip',
    ]) {
      final asset = brandForWalletName(name)!.asset;
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  group('brandForWalletName', () {
    test('exact name, any case and spacing', () {
      expect(brandForWalletName('BCA')?.name, 'BCA');
      expect(brandForWalletName('  gopay ')?.name, 'GoPay');
      expect(brandForWalletName('Shopee   Pay')?.name, 'ShopeePay');
    });

    test('brand as a whole word inside a longer name', () {
      expect(brandForWalletName('Kartu kredit BCA')?.name, 'BCA');
      expect(brandForWalletName('bri tabungan')?.name, 'BRI');
    });

    test('the longer brand wins over the shorter one it contains', () {
      expect(brandForWalletName('blu by BCA')?.name, 'blu by BCA');
      expect(brandForWalletName('BCA Flazz')?.name, 'BCA Flazz');
      expect(brandForWalletName('Mandiri e-money')?.name, 'Mandiri e-money');
    });

    test('no match inside another word or for unknown names', () {
      expect(brandForWalletName('Tunai'), isNull);
      expect(brandForWalletName('Tabungan Kurban'), isNull);
      expect(brandForWalletName('Ovomaltine'), isNull);
      expect(brandForWalletName('Abcade'), isNull);
      expect(brandForWalletName(''), isNull);
    });

    test('"dana" and "jago" as everyday words are not brands', () {
      for (final name in [
        'Dana darurat',
        'Dana pendidikan',
        'Dana liburan',
        'dana-darurat',
        'Jago masak',
        'Tabungan jago',
      ]) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });

    test('"dana" and "jago" match alone or with a bank/e-wallet cue', () {
      for (final (name, brand) in [
        ('DANA', 'DANA'),
        ('dana', 'DANA'),
        (' Dana. ', 'DANA'),
        ('DANA e-wallet', 'DANA'),
        ('Dana ewallet', 'DANA'),
        ('Jago', 'Jago'),
        ('Bank Jago', 'Jago'),
        ('Jago Syariah', 'Jago'),
      ]) {
        expect(brandForWalletName(name)?.name, brand, reason: name);
      }
    });

    test('a common word next to a clear brand keeps that brand', () {
      expect(brandForWalletName('Dana darurat BCA')?.name, 'BCA');
      expect(brandForWalletName('Mandiri Syariah')?.name, 'Mandiri');
      expect(brandForWalletName('BRI Syariah')?.name, 'BRI');
    });

    test('punctuation separates words', () {
      for (final (name, brand) in [
        ('Kartu kredit BCA.', 'BCA'),
        ('(BCA)', 'BCA'),
        ('GoPay, harian', 'GoPay'),
        ('BCA-Kredit', 'BCA'),
        ('Tabungan (Mandiri)', 'Mandiri'),
        ('Mandiri e-money', 'Mandiri e-money'),
        ('e-money kantor', 'Mandiri e-money'),
        ('E-Money', 'Mandiri e-money'),
      ]) {
        expect(brandForWalletName(name)?.name, brand, reason: name);
      }
    });

    test('two brands in one name: the longer spelling wins', () {
      // "mandiri" (7) is longer than "bca" (3), whatever the order.
      expect(brandForWalletName('BCA/Mandiri')?.name, 'Mandiri');
      expect(brandForWalletName('Mandiri/BCA')?.name, 'Mandiri');
      // Same length: the first brand in list order (extras, then picker).
      expect(brandForWalletName('BNI/BRI')?.name, 'BNI');
    });

    test('punctuation never creates a match inside a word', () {
      for (final name in [
        'BCAX',
        'Danamon',
        'Ovoid',
        'Bluebird',
        'Flipper',
        'Jagoan',
        'Gopayment',
        'Abca.',
        '(Danamon)',
        'Bluebird/Ovoid',
        'x.bca2',
      ]) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });
  });
}
