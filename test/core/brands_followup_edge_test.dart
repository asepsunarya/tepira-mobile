// Independent edge tests for the brand-matching follow-up (ambiguous
// "dana"/"jago", non-alphanumeric separators, longest spelling wins).
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';

String? _brand(String name) => brandForWalletName(name)?.name;

void main() {
  group('brandForWalletName edge cases', () {
    test('empty, whitespace-only and punctuation-only names have no brand', () {
      for (final name in [
        '',
        ' ',
        '   ',
        '\t\n',
        '\u00A0\u00A0',
        '-',
        '---',
        '()',
        './,',
        '💳',
      ]) {
        expect(brandForWalletName(name), isNull, reason: '"$name"');
      }
    });

    test('numeric-only names have no brand', () {
      for (final name in ['0', '123', '0812 3456 7890', '1.000.000']) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });

    test('mixed case is ignored', () {
      for (final (name, brand) in [
        ('bCa', 'BCA'),
        ('GOPAY', 'GoPay'),
        ('mAnDiRi', 'Mandiri'),
        ('sHoPeE pAy', 'ShopeePay'),
        ('dAnA', 'DANA'),
        ('JAGO', 'Jago'),
        ('BANK jAgO', 'Jago'),
        ('MANDIRI E-MONEY', 'Mandiri e-money'),
      ]) {
        expect(_brand(name), brand, reason: name);
      }
    });

    test('unicode separators, emoji and diacritics around a brand', () {
      for (final (name, brand) in [
        ('BCA\u00A0Utama', 'BCA'), // no-break space
        ('BCA\u2013Utama', 'BCA'), // en dash
        ('BCA_utama', 'BCA'), // underscore is not a letter or digit
        ('💳 BCA 💳', 'BCA'),
        ('Café BCA', 'BCA'),
        ('Tabungan Ibu Ságara (BRI)', 'BRI'),
        ('«OVO»', 'OVO'),
      ]) {
        expect(_brand(name), brand, reason: name);
      }
    });

    test('a brand fused with letters, digits or accents is not matched', () {
      for (final name in [
        'BCA123',
        '123BCA',
        'Mandirí', // accented i is a different letter
        'Danamon',
        'Bank Danamon', // cue present, but "dana" is not a whole word
        'Jagoan',
        'Ovoid',
        'Abcade',
      ]) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });

    test('a brand separated from digits by punctuation is matched', () {
      expect(_brand('BCA 123'), 'BCA');
      expect(_brand('BCA-0812'), 'BCA');
      expect(_brand('2024/BNI'), 'BNI');
    });

    test('ambiguous words need a cue that is a whole word', () {
      for (final name in [
        'Dana bankrut', // "bankrut" is not "bank"
        'Dana wallets', // plural is not a cue
        'Dana jago', // two ambiguous words, no cue
        'Jago dana',
        'Dana dana',
      ]) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });

    test('cues work with any separator and in any case', () {
      for (final (name, brand) in [
        ('Dana (wallet)', 'DANA'),
        ('Dana_Wallet', 'DANA'),
        ('DANA E-Wallet', 'DANA'), // "e wallet" still holds the word wallet
        ('dana/EWALLET', 'DANA'),
        ('Jago bank', 'Jago'),
        ('jago-SYARIAH', 'Jago'),
        ('Bank Jago Syariah', 'Jago'),
      ]) {
        expect(_brand(name), brand, reason: name);
      }
    });

    test('e-money spellings all reach Mandiri e-money', () {
      for (final name in [
        'e-money',
        'E-Money',
        'emoney',
        'e money',
        'e.money',
        'Mandiri e-money',
        'Kartu e\u2013money', // en dash
      ]) {
        expect(_brand(name), 'Mandiri e-money', reason: name);
      }
    });

    test('longest spelling wins over a shorter one in the same name', () {
      expect(_brand('BCA Flazz'), 'BCA Flazz');
      expect(_brand('Flazz BCA'), 'BCA Flazz'); // alias "flazz" (5) > "bca"
      expect(_brand('blu by BCA'), 'blu by BCA');
      expect(_brand('BRI/Mandiri'), 'Mandiri');
      expect(_brand('BNI TapCash'), 'BNI TapCash');
      expect(_brand('Mandiri e-money'), 'Mandiri e-money');
      expect(_brand('GoPay / OVO'), 'GoPay');
      expect(_brand('Bank Jago / BCA'), 'Jago');
    });

    test('equal-length spellings fall back to list order, not name order', () {
      // BCA, BNI, BRI, BTN are all three letters; ties keep list order,
      // which relies on List.sort leaving equal lengths in place.
      expect(_brand('BNI/BCA'), 'BCA');
      expect(_brand('BRI BNI'), 'BNI');
      // Name-only brands are listed before picker brands.
      expect(_brand('BRI BTN'), 'BTN');
    });

    test(
      'a cue meant for another brand does not turn "dana" into DANA',
      () {
        // "bank" belongs to BCA/BNI here, but the cue check is global and
        // "dana" (4 letters) outranks "bca"/"bni" (3), so DANA wins.
        expect(_brand('Dana darurat di bank BCA'), 'BCA');
        expect(_brand('Dana pensiun BNI Syariah'), 'BNI');
        expect(_brand('Dana kaget OVO wallet'), 'OVO');
        expect(_brand('Jago masak, bank BRI'), 'BRI');
      },
      skip: 'BUG lib/core/brands.dart:85-93: the bank/syariah/wallet cue is '
          'checked against the whole name, not the word next to "dana"/'
          '"jago", and "dana" (4) outranks 3-letter brands; '
          '"Dana darurat di bank BCA" gets the DANA logo.',
    );
  });
}
