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

  group('signIn serialization', () {
    test('concurrent calls share one Google sign-in', () async {
      final repository = FakeAuthRepository()..signInGate = Completer<void>();
      final container = _container(repository);
      await _settled(container);
      final controller = container.read(authStateProvider.notifier);

      final first = controller.signIn();
      final second = controller.signIn();
      await Future<void>.delayed(Duration.zero);
      repository.signInGate!.complete();
      await Future.wait([first, second]);

      expect(repository.signInCalls, 1);
      expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    });

    test('a later call starts a new sign-in', () async {
      final repository = FakeAuthRepository()..signInUser = null;
      final container = _container(repository);
      await _settled(container);
      final controller = container.read(authStateProvider.notifier);

      await controller.signIn();
      await controller.signIn();

      expect(repository.signInCalls, 2);
    });

    test('a failed sign-in does not block the next one', () async {
      final repository = FakeAuthRepository()
        ..signInError = const NetworkException();
      final container = _container(repository);
      await _settled(container);
      final controller = container.read(authStateProvider.notifier);
      await expectLater(controller.signIn(), throwsA(isA<NetworkException>()));

      repository.signInError = null;
      await controller.signIn();

      expect(repository.signInCalls, 2);
      expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    });

    test('sign-in right after a 401 waits for the session to be cleared',
        () async {
      final store = FakeSessionStore(token: 'old', userJson: '{}');
      final repository =
          FakeAuthRepository(restoredUser: testUser, store: store)
            ..signOutGate = Completer<void>();
      final container = _container(repository);
      await _settled(container);
      container.read(unauthorizedEventsProvider).notify();
      expect(
        await _settled(container),
        const AuthSignedOut(sessionExpired: true),
      );

      final signIn = container.read(authStateProvider.notifier).signIn();
      await Future<void>.delayed(Duration.zero);
      expect(repository.signInCalls, 0);

      repository.signOutGate!.complete();
      await signIn;

      expect(repository.signInCalls, 1);
      expect(container.read(authStateProvider), const AuthSignedIn(testUser));
      // The late clear() of the expired session did not wipe the new one.
      expect(store.token, 'jwe');
    });
  });
}
