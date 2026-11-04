// Independent edge cases for PR #25: forward Delete onto a `.` separator
// deletes the digit after it, while backspace, a selection of just the `.`
// and every other edit keep their old behaviour. Unit cases use the
// (old, new) pair Flutter hands the formatter; the widget cases drive a real
// TextField with key events.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/rupiah_input_formatter.dart';

TextEditingValue _at(String text, int cursor) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );

TextEditingValue _sel(String text, int base, int extent) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );

void _expectValue(TextEditingValue v, String text, int cursor) {
  expect(v.text, text);
  expect(v.selection, TextSelection.collapsed(offset: cursor));
}

/// Flutter's forward Delete of one character at a collapsed [cursor].
TextEditingValue _delete(TextInputFormatter f, String text, int cursor) =>
    f.formatEditUpdate(
      _at(text, cursor),
      _at(text.substring(0, cursor) + text.substring(cursor + 1), cursor),
    );

/// Flutter's backspace of one character before a collapsed [cursor].
TextEditingValue _backspace(TextInputFormatter f, String text, int cursor) =>
    f.formatEditUpdate(
      _at(text, cursor),
      _at(text.substring(0, cursor - 1) + text.substring(cursor), cursor - 1),
    );

/// Removing the selection [start]..[end] (in either direction).
TextEditingValue _cut(
  TextInputFormatter f,
  String text,
  int base,
  int extent,
) {
  final start = base < extent ? base : extent;
  final end = base < extent ? extent : base;
  return f.formatEditUpdate(
    _sel(text, base, extent),
    _at(text.substring(0, start) + text.substring(end), start),
  );
}

const _unsigned = RupiahInputFormatter();
const _signed = SignedRupiahFormatter();

void main() {
  group('forward Delete before a separator (unit)', () {
    for (final (name, f) in [
      ('RupiahInputFormatter', _unsigned),
      ('SignedRupiahFormatter', _signed),
    ]) {
      test('$name: 1|.234.567 deletes the 2', () {
        _expectValue(_delete(f, '1.234.567', 1), '134.567', 1);
      });

      test('$name: 12.345|.678 deletes the 6 and regroups', () {
        // Digits 1234578 regroup to 1.234.578; the cursor stays after the
        // '5' it followed.
        _expectValue(_delete(f, '12.345.678', 6), '1.234.578', 7);
      });

      test('$name: 1|.500 gives 100 with the cursor after the 1', () {
        _expectValue(_delete(f, '1.500', 1), '100', 1);
      });

      test('$name: a zero after the separator is deleted, not dropped', () {
        _expectValue(_delete(f, '1.050.000', 1), '150.000', 1);
        _expectValue(_delete(f, '1.000', 1), '100', 1);
      });

      test('$name: repeated Delete walks through the separators', () {
        var v = _delete(f, '1.234.567', 1);
        _expectValue(v, '134.567', 1);
        v = _delete(f, v.text, v.selection.extentOffset);
        _expectValue(v, '14.567', 1);
        v = _delete(f, v.text, v.selection.extentOffset);
        _expectValue(v, '1.567', 1);
        v = _delete(f, v.text, v.selection.extentOffset);
        _expectValue(v, '167', 1);
      });

      test('$name: Delete at the end of the text changes nothing', () {
        // Flutter hands the formatter an unchanged value.
        final r = f.formatEditUpdate(_at('1.500', 5), _at('1.500', 5));
        _expectValue(r, '1.500', 5);
      });

      test('$name: Delete of the last digit regroups', () {
        _expectValue(_delete(f, '1.500', 4), '150', 3);
      });

      test('$name: Delete on an empty field stays empty', () {
        final r = f.formatEditUpdate(_at('', 0), _at('', 0));
        _expectValue(r, '', 0);
      });

      test('$name: backspace after a separator is unchanged', () {
        _expectValue(_backspace(f, '1.500', 2), '500', 0);
        _expectValue(_backspace(f, '12.345.678', 7), '1.234.678', 5);
      });

      test('$name: removing only the separator just regroups', () {
        _expectValue(_cut(f, '1.234.567', 1, 2), '1.234.567', 1);
        // A backwards selection of the same '.'.
        _expectValue(_cut(f, '1.234.567', 2, 1), '1.234.567', 1);
        _expectValue(_cut(f, '12.345.678', 6, 7), '12.345.678', 6);
      });

      test('$name: a selection spanning a separator removes its digits', () {
        // '.234.' -> 1567.
        _expectValue(_cut(f, '1.234.567', 1, 6), '1.567', 1);
        // '1.2' -> 34567.
        _expectValue(_cut(f, '1.234.567', 0, 3), '34.567', 0);
        // '4.5' -> 123.67 -> 12.367, cursor after the '3'.
        _expectValue(_cut(f, '1.234.567', 4, 7), '12.367', 4);
      });

      test('$name: a selection leaving only zeros keeps one zero', () {
        _expectValue(_cut(f, '1.000', 0, 2), '0', 0);
      });
    }
  });

  group('forward Delete with a sign (SignedRupiahFormatter)', () {
    test('-1|.500 gives -100 with the cursor after the 1', () {
      _expectValue(_delete(_signed, '-1.500', 2), '-100', 2);
    });

    test('-1|.234.567 and -12.345|.678 delete the next digit', () {
      _expectValue(_delete(_signed, '-1.234.567', 2), '-134.567', 2);
      _expectValue(_delete(_signed, '-12.345.678', 7), '-1.234.578', 8);
    });

    test('Delete of the minus sign drops only the sign', () {
      _expectValue(_delete(_signed, '-1.500', 0), '1.500', 0);
    });

    test('Delete on a lone minus empties the field', () {
      _expectValue(_delete(_signed, '-', 0), '', 0);
    });

    test('Delete at the end of a negative amount changes nothing', () {
      final r = _signed.formatEditUpdate(_at('-1.500', 6), _at('-1.500', 6));
      _expectValue(r, '-1.500', 6);
    });

    test('a selection of "-1." removes the sign and the digit', () {
      _expectValue(_cut(_signed, '-1.500', 0, 3), '500', 0);
    });

    test('the unsigned formatter never keeps a typed minus', () {
      final r = _unsigned.formatEditUpdate(_at('1.500', 0), _at('-1.500', 1));
      _expectValue(r, '1.500', 0);
    });
  });

  group('forward Delete through a real TextField', () {
    Future<TextEditingController> pumpField(
      WidgetTester tester,
      TextInputFormatter formatter,
      String typed,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(
              controller: controller,
              autofocus: true,
              inputFormatters: [formatter],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      return controller;
    }

    Future<void> press(
      WidgetTester tester,
      TextEditingController controller,
      int cursor,
      LogicalKeyboardKey key,
    ) async {
      controller.selection = TextSelection.collapsed(offset: cursor);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets('Delete key at 1|.500 gives 100, cursor after the 1',
        (tester) async {
      final c = await pumpField(tester, _unsigned, '1500');
      expect(c.text, '1.500');
      await press(tester, c, 1, LogicalKeyboardKey.delete);
      expect(c.text, '100');
      expect(c.selection, const TextSelection.collapsed(offset: 1));
    });

    testWidgets('Delete key at the second separator of 12.345.678',
        (tester) async {
      final c = await pumpField(tester, _unsigned, '12345678');
      expect(c.text, '12.345.678');
      await press(tester, c, 6, LogicalKeyboardKey.delete);
      expect(c.text, '1.234.578');
      expect(c.selection, const TextSelection.collapsed(offset: 7));
    });

    testWidgets('Delete key at the end leaves the amount', (tester) async {
      final c = await pumpField(tester, _unsigned, '1500');
      await press(tester, c, 5, LogicalKeyboardKey.delete);
      expect(c.text, '1.500');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('Delete key on an empty field', (tester) async {
      final c = await pumpField(tester, _unsigned, '');
      await press(tester, c, 0, LogicalKeyboardKey.delete);
      expect(c.text, '');
    });

    testWidgets('Delete key on a negative amount', (tester) async {
      final c = await pumpField(tester, _signed, '-1234567');
      expect(c.text, '-1.234.567');
      await press(tester, c, 2, LogicalKeyboardKey.delete);
      expect(c.text, '-134.567');
      expect(c.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('Backspace key after a separator still deletes before it',
        (tester) async {
      final c = await pumpField(tester, _unsigned, '1500');
      await press(tester, c, 2, LogicalKeyboardKey.backspace);
      expect(c.text, '500');
      expect(c.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('Delete key on a selection of just the separator regroups',
        (tester) async {
      final c = await pumpField(tester, _unsigned, '1234567');
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(c.text, '1.234.567');
      expect(c.selection, const TextSelection.collapsed(offset: 1));
    });
  });
}
