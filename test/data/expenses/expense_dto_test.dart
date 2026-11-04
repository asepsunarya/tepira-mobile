import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';

import '../../helpers/fake_today_repository.dart';

void main() {
  group('list (contract §7)', () {
    final list = expenseListFromJson(readFixture('mobile_expenses'));

    test('reads the month, sums and rows newest first', () {
      expect(list.asOf, DateTime.utc(2026, 11, 1, 7));
      expect(list.period, WibMonth(2026, 11));
      expect(list.total, 50000);
      expect(list.count, 3);
      expect(list.more, isFalse);
      expect([for (final e in list.expenses) e.id], [499, 498, 497]);

      final first = list.expenses.first;
      expect(first.amount, 25000);
      expect(first.category, 'Makan harian');
      expect(first.note, 'nasi padang');
      expect(first.source, 'gaji');
      expect(first.date, DateTime.utc(2026, 11, 1, 5, 30));
      expect(first.createdAt, DateTime.utc(2026, 11, 1, 5, 30, 2));
      expect(first.walletId, 3);
      expect(first.walletName, 'BCA');
      expect(first.placeName, isNull);
    });

    test('an orphan row has null wallet fields', () {
      final orphan = list.expenses.last;

      expect(orphan.walletId, isNull);
      expect(orphan.walletName, isNull);
      expect(orphan.category, 'Transport');
    });

    test('a row dated 2026-10-31T23:40Z falls in the November WIB month', () {
      final orphan = list.expenses.last;

      expect(orphan.date, DateTime.utc(2026, 10, 31, 23, 40));
      expect(WibMonth.of(orphan.date), list.period);
      expect(wibDayKey(orphan.date), '2026-11-01');
    });
  });

  test('created (201) and deduped (200) parse to the same expense', () {
    final created =
        expenseCreatedFromJson(readFixture('mobile_expense_created'));
    final deduped =
        expenseCreatedFromJson(readFixture('mobile_expense_deduped'));

    expect(created.deduped, isFalse);
    expect(deduped.deduped, isTrue);
    expect(deduped.expense.id, created.expense.id);
    expect(created.expense.amount, 18000);
    expect(created.wallet!.id, 3);
    expect(created.wallet!.balance, 8232000);
    expect(created.wallets, [created.wallet]);
    expect(created.today.safeToday.remaining, 82000);
    expect(created.today.walletsFree, 7052000);
  });

  test('created with a vanished wallet -> wallet null, no wallets', () {
    final json = readFixture('mobile_expense_created')..['wallet'] = null;

    final created = expenseCreatedFromJson(json);

    expect(created.wallet, isNull);
    expect(created.wallets, isEmpty);
  });

  test('updated: both wallets when the wallet changed, sorted by id', () {
    final updated =
        expenseUpdatedFromJson(readFixture('mobile_expense_updated'));

    expect(updated.expense.id, 499);
    expect(updated.expense.walletId, 9);
    expect(updated.expense.note, isNull);
    expect([for (final w in updated.wallets) w.id], [3, 9]);
    expect(updated.wallets.last.displayBalance, -1230000);
    expect(updated.today.spentMonth, 55000);
  });

  test('deleted: the restored wallet, or null for an orphan row', () {
    final deleted =
        expenseDeletedFromJson(readFixture('mobile_expense_deleted'));
    final orphan =
        expenseDeletedFromJson(readFixture('mobile_expense_deleted_orphan'));

    expect(deleted.id, 499);
    expect(deleted.amount, 25000);
    expect(deleted.wallet!.balance, 8275000);
    expect(orphan.id, 497);
    expect(orphan.wallet, isNull);
    expect(orphan.wallets, isEmpty);
    expect(orphan.today.spentToday, 10000);
  });

  group('rejects', () {
    test('a write answer without today', () {
      final json = readFixture('mobile_expense_created')..remove('today');

      expect(() => expenseCreatedFromJson(json), throwsFormatException);
    });

    test('an expense without a nullable key', () {
      final json = readFixture('mobile_expenses');
      final rows = json['expenses']! as List<Object?>;
      (rows.first! as Map<String, Object?>).remove('placeName');

      expect(() => expenseListFromJson(json), throwsFormatException);
    });

    test('a local timestamp as date', () {
      final json = readFixture('mobile_expenses');
      final rows = json['expenses']! as List<Object?>;
      (rows.first! as Map<String, Object?>)['date'] = '2026-11-01 12:30:00';

      expect(() => expenseListFromJson(json), throwsFormatException);
    });
  });
}
