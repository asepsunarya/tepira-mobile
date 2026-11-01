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
      if (error.code == GoogleSignIn.kNetworkError) {
        throw const NetworkException();
      }
      throw const ApiException('Masuk dengan Google gagal. Coba lagi.');
    }
    if (account == null) return null;
    final authentication = await account.authentication;
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

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => GoogleSignInIdTokenSource(),
);
