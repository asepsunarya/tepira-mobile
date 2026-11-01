// Independent edge cases for AuthController sign-in serialization and 401
// handling, driven by FakeAuthRepository.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';

import '../../helpers/fake_auth_repository.dart';

/// Repository whose sign-out fails, as a broken keystore would.
class _FailingSignOutRepository extends FakeAuthRepository {
  _FailingSignOutRepository({super.restoredUser});

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await signOutGate?.future;
    throw StateError('keystore delete failed');
  }
}

ProviderContainer _container(FakeAuthRepository repository) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('every joined caller receives the same sign-in failure', () async {
    final repository = FakeAuthRepository()
      ..signInGate = Completer<void>()
      ..signInError = const NetworkException();
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();
    final auth = container.read(authStateProvider.notifier);

    final calls = List.generate(3, (_) => auth.signIn());
    repository.signInGate!.complete();

    for (final call in calls) {
      await expectLater(call, throwsA(isA<NetworkException>()));
    }
    expect(repository.signInCalls, 1);
    expect(container.read(authStateProvider), const AuthSignedOut());
  });

  test('a cancelled joined sign-in completes for every caller', () async {
    final repository = FakeAuthRepository()
      ..signInGate = Completer<void>()
      ..signInUser = null;
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();
    final auth = container.read(authStateProvider.notifier);

    final calls = [auth.signIn(), auth.signIn()];
    repository.signInGate!.complete();
    await Future.wait(calls);

    expect(repository.signInCalls, 1);
    expect(container.read(authStateProvider), const AuthSignedOut());
  });

  test('a 401 arriving while signed out (mid sign-in) is ignored', () async {
    final repository = FakeAuthRepository()..signInGate = Completer<void>();
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();

    final signIn = container.read(authStateProvider.notifier).signIn();
    container.read(unauthorizedEventsProvider).notify();
    await _flush();
    expect(container.read(authStateProvider), const AuthSignedOut());
    repository.signInGate!.complete();
    await signIn;

    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    expect(repository.signOutCalls, 0);
  });

  test('a burst of 401 events signs out once', () async {
    final repository = FakeAuthRepository(restoredUser: testUser);
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();

    final events = container.read(unauthorizedEventsProvider);
    for (var i = 0; i < 5; i++) {
      events.notify();
    }
    await _flush();

    expect(
      container.read(authStateProvider),
      const AuthSignedOut(sessionExpired: true),
    );
    expect(repository.signOutCalls, 1);
  });

  test('a failed 401 sign-out does not block the next sign-in', () async {
    final repository = _FailingSignOutRepository(restoredUser: testUser);
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();

    container.read(unauthorizedEventsProvider).notify();
    await _flush();
    await container.read(authStateProvider.notifier).signIn();

    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  test('a slow restore that finishes after sign-in does not undo it', () async {
    final repository = FakeAuthRepository()..restoreGate = Completer<void>();
    final container = _container(repository);
    expect(container.read(authStateProvider), const AuthUnknown());

    await container.read(authStateProvider.notifier).signIn();
    repository.restoreGate!.complete(); // restore() answers "no session"
    await _flush();

    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  test('dismissSessionExpired during the pending sign-out keeps waiting',
      () async {
    final repository = FakeAuthRepository(restoredUser: testUser)
      ..signOutGate = Completer<void>();
    final container = _container(repository);
    container.read(authStateProvider);
    await _flush();
    container.read(unauthorizedEventsProvider).notify();
    await _flush();

    final auth = container.read(authStateProvider.notifier)
      ..dismissSessionExpired();
    final signIn = auth.signIn();
    await _flush();
    expect(repository.signInCalls, 0);

    repository.signOutGate!.complete();
    await signIn;
    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    expect(repository.store.token, 'jwe');
  });
}
