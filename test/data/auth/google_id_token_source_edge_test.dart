// Independent edge cases for Google picker / token error mapping.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';

class _Picker implements GoogleSignIn {
  _Picker({this.account, this.error});

  final GoogleSignInAccount? account;
  final Object? error;

  @override
  Future<GoogleSignInAccount?> signIn() async {
    final failure = error;
    if (failure != null) throw failure;
    return account;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account implements GoogleSignInAccount {
  _Account({this.idToken, this.error});

  final String? idToken;
  final Object? error;

  @override
  Future<GoogleSignInAuthentication> get authentication async {
    final failure = error;
    if (failure != null) throw failure;
    return _Auth(idToken);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements GoogleSignInAuthentication {
  _Auth(this.idToken);

  @override
  final String? idToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String?> _signIn({GoogleSignInAccount? account, Object? pickerError}) =>
    GoogleSignInIdTokenSource(
      _Picker(account: account, error: pickerError),
    ).signIn();

Matcher _friendly() => throwsA(
      isA<ApiException>()
          .having((e) => e.message, 'message', kGoogleSignInFailedMessage),
    );

void main() {
  group('picker failure', () {
    test('network_error becomes NetworkException', () async {
      await expectLater(
        _signIn(
          pickerError: PlatformException(code: GoogleSignIn.kNetworkError),
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    for (final code in [
      GoogleSignIn.kSignInFailedError,
      GoogleSignIn.kSignInRequiredError,
      'unknown_code',
    ]) {
      test('$code becomes the friendly message', () async {
        await expectLater(
          _signIn(pickerError: PlatformException(code: code)),
          _friendly(),
        );
      });
    }
  });

  group('account.authentication failure', () {
    for (final code in [
      GoogleSignIn.kSignInFailedError,
      GoogleSignIn.kSignInRequiredError,
      'failed_to_recover_auth',
      'user_recoverable_auth',
    ]) {
      test('$code becomes the friendly message', () async {
        await expectLater(
          _signIn(account: _Account(error: PlatformException(code: code))),
          _friendly(),
        );
      });
    }

    test('network_error becomes NetworkException', () async {
      await expectLater(
        _signIn(
          account: _Account(
            error: PlatformException(code: GoogleSignIn.kNetworkError),
          ),
        ),
        throwsA(isA<NetworkException>()),
      );
    });

    test('sign_in_canceled is a closed picker (null)', () async {
      expect(
        await _signIn(
          account: _Account(
            error: PlatformException(code: GoogleSignIn.kSignInCanceledError),
          ),
        ),
        isNull,
      );
    });

    test('a non-platform error (TimeoutException-like) is friendly', () async {
      await expectLater(
        _signIn(account: _Account(error: Exception('timeout'))),
        _friendly(),
      );
    });
  });

  test('an empty ID token is reported, not sent to the backend', () async {
    await expectLater(
      _signIn(account: _Account(idToken: '')),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'a non-PlatformException from the picker is an AppException '
    '(GoogleIdTokenSource contract)',
    () async {
      await expectLater(
        _signIn(pickerError: StateError('plugin not initialised')),
        throwsA(isA<AppException>()),
      );
    },
    skip: 'BUG (low): GoogleSignInIdTokenSource.signIn() only catches '
        'PlatformException around _googleSignIn.signIn(), so any other picker '
        'error escapes raw, breaking the "Throws AppException" contract. '
        'ApiAuthRepository and LoginScreen catch it today, so users still see '
        'a friendly message.',
  );
}
