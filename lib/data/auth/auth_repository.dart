import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../api_client.dart';
import '../session_store.dart';
import 'auth_user.dart';
import 'google_id_token_source.dart';

/// Signs the user in with Google, keeps the backend session, and ends it.
abstract interface class AuthRepository {
  /// Returns the stored user, or null when no usable session is stored.
  Future<AuthUser?> restore();

  /// Exchanges a Google ID token for a tepira session and stores it.
  /// Returns null when the user cancels the Google picker.
  /// Throws [AppException] with a message for the Login screen.
  Future<AuthUser?> signInWithGoogle();

  /// Clears the stored session and the Google account selection.
  Future<void> signOut();
}

/// Message for 403 `not_allowed`: the Google account is outside the allowlist.
const String kNotAllowedMessage = 'Akun ini belum terdaftar di tepira.id';

/// Message for 401 `invalid_token` on sign-in.
const String kInvalidTokenMessage =
    'Google tidak bisa memastikan akunmu. Coba masuk lagi.';

/// Message for 429 on sign-in.
const String kTooManyAttemptsMessage =
    'Terlalu banyak percobaan masuk. Tunggu sebentar, lalu coba lagi.';

/// [AuthRepository] for `POST /api/mobile/session` (SPEC section 3.1).
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required Dio dio,
    required SessionStore sessionStore,
    required GoogleIdTokenSource google,
  })  : _dio = dio,
        _sessionStore = sessionStore,
        _google = google;

  final Dio _dio;
  final SessionStore _sessionStore;
  final GoogleIdTokenSource _google;

  @override
  Future<AuthUser?> restore() async {
    final token = await _sessionStore.readToken();
    final userJson = await _sessionStore.readUserJson();
    if (token == null || token.isEmpty) return null;
    if (userJson == null) {
      // A token without its user is unusable: drop it so it is not sent as
      // the session cookie on the next request.
      await _sessionStore.clear();
      return null;
    }
    try {
      return AuthUser.fromJson(jsonDecode(userJson) as Map<String, Object?>);
    } on Object {
      await _sessionStore.clear();
      return null;
    }
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    final String? idToken;
    try {
      idToken = await _google.signIn();
    } on AppException {
      rethrow;
    } on Object {
      // Any other failure from the platform plugin (e.g. a PlatformException
      // from `account.authentication`) must still reach the Login screen as
      // a readable message, not as an unhandled error.
      throw const ApiException(kGoogleSignInFailedMessage);
    }
    if (idToken == null) return null;

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        '/mobile/session',
        data: {'idToken': idToken},
        options: Options(extra: const {kSkipUnauthorizedEvent: true}),
      );
    } on DioException catch (error) {
      throw _signInError(error.error);
    }

    final (token, user) = _parseSession(response.data);
    await _sessionStore.save(token: token, userJson: jsonEncode(user.toJson()));
    return user;
  }

  @override
  Future<void> signOut() async {
    await _sessionStore.clear();
    try {
      await _google.signOut();
    } on Object {
      // The tepira session is already gone; a stale Google account
      // selection only means the picker is skipped next time.
    }
  }
}

AppException _signInError(Object? error) {
  return switch (error) {
    UnauthorizedException() => const ApiException(
        kInvalidTokenMessage,
        statusCode: 401,
      ),
    ForbiddenException(code: 'not_allowed') => const ForbiddenException(
        message: kNotAllowedMessage,
        code: 'not_allowed',
      ),
    RateLimitedException() => const ApiException(
        kTooManyAttemptsMessage,
        statusCode: 429,
      ),
    AppException() => error,
    _ => const ApiException('Masuk gagal. Coba lagi.'),
  };
}

(String, AuthUser) _parseSession(Object? body) {
  if (body is Map) {
    final token = body['token'];
    final user = body['user'];
    if (token is String && token.isNotEmpty && user is Map) {
      try {
        return (token, AuthUser.fromJson(user.cast<String, Object?>()));
      } on FormatException {
        // Fall through to the malformed-response error.
      }
    }
  }
  throw const ServerException(message: 'Jawaban server tidak dikenali.');
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(
    dio: ref.watch(dioProvider),
    sessionStore: ref.watch(sessionStoreProvider),
    google: ref.watch(googleIdTokenSourceProvider),
  ),
);
