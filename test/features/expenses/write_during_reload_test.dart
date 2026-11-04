import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/today/today_providers.dart';
import 'package:tepira_mobile/features/wallets/wallet_providers.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

void main() {
  group('a write answer during an in-flight reload', () {
    test('today: the stale GET cannot replace the newer summary', () async {
      final stale = testToday(remaining: 111);
      final fresh = testToday(remaining: 333);
      final today = FakeTodayRepository([fixtureTodayBudget(), stale, fresh]);
      final container = ProviderContainer(
        overrides: [todayRepositoryProvider.overrideWithValue(today)],
      );
      addTearDown(container.dispose);
      container.listen(todayProvider, (_, __) {});
      await container.read(todayProvider.future);

      // A reload starts (resume, midnight) and its GET is still out when
      // the write answer arrives.
      today.gate = Completer<void>();
      container.invalidate(todayProvider);
      expect(container.read(todayProvider).isLoading, isTrue);

      final written = testToday(remaining: 222);
      container.read(todayProvider.notifier).applySummary(written);
      expect(container.read(todayProvider).value?.safeToday.remaining, 222);

      today.gate!.complete();
      final after = await container.read(todayProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(today.calls, 3);
      expect(after.safeToday.remaining, 333);
      expect(container.read(todayProvider).value?.safeToday.remaining, 333);
    });

    test('today: with nothing in flight the summary is applied, no reload',
        () async {
      final today = FakeTodayRepository.budget();
      final container = ProviderContainer(
        overrides: [todayRepositoryProvider.overrideWithValue(today)],
      );
      addTearDown(container.dispose);
      container.listen(todayProvider, (_, __) {});
      await container.read(todayProvider.future);

      container
          .read(todayProvider.notifier)
          .applySummary(testToday(remaining: 222));
      await Future<void>.delayed(Duration.zero);

      expect(today.calls, 1);
      expect(container.read(todayProvider).value?.safeToday.remaining, 222);
    });

    test('wallets: the stale GET cannot replace the newer list', () async {
      final wallets = FakeWalletsRepository([
        fixtureWalletList(),
        fixtureWalletList(),
        testWalletList([testWallet(id: 3, balance: 1)]),
      ]);
      final container = ProviderContainer(
        overrides: [
          walletsRepositoryProvider.overrideWithValue(wallets),
          expensesRepositoryProvider
              .overrideWithValue(FakeExpensesRepository()),
          todayRepositoryProvider
              .overrideWithValue(FakeTodayRepository.budget()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(walletsProvider, (_, __) {});
      await container.read(walletsProvider.future);

      wallets.listGate = Completer<void>();
      container.invalidate(walletsProvider);
      expect(container.read(walletsProvider).isLoading, isTrue);

      final created = fixtureExpenseCreated();
      container.read(expenseWriterProvider).applyWriteResult(created);
      final patched = container.read(walletsProvider).value!;
      expect(
        patched.wallets.firstWhere((w) => w.id == created.wallet!.id).balance,
        created.wallet!.balance,
      );

      wallets.listGate!.complete();
      final after = await container.read(walletsProvider.future);

      expect(wallets.listCalls, 3);
      expect(after.wallets.single.balance, 1);
    });
  });
}
