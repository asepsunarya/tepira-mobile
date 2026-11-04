import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/features/expenses/model/expense_day.dart';

import '../../../helpers/fake_expenses_repository.dart';

void main() {
  test('splits at 00:00 WIB (17:00 UTC), not at UTC or device midnight', () {
    final days = groupByWibDay([
      testExpense(id: 4, date: DateTime.utc(2026, 11, 1, 17)),
      testExpense(id: 3, date: DateTime.utc(2026, 11, 1, 16, 59, 59)),
      testExpense(id: 2, date: DateTime.utc(2026, 11, 1)),
      testExpense(id: 1, date: DateTime.utc(2026, 10, 31, 16, 59)),
    ]);

    expect(
      [for (final d in days) d.day],
      [
        DateTime.utc(2026, 11, 2),
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 10, 31),
      ],
    );
    expect(
      [for (final d in days) d.expenses.map((e) => e.id).toList()],
      [
        [4],
        [3, 2],
        [1],
      ],
    );
  });

  test('keeps the list order inside a day', () {
    final days = groupByWibDay([
      testExpense(id: 9, date: DateTime.utc(2026, 11, 1, 5)),
      testExpense(id: 7, date: DateTime.utc(2026, 11, 1, 5)),
      testExpense(id: 8, date: DateTime.utc(2026, 11, 1, 2)),
    ]);

    expect(days.single.expenses.map((e) => e.id), [9, 7, 8]);
  });

  test('no expenses, no days', () {
    expect(groupByWibDay(const []), isEmpty);
  });
}
