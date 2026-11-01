import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/errors.dart';

/// OAuth client ID of the backend ("Web application" client). Android and iOS
/// ask Google for an ID token with this audience, which the tepira backend
/// verifies. Set with `--dart-define=TEPIRA_GOOGLE_SERVER_CLIENT_ID=...`.
const String kGoogleServerClientId = String.fromEnvironment(
  'TEPIRA_GOOGLE_SERVER_CLIENT_ID',
);

/// OAuth client ID of the iOS app. Set with
/// `--dart-define=TEPIRA_GOOGLE_IOS_CLIENT_ID=...`. Android needs no client ID
/// in code: Google matches its client by package name and SHA-1.
const String kGoogleIosClientId = String.fromEnvironment(
  'TEPIRA_GOOGLE_IOS_CLIENT_ID',
);

/// Gets a Google ID token from the device account picker. Kept behind an
/// interface so tests never talk to Google.
abstract interface class GoogleIdTokenSource {
  /// Returns the ID token, or null when the user closes the picker.
  /// Throws [AppException] on failure.
  Future<String?> signIn();

  Future<void> signOut();
}

/// [GoogleIdTokenSource] backed by the `google_sign_in` plugin.
class GoogleSignInIdTokenSource implements GoogleIdTokenSource {
  GoogleSignInIdTokenSource([GoogleSignIn? googleSignIn])
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email', 'profile'],
              clientId: defaultTargetPlatform == TargetPlatform.iOS &&
                      kGoogleIosClientId.isNotEmpty
                  ? kGoogleIosClientId
                  : null,
              serverClientId:
                  kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
            );

  final GoogleSignIn _googleSignIn;

  @override
  Future<String?> signIn() async {
    final GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) return null;
      throw _platformError(error);
    }
    if (account == null) return null;
    // Fetching the tokens is a second platform call: it fails on its own
    // (expired account, revoked consent, no network) after the picker closed.
    final GoogleSignInAuthentication authentication;
    try {
      authentication = await account.authentication;
    } on PlatformException catch (error) {
      if (error.code == GoogleSignIn.kSignInCanceledError) return null;
      throw _platformError(error);
    } on Object {
      throw const ApiException(kGoogleSignInFailedMessage);
    }
    final idToken = authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const ApiException(
        'Google tidak memberi token masuk. Coba lagi nanti.',
      );
    }
    return idToken;
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}

/// Message when Google sign-in fails for a reason the user cannot act on.
const String kGoogleSignInFailedMessage =
    'Masuk dengan Google gagal. Coba lagi.';

AppException _platformError(PlatformException error) {
  if (error.code == GoogleSignIn.kNetworkError) return const NetworkException();
  return const ApiException(kGoogleSignInFailedMessage);
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => GoogleSignInIdTokenSource(),
);
