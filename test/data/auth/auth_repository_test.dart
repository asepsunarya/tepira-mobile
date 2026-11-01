import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';

import '../../helpers/fake_google_id_token_source.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';

const _user = {
  'id': 'u1',
  'name': 'Asep',
  'email': 'asep@example.com',
  'image': 'https://example.com/a.png',
};

const _okBody = {
  'ok': true,
  'token': 'jwe-token',
  'expiresAt': '2026-12-01T00:00:00.000Z',
  'user': _user,
};

class _Setup {
  _Setup({FakeHttpAdapter? adapter, FakeSessionStore? store})
      : adapter = adapter ?? FakeHttpAdapter(body: _okBody),
        store = store ?? FakeSessionStore() {
    final dio = createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: this.store,
      onUnauthorized: () => unauthorizedEvents++,
    )..httpClientAdapter = this.adapter;
    repository = ApiAuthRepository(
      dio: dio,
      sessionStore: this.store,
      google: google,
    );
  }

  final FakeHttpAdapter adapter;
  final FakeSessionStore store;
  final google = FakeGoogleIdTokenSource();
  late final ApiAuthRepository repository;
  int unauthorizedEvents = 0;
}

Matcher _throwsMessage<T extends AppException>(String message) =>
    throwsA(isA<T>().having((e) => e.message, 'message', message));

void main() {
  group('signInWithGoogle', () {
    test('posts the Google ID token and stores token and user', () async {
      final s = _Setup();

      final user = await s.repository.signInWithGoogle();

      final request = s.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://api.test/api/mobile/session');
      expect(request.data, {'idToken': 'google-id-token'});
      expect(user, AuthUser.fromJson(_user));
      expect(s.store.token, 'jwe-token');
      expect(jsonDecode(s.store.userJson!), _user);
    });

    test('returns null without calling the API when the picker is closed',
        () async {
      final s = _Setup()..google.idToken = null;

      expect(await s.repository.signInWithGoogle(), isNull);
      expect(s.adapter.requests, isEmpty);
      expect(s.store.token, isNull);
    });

    test('401 invalid_token explains the Google check failed', () async {
      final s = _Setup(
        adapter: FakeHttpAdapter(
          status: 401,
          body: {'ok': false, 'error': 'invalid_token', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.signInWithGoogle(),
        _throwsMessage<ApiException>(kInvalidTokenMessage),
      );
      expect(s.store.token, isNull);
    });

    test('401 on sign-in does not raise the session-expired event', () async {
      final s = _Setup(adapter: FakeHttpAdapter(status: 401, body: const {}));

      await expectLater(s.repository.signInWithGoogle(), throwsA(anything));
      expect(s.unauthorizedEvents, 0);
    });

    test('403 not_allowed shows the allowlist message', () async {
      final s = _Setup(
        adapter: FakeHttpAdapter(
          status: 403,
          body: {'ok': false, 'error': 'not_allowed', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.signInWithGoogle(),
        throwsA(
          isA<ForbiddenException>()
              .having((e) => e.message, 'message', kNotAllowedMessage)
              .having((e) => e.code, 'code', 'not_allowed'),
        ),
      );
    });

    test('429 asks the user to wait', () async {
      final s = _Setup(
        adapter: FakeHttpAdapter(
          status: 429,
          body: {'ok': false, 'error': 'rate_limited', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.signInWithGoogle(),
        _throwsMessage<ApiException>(kTooManyAttemptsMessage),
      );
    });

    test('429 without the error body also asks the user to wait', () async {
      final s = _Setup(adapter: FakeHttpAdapter(status: 429, body: const {}));

      await expectLater(
        s.repository.signInWithGoogle(),
        _throwsMessage<ApiException>(kTooManyAttemptsMessage),
      );
    });

    test('network failure surfaces NetworkException', () async {
      final s = _Setup(
        adapter: FakeHttpAdapter.failing(DioExceptionType.connectionError),
      );

      await expectLater(
        s.repository.signInWithGoogle(),
        _throwsMessage<NetworkException>(const NetworkException().message),
      );
    });

    test('Google picker failure is passed through', () async {
      final s = _Setup()..google.error = const NetworkException();

      await expectLater(
        s.repository.signInWithGoogle(),
        throwsA(isA<NetworkException>()),
      );
      expect(s.adapter.requests, isEmpty);
    });

    test('an unexpected Google plugin error becomes a friendly message',
        () async {
      final s = _Setup()
        ..google.error = PlatformException(code: 'sign_in_failed');

      await expectLater(
        s.repository.signInWithGoogle(),
        _throwsMessage<ApiException>(kGoogleSignInFailedMessage),
      );
      expect(s.adapter.requests, isEmpty);
      expect(s.store.token, isNull);
    });

    test('response without token is a ServerException and stores nothing',
        () async {
      final s = _Setup(
        adapter: FakeHttpAdapter(body: const {'ok': true, 'user': _user}),
      );

      await expectLater(
        s.repository.signInWithGoogle(),
        throwsA(isA<ServerException>()),
      );
      expect(s.store.token, isNull);
    });
  });

  group('restore', () {
    test('returns the stored user', () async {
      final s = _Setup(
        store: FakeSessionStore(token: 't', userJson: jsonEncode(_user)),
      );

      expect(await s.repository.restore(), AuthUser.fromJson(_user));
    });

    test('returns null when nothing is stored', () async {
      expect(await _Setup().repository.restore(), isNull);
    });

    test('returns null when the token is missing', () async {
      final s = _Setup(store: FakeSessionStore(userJson: jsonEncode(_user)));

      expect(await s.repository.restore(), isNull);
    });

    test('clears a corrupt stored user', () async {
      final s = _Setup(store: FakeSessionStore(token: 't', userJson: '{bad'));

      expect(await s.repository.restore(), isNull);
      expect(s.store.token, isNull);
      expect(s.store.userJson, isNull);
    });
  });

  test('signOut clears the store and the Google selection', () async {
    final s = _Setup(
      store: FakeSessionStore(token: 't', userJson: jsonEncode(_user)),
    );

    await s.repository.signOut();

    expect(s.store.token, isNull);
    expect(s.store.userJson, isNull);
    expect(s.google.signOutCalls, 1);
  });
}
