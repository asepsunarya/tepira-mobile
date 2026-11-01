import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_session_store.dart';

ProviderContainer _container(FakeAuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the auth state after pending restores and events have run.
Future<AuthState> _settled(ProviderContainer container) async {
  container.read(authStateProvider);
  await Future<void>.delayed(Duration.zero);
  return container.read(authStateProvider);
}

void main() {
  test('starts unknown while the stored session is read', () async {
    final repository = FakeAuthRepository()..restoreGate = Completer<void>();
    final container = _container(repository);

    expect(container.read(authStateProvider), const AuthUnknown());

    repository.restoreGate!.complete();
    expect(await _settled(container), const AuthSignedOut());
  });

  test('restores to signedIn when a session is stored', () async {
    final container = _container(FakeAuthRepository(restoredUser: testUser));

    expect(await _settled(container), const AuthSignedIn(testUser));
  });

  test('restores to signedOut when nothing is stored', () async {
    final container = _container(FakeAuthRepository());

    expect(await _settled(container), const AuthSignedOut());
  });

  test('signIn moves signedOut to signedIn', () async {
    final container = _container(FakeAuthRepository());
    await _settled(container);

    await container.read(authStateProvider.notifier).signIn();

    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  test('cancelled signIn stays signedOut', () async {
    final repository = FakeAuthRepository()..signInUser = null;
    final container = _container(repository);
    await _settled(container);

    await container.read(authStateProvider.notifier).signIn();

    expect(container.read(authStateProvider), const AuthSignedOut());
  });

  test('failed signIn rethrows and stays signedOut', () async {
    final repository = FakeAuthRepository()
      ..signInError = const ForbiddenException(
        message: kNotAllowedMessage,
        code: 'not_allowed',
      );
    final container = _container(repository);
    await _settled(container);

    await expectLater(
      container.read(authStateProvider.notifier).signIn(),
      throwsA(isA<ForbiddenException>()),
    );
    expect(container.read(authStateProvider), const AuthSignedOut());
  });

  test('signOut clears the store and moves to signedOut', () async {
    final store = FakeSessionStore(token: 'jwe', userJson: '{}');
    final repository = FakeAuthRepository(restoredUser: testUser, store: store);
    final container = _container(repository);
    await _settled(container);

    await container.read(authStateProvider.notifier).signOut();

    expect(container.read(authStateProvider), const AuthSignedOut());
    expect(store.token, isNull);
    expect(store.userJson, isNull);
  });

  group('unauthorized event', () {
    test('ends a signed-in session and flags it expired', () async {
      final store = FakeSessionStore(token: 'jwe', userJson: '{}');
      final repository =
          FakeAuthRepository(restoredUser: testUser, store: store);
      final container = _container(repository);
      await _settled(container);

      container.read(unauthorizedEventsProvider).notify();

      expect(
        await _settled(container),
        const AuthSignedOut(sessionExpired: true),
      );
      expect(store.token, isNull);
      expect(repository.signOutCalls, 1);
    });

    test('is ignored when already signed out', () async {
      final repository = FakeAuthRepository();
      final container = _container(repository);
      await _settled(container);

      container.read(unauthorizedEventsProvider).notify();

      expect(await _settled(container), const AuthSignedOut());
      expect(repository.signOutCalls, 0);
    });

    test('dismissSessionExpired hides the overlay flag', () async {
      final container = _container(FakeAuthRepository(restoredUser: testUser));
      await _settled(container);
      container.read(unauthorizedEventsProvider).notify();
      await _settled(container);

      container.read(authStateProvider.notifier).dismissSessionExpired();

      expect(container.read(authStateProvider), const AuthSignedOut());
    });
  });
}
