// Independent edge tests for fix 2 (PR #22 fix round): a written wallet
// whose debt flag flipped must reload the list. The older "became/stopped
// being debt" tests only check totals when no reload happened, so they pass
// vacuously on the reload path; these pin the reload and its result.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';
import 'package:tepira_mobile/features/today/today_providers.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/wallet_providers.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

/// The fixture list with wallet [id] replaced by [replacement], and the
/// server's own totals over it.
WalletList _serverList(int id, Wallet replacement) {
  final wallets = [
    for (final w in fixtureWalletList().wallets) w.id == id ? replacement : w,
  ];
  return testWalletList(wallets, totals: summarizeWallets(wallets));
}

ExpenseCreated _created(Wallet wallet, WalletTotals server) {
  final base = fixtureExpenseCreated();
  final t = fixtureTodayBudget();
  return ExpenseCreated(
    deduped: false,
    expense: base.expense,
    wallet: wallet,
    today: TodaySummary(
      asOf: null,
      date: t.date,
      period: t.period,
      spentToday: t.spentToday,
      spentMonth: t.spentMonth,
      savedThisMonth: t.savedThisMonth,
      budget: t.budget,
      safeToday: t.safeToday,
      walletsFree: server.free,
      walletsReserved: server.reserved,
    ),
  );
}

Future<void> _flipCase(Wallet flipped) async {
  final reloaded = _serverList(flipped.id, flipped);
  final wallets = FakeWalletsRepository([fixtureWalletList(), reloaded]);
  final container = ProviderContainer(
    overrides: [
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      walletsRepositoryProvider.overrideWithValue(wallets),
      todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
    ],
  );
  addTearDown(container.dispose);
  container.listen(walletsProvider, (_, __) {});
  container.listen(todayProvider, (_, __) {});
  await container.read(walletsProvider.future);

  container
      .read(expenseWriterProvider)
      .applyWriteResult(_created(flipped, reloaded.totals));
  final list = await container.read(walletsProvider.future);

  expect(wallets.listCalls, 2, reason: 'a debt-flag flip must reload');
  expect(list.totals, reloaded.totals);
  expect(list.totals, summarizeWallets(list.wallets));
  expect(
    list.wallets.firstWhere((w) => w.id == flipped.id).isDebt,
    flipped.isDebt,
  );
}

void main() {
  test('asset -> debt flip reloads and ends on the server totals', () async {
    await _flipCase(
      testWallet(
        id: 11,
        name: 'Tunai',
        type: 'paylater',
        balance: 25000,
        isDebt: true,
        sortOrder: 3,
        spentThisMonth: 25000,
      ),
    );
  });

  test('debt -> asset flip reloads and ends on the server totals', () async {
    await _flipCase(
      testWallet(
        id: 9,
        name: 'Kartu Kredit',
        type: 'bank',
        balance: 475000,
        sortOrder: 2,
        spentThisMonth: 35000,
      ),
    );
  });

  test('summarizeWallets matches the fixture totals the server sent', () {
    final list = fixtureWalletList();
    expect(summarizeWallets(list.wallets), list.totals);
  });
}
