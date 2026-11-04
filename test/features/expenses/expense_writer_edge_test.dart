import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';
import 'package:tepira_mobile/features/today/today_providers.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/wallet_providers.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

const _body = NewExpense(amount: 25000, walletId: 9);

class _Setup {
  _Setup(this.expenses, {List<Object>? walletLists})
      : wallets = FakeWalletsRepository(walletLists ?? [fixtureWalletList()]) {
    container = ProviderContainer(
      overrides: [
        expensesRepositoryProvider.overrideWithValue(expenses),
        walletsRepositoryProvider.overrideWithValue(wallets),
        todayRepositoryProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);
    container.listen(walletsProvider, (_, __) {});
    container.listen(todayProvider, (_, __) {});
  }

  final FakeExpensesRepository expenses;
  final FakeWalletsRepository wallets;
  final today = FakeTodayRepository.budget();
  late final ProviderContainer container;

  ExpenseWriter get writer => container.read(expenseWriterProvider);

  Future<WalletList> loaded() => container.read(walletsProvider.future);

  WalletList get list => container.read(walletsProvider).requireValue;
}

/// The fixture `today` with Uang bebas and Dana dicadangkan replaced.
TodaySummary _today({required int free, required int reserved}) {
  final base = fixtureTodayBudget();
  return TodaySummary(
    asOf: null,
    date: base.date,
    period: base.period,
    spentToday: base.spentToday,
    spentMonth: base.spentMonth,
    savedThisMonth: base.savedThisMonth,
    budget: base.budget,
    safeToday: base.safeToday,
    walletsFree: free,
    walletsReserved: reserved,
  );
}

ExpenseCreated _created(
  Wallet wallet, {
  required int free,
  required int reserved,
  bool deduped = false,
}) {
  final base = fixtureExpenseCreated();
  return ExpenseCreated(
    deduped: deduped,
    expense: base.expense,
    wallet: wallet,
    today: _today(free: free, reserved: reserved),
  );
}

/// The server's `summarizeWallets` (SPEC-v2 §2) over [wallets].
WalletTotals _serverTotals(List<Wallet> wallets) {
  var assets = 0;
  var debts = 0;
  var reserved = 0;
  for (final w in wallets) {
    if (w.isDebt) {
      debts += w.displayBalance.abs();
    } else {
      assets += w.displayBalance;
      if (w.isReserved) reserved += w.displayBalance;
    }
  }
  final netWorth = assets - debts;
  return WalletTotals(
    assets: assets,
    debts: debts,
    reserved: reserved,
    netWorth: netWorth,
    free: netWorth - reserved,
  );
}

void _expectTotals(WalletTotals actual, WalletTotals expected) {
  expect(
    [
      actual.assets,
      actual.debts,
      actual.reserved,
      actual.netWorth,
      actual.free,
    ],
    [
      expected.assets,
      expected.debts,
      expected.reserved,
      expected.netWorth,
      expected.free,
    ],
    reason: '[assets, debts, reserved, netWorth, free]',
  );
}

void main() {
  group('retry only on 500 + Retry-After', () {
    for (final status in [502, 503, 504]) {
      test(
        '$status with Retry-After is not resent (outcome unknown)',
        () async {
          final error = ServerException(
            statusCode: status,
            retryAfter: const Duration(milliseconds: 1),
          );
          final s = _Setup(
            FakeExpensesRepository(
              createResults: [error, fixtureExpenseCreated()],
            ),
          );

          await expectLater(s.writer.create(_body), throwsA(same(error)));
          expect(s.expenses.created, hasLength(1));
        },
        skip: 'BUG: ExpenseWriter.create resends on any ServerException '
            'with retryAfter, not only HTTP 500 (SPEC-v2 §3.5 / §4 '
            'core-network: only 500 server_error + Retry-After is a '
            'safe resend). lib/features/expenses/expense_providers.dart '
            'create(): no statusCode == 500 check.',
      );
    }

    test('a 500 with Retry-After from the mapping is resent once', () async {
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

      await s.writer.create(_body);

      expect(s.expenses.created, hasLength(2));
    });

    test('500 without Retry-After is not resent', () async {
      const error = ServerException(statusCode: 500, code: 'server_error');
      final s = _Setup(FakeExpensesRepository(createResults: [error]));

      await expectLater(s.writer.create(_body), throwsA(same(error)));
      expect(s.expenses.created, hasLength(1));
    });

    test('a network error on the resend is thrown, no third try', () async {
      final s = _Setup(
        FakeExpensesRepository(
          createResults: [
            const ServerException(
              statusCode: 500,
              retryAfter: Duration(milliseconds: 1),
            ),
            const NetworkException(),
            fixtureExpenseCreated(),
          ],
        ),
      );

      await expectLater(
        s.writer.create(_body),
        throwsA(isA<NetworkException>()),
      );
      expect(s.expenses.created, hasLength(2));
    });

    test('a 429 with Retry-After is not resent automatically', () async {
      const error = RateLimitedException(retryAfter: Duration(seconds: 1));
      final s = _Setup(FakeExpensesRepository(createResults: [error]));

      await expectLater(s.writer.create(_body), throwsA(same(error)));
      expect(s.expenses.created, hasLength(1));
    });

    test('the resend waits the Retry-After first', () async {
      final s = _Setup(
        FakeExpensesRepository(
          createResults: [
            const ServerException(
              statusCode: 500,
              retryAfter: Duration(milliseconds: 300),
            ),
            fixtureExpenseCreated(),
          ],
        ),
      );
      final watch = Stopwatch()..start();

      final pending = s.writer.create(_body);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.expenses.created, hasLength(1));
      await pending;

      expect(s.expenses.created, hasLength(2));
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 300)),
      );
    });
  });

  group('deduped answers are not applied twice', () {
    test('applying the same debt answer twice moves debts once', () async {
      final s = _Setup(FakeExpensesRepository());
      final before = await s.loaded();
      final answer = _created(
        testWallet(
          id: 9,
          name: 'Kartu Kredit',
          type: 'credit',
          balance: 1225000,
          isDebt: true,
          sortOrder: 2,
          spentThisMonth: 35000,
        ),
        free: 7045000,
        reserved: 3000000,
      );

      s.writer.applyWriteResult(answer);
      final once = s.list.totals;
      s.writer.applyWriteResult(
        _created(
          answer.wallet!,
          free: 7045000,
          reserved: 3000000,
          deduped: true,
        ),
      );

      _expectTotals(s.list.totals, once);
      expect(once.debts, before.totals.debts + 25000);
    });

    test('create then a deduped resend leaves the totals of one write',
        () async {
      final s = _Setup(
        FakeExpensesRepository(
          createResults: [fixtureExpenseCreated(), fixtureExpenseDeduped()],
        ),
      );
      await s.loaded();

      await s.writer.create(_body);
      final once = s.list.totals;
      final again = await s.writer.create(_body);

      expect(again.deduped, isTrue);
      _expectTotals(s.list.totals, once);
      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
    });
  });

  group('wallet totals derived after a write match summarizeWallets', () {
    test('spending from a debt wallet: debts up, assets same', () async {
      final s = _Setup(FakeExpensesRepository());
      await s.loaded();

      s.writer.applyWriteResult(
        _created(
          testWallet(
            id: 9,
            name: 'Kartu Kredit',
            type: 'credit',
            balance: 1225000,
            isDebt: true,
            sortOrder: 2,
            spentThisMonth: 35000,
          ),
          free: 7045000,
          reserved: 3000000,
        ),
      );

      _expectTotals(
        s.list.totals,
        const WalletTotals(
          assets: 11270000,
          debts: 1225000,
          reserved: 3000000,
          netWorth: 10045000,
          free: 7045000,
        ),
      );
      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
    });

    test(
        'spending from a reserved wallet: free same, reserved and assets '
        'down', () async {
      final s = _Setup(FakeExpensesRepository());
      await s.loaded();

      s.writer.applyWriteResult(
        _created(
          testWallet(
            id: 7,
            name: 'Tabungan Kurban',
            balance: 2975000,
            isReserved: true,
            description: 'Kurban 2027',
            sortOrder: 1,
            spentThisMonth: 25000,
          ),
          free: 7070000,
          reserved: 2975000,
        ),
      );

      _expectTotals(
        s.list.totals,
        const WalletTotals(
          assets: 11245000,
          debts: 1200000,
          reserved: 2975000,
          netWorth: 10045000,
          free: 7070000,
        ),
      );
      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
    });

    test('overdraft: an asset wallet going negative is summed as is', () async {
      final s = _Setup(FakeExpensesRepository());
      await s.loaded();

      // Tunai 20.000 pays 50.000 -> -30.000 (SPEC-v2 K14).
      s.writer.applyWriteResult(
        _created(
          testWallet(
            id: 11,
            name: 'Tunai',
            type: 'cash',
            balance: -30000,
            sortOrder: 3,
            spentThisMonth: 50000,
          ),
          free: 7020000,
          reserved: 3000000,
        ),
      );

      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
      expect(s.list.totals.assets, 11220000);
    });

    test('deleting a debt expense gives the debt back', () async {
      final s = _Setup(FakeExpensesRepository());
      await s.loaded();

      s.writer.applyWriteResult(
        ExpenseDeleted(
          id: 1,
          amount: 10000,
          wallet: testWallet(
            id: 9,
            name: 'Kartu Kredit',
            type: 'credit',
            balance: 1190000,
            isDebt: true,
            sortOrder: 2,
          ),
          today: _today(free: 7080000, reserved: 3000000),
        ),
      );

      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
      expect(s.list.totals.debts, 1190000);
    });

    test('moving an expense from a debt wallet to a reserved one', () async {
      final s = _Setup(FakeExpensesRepository());
      await s.loaded();

      // 10.000 moves from Kartu Kredit (9) to Tabungan Kurban (7).
      s.writer.applyWriteResult(
        ExpenseUpdated(
          expense: fixtureExpenseCreated().expense,
          wallets: [
            testWallet(
              id: 7,
              name: 'Tabungan Kurban',
              balance: 2990000,
              isReserved: true,
              sortOrder: 1,
              spentThisMonth: 10000,
            ),
            testWallet(
              id: 9,
              name: 'Kartu Kredit',
              type: 'credit',
              balance: 1190000,
              isDebt: true,
              sortOrder: 2,
            ),
          ],
          today: _today(free: 7080000, reserved: 2990000),
        ),
      );

      _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
    });

    test(
      'a written wallet that became debt on the web: totals still match '
      'the wallets (or the list reloads)',
      () async {
        final s = _Setup(FakeExpensesRepository());
        await s.loaded();

        // Tunai (11, asset 20.000) was turned into a paylater on the web and
        // now owes 25.000. Server: free = 10.070.000 - 20.000 - 25.000 - 3M.
        s.writer.applyWriteResult(
          _created(
            testWallet(
              id: 11,
              name: 'Tunai',
              type: 'paylater',
              balance: 25000,
              isDebt: true,
              sortOrder: 3,
              spentThisMonth: 25000,
            ),
            free: 7025000,
            reserved: 3000000,
          ),
        );
        await s.loaded();

        if (s.wallets.listCalls == 1) {
          _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
        }
      },
      skip: 'BUG: applyExpenseWrite uses the new wallet\'s isDebt only; '
          'when the stored wallet was an asset the delta is '
          'new.display - old.display (-45.000) instead of +25.000 debt, so '
          'debts=1.245.000 and assets=11.270.000 vs server 1.225.000 / '
          '11.250.000. lib/features/wallets/wallet_providers.dart '
          'applyExpenseWrite (should reload, or use old.isDebt for the old '
          'side).',
    );

    test(
      'a written wallet that stopped being debt on the web: totals still '
      'match the wallets (or the list reloads)',
      () async {
        final s = _Setup(FakeExpensesRepository());
        await s.loaded();

        // Kartu Kredit (9) was turned into an ordinary wallet on the web with
        // balance 500.000 and pays 25.000.
        s.writer.applyWriteResult(
          _created(
            testWallet(
              id: 9,
              name: 'Kartu Kredit',
              type: 'bank',
              balance: 475000,
              sortOrder: 2,
              spentThisMonth: 35000,
            ),
            free: 8745000,
            reserved: 3000000,
          ),
        );
        await s.loaded();

        if (s.wallets.listCalls == 1) {
          _expectTotals(s.list.totals, _serverTotals(s.list.wallets));
        }
      },
      skip: 'BUG: a stored debt wallet returned as non-debt keeps its old '
          'debt in the debts total (1.200.000 instead of 0), so assets is '
          '1.200.000 too high. lib/features/wallets/wallet_providers.dart '
          'applyExpenseWrite.',
    );

    test(
        'a written debt wallet the list does not hold reloads, no partial '
        'state', () async {
      final s = _Setup(
        FakeExpensesRepository(),
        walletLists: [
          testWalletList([testWallet(id: 3)]),
          fixtureWalletList(),
        ],
      );
      await s.loaded();

      s.writer.applyWriteResult(
        ExpenseUpdated(
          expense: fixtureExpenseCreated().expense,
          wallets: [
            testWallet(id: 3, balance: 8260000),
            testWallet(id: 9, type: 'credit', balance: 1210000, isDebt: true),
          ],
          today: _today(free: 7070000, reserved: 3000000),
        ),
      );
      final after = await s.loaded();

      expect(s.wallets.listCalls, 2);
      expect([for (final w in after.wallets) w.id], [3, 7, 9, 11]);
    });

    test('a list in error is reloaded, not patched', () async {
      final s = _Setup(
        FakeExpensesRepository(),
        walletLists: [const NetworkException(), fixtureWalletList()],
      );
      await expectLater(s.loaded(), throwsA(isA<NetworkException>()));

      s.writer.applyWriteResult(fixtureExpenseCreated());
      final after = await s.loaded();

      expect(s.wallets.listCalls, 2);
      expect(after.wallets.first.balance, 8250000);
    });
  });
}
