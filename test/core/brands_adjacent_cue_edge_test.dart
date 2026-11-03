// Independent edge tests for the adjacent-cue rule on the ambiguous brand
// words "dana"/"jago" and for the equal-length tie-break (PR #19, 3811118).
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';

String? _brand(String name) => brandForWalletName(name)?.name;

void _expectAll(Map<String, String?> cases) {
  for (final MapEntry(:key, :value) in cases.entries) {
    expect(_brand(key), value, reason: 'wallet name ${_show(key)}');
  }
}

String _show(String s) =>
    '"${s.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}"';

void main() {
  group('adjacent cue: PR scope examples', () {
    test('a cue next to another brand does not unlock dana/jago', () {
      _expectAll({
        'Dana darurat di bank BCA': 'BCA',
        'Dana pensiun BNI Syariah': 'BNI',
        'Dana kaget OVO wallet': 'OVO',
        'Jago masak, bank BRI': 'BRI',
        'DANA e-wallet': 'DANA',
      });
    });
  });

  group('adjacent cue: separators and case', () {
    test('punctuation, case and runs of spaces around the cue', () {
      _expectAll({
        'DANA,e-wallet': 'DANA',
        'dana   E   WALLET': 'DANA',
        'dana.Wallet': 'DANA',
        'DANA/eWallet': 'DANA',
        'dana - e - wallet': 'DANA',
        'dana_bank': 'DANA',
        'Dana bank': 'DANA',
        'Dana\tbank\nBCA': 'BCA',
        'Dana bank, BCA': 'DANA',
        '(Bank) jago': 'Jago',
        'Bank—Jago': 'Jago',
        'JAGO  SYARIAH!!': 'Jago',
        'jago...syariah': 'Jago',
      });
    });

    test('cue before, after and on both sides', () {
      _expectAll({
        'e-wallet DANA': 'DANA',
        'ewallet dana': 'DANA',
        'Wallet DANA wallet': 'DANA',
        'bank dana bank': 'DANA',
        'Syariah Jago': 'Jago',
        'Jago Syariah': 'Jago',
        'bank jago bank': 'Jago',
      });
    });

    test('a cue that is not directly adjacent does not count', () {
      _expectAll({
        'Dana untuk bank': null,
        'Dana di e-wallet': null,
        'e-wallet untuk dana': null,
        'Jago, tabungan syariah': null,
        'Tabungan Jago': null,
        'Dana e': null,
        'Dana walletku': null,
        'Dana e-walletku': null,
        'Dana ewallets': null,
        'Dana Jago': null,
      });
    });

    test('a later occurrence with an adjacent cue still matches', () {
      _expectAll({
        'dana darurat, dana bank': 'DANA',
        'jago masak jago syariah': 'Jago',
      });
    });
  });

  group('pinned current behavior', () {
    // Decision on PR #20 (replaces the PR #19 pin "Dana bank BCA" is DANA):
    // a cue directly followed by another brand's spelling belongs to that
    // brand, so "bank" here is BCA's and does not back "dana".
    test('"Dana bank BCA" is BCA', () {
      expect(_brand('Dana bank BCA'), 'BCA');
      expect(_brand('dana, bank bca'), 'BCA');
    });

    test('Bank Jago and bare dana/jago', () {
      _expectAll({
        'Bank Jago': 'Jago',
        'BANK JAGO': 'Jago',
        'bank-jago': 'Jago',
        'Jago': 'Jago',
        ' jago ': 'Jago',
        'DANA': 'DANA',
        'dana.': 'DANA',
      });
    });
  });

  group('dana/jago inside other words', () {
    test('mid-word or fused spellings never match', () {
      _expectAll({
        'Jagoan bank': null,
        'bank Jagoan': null,
        'Rajagoal bank': null,
        'bankjago': null,
        'danabank': null,
        'Bank Danamon': null,
        'Danamon e-wallet': null,
        'dana2 bank': null,
        'Pendanaan wallet': null,
      });
    });
  });

  group('empty and cue-only names', () {
    test('empty, whitespace and cue-only names have no brand', () {
      _expectAll({
        '': null,
        ' ': null,
        '   \t\n ': null,
        '  ': null,
        'bank': null,
        'wallet': null,
        'e-wallet': null,
        'Bank Syariah': null,
        'e': null,
      });
    });
  });

  group('explicit cue takes priority', () {
    test('a cue-backed DANA/Jago beats other brands in the name', () {
      _expectAll({
        'DANA e-wallet via Flip': 'DANA',
        'Flip via DANA e-wallet': 'DANA',
        'Bank Jago via Flip': 'Jago',
        'Top up Flip ke Bank Jago': 'Jago',
        'DANA e-wallet / blu by BCA': 'DANA',
      });
    });

    test('without a cue the existing order still applies', () {
      _expectAll({
        'Top up via Flip': 'Flip',
        'Flip': 'Flip',
        'Dana via Flip': 'Flip',
        'Dana darurat': null,
        'Dana darurat di bank BCA': 'BCA',
        'Dana pensiun BNI Syariah': 'BNI',
      });
    });

    test('several cue-backed spellings: longest, then list order', () {
      _expectAll({
        'dana bank jago': 'Jago',
        'Jago wallet dana wallet': 'DANA',
        'Bank Jago, DANA e-wallet, Flip': 'Jago',
      });
    });
  });

  group('equal-length tie-break', () {
    test('equal-length spellings resolve by list position, not name order', () {
      _expectAll({
        // picker order: OVO (1) before BCA (5) before BNI (7) before BRI (8)
        'BRI BNI BCA': 'BCA',
        'BNI BCA': 'BCA',
        'BCA OVO': 'OVO',
        // name-only brands come before picker brands
        'BCA BTN': 'BTN',
        'BNI blu': 'blu by BCA',
        // dana/jago (4) tie: DANA precedes Jago in the picker list
        'Jago wallet dana wallet': 'DANA',
        'dana wallet jago wallet': 'DANA',
      });
    });

    test('result is the same for every call and every word order', () {
      const names = [
        'BRI BNI BCA',
        'BCA BNI BRI',
        'BNI BRI BCA',
        'BCA BRI BNI',
      ];
      for (var i = 0; i < 500; i++) {
        for (final name in names) {
          expect(_brand(name), 'BCA', reason: name);
        }
      }
    });

    test('longer spelling still beats list order', () {
      _expectAll({
        'Jago bank jago': 'Jago',
        'dana bank jago': 'Jago',
        'blu by BCA': 'blu by BCA',
        'BCA blu by bca': 'blu by BCA',
      });
    });
  });
}
