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
  });
}
