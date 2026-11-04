import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/model/signed_rupiah_formatter.dart';

// Re-test of PR #21 at 96c2315: separator handling of SignedRupiahFormatter.
// Each case is the (old, new) pair Flutter hands the formatter for a real
// edit.

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
  group('SignedRupiahFormatter separators', () {
    test('backspace after each separator deletes the digit before it', () {
      // '1.234.567': backspace at offset 2 (after the first '.').
      final first = _f.formatEditUpdate(
        _at('1.234.567', 2),
        _at('1234.567', 1),
      );
      _expectValue(first, '234.567', 0);
      // Backspace at offset 6 (after the second '.') deletes the '4'.
      final second = _f.formatEditUpdate(
        _at('1.234.567', 6),
        _at('1.234567', 5),
      );
      _expectValue(second, '123.567', 3);
    });

    test('backspace after each separator of a negative amount', () {
      final first = _f.formatEditUpdate(
        _at('-1.234.567', 3),
        _at('-1234.567', 2),
      );
      _expectValue(first, '-234.567', 1);
      final second = _f.formatEditUpdate(
        _at('-1.234.567', 7),
        _at('-1.234567', 6),
      );
      _expectValue(second, '-123.567', 4);
    });

    test('forward Delete on each separator keeps the amount', () {
      final first = _f.formatEditUpdate(
        _at('1.234.567', 1),
        _at('1234.567', 1),
      );
      _expectValue(first, '1.234.567', 1);
      final second = _f.formatEditUpdate(
        _at('1.234.567', 5),
        _at('1.234567', 5),
      );
      _expectValue(second, '1.234.567', 5);
      final negative = _f.formatEditUpdate(
        _at('-1.234.567', 6),
        _at('-1.234567', 6),
      );
      _expectValue(negative, '-1.234.567', 6);
    });

    test('deleting a selection of separator plus digits', () {
      // Select '.5' in '1.500' (1..3), backspace -> '100'.
      final right = _f.formatEditUpdate(_sel('1.500', 1, 3), _at('100', 1));
      _expectValue(right, '100', 1);
      // Select '1.' (0..2) -> '500', cursor at start.
      final left = _f.formatEditUpdate(_sel('1.500', 0, 2), _at('500', 0));
      _expectValue(left, '500', 0);
      // Select '4.5' leftward in '-1.234.567' (8..5) -> '-1.2367'.
      final neg = _f.formatEditUpdate(
        _sel('-1.234.567', 8, 5),
        _at('-1.2367', 5),
      );
      _expectValue(neg, '-12.367', 5);
    });

    test('cut over a separator then paste digits back', () {
      // Cut '.5' from '1.500' then paste '5' at the same place.
      final cut = _f.formatEditUpdate(_sel('1.500', 1, 3), _at('100', 1));
      _expectValue(cut, '100', 1);
      final paste = _f.formatEditUpdate(cut, _at('1500', 2));
      _expectValue(paste, '1.500', 3);
    });

    test('paste replacing a selection that spans a separator', () {
      // Select '0.0' in '1.000.000' (4..7) and paste '9.9'.
      final r = _f.formatEditUpdate(
        _sel('1.000.000', 4, 7),
        _at('1.009.900', 7),
      );
      _expectValue(r, '1.009.900', 7);
      // Paste a grouped amount with a fraction over the same selection.
      final frac = _f.formatEditUpdate(
        _sel('1.000.000', 4, 7),
        _at('1.002.500,7500', 12),
      );
      // The fraction (and everything after the comma) is dropped.
      expect(frac.text, '1.002.500');
    });

    test('typing at the end regroups with the cursor at the end', () {
      final r = _f.formatEditUpdate(_at('100.000', 7), _at('100.0005', 8));
      _expectValue(r, '1.000.005', 9);
      final neg = _f.formatEditUpdate(_at('-999', 4), _at('-9999', 5));
      _expectValue(neg, '-9.999', 6);
    });

    test('backspace at the end regroups with the cursor at the end', () {
      final r = _f.formatEditUpdate(_at('1.000.005', 9), _at('1.000.00', 8));
      _expectValue(r, '100.000', 7);
      final neg = _f.formatEditUpdate(_at('-1.000', 6), _at('-1.00', 5));
      _expectValue(neg, '-100', 4);
    });

    test('forward Delete at the end is a no-op', () {
      final r = _f.formatEditUpdate(_at('1.500', 5), _at('1.500', 5));
      _expectValue(r, '1.500', 5);
    });
  });
}
