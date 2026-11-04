// Independent edge tests for forgetting the last Jajan wallet on sign-out
// (fix round on PR #22): a failing or hanging clear never blocks sign-out or
// the next sign-in, and the next user never gets the old wallet preselected.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense_wallet_choice.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_wallets_repository.dart';

const _otherUser = AuthUser(id: 'u2', email: 'budi@example.com', name: 'Budi');

enum _Failure { syncThrow, asyncThrow, hang }

/// A store whose [clear] fails as [failure] says; reads keep the old id.
class _BrokenClearStore implements LastExpenseWalletStore {
  _BrokenClearStore(this.failure, this.walletId);

  final _Failure failure;
  int? walletId;
  int clearCalls = 0;
  final hang = Completer<void>();

  @override
  Future<int?> read() async => walletId;

  @override
  Future<void> write(int walletId) async => this.walletId = walletId;

  @override
  Future<void> clear() {
    clearCalls++;
    switch (failure) {
      case _Failure.syncThrow:
        throw StateError('keystore locked');
      case _Failure.asyncThrow:
        return Future<void>.error(StateError('keystore locked'));
      case _Failure.hang:
        return hang.future;
    }
  }
}

ProviderContainer _container(
  FakeAuthRepository repository,
  LastExpenseWalletStore lastWallet,
) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      lastExpenseWalletStoreProvider.overrideWithValue(lastWallet),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AuthState> _settled(ProviderContainer container) async {
  container.read(authStateProvider);
  await Future<void>.delayed(Duration.zero);
  return container.read(authStateProvider);
}

/// User B's wallets: none share an id with user A's (ids are server rows).
List<Wallet> _walletsOfB() => [
      testWallet(id: 101, name: 'Dompet Budi', balance: 50000),
      testWallet(id: 102, name: 'Bank Budi', type: 'bank', balance: 900000),
    ];

void main() {
  for (final failure in _Failure.values) {
    group('clear ${failure.name}', () {
      test('signOut still completes and moves to signedOut', () async {
        final store = _BrokenClearStore(failure, 9);
        final repository = FakeAuthRepository(restoredUser: testUser);
        final container = _container(repository, store);
        await _settled(container);

        await container
            .read(authStateProvider.notifier)
            .signOut()
            .timeout(const Duration(seconds: 2));

        expect(container.read(authStateProvider), const AuthSignedOut());
        expect(repository.store.token, isNull);
        expect(store.clearCalls, 1);
      });

      test('an expired session still ends and a new sign-in works', () async {
        final store = _BrokenClearStore(failure, 9);
        final repository = FakeAuthRepository(restoredUser: testUser);
        final container = _container(repository, store);
        await _settled(container);

        container.read(unauthorizedEventsProvider).notify();
        expect(
          await _settled(container),
          const AuthSignedOut(sessionExpired: true),
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.clearCalls, 1);

        repository.signInUser = _otherUser;
        await container
            .read(authStateProvider.notifier)
            .signIn()
            .timeout(const Duration(seconds: 2));
        expect(
          container.read(authStateProvider),
          const AuthSignedIn(_otherUser),
        );
      });

      test('the next user still gets their own default, not A\'s wallet',
          () async {
        final store = _BrokenClearStore(failure, 9);
        final repository = FakeAuthRepository(restoredUser: testUser);
        final container = _container(repository, store);
        await _settled(container);
        await container.read(authStateProvider.notifier).signOut();
        repository.signInUser = _otherUser;
        await container.read(authStateProvider.notifier).signIn();

        // The failed clear left A's id behind.
        final stale = await container.read(lastExpenseWalletIdProvider.future);
        final wallets = _walletsOfB();
        final chosen = defaultExpenseWallet(wallets, stale);

        expect(chosen, isNotNull);
        expect(wallets.map((w) => w.id), contains(chosen!.id));
        expect(chosen.id, isNot(9));
      });
    });
  }

  test('a successful clear: the next user reads no stored wallet', () async {
    final store = FakeLastExpenseWalletStore(9);
    final repository = FakeAuthRepository(restoredUser: testUser);
    final container = _container(repository, store);
    await _settled(container);
    // A's form read the stored id before signing out.
    final sub = container.listen(lastExpenseWalletIdProvider, (_, __) {});
    expect(await container.read(lastExpenseWalletIdProvider.future), 9);
    sub.close();
    await Future<void>.delayed(Duration.zero);

    await container.read(authStateProvider.notifier).signOut();
    repository.signInUser = _otherUser;
    await container.read(authStateProvider.notifier).signIn();

    expect(await container.read(lastExpenseWalletIdProvider.future), isNull);
  });

  test(
      'a form kept open across sign-out does not hand A\'s cached id to B '
      '(the provider is re-read)', () async {
    final store = FakeLastExpenseWalletStore(9);
    final repository = FakeAuthRepository(restoredUser: testUser);
    final container = _container(repository, store);
    await _settled(container);
    final sub = container.listen(lastExpenseWalletIdProvider, (_, __) {});
    expect(await container.read(lastExpenseWalletIdProvider.future), 9);

    await container.read(authStateProvider.notifier).signOut();
    repository.signInUser = _otherUser;
    await container.read(authStateProvider.notifier).signIn();
    // Leaving the signed-in shell disposes the form; a new visit re-reads.
    sub.close();
    await Future<void>.delayed(Duration.zero);

    expect(await container.read(lastExpenseWalletIdProvider.future), isNull);
  });
}
