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
}
