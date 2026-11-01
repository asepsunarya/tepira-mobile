import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';

/// [GoogleSignIn] whose picker returns [account] or throws [error].
class _FakeGoogleSignIn implements GoogleSignIn {
  _FakeGoogleSignIn({this.account, this.error});

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

/// [GoogleSignInAccount] whose `authentication` returns [idToken] or throws
/// [error].
class _FakeAccount implements GoogleSignInAccount {
  _FakeAccount({this.idToken, this.error});

  final String? idToken;
  final Object? error;

  @override
  Future<GoogleSignInAuthentication> get authentication async {
    final failure = error;
    if (failure != null) throw failure;
    return _FakeAuthentication(idToken);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthentication implements GoogleSignInAuthentication {
  _FakeAuthentication(this.idToken);

  @override
  final String? idToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _throwsMessage<T extends AppException>(String message) =>
    throwsA(isA<T>().having((e) => e.message, 'message', message));

void main() {
  GoogleSignInIdTokenSource source({
    GoogleSignInAccount? account,
    Object? pickerError,
  }) =>
      GoogleSignInIdTokenSource(
        _FakeGoogleSignIn(account: account, error: pickerError),
      );

  test('returns the ID token of the picked account', () async {
    final token =
        await source(account: _FakeAccount(idToken: 'id-token')).signIn();

    expect(token, 'id-token');
  });

  test('returns null when the picker is closed', () async {
    expect(await source().signIn(), isNull);
    expect(
      await source(
        pickerError: PlatformException(
          code: GoogleSignIn.kSignInCanceledError,
        ),
      ).signIn(),
      isNull,
    );
  });

  group('account.authentication failure', () {
    test('PlatformException becomes a friendly message', () async {
      final account = _FakeAccount(
        error: PlatformException(code: 'failed_to_recover_auth'),
      );

      await expectLater(
        source(account: account).signIn(),
        _throwsMessage<ApiException>(kGoogleSignInFailedMessage),
      );
    });

    test('network error becomes NetworkException', () async {
      final account = _FakeAccount(
        error: PlatformException(code: GoogleSignIn.kNetworkError),
      );

      await expectLater(
        source(account: account).signIn(),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a cancelled consent is treated as a closed picker', () async {
      final account = _FakeAccount(
        error: PlatformException(code: GoogleSignIn.kSignInCanceledError),
      );

      expect(await source(account: account).signIn(), isNull);
    });

    test('any other error becomes a friendly message', () async {
      final account = _FakeAccount(error: StateError('plugin crashed'));

      await expectLater(
        source(account: account).signIn(),
        _throwsMessage<ApiException>(kGoogleSignInFailedMessage),
      );
    });
  });

  test('missing ID token is reported', () async {
    await expectLater(
      source(account: _FakeAccount()).signIn(),
      throwsA(isA<ApiException>()),
    );
  });
}
