import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/rupiah_input_formatter.dart';

TextEditingValue _typed(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

String _format(TextInputFormatter formatter, String text) =>
    formatter.formatEditUpdate(TextEditingValue.empty, _typed(text)).text;

void main() {
  const positive = RupiahInputFormatter();
  const signed = SignedRupiahFormatter();

  test('positive by default: a typed or pasted minus is dropped', () {
    expect(_format(positive, '-25000'), '25.000');
    expect(_format(positive, ' -1.500.000 '), '1.500.000');
    expect(_format(positive, '-'), '');
  });

  test('positive reads Indonesian amounts like the signed one', () {
    for (final text in ['1.500.000,50', 'Rp1.500.000,-', '0025000']) {
      expect(
        _format(positive, text),
        _format(signed, text),
        reason: text,
      );
    }
    expect(_format(positive, '1.500.000,50'), '1.500.000');
  });

  test('the signed formatter still keeps the sign', () {
    expect(_format(signed, '-25000'), '-25.000');
  });
}
