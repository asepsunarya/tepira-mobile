import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';
import 'package:tepira_mobile/features/today/today_providers.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/wallet_providers.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

const _bakso = NewExpense(
  amount: 18000,
  walletId: 3,
  category: 'Makan harian',
  note: 'bakso',
);

class _Setup {
  _Setup(this.expenses, {bool watchWallets = true, bool watchToday = true}) {
    container = ProviderContainer(
      overrides: [
        expensesRepositoryProvider.overrideWithValue(expenses),
        walletsRepositoryProvider.overrideWithValue(wallets),
        todayRepositoryProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);
    if (watchWallets) container.listen(walletsProvider, (_, __) {});
    if (watchToday) container.listen(todayProvider, (_, __) {});
  }

  final FakeExpensesRepository expenses;
  final wallets = FakeWalletsRepository([fixtureWalletList()]);
  final today = FakeTodayRepository.budget();
  late final ProviderContainer container;

  ExpenseWriter get writer => container.read(expenseWriterProvider);

  Future<WalletList> loadedWallets() => container.read(walletsProvider.future);

  Wallet wallet(int id) => container
      .read(walletsProvider)
      .requireValue
      .wallets
      .firstWhere((w) => w.id == id);
}

void main() {
  test('create puts the answer wallet and today in place, no reload', () async {
    final s = _Setup(
      FakeExpensesRepository(createResults: [fixtureExpenseCreated()]),
    );
    final before = await s.loadedWallets();
    await s.container.read(todayProvider.future);

    await s.writer.create(_bakso);

    final after = s.container.read(walletsProvider).requireValue;
    expect(s.wallet(3).balance, 8232000);
    expect(s.wallet(3).spentThisMonth, 43000);
    // Every other wallet is untouched, in the same order.
    expect([for (final w in after.wallets) w.id], [3, 7, 9, 11]);
    for (final i in [1, 2, 3]) {
      expect(after.wallets[i], before.wallets[i]);
    }
    expect(after.totals.free, 7052000);
    expect(after.totals.reserved, 3000000);
    expect(after.totals.debts, before.totals.debts);
    expect(after.totals.assets, before.totals.assets - 18000);
    expect(after.totals.netWorth, before.totals.netWorth - 18000);
    final today = s.container.read(todayProvider).requireValue;
    expect(today.safeToday.remaining, 82000);
    expect(s.wallets.listCalls, 1);
    expect(s.today.calls, 1);
  });

  test('a deduped answer is a success and does not count twice', () async {
    final s = _Setup(
      FakeExpensesRepository(
        createResults: [fixtureExpenseCreated(), fixtureExpenseDeduped()],
      ),
    );
    await s.loadedWallets();

    final first = await s.writer.create(_bakso);
    final second = await s.writer.create(_bakso);

    expect(second.deduped, isTrue);
    expect(second.expense.id, first.expense.id);
    // The wallet shows the server's balance, moved once.
    expect(s.wallet(3).balance, 8232000);
    expect(s.container.read(walletsProvider).requireValue.totals.free, 7052000);
    expect(
      s.container.read(todayProvider).requireValue.spentToday,
      first.today.spentToday,
    );
  });

  test('update replaces both wallets and moves the debts total', () async {
    final updated =
        expenseUpdatedFromJson(readFixture('mobile_expense_updated'));
    final s = _Setup(FakeExpensesRepository(updateResults: [updated]));
    final before = await s.loadedWallets();

    await s.writer.update(
      499,
      ExpensePatch.between(
        fixtureExpenseCreated().expense,
        const ExpenseEdit(
          amount: 18000,
          walletId: 9,
          category: 'Makan harian',
          note: 'bakso',
          source: ExpenseSource.gaji,
          day: '2026-11-01',
        ),
      ),
    );

    final after = s.container.read(walletsProvider).requireValue;
    expect(s.wallet(3).balance, 8275000);
    expect(s.wallet(9).displayBalance, -1230000);
    expect(after.totals.debts, 1230000);
    expect(after.totals.free, 7065000);
    expect(
      after.totals.assets,
      after.totals.free + after.totals.reserved + after.totals.debts,
    );
    expect(after.totals.netWorth, after.totals.assets - after.totals.debts);
    expect(before.totals.debts, 1200000);
  });

  test('delete of an orphan row only updates today', () async {
    final deleted =
        expenseDeletedFromJson(readFixture('mobile_expense_deleted_orphan'));
    final s = _Setup(FakeExpensesRepository(deleteResults: [deleted]));
    final before = await s.loadedWallets();

    await s.writer.delete(497);

    final after = s.container.read(walletsProvider).requireValue;
    expect(after.wallets, before.wallets);
    expect(s.container.read(todayProvider).requireValue.spentToday, 10000);
  });

  test('providers nobody watches are not loaded by a write', () async {
    final s = _Setup(
      FakeExpensesRepository(createResults: [fixtureExpenseCreated()]),
      watchWallets: false,
      watchToday: false,
    );

    await s.writer.create(_bakso);

    expect(s.wallets.listCalls, 0);
    expect(s.today.calls, 0);
  });

  test('a wallet the list does not hold reloads the list', () async {
    final s = _Setup(
      FakeExpensesRepository(createResults: [fixtureExpenseCreated()]),
    );
    s.wallets.listResults
      ..clear()
      ..add(testWalletList([testWallet(id: 7)]));
    await s.loadedWallets();

    await s.writer.create(_bakso);
    await s.loadedWallets();

    expect(s.wallets.listCalls, 2);
  });

  group('retry', () {
    test('500 with Retry-After is sent once more', () async {
      final s = _Setup(
        FakeExpensesRepository(
          createResults: [
            const ServerException(
              statusCode: 500,
              code: 'server_error',
              retryAfter: Duration(milliseconds: 1),
            ),
            fixtureExpenseCreated(),
          ],
        ),
      );

      final created = await s.writer.create(_bakso);

      expect(s.expenses.created, hasLength(2));
      expect(s.expenses.created.last.toJson(), _bakso.toJson());
      expect(created.expense.id, 500);
    });

    test('only once: a second retryable 500 is thrown', () async {
      final s = _Setup(
        FakeExpensesRepository(
          createResults: [
            const ServerException(
              statusCode: 500,
              code: 'server_error',
              retryAfter: Duration(milliseconds: 1),
            ),
          ],
        ),
      );

      await expectLater(
        s.writer.create(_bakso),
        throwsA(isA<ServerException>()),
      );
      expect(s.expenses.created, hasLength(2));
    });

    for (final error in <AppException>[
      const ServerException(),
      const RateLimitedException(retryAfter: Duration(seconds: 2)),
      const NetworkException(),
      const BadRequestException(code: 'wallet_not_found'),
    ]) {
      test('${error.runtimeType} without the retry signal is not resent',
          () async {
        final s = _Setup(FakeExpensesRepository(createResults: [error]));

        await expectLater(s.writer.create(_bakso), throwsA(same(error)));
        expect(s.expenses.created, hasLength(1));
      });
    }

    for (final error in <ServerException>[
      const ServerException(
        statusCode: 500,
        code: 'server_error',
        retryAfter: Duration(seconds: 300),
      ),
      const ServerException(
        statusCode: 500,
        code: 'server_error',
        retryAfter: Duration(seconds: 6),
      ),
      const ServerException(
        statusCode: 500,
        code: 'internal',
        retryAfter: Duration(milliseconds: 1),
      ),
    ]) {
      test(
          '500 ${error.code} with Retry-After ${error.retryAfter!.inSeconds}s '
          'is not resent', () async {
        final s = _Setup(FakeExpensesRepository(createResults: [error]));

        await expectLater(s.writer.create(_bakso), throwsA(same(error)));
        expect(s.expenses.created, hasLength(1));
      });
    }
  });
}
