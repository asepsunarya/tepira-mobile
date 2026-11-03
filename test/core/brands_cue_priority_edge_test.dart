// Independent edge tests for the explicit-cue priority in
// brandForWalletName (PR #20): a DANA/Jago spelling backed by a bank or
// e-wallet cue outranks the other brands in the name; without such a cue the
// longest-first, then list-order rule still applies.
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';

String? _brand(String name) => brandForWalletName(name)?.name;

void _expectAll(Map<String, String?> cases) {
  for (final MapEntry(:key, :value) in cases.entries) {
    expect(_brand(key), value, reason: 'wallet name "$key"');
  }
}

void main() {
  group('case, whitespace and punctuation variants', () {
    test('cue-backed DANA wins regardless of case and separators', () {
      _expectAll({
        'dana E-Wallet via flip': 'DANA',
        'DANA  ewallet / Flip': 'DANA',
        '  DANA\te-wallet\nvia FLIP  ': 'DANA',
        'DANA-wallet (Flip)': 'DANA',
        'Flip, dana_ewallet': 'DANA',
        'FLIP/DANA E WALLET': 'DANA',
      });
    });

    test('cue-backed Jago wins regardless of case and separators', () {
      _expectAll({
        'BANK JAGO via flip': 'Jago',
        'bank-jago / FLIP': 'Jago',
        'Flip -> jago SYARIAH': 'Jago',
      });
    });
  });

  group('every cue word unlocks the priority', () {
    test('bank, syariah, wallet, ewallet and e wallet, before or after', () {
      _expectAll({
        'Flip dana wallet': 'DANA',
        'Flip wallet dana': 'DANA',
        'Flip dana ewallet': 'DANA',
        'Flip ewallet dana': 'DANA',
        'Flip e-wallet dana': 'DANA',
        'Flip dana e-wallet': 'DANA',
        'Flip jago syariah': 'Jago',
        'Flip syariah jago': 'Jago',
        'Flip jago bank': 'Jago',
        'Flip bank jago': 'Jago',
      });
    });

    test('a lone "e" or a non-cue word does not unlock the priority', () {
      _expectAll({
        'Flip dana e': 'Flip',
        'Flip e dana': 'Flip',
        'Flip dana digital': 'Flip',
        'Flip dompet dana': 'Flip',
        'Flip dana wallets': 'Flip',
      });
    });

    test('a cue that is not adjacent does not unlock the priority', () {
      _expectAll({
        'Dana via Flip wallet': 'Flip',
        'Wallet Flip dana': 'Flip',
        'Jago top up Flip bank': 'Flip',
      });
    });
  });

  group('no cue: old rule unchanged', () {
    test('ambiguous words without a cue are ignored', () {
      _expectAll({
        'Jago via DANA': null,
        'DANA via Jago': null,
        'Jago via DANA ke Flip': 'Flip',
        'Jago via DANA ke OVO': 'OVO',
      });
    });

    test('longest first, then list order, among clear brands', () {
      _expectAll({
        'OVO via GoPay': 'GoPay',
        'BCA via Flip': 'Flip',
        'blu by BCA via Mandiri': 'blu by BCA',
        'Mandiri e-money / BCA Flazz': 'Mandiri e-money',
        'BNI Syariah via BRI': 'BNI',
      });
    });
  });

  group('cue-backed DANA beats unrelated clear brands', () {
    test('cue-backed DANA beats any other brand in the name', () {
      _expectAll({
        'OVO via DANA e-wallet': 'DANA',
        'DANA e-wallet via OVO': 'DANA',
        'ShopeePay ke DANA wallet': 'DANA',
        'Mandiri e-money ke DANA e-wallet': 'DANA',
        'blu by BCA / DANA ewallet': 'DANA',
      });
    });

    test('names without dana/jago are unaffected', () {
      _expectAll({
        'GoPay wallet': 'GoPay',
        'OVO e-wallet via Flip': 'Flip',
        'Bank BCA via Flip': 'Flip',
        'BNI Syariah': 'BNI',
        'Bank Mandiri': 'Mandiri',
        'SeaBank / Flip': 'SeaBank',
        'Sea Bank wallet': 'SeaBank',
      });
    });
  });

  group('degenerate names', () {
    test('empty, blank and punctuation-only names have no brand', () {
      _expectAll({'': null, '   ': null, '\t\n': null, '-/.,()': null});
    });

    test('names made only of cue words have no brand', () {
      _expectAll({
        'Bank': null,
        'e-wallet': null,
        'Bank Syariah e-wallet': null,
        'wallet ewallet bank': null,
      });
    });

    test('whole-name ambiguous words still match on their own', () {
      _expectAll({'DANA': 'DANA', ' jago ': 'Jago', 'Dana.': 'DANA'});
    });
  });

  group('regression: cue word that belongs to the next brand', () {
    // "Dana bank Mandiri" reads "funds at bank Mandiri": the cue "bank"
    // belongs to Mandiri, not to "dana". A cue directly followed by another
    // brand's spelling belongs to that brand, so it never backs dana/jago.
    test('a cue between dana/jago and a clear brand keeps the clear brand', () {
      _expectAll({
        'Dana bank Mandiri': 'Mandiri',
        'Dana Syariah Mandiri': 'Mandiri',
        'Jago bank Mandiri': 'Mandiri',
        'Tabungan dana bank Jenius': 'Jenius',
        'Dana wallet ShopeePay': 'ShopeePay',
        'Dana e-wallet ShopeePay': 'ShopeePay',
        'Dana bank BCA': 'BCA',
        'Dana bank BRI': 'BRI',
        'Dana Bank BNI Syariah': 'BNI',
      });
    });

    test('a cue of its own still backs dana/jago', () {
      _expectAll({
        'DANA e-wallet via Flip': 'DANA',
        'Bank Jago via Flip': 'Jago',
        'Dana darurat': null,
        'Dana via Flip': 'Flip',
        'Jago via DANA': null,
        'OVO via DANA e-wallet': 'DANA',
        'Mandiri e-money dana wallet': 'DANA',
        'Bank Jago / ShopeePay': 'Jago',
        'Dana bank Jago': 'Jago',
        'Dana bank / Mandiri': 'DANA',
        'dana wallet jago wallet': 'DANA',
      });
    });
  });
}
