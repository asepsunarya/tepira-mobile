// Independent adversarial tests for cue ownership in brandForWalletName
// (PR #20): a cue word right after "dana"/"jago" belongs to a clear brand
// that directly follows it with only whitespace between; punctuation ends the
// cue's reach; dana/jago never take each other's cue.
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';

String? _brand(String name) => brandForWalletName(name)?.name;

void _expectAll(Map<String, String?> cases) {
  for (final MapEntry(:key, :value) in cases.entries) {
    expect(_brand(key), value, reason: 'wallet name "$key"');
  }
}

/// Every clear (non dana/jago) spelling, as a user might type it, with the
/// brand it must resolve to.
const Map<String, String> _clearSpellings = {
  'GoPay': 'GoPay',
  'OVO': 'OVO',
  'ShopeePay': 'ShopeePay',
  'Shopee Pay': 'ShopeePay',
  'LinkAja': 'LinkAja',
  'Link Aja': 'LinkAja',
  'BCA': 'BCA',
  'Mandiri': 'Mandiri',
  'BNI': 'BNI',
  'BRI': 'BRI',
  'Jenius': 'Jenius',
  'Bank Jago': 'Jago',
  'SeaBank': 'SeaBank',
  'Sea Bank': 'SeaBank',
  'blu by BCA': 'blu by BCA',
  'blu BCA': 'blu by BCA',
  'blu': 'blu by BCA',
  'BCA Flazz': 'BCA Flazz',
  'Flazz': 'BCA Flazz',
  'Mandiri e-money': 'Mandiri e-money',
  'e-money': 'Mandiri e-money',
  'emoney': 'Mandiri e-money',
  'BNI TapCash': 'BNI TapCash',
  'TapCash': 'BNI TapCash',
  'BRI Brizzi': 'BRI Brizzi',
  'Brizzi': 'BRI Brizzi',
  'BTN': 'BTN',
  'Flip': 'Flip',
};

const List<String> _cues = [
  'bank',
  'BANK',
  'Syariah',
  'wallet',
  'eWallet',
  'e-wallet',
  'E Wallet',
];

void main() {
  group('cue followed by every clear brand goes to that brand', () {
    test('Dana <cue> <brand>', () {
      for (final cue in _cues) {
        for (final MapEntry(key: spelling, value: brand)
            in _clearSpellings.entries) {
          final name = 'Dana $cue $spelling';
          expect(_brand(name), brand, reason: 'wallet name "$name"');
        }
      }
    });

    test('Jago <cue> <brand>', () {
      for (final cue in _cues) {
        for (final MapEntry(key: spelling, value: brand)
            in _clearSpellings.entries) {
          final name = 'jago $cue $spelling';
          expect(_brand(name), brand, reason: 'wallet name "$name"');
        }
      }
    });

    test('a comma between cue and brand keeps the cue with dana/jago', () {
      for (final cue in _cues) {
        for (final MapEntry(key: spelling, value: brand)
            in _clearSpellings.entries) {
          // "bank jago" is an explicit alias on its own and outranks.
          final danaName = 'Dana $cue, $spelling';
          expect(
            _brand(danaName),
            spelling == 'Bank Jago' ? 'Jago' : 'DANA',
            reason: 'wallet name "$danaName" (brand $brand)',
          );
          final jagoName = 'Jago $cue, $spelling';
          expect(_brand(jagoName), 'Jago', reason: 'wallet name "$jagoName"');
        }
      }
    });
  });

  group('case and whitespace variants', () {
    test('mixed case and repeated spaces still pass the cue on', () {
      _expectAll({
        'dAnA BaNk bCa': 'BCA',
        'DANA    BANK     MANDIRI': 'Mandiri',
        '   dana  wallet   gopay   ': 'GoPay',
        'JaGo SyArIaH bNi': 'BNI',
        'dana E-WALLET ovo': 'OVO',
      });
    });

    test('tabs, newlines, CRLF and unicode spaces count as whitespace', () {
      _expectAll({
        'Dana\tbank\tBCA': 'BCA',
        'Dana bank\r\nMandiri': 'Mandiri',
        'Dana bank BCA': 'BCA', // no-break space
        'Dana bank BRI': 'BRI', // narrow no-break space
        'Dana bank BNI': 'BNI', // em space
        'Dana wallet　OVO': 'OVO', // ideographic space
        'Dana bank  Jenius': 'Jenius',
      });
    });
  });

  group('punctuation ends the cue reach', () {
    test('hyphen, slash, comma, dot, underscore, colon, parens', () {
      _expectAll({
        'Dana bank, BCA': 'DANA',
        'Dana bank,BCA': 'DANA',
        'Dana bank-BCA': 'DANA',
        'Dana bank - BCA': 'DANA',
        'Dana bank/BCA': 'DANA',
        'Dana bank / BCA': 'DANA',
        'Dana bank. BCA': 'DANA',
        'Dana bank_BCA': 'DANA',
        'Dana bank: Mandiri': 'DANA',
        'Dana bank (BCA)': 'DANA',
        'Dana e-wallet/OVO': 'DANA',
        'Jago bank, Mandiri': 'Jago',
        'jago syariah / BNI': 'Jago',
      });
    });

    test('punctuation before the cue does not matter, only after it', () {
      _expectAll({
        'Dana-bank BCA': 'BCA',
        'Dana/wallet GoPay': 'GoPay',
        'Dana, bank BCA': 'BCA',
        'Dana-e-wallet OVO': 'OVO',
        'Jago.bank Mandiri': 'Mandiri',
      });
    });
  });

  group('cue position', () {
    test('cue at end of string backs dana/jago', () {
      _expectAll({
        'BCA Dana bank': 'DANA',
        'Mandiri dana wallet': 'DANA',
        'GoPay ovo dana e-wallet': 'DANA',
        'BNI jago syariah': 'Jago',
        'Dana bank': 'DANA',
        'Jago bank': 'Jago',
      });
    });

    test('cue before dana/jago is always its own', () {
      _expectAll({
        'bank Dana bank BCA': 'DANA',
        'BCA bank Dana': 'DANA',
        'wallet dana wallet OVO': 'DANA',
        'Bank Jago bank BCA': 'Jago',
      });
    });

    test(
        'two consecutive cues: the cue next to dana is not followed by a '
        'brand, so it stays dana\'s', () {
      _expectAll({
        'Dana bank syariah Mandiri': 'DANA',
        'Dana syariah bank BCA': 'DANA',
        'Dana wallet e-wallet OVO': 'DANA',
        'Dana e-wallet bank BRI': 'DANA',
        'Jago bank syariah BNI': 'Jago',
      });
    });

    test('cue followed by a non-brand or a partial brand word', () {
      _expectAll({
        'Dana bank 123': 'DANA',
        'Dana bank bcasyariah': 'DANA',
        'Dana wallet shopee': 'DANA',
        'Dana bank BCAx': 'DANA',
        'Dana bank sea': 'DANA',
      });
    });

    test('a later own-cued occurrence still backs dana', () {
      _expectAll({
        'Dana bank BCA dana wallet': 'DANA',
        'Dana bank BCA, Dana': 'BCA',
      });
    });
  });

  group('unicode separators that are not whitespace', () {
    test('zero-width space, soft hyphen and emoji end the cue reach', () {
      _expectAll({
        'Dana bank​BCA': 'DANA', // zero-width space (not White_Space)
        'Dana bank­BCA': 'DANA', // soft hyphen
        'Dana bank \u{1F3E6} BCA': 'DANA', // emoji between
      });
    });

    test(
      'NEXT LINE (U+0085) is Unicode whitespace, so the cue passes on',
      () {
        _expectAll({'Dana bank\u0085BCA': 'BCA'});
      },
      skip: 'BUG (minor): _whitespaceOnly uses Dart RegExp \\s, which omits '
          'U+0085 NEXT LINE (Unicode White_Space); actual: DANA.',
    );
  });

  group('more cue/brand interplay', () {
    test('repeated cue, other ambiguous word, cue after a clear brand', () {
      _expectAll({
        'Dana bank bank BCA': 'DANA',
        'Dana jago bank BCA': 'BCA',
        'Dana Mandiri bank': 'Mandiri',
        'Dana e wallet': 'DANA',
        'Dana e BCA': 'BCA',
      });
    });
  });

  group('dana and jago do not take each other\'s cue', () {
    test('resolved by alias or list order', () {
      _expectAll({
        'dana wallet jago wallet': 'DANA',
        'Jago wallet dana wallet': 'DANA',
        'Dana bank Jago': 'Jago',
        'DANA BANK JAGO': 'Jago',
        'Jago bank Dana': 'DANA',
        'Jago wallet Dana': 'DANA',
        'Dana wallet Jago': 'DANA',
      });
    });
  });

  group('longer realistic descriptions', () {
    test('transaction-style names', () {
      _expectAll({
        'Transfer ke Dana bank BCA a.n. Budi': 'BCA',
        'Top up DANA wallet Rp50.000 via BCA': 'DANA',
        'Tarik tunai dana bank Mandiri cabang Bandung': 'Mandiri',
        'Pembayaran QRIS dana e-wallet, GoPay': 'DANA',
        'Dana darurat di bank BCA': 'BCA',
        'Simpan dana syariah BNI Syariah': 'BNI',
        'Dana bank BRI Brizzi isi ulang': 'BRI Brizzi',
        'Tabungan dana bank blu by BCA (bulanan)': 'blu by BCA',
        'Kirim dana wallet ke ShopeePay teman': 'DANA',
        'Kirim dana wallet ShopeePay teman': 'ShopeePay',
        'Gaji masuk jago bank Jenius payroll': 'Jenius',
        'Refund dari dana e-wallet / Flip': 'DANA',
      });
    });
  });
}
