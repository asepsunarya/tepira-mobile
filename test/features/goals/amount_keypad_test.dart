import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/goals/widgets/amount_keypad.dart';

void main() {
  test('digits append, and zeros do not start an amount', () {
    expect(keypadAmount(0, '0'), 0);
    expect(keypadAmount(0, '000'), 0);
    expect(keypadAmount(0, '5'), 5);
    expect(keypadAmount(5, '000'), 5000);
    expect(keypadAmount(5000, '0'), 50000);
  });

  test('backspace drops the last digit', () {
    expect(keypadAmount(20000, AmountKeypad.backspace), 2000);
    expect(keypadAmount(7, AmountKeypad.backspace), 0);
    expect(keypadAmount(0, AmountKeypad.backspace), 0);
  });

  test('presses past the maximum are ignored', () {
    expect(keypadAmount(99999999, '9'), kMaxKeypadAmount);
    expect(keypadAmount(kMaxKeypadAmount, '0'), kMaxKeypadAmount);
    expect(keypadAmount(1000000, '000'), 1000000);
  });

  test('000 near the cap lands only when it fits', () {
    expect(keypadAmount(999999, '000'), 999999000);
    expect(keypadAmount(999999000, '000'), 999999000);
    expect(keypadAmount(99999999, '000'), 99999999);
    expect(keypadAmount(999999999, '000'), kMaxKeypadAmount);
    expect(keypadAmount(100000000, '0'), 100000000);
    expect(keypadAmount(10000000, '0'), 100000000);
  });

  test('backspace from the cap reaches 0 in nine presses', () {
    var amount = kMaxKeypadAmount;
    for (var i = 0; i < 9; i++) {
      amount = keypadAmount(amount, AmountKeypad.backspace);
    }
    expect(amount, 0);
  });

  test('every key on the pad is accepted from 0 and from the cap', () {
    for (final key in AmountKeypad.keys) {
      expect(keypadAmount(0, key), inInclusiveRange(0, 9));
      expect(
        keypadAmount(kMaxKeypadAmount, key),
        key == AmountKeypad.backspace ? 99999999 : kMaxKeypadAmount,
      );
    }
  });
}
