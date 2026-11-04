import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

/// Stored at 2026-10-31T17:30Z = 1 Nov 00:30 WIB.
final _stored = Expense(
  id: 499,
  amount: 25000,
  category: 'Makan harian',
  note: 'nasi padang',
  source: 'gaji',
  date: DateTime.utc(2026, 10, 31, 17, 30),
  createdAt: DateTime.utc(2026, 10, 31, 17, 30),
  walletId: 3,
  walletName: 'BCA',
  placeName: null,
);

ExpenseEdit _edit({
  int amount = 25000,
  int walletId = 3,
  String? category = 'Makan harian',
  String? note = 'nasi padang',
  ExpenseSource source = ExpenseSource.gaji,
  String day = '2026-11-01',
}) =>
    ExpenseEdit(
      amount: amount,
      walletId: walletId,
      category: category,
      note: note,
      source: source,
      day: day,
    );

void main() {
  group('NewExpense.toJson', () {
    test('today: no date key at all', () {
      const expense = NewExpense(amount: 25000, walletId: 3);

      expect(expense.toJson(), {
        'amount': 25000,
        'walletId': 3,
        'category': null,
        'note': null,
        'source': 'gaji',
      });
    });

    test('trims the note', () {
      const expense = NewExpense(amount: 1, walletId: 3, note: '  bakso ');

      expect(expense.toJson()['note'], 'bakso');
    });
  });

  group('ExpensePatch.between', () {
    test('nothing changed -> empty', () {
      expect(ExpensePatch.between(_stored, _edit()).isEmpty, isTrue);
    });

    test('a cleared category and a blank note are sent as null', () {
      final patch = ExpensePatch.between(
        _stored,
        _edit(category: null, note: '   '),
      );

      expect(patch.toJson(), {'category': null, 'note': null});
    });

    test('only the changed fields', () {
      final patch = ExpensePatch.between(
        _stored,
        _edit(amount: 30000, source: ExpenseSource.bonus),
      );

      expect(patch.toJson(), {'amount': 30000, 'source': 'bonus'});
    });

    test('the WIB day is compared, not the UTC date', () {
      // Stored on 1 Nov WIB although its UTC date is 31 Oct.
      expect(
        ExpensePatch.between(_stored, _edit(day: '2026-11-01')).isEmpty,
        isTrue,
      );
      expect(
        ExpensePatch.between(_stored, _edit(day: '2026-10-31')).toJson(),
        {'date': '2026-10-31'},
      );
    });

    test('an orphan row gets the picked wallet', () {
      final orphan = Expense(
        id: 497,
        amount: 15000,
        category: null,
        note: null,
        source: 'gaji',
        date: DateTime.utc(2026, 10, 31, 23, 40),
        createdAt: DateTime.utc(2026, 10, 31, 23, 40),
        walletId: null,
        walletName: null,
        placeName: null,
      );

      final patch = ExpensePatch.between(
        orphan,
        _edit(amount: 15000, walletId: 3, category: null, note: null),
      );

      expect(patch.toJson(), {'walletId': 3});
    });
  });
}
