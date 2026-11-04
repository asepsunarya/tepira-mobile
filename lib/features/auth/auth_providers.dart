import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/api_client.dart';
import '../../data/auth/auth_repository.dart';
import '../../data/auth/auth_user.dart';
import '../../data/expenses/last_expense_wallet_store.dart';

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

  /// The sign-in that is running, shared by every caller until it ends.
  Future<void>? _signIn;

  /// The sign-out started by a 401, which a new sign-in must wait for:
  /// otherwise its late `clear()` would wipe the session just stored.
  Future<void>? _expiredSignOut;

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
  ///
  /// Calls made while a sign-in is running join it instead of opening a
  /// second Google picker.
  Future<void> signIn() {
    return _signIn ??= _runSignIn().whenComplete(() => _signIn = null);
  }

  Future<void> _runSignIn() async {
    final pendingSignOut = _expiredSignOut;
    if (pendingSignOut != null) await pendingSignOut;
    final user = await _repository.signInWithGoogle();
    if (user != null) state = AuthSignedIn(user);
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _forgetUserData();
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
    final signOut = _signOutQuietly();
    _expiredSignOut = signOut;
    await signOut;
    if (identical(_expiredSignOut, signOut)) _expiredSignOut = null;
  }

  Future<void> _signOutQuietly() async {
    try {
      await _repository.signOut();
    } on Object {
      // The session is already treated as ended; a failed clear must not
      // block the next sign-in.
    }
    _forgetUserData();
  }

  /// Clears what the app stored for the signed-in user besides the session
  /// (the last Jajan wallet). Best effort and not awaited: a slow or failed
  /// storage call must not keep the user signed in.
  void _forgetUserData() {
    try {
      unawaited(
        ref
            .read(lastExpenseWalletStoreProvider)
            .clear()
            .catchError((Object _) {}),
      );
    } on Object {
      // Only the next Jajan default is affected.
    }
  }
}

final authStateProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
