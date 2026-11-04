import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

final _november = WibMonth(2026, 11);
final _october = WibMonth(2026, 10);

const _bakso = NewExpense(amount: 18000, walletId: 3, note: 'bakso');

ExpenseUpdated _updated() =>
    expenseUpdatedFromJson(readFixture('mobile_expense_updated'));

ExpenseDeleted _deleted() =>
    expenseDeletedFromJson(readFixture('mobile_expense_deleted'));

/// The update fixture with its expense moved to [date].
ExpenseUpdated _updatedOn(DateTime date) {
  final base = _updated();
  final e = base.expense;
  return ExpenseUpdated(
    expense: Expense(
      id: e.id,
      amount: e.amount,
      category: e.category,
      note: e.note,
      source: e.source,
      date: date,
      createdAt: e.createdAt,
      walletId: e.walletId,
      walletName: e.walletName,
      placeName: e.placeName,
    ),
    wallets: base.wallets,
    today: base.today,
  );
}

/// A 500 the server sends when it rolled the transaction back.
const _aborted = ServerException(
  statusCode: 500,
  code: 'server_error',
  retryAfter: Duration.zero,
);

class _Setup {
  _Setup(this.expenses, {List<WibMonth>? watch}) {
    container = ProviderContainer(
      overrides: [
        expensesRepositoryProvider.overrideWithValue(expenses),
        walletsRepositoryProvider
            .overrideWithValue(FakeWalletsRepository([fixtureWalletList()])),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
      ],
    );
    addTearDown(container.dispose);
    for (final month in watch ?? [_november]) {
      container.listen(historyProvider(month), (_, __) {});
    }
  }

  final FakeExpensesRepository expenses;
  late final ProviderContainer container;

  ExpenseWriter get writer => container.read(expenseWriterProvider);

  Future<ExpenseList> loaded(WibMonth month) =>
      container.read(historyProvider(month).future);

  ExpenseList month(WibMonth month) =>
      container.read(historyProvider(month)).requireValue;
}

List<int> _ids(ExpenseList list) => [for (final e in list.expenses) e.id];

void main() {
  test('update replaces the row; total moves by its change, no reload',
      () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updated()],
      ),
    );
    await s.loaded(_november);

    await s.writer.update(
      499,
      ExpensePatch.between(
        fixtureExpenseList().expenses.first,
        const ExpenseEdit(
          amount: 30000,
          walletId: 9,
          category: 'Makan harian',
          note: null,
          source: ExpenseSource.gaji,
          day: '2026-11-01',
        ),
      ),
      listedIn: _november,
    );

    final after = s.month(_november);
    expect(s.expenses.listed, [_november]);
    expect(_ids(after), [499, 498, 497]);
    expect(after.expenses.first.amount, 30000);
    expect(after.expenses.first.walletName, 'Kartu Kredit');
    expect(after.total, 55000);
    expect(after.count, 3);
  });

  test('an update that moves the day to another month moves the row', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [
          fixtureExpenseList(),
          testExpenseList(_october, [
            testExpense(id: 300, amount: 5000, date: DateTime.utc(2026, 10, 2)),
          ]),
        ],
        updateResults: [_updatedOn(DateTime.utc(2026, 10, 28, 5))],
      ),
      watch: [_november, _october],
    );
    await s.loaded(_november);
    await s.loaded(_october);

    await s.writer.update(
      499,
      ExpensePatch.between(
        fixtureExpenseList().expenses.first,
        const ExpenseEdit(
          amount: 30000,
          walletId: 9,
          category: 'Makan harian',
          note: null,
          source: ExpenseSource.gaji,
          day: '2026-10-28',
        ),
      ),
      listedIn: _november,
    );

    final november = s.month(_november);
    expect(_ids(november), [498, 497]);
    expect(november.total, 25000);
    expect(november.count, 2);
    final october = s.month(_october);
    expect(_ids(october), [499, 300]);
    expect(october.total, 35000);
    expect(october.count, 2);
  });

  test('update keeps the server order: date desc, then id desc', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        // 499 moves to 06:00 WIB, before 497 (06:40), so it goes last.
        updateResults: [_updatedOn(DateTime.utc(2026, 10, 31, 23))],
      ),
    );
    await s.loaded(_november);

    await s.writer.update(
      499,
      ExpensePatch.between(
        fixtureExpenseList().expenses.first,
        const ExpenseEdit(
          amount: 30000,
          walletId: 9,
          category: 'Makan harian',
          note: null,
          source: ExpenseSource.gaji,
          day: '2026-11-01',
        ),
      ),
      listedIn: _november,
    );

    expect(_ids(s.month(_november)), [498, 497, 499]);
  });

  test('delete drops the row and its amount from the month', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [_deleted()],
      ),
    );
    await s.loaded(_november);

    await s.writer.delete(499, listedIn: _november);

    final after = s.month(_november);
    expect(_ids(after), [498, 497]);
    expect(after.total, 25000);
    expect(after.count, 2);
    expect(s.expenses.listed, [_november]);
  });

  test('create adds the new row to its loaded month, newest first', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        createResults: [fixtureExpenseCreated()],
      ),
    );
    await s.loaded(_november);

    await s.writer.create(_bakso);

    final after = s.month(_november);
    expect(_ids(after), [500, 499, 498, 497]);
    expect(after.total, 68000);
    expect(after.count, 4);
  });

  test('a dedupe answer for a listed row does not count it twice', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [
          testExpenseList(_november, [
            fixtureExpenseCreated().expense,
            ...fixtureExpenseList().expenses,
          ]),
        ],
        createResults: [fixtureExpenseDeduped()],
      ),
    );
    await s.loaded(_november);

    await s.writer.create(_bakso);

    final after = s.month(_november);
    expect(_ids(after), [500, 499, 498, 497]);
    expect(after.total, 68000);
    expect(after.count, 4);
  });

  test('a dedupe answer for a row not listed reloads the month', () async {
    // The row was written after the month loaded (maybe through another
    // channel), so the loaded total may already count it.
    // The server's month also counts a row past those sent, so a local
    // add (68.000, 4) would differ from the reload.
    final reloaded = testExpenseList(
      _november,
      [fixtureExpenseCreated().expense, ...fixtureExpenseList().expenses],
      total: 90000,
      count: 5,
    );
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList(), reloaded],
        createResults: [fixtureExpenseDeduped()],
      ),
    );
    await s.loaded(_november);

    await s.writer.create(_bakso);
    final after = await s.loaded(_november);

    expect(s.expenses.listed, [_november, _november]);
    expect(_ids(after), [500, 499, 498, 497]);
    expect(after.total, 90000);
    expect(after.count, 5);
  });

  test('a month nobody shows is not loaded by a write', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updated()],
        deleteResults: [_deleted()],
        createResults: [fixtureExpenseCreated()],
      ),
      watch: const [],
    );

    await s.writer.create(_bakso);
    await s.writer.update(
      499,
      ExpensePatch.between(
        fixtureExpenseList().expenses.first,
        const ExpenseEdit(
          amount: 30000,
          walletId: 3,
          category: 'Makan harian',
          note: 'nasi padang',
          source: ExpenseSource.gaji,
          day: '2026-11-01',
        ),
      ),
      listedIn: _november,
    );
    await s.writer.delete(499, listedIn: _november);

    expect(s.expenses.listed, isEmpty);
  });

  test('a 404 on update reloads the listed month and is rethrown', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [const NotFoundException()],
      ),
    );
    await s.loaded(_november);

    await expectLater(
      s.writer.update(
        499,
        ExpensePatch.between(
          fixtureExpenseList().expenses.first,
          const ExpenseEdit(
            amount: 30000,
            walletId: 3,
            category: 'Makan harian',
            note: 'nasi padang',
            source: ExpenseSource.gaji,
            day: '2026-11-01',
          ),
        ),
        listedIn: _november,
      ),
      throwsA(isA<NotFoundException>()),
    );
    await s.loaded(_november);

    expect(s.expenses.listed, [_november, _november]);
  });

  test('a 404 on delete reloads the listed month and is rethrown', () async {
    final s = _Setup(
      FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [const NotFoundException()],
      ),
    );
    await s.loaded(_november);

    await expectLater(
      s.writer.delete(499, listedIn: _november),
      throwsA(isA<NotFoundException>()),
    );
    await s.loaded(_november);

    expect(s.expenses.listed, [_november, _november]);
  });

  group('a rolled-back 500 with a short Retry-After is resent once', () {
    test('update', () async {
      final s = _Setup(
        FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          updateResults: [_aborted, _updated()],
        ),
      );
      await s.loaded(_november);
      final patch = ExpensePatch.between(
        fixtureExpenseList().expenses.first,
        const ExpenseEdit(
          amount: 30000,
          walletId: 9,
          category: 'Makan harian',
          note: null,
          source: ExpenseSource.gaji,
          day: '2026-11-01',
        ),
      );

      await s.writer.update(499, patch, listedIn: _november);

      expect([
        for (final (id, body) in s.expenses.updated) [id, body],
      ], [
        [499, patch.toJson()],
        [499, patch.toJson()],
      ]);
      expect(s.month(_november).total, 55000);
    });

    test('delete', () async {
      final s = _Setup(
        FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          deleteResults: [_aborted, _deleted()],
        ),
      );
      await s.loaded(_november);

      await s.writer.delete(499, listedIn: _november);

      expect(s.expenses.deleted, [499, 499]);
      expect(s.month(_november).total, 25000);
    });

    test('a gateway error is not resent: the outcome is unknown', () async {
      final s = _Setup(
        FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          deleteResults: [
            const ServerException(statusCode: 502, retryAfter: Duration.zero),
            _deleted(),
          ],
        ),
      );
      await s.loaded(_november);

      await expectLater(
        s.writer.delete(499, listedIn: _november),
        throwsA(isA<ServerException>()),
      );

      expect(s.expenses.deleted, [499]);
      expect(s.month(_november).total, 50000);
    });
  });
}
