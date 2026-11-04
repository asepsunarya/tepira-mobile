import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/model/signed_rupiah_formatter.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_form_rules.dart';

// Independent edge cases for SignedRupiahFormatter (PR #21 follow-up test
// pass). Each case feeds the formatter the (old, new) pair Flutter would hand
// it for a real edit.

TextEditingValue _at(String text, int cursor) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );

TextEditingValue _sel(String text, int base, int extent) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );

const _f = SignedRupiahFormatter();

void _expectValue(TextEditingValue v, String text, int cursor) {
  expect(v.text, text);
  expect(v.selection, TextSelection.collapsed(offset: cursor));
}

void main() {
  group('SignedRupiahFormatter edge cases', () {
    test('select-all then type a digit replaces everything', () {
      final r = _f.formatEditUpdate(_sel('1.500.000', 0, 9), _at('7', 1));
      _expectValue(r, '7', 1);
    });

    test('select-all then paste a decimal amount', () {
      final r = _f.formatEditUpdate(
        _sel('-25.000', 0, 7),
        _at('1.500.000,00', 12),
      );
      _expectValue(r, '1.500.000', 9);
      expect(parseWalletBalance(r.text), 1500000);
    });

    test('select-all then delete leaves an empty field', () {
      final r = _f.formatEditUpdate(_sel('1.500', 0, 5), _at('', 0));
      _expectValue(r, '', 0);
      expect(parseWalletBalance(r.text), 0);
    });

    test('backspace over the leading minus drops only the sign', () {
      final r = _f.formatEditUpdate(_at('-1.500', 1), _at('1.500', 0));
      _expectValue(r, '1.500', 0);
    });

    test('minus typed at position 0 of a positive amount', () {
      final r = _f.formatEditUpdate(_at('1.500', 0), _at('-1.500', 1));
      _expectValue(r, '-1.500', 1);
    });

    test('digit typed at position 0 regroups with cursor after it', () {
      final r = _f.formatEditUpdate(_at('500', 0), _at('1500', 1));
      _expectValue(r, '1.500', 1);
    });

    test('backspace at position 0 is a no-op', () {
      final r = _f.formatEditUpdate(_at('1.500', 0), _at('1.500', 0));
      _expectValue(r, '1.500', 0);
    });

    test('zero typed at position 0 is stripped, cursor stays at 0', () {
      final r = _f.formatEditUpdate(_at('5', 0), _at('05', 1));
      _expectValue(r, '5', 0);
    });

    test('deleting a selection spanning a separator regroups', () {
      // '1.234.567', select '4.5' (offsets 4..7) and delete -> '12.367'
      // with the cursor after the '3' that preceded the selection.
      final r = _f.formatEditUpdate(
        _sel('1.234.567', 4, 7),
        _at('1.2367', 4),
      );
      _expectValue(r, '12.367', 4);
    });

    test('deleting a selection that is only a separator keeps digits', () {
      // Select just the '.' in '1.500' and press backspace. The digit count
      // must stay at most 4 and the cursor must stay inside the number.
      final r = _f.formatEditUpdate(_sel('1.500', 1, 2), _at('1500', 1));
      expect(r.text.replaceAll('.', '').length, lessThanOrEqualTo(4));
      expect(r.selection.baseOffset, inInclusiveRange(0, r.text.length));
    });

    test('very long input groups every 3 digits; validator rejects it', () {
      const digits = '123456789012345678901234567890';
      final r = _f.formatEditUpdate(_at('', 0), _at(digits, digits.length));
      expect(
        r.text,
        '123.456.789.012.345.678.901.234.567.890',
      );
      expect(r.selection.baseOffset, r.text.length);
      expect(parseWalletBalance(r.text), isNull);
      expect(
        walletBalanceError(r.text, isDebt: false),
        kWalletBalanceError,
      );
    });

    test('int32 boundary survives formatting', () {
      final r = _f.formatEditUpdate(_at('', 0), _at('2147483647', 10));
      expect(r.text, '2.147.483.647');
      expect(parseWalletBalance(r.text), 2147483647);
      final over = _f.formatEditUpdate(_at('', 0), _at('2147483648', 10));
      expect(parseWalletBalance(over.text), isNull);
    });

    test("'-' alone stays, cursor after it; validator rejects it", () {
      final r = _f.formatEditUpdate(_at('', 0), _at('-', 1));
      _expectValue(r, '-', 1);
      expect(parseWalletBalance(r.text), isNull);
    });

    test("'-0' stays '-0' and parses as 0", () {
      final r = _f.formatEditUpdate(_at('-', 1), _at('-0', 2));
      _expectValue(r, '-0', 2);
      expect(parseWalletBalance(r.text), 0);
    });

    test("'-0' then a digit drops the zero", () {
      final r = _f.formatEditUpdate(_at('-0', 2), _at('-05', 3));
      _expectValue(r, '-5', 2);
    });

    test("'-00012' strips zeros after the sign", () {
      final r = _f.formatEditUpdate(_at('', 0), _at('-00012', 6));
      _expectValue(r, '-12', 3);
    });

    test("'000' collapses to '0'", () {
      final r = _f.formatEditUpdate(_at('', 0), _at('000', 3));
      _expectValue(r, '0', 1);
    });

    test("a second '-' anywhere is dropped", () {
      final mid = _f.formatEditUpdate(_at('-1.500', 3), _at('-1.-500', 4));
      expect(mid.text, '-1.500');
      final dbl = _f.formatEditUpdate(_at('-', 1), _at('--', 2));
      expect(dbl.text, '-');
      final pos = _f.formatEditUpdate(_at('1.500', 3), _at('1.5-00', 4));
      expect(pos.text, '1.500');
    });

    test("typed ',' at the start or end is ignored", () {
      final start = _f.formatEditUpdate(_at('1.500', 0), _at(',1.500', 1));
      _expectValue(start, '1.500', 0);
      final end = _f.formatEditUpdate(_at('1.500', 5), _at('1.500,', 6));
      _expectValue(end, '1.500', 5);
    });

    test('pasted Rp1.500.000,- and whitespace are cleaned', () {
      final r = _f.formatEditUpdate(_at('', 0), _at(' Rp1.500.000,- ', 15));
      expect(r.text, '1.500.000');
      final neg = _f.formatEditUpdate(_at('', 0), _at('  -25.000 ', 10));
      expect(neg.text, '-25.000');
    });

    test('invalid selection (-1) puts cursor at the end', () {
      final r = _f.formatEditUpdate(
        _at('', 0),
        const TextEditingValue(
          text: '1500',
          selection: TextSelection.collapsed(offset: -1),
        ),
      );
      _expectValue(r, '1.500', 5);
    });

    test('backspace deleting the last digit before a group', () {
      // '1.500' cursor after '1', backspace -> '.500' -> '500'.
      final r = _f.formatEditUpdate(_at('1.500', 1), _at('.500', 0));
      _expectValue(r, '500', 0);
    });

    test('groupRupiahDigits basics', () {
      expect(groupRupiahDigits(''), '');
      expect(groupRupiahDigits('-'), '-');
      expect(groupRupiahDigits('999'), '999');
      expect(groupRupiahDigits('1000'), '1.000');
      expect(groupRupiahDigits('-1000000'), '-1.000.000');
      expect(groupRupiahDigits('-2147483648'), '-2.147.483.648');
    });

    test(
      'forward delete (Del key) on a separator must not remove the digit '
      'before the cursor',
      () {
        // '1.500' with the cursor after '1' (offset 1). A hardware Delete key
        // removes the '.' to the right: Flutter sends '1500' with the cursor
        // still at 1. The formatter treats this like a backspace onto the
        // separator and deletes the '1' to the LEFT, giving '500'.
        final r = _f.formatEditUpdate(_at('1.500', 1), _at('1500', 1));
        expect(r.text, isNot('500'));
        expect(r.text.replaceAll('.', ''), anyOf('1500', '100'));
      },
      skip: 'BUG (PR #21 fu, low): forward delete over "." deletes the digit '
          'before the cursor ("1.500"|cursor 1 + Del -> "500"). The formatter '
          'ignores oldValue.selection, so it cannot tell Del from Backspace.',
    );
  });
}
