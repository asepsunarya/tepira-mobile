import '../../../core/wib.dart';
import 'expense.dart';

/// The expenses of one WIB calendar day, in list order.
class ExpenseDay {
  const ExpenseDay({required this.day, required this.expenses});

  /// The WIB date as [wibDate] returns it (UTC midnight).
  final DateTime day;
  final List<Expense> expenses;
}

/// Splits [expenses] into WIB days, keeping their order. The server sends
/// them newest first, so the days come out newest first too. The device
/// time zone plays no part: 23:59 and 00:00 WIB land on different days on
/// every phone.
List<ExpenseDay> groupByWibDay(List<Expense> expenses) {
  final days = <ExpenseDay>[];
  for (final expense in expenses) {
    final day = wibDate(expense.date);
    if (days.isEmpty || days.last.day != day) {
      days.add(ExpenseDay(day: day, expenses: [expense]));
    } else {
      days.last.expenses.add(expense);
    }
  }
  return days;
}
