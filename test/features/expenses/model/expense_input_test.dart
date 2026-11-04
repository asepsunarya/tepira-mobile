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

/// [e] with [category] and [note] replaced.
Expense _copy(Expense e, {String? category, String? note}) => Expense(
      id: e.id,
      amount: e.amount,
      category: category ?? e.category,
      note: note ?? e.note,
      source: e.source,
      date: e.date,
      createdAt: e.createdAt,
      walletId: e.walletId,
      walletName: e.walletName,
      placeName: e.placeName,
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

    test('a stored note with surrounding spaces is not a change', () {
      final stored = _copy(_stored, note: '  nasi padang ');

      expect(ExpensePatch.between(stored, _edit()).isEmpty, isTrue);
      expect(
        ExpensePatch.between(stored, _edit(note: '  nasi padang ')).isEmpty,
        isTrue,
      );
      expect(
        ExpensePatch.between(stored, _edit(note: 'bakso')).toJson(),
        {'note': 'bakso'},
      );
    });

    test('a blank stored note equals a cleared one', () {
      final stored = _copy(_stored, note: '   ');

      expect(ExpensePatch.between(stored, _edit(note: '')).isEmpty, isTrue);
    });

    test('a stored web key equals its label', () {
      final stored = _copy(_stored, category: 'transport');

      expect(
        ExpensePatch.between(stored, _edit(category: 'Transport')).isEmpty,
        isTrue,
      );
      expect(
        ExpensePatch.between(stored, _edit(category: 'Makan harian')).toJson(),
        {'category': 'Makan harian'},
      );
      expect(
        ExpensePatch.between(stored, _edit(category: null)).toJson(),
        {'category': null},
      );
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

  group('ExpensePatch.between, legacy edge cases', () {
    Expense stored({String? category, String? note}) => Expense(
          id: _stored.id,
          amount: _stored.amount,
          category: category,
          note: note,
          source: _stored.source,
          date: _stored.date,
          createdAt: _stored.createdAt,
          walletId: _stored.walletId,
          walletName: _stored.walletName,
          placeName: _stored.placeName,
        );

    test('legacy key + changed amount sends only the amount', () {
      final row = stored(category: 'transport', note: 'nasi padang');

      expect(
        ExpensePatch.between(row, _edit(amount: 15000, category: 'Transport'))
            .toJson(),
        {'amount': 15000},
      );
    });

    test('an unknown stored category is unchanged when kept', () {
      final row = stored(category: 'Lain-lain', note: 'nasi padang');

      expect(
        ExpensePatch.between(row, _edit(category: 'Lain-lain')).isEmpty,
        isTrue,
      );
      expect(
        ExpensePatch.between(row, _edit(category: 'Transport')).toJson(),
        {'category': 'Transport'},
      );
      expect(
        ExpensePatch.between(row, _edit(category: null)).toJson(),
        {'category': null},
      );
    });

    test('a null stored category vs a picked one', () {
      final row = stored(category: null, note: 'nasi padang');

      expect(ExpensePatch.between(row, _edit(category: null)).isEmpty, isTrue);
      expect(
        ExpensePatch.between(row, _edit(category: 'Transport')).toJson(),
        {'category': 'Transport'},
      );
    });

    test('null stored note: null, empty and whitespace edits are no change',
        () {
      final row = stored(category: 'Makan harian', note: null);

      for (final note in [null, '', '   ', '\t\n']) {
        expect(
          ExpensePatch.between(row, _edit(note: note)).isEmpty,
          isTrue,
          reason: 'note ${note?.codeUnits}',
        );
      }
      expect(
        ExpensePatch.between(row, _edit(note: '  soto ')).toJson(),
        {'note': 'soto'},
      );
    });

    test('whitespace-only stored note vs a null edit is no change', () {
      final row = stored(category: 'Makan harian', note: ' \t ');

      expect(ExpensePatch.between(row, _edit(note: null)).isEmpty, isTrue);
    });

    test('a stored note with inner spacing changed is a change', () {
      final row = stored(category: 'Makan harian', note: ' nasi  padang ');

      expect(
        ExpensePatch.between(row, _edit(note: 'nasi padang')).toJson(),
        {'note': 'nasi padang'},
      );
    });
  });
}
