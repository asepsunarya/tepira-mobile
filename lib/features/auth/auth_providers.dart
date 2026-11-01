import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/api_client.dart';
import '../../data/auth/auth_repository.dart';
import '../../data/auth/auth_user.dart';

/// Where the user stands with the tepira backend.
@immutable
sealed class AuthState {
  const AuthState();
}

/// The stored session is still being read.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// No session. [sessionExpired] is true when the API rejected the session
/// (401), so the Login screen shows the "Sesi berakhir" overlay.
class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.sessionExpired = false});

  final bool sessionExpired;

  @override
  bool operator ==(Object other) =>
      other is AuthSignedOut && other.sessionExpired == sessionExpired;

  @override
  int get hashCode => sessionExpired.hashCode;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AuthUser user;

  @override
  bool operator ==(Object other) => other is AuthSignedIn && other.user == user;

  @override
  int get hashCode => user.hashCode;
}

/// Owns [AuthState]: restores the stored session on start, signs in and out,
/// and ends the session when any API call answers 401.
class AuthController extends Notifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final subscription = ref
        .watch(unauthorizedEventsProvider)
        .stream
        .listen((_) => _onUnauthorized());
    ref.onDispose(subscription.cancel);
    unawaited(_restore());
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    AuthUser? user;
    try {
      user = await _repository.restore();
    } on Object {
      user = null;
    }
    if (state is! AuthUnknown) return;
    state = user == null ? const AuthSignedOut() : AuthSignedIn(user);
  }

  /// Runs the Google sign-in. Stays signed out when the user cancels.
  /// Throws [AppException] with a message for the Login screen.
  Future<void> signIn() async {
    final user = await _repository.signInWithGoogle();
    if (user != null) state = AuthSignedIn(user);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthSignedOut();
  }

  /// Hides the "Sesi berakhir" overlay.
  void dismissSessionExpired() {
    if (state case AuthSignedOut(sessionExpired: true)) {
      state = const AuthSignedOut();
    }
  }

  Future<void> _onUnauthorized() async {
    if (state is! AuthSignedIn) return;
    state = const AuthSignedOut(sessionExpired: true);
    await _repository.signOut();
  }
}

final authStateProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
