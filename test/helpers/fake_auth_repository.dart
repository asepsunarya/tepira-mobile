import 'dart:async';

import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';

import 'fake_session_store.dart';

const testUser = AuthUser(id: 'u1', email: 'asep@example.com', name: 'Asep');

/// [AuthRepository] driven by fields, backed by a [FakeSessionStore] so tests
/// can check what is stored.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.restoredUser, FakeSessionStore? store})
      : store = store ?? FakeSessionStore();

  final FakeSessionStore store;

  /// Returned by [restore].
  AuthUser? restoredUser;

  /// Returned by [signInWithGoogle] unless [signInError] is set.
  AuthUser? signInUser = testUser;
  Object? signInError;

  /// When set, [restore] waits for it before answering.
  Completer<void>? restoreGate;

  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<AuthUser?> restore() async {
    await restoreGate?.future;
    return restoredUser;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    signInCalls++;
    final error = signInError;
    if (error != null) throw error;
    final user = signInUser;
    if (user != null) await store.save(token: 'jwe', userJson: '{}');
    return user;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await store.clear();
  }
}
