import 'package:tepira_mobile/data/auth/google_id_token_source.dart';

/// [GoogleIdTokenSource] that returns [idToken] (null = user cancelled) or
/// throws [error], and counts calls. Never talks to Google.
class FakeGoogleIdTokenSource implements GoogleIdTokenSource {
  FakeGoogleIdTokenSource({
    this.idToken = 'google-id-token',
    this.error,
    this.signOutError,
  });

  String? idToken;
  Object? error;

  /// Thrown by [signOut] after counting the call.
  Object? signOutError;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> signIn() async {
    signInCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final failure = signOutError;
    if (failure != null) throw failure;
  }
}
