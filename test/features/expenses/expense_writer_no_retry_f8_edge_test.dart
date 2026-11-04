// Independent edge tests for Fase 8: which write failures the expense
// writer resends. Only a rolled-back 500 `server_error` with a short
// Retry-After is safe; everything else must reach the caller unsent.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

final _november = WibMonth(2026, 11);

const _bakso = NewExpense(amount: 18000, walletId: 3, note: 'bakso');

ExpensePatch _patch() => ExpensePatch.between(
      fixtureExpenseList().expenses.first,
      const ExpenseEdit(
        amount: 30000,
        walletId: 3,
        category: 'Makan harian',
        note: 'nasi padang',
        source: ExpenseSource.gaji,
        day: '2026-11-01',
      ),
    );

ProviderContainer _container(FakeExpensesRepository expenses) {
  final container = ProviderContainer(
    overrides: [
      expensesRepositoryProvider.overrideWithValue(expenses),
      walletsRepositoryProvider
          .overrideWithValue(FakeWalletsRepository([fixtureWalletList()])),
      todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
    ],
  );
  addTearDown(container.dispose);
  container.listen(historyProvider(_november), (_, __) {});
  return container;
}

/// Failures that must never be resent, with a zero Retry-After so a
/// resend would be immediate if the writer allowed it.
final Map<String, AppException> _notResent = {
  '502': const ServerException(statusCode: 502, retryAfter: Duration.zero),
  '503': const ServerException(statusCode: 503, retryAfter: Duration.zero),
  '504': const ServerException(statusCode: 504, retryAfter: Duration.zero),
  '503 server_error': const ServerException(
    statusCode: 503,
    code: 'server_error',
    retryAfter: Duration.zero,
  ),
  '429': const RateLimitedException(retryAfter: Duration.zero),
  '500 without Retry-After':
      const ServerException(statusCode: 500, code: 'server_error'),
  '500 with Retry-After over 5 s': const ServerException(
    statusCode: 500,
    code: 'server_error',
    retryAfter: Duration(seconds: 6),
  ),
  '500 with another code': const ServerException(
    statusCode: 500,
    code: 'internal',
    retryAfter: Duration.zero,
  ),
  'network': const NetworkException(),
};

void main() {
  for (final MapEntry(key: name, value: error) in _notResent.entries) {
    group('$name is not resent', () {
      test('create', () async {
        final expenses = FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          createResults: [error, fixtureExpenseCreated()],
        );
        final c = _container(expenses);
        await c.read(historyProvider(_november).future);

        await expectLater(
          c.read(expenseWriterProvider).create(_bakso),
          throwsA(same(error)),
        );
        expect(expenses.created, hasLength(1));
      });

      test('update', () async {
        final expenses = FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          updateResults: [
            error,
            expenseUpdatedFromJson(readFixture('mobile_expense_updated')),
          ],
        );
        final c = _container(expenses);
        await c.read(historyProvider(_november).future);

        await expectLater(
          c.read(expenseWriterProvider).update(
                499,
                _patch(),
                listedIn: _november,
              ),
          throwsA(same(error)),
        );
        expect(expenses.updated, hasLength(1));
        expect(c.read(historyProvider(_november)).requireValue.total, 50000);
      });

      test('delete', () async {
        final expenses = FakeExpensesRepository(
          listResults: [fixtureExpenseList()],
          deleteResults: [
            error,
            expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
          ],
        );
        final c = _container(expenses);
        await c.read(historyProvider(_november).future);

        await expectLater(
          c.read(expenseWriterProvider).delete(499, listedIn: _november),
          throwsA(same(error)),
        );
        expect(expenses.deleted, [499]);
        expect(c.read(historyProvider(_november)).requireValue.count, 3);
      });
    });
  }

  test('a rolled-back 500 is resent at most once', () async {
    const aborted = ServerException(
      statusCode: 500,
      code: 'server_error',
      retryAfter: Duration.zero,
    );
    final expenses = FakeExpensesRepository(
      listResults: [fixtureExpenseList()],
      deleteResults: [
        aborted,
        aborted,
        expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
      ],
    );
    final c = _container(expenses);
    await c.read(historyProvider(_november).future);

    await expectLater(
      c.read(expenseWriterProvider).delete(499, listedIn: _november),
      throwsA(isA<ServerException>()),
    );
    expect(expenses.deleted, [499, 499]);
  });

  test('retryWaitOf accepts exactly 5 s, not more', () {
    expect(
      retryWaitOf(
        const ServerException(
          statusCode: 500,
          code: 'server_error',
          retryAfter: Duration(seconds: 5),
        ),
      ),
      const Duration(seconds: 5),
    );
    expect(
      retryWaitOf(
        const ServerException(
          statusCode: 500,
          code: 'server_error',
          retryAfter: Duration(seconds: 5, milliseconds: 1),
        ),
      ),
      isNull,
    );
  });
}
