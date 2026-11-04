import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/wallets/model/signed_rupiah_formatter.dart';

TextEditingValue _value(String text, int cursor) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );

const _formatter = SignedRupiahFormatter();

TextEditingValue _format(TextEditingValue from, TextEditingValue to) =>
    _formatter.formatEditUpdate(from, to);

void main() {
  group('SignedRupiahFormatter', () {
    test('groups thousands and keeps a leading minus', () {
      final result = _format(_value('', 0), _value('-1500000', 8));
      expect(result.text, '-1.500.000');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('a digit typed mid-number keeps the cursor after it', () {
      // '1.500' with the cursor after '1'; typing '2' gives '12.500'.
      final result = _format(_value('1.500', 1), _value('12.500', 2));
      expect(result.text, '12.500');
      expect(result.selection, const TextSelection.collapsed(offset: 2));

      // '12.500' -> '125.500': regrouped, cursor still after the new '5'.
      final regrouped = _format(_value('12.500', 2), _value('125.500', 3));
      expect(regrouped.text, '125.500');
      expect(regrouped.selection, const TextSelection.collapsed(offset: 3));

      // '125.500' -> '1.255.500': the cursor follows the digit, not the end.
      final grown = _format(_value('125.500', 3), _value('1255.500', 4));
      expect(grown.text, '1.255.500');
      expect(grown.selection, const TextSelection.collapsed(offset: 5));
    });

    test('backspace onto a separator deletes the digit before it', () {
      // '1.500.000' with the cursor after the second '.'; backspace.
      final result = _format(_value('1.500.000', 6), _value('1.500000', 5));
      expect(result.text, '150.000');
      expect(result.selection, const TextSelection.collapsed(offset: 3));
    });

    test('a comma typed mid-number is ignored', () {
      final result = _format(_value('1.500.000', 1), _value('1,.500.000', 2));
      expect(result.text, '1.500.000');
      expect(result.selection, const TextSelection.collapsed(offset: 1));
    });

    test('a pasted decimal amount still drops the fraction', () {
      final result = _format(_value('', 0), _value('1.500.000,00', 12));
      expect(result.text, '1.500.000');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('a minus after the first character is dropped', () {
      final result = _format(_value('15', 2), _value('15-', 3));
      expect(result.text, '15');
    });

    test('leading zeros are dropped', () {
      final result = _format(_value('0', 1), _value('05', 2));
      expect(result.text, '5');
      expect(result.selection, const TextSelection.collapsed(offset: 1));
    });
  });
}
