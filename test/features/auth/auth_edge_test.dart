// Edge cases for T5 auth, wired end to end: real ApiAuthRepository, real dio
// interceptors, fake HTTP adapter, fake secure store, fake Google source.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';
import 'package:tepira_mobile/data/session_store.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_google_id_token_source.dart';
import '../../helpers/fake_session_store.dart';

const _baseUrl = 'https://api.test/api';
const _cookie = '__Secure-authjs.session-token';
const _userJson =
    '{"id":"u1","email":"asep@example.com","name":"Asep","image":null}';

Map<String, Object?> _sessionBody(String token) => {
      'ok': true,
      'token': token,
      'expiresAt': '2026-12-01T00:00:00.000Z',
      'user': {
        'id': 'u1',
        'name': 'Asep',
        'email': 'asep@example.com',
        'image': null,
      },
    };

/// Adapter whose answers are queued per path; a reply can be held open with
/// a [Completer] to simulate an in-flight request.
class _ScriptedAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final _replies = <String, List<Future<(int, Object?)>>>{};

  void reply(String path, int status, Object? body) =>
      (_replies[path] ??= []).add(Future.value((status, body)));

  Completer<(int, Object?)> hold(String path) {
    final gate = Completer<(int, Object?)>();
    (_replies[path] ??= []).add(gate.future);
    return gate;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final queue = _replies[options.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('no reply scripted for ${options.path}');
    }
    final (status, body) = await queue.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _World {
  _World({FakeSessionStore? store}) : store = store ?? FakeSessionStore() {
    container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(this.store),
        googleIdTokenSourceProvider.overrideWithValue(google),
        dioProvider.overrideWith(
          (ref) => createApiDio(
            baseUrl: _baseUrl,
            sessionStore: ref.watch(sessionStoreProvider),
            onUnauthorized: ref.watch(unauthorizedEventsProvider).notify,
          )..httpClientAdapter = adapter,
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeSessionStore store;
  final google = FakeGoogleIdTokenSource();
  final adapter = _ScriptedAdapter();
  late final ProviderContainer container;

  Dio get dio => container.read(dioProvider);
  AuthController get auth => container.read(authStateProvider.notifier);

  Future<AuthState> settled() async {
    container.read(authStateProvider);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(authStateProvider);
  }

  /// A goal request that ignores its own failure (the screen would show it).
  Future<void> goals() async {
    try {
      await dio.get<Object?>('/mobile/goals');
    } on DioException {
      // expected for 401
    }
  }
}

void main() {
  group('restore()', () {
    ApiAuthRepository repo(FakeSessionStore store) => ApiAuthRepository(
          dio: Dio(),
          sessionStore: store,
          google: FakeGoogleIdTokenSource(),
        );

    test('stored user JSON that is not an object is cleared', () async {
      final store = FakeSessionStore(token: 'jwe', userJson: '[]');

      expect(await repo(store).restore(), isNull);
      expect(store.token, isNull);
      expect(store.userJson, isNull);
    });

    test('stored user without id/email is cleared', () async {
      final store = FakeSessionStore(token: 'jwe', userJson: '{"id":1}');

      expect(await repo(store).restore(), isNull);
      expect(store.token, isNull);
    });

    test('truncated JSON is cleared', () async {
      final store = FakeSessionStore(token: 'jwe', userJson: '{"id":"u1",');

      expect(await repo(store).restore(), isNull);
      expect(store.token, isNull);
    });

    test(
      'BUG: a token without a stored user is left behind in secure storage',
      () async {
        // auth_repository.dart:55 returns null when userJson is missing but
        // never clears the orphaned token, so it stays in the keychain and is
        // still attached as the session cookie to the next request
        // (POST /mobile/session) by SessionCookieInterceptor.
        final store = FakeSessionStore(token: 'orphan-jwe');

        expect(await repo(store).restore(), isNull);
        expect(store.token, isNull);
      },
      skip: 'BUG (minor): restore() does not clear an orphaned token '
          '(lib/data/auth/auth_repository.dart:55)',
    );

    test('a store that throws on read ends signedOut, not stuck unknown',
        () async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_ThrowingRestoreRepo()),
        ],
      );
      addTearDown(container.dispose);
      container.read(authStateProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authStateProvider), const AuthSignedOut());
    });

    test(
        'an expired stored session restores signedIn, then the first 401 '
        'ends it with the overlay and wipes the store', () async {
      // expiresAt is not persisted, so expiry is only learnt from the API.
      final w =
          _World(store: FakeSessionStore(token: 'old', userJson: _userJson));
      expect(await w.settled(), isA<AuthSignedIn>());

      w.adapter.reply('/mobile/goals', 401, {
        'ok': false,
        'error': 'unauthorized',
        'message': 'Sesi sudah berakhir. Silakan masuk lagi.',
      });
      await w.goals();

      expect(await w.settled(), const AuthSignedOut(sessionExpired: true));
      expect(w.store.token, isNull);
      expect(w.store.userJson, isNull);
      expect(w.adapter.requests.single.headers['Cookie'], '$_cookie=old');
    });
  });

  group('global 401', () {
    test('concurrent 401s flag the session expired once', () async {
      final w =
          _World(store: FakeSessionStore(token: 't1', userJson: _userJson));
      await w.settled();
      final states = <AuthState>[];
      w.container.listen(authStateProvider, (_, next) => states.add(next));

      for (var i = 0; i < 3; i++) {
        w.adapter.reply('/mobile/goals', 401, const {});
      }
      await Future.wait([w.goals(), w.goals(), w.goals()]);

      expect(await w.settled(), const AuthSignedOut(sessionExpired: true));
      expect(states, [const AuthSignedOut(sessionExpired: true)]);
      expect(w.google.signOutCalls, 1);
    });

    test('a 401 arriving after the user signed out shows no overlay', () async {
      final w =
          _World(store: FakeSessionStore(token: 't1', userJson: _userJson));
      await w.settled();
      final gate = w.adapter.hold('/mobile/goals');
      final inFlight = w.goals();
      await Future<void>.delayed(Duration.zero);

      await w.auth.signOut();
      gate.complete((401, const <String, Object?>{}));
      await inFlight;

      expect(await w.settled(), const AuthSignedOut());
    });

    test(
      'BUG: a stale 401 from before re-sign-in ends the new session',
      () async {
        // Request A leaves with token t1. The session ends (sign-out or a
        // first 401) and the user signs in again, storing t2. When A finally
        // answers 401 for t1, UnauthorizedInterceptor (api_client.dart:97)
        // fires a token-less event and AuthController._onUnauthorized
        // (auth_providers.dart:95-99) sees signedIn, so it flags the new
        // session expired and wipes t2. The 401 should be ignored when the
        // request's cookie is no longer the stored token.
        final w =
            _World(store: FakeSessionStore(token: 't1', userJson: _userJson));
        await w.settled();
        final gate = w.adapter.hold('/mobile/goals');
        final staleRequest = w.goals();
        await Future<void>.delayed(Duration.zero);

        await w.auth.signOut();
        w.adapter.reply('/mobile/session', 200, _sessionBody('t2'));
        await w.auth.signIn();
        expect(w.store.token, 't2');

        gate.complete((401, const <String, Object?>{}));
        await staleRequest;

        expect(await w.settled(), isA<AuthSignedIn>());
        expect(w.store.token, 't2');
      },
      skip: 'BUG: stale 401 for an old token signs out the fresh session '
          '(lib/data/api_client.dart:97, '
          'lib/features/auth/auth_providers.dart:95)',
    );

    test('after sign-out no session cookie is sent', () async {
      final w =
          _World(store: FakeSessionStore(token: 't1', userJson: _userJson));
      await w.settled();

      await w.auth.signOut();
      w.adapter.reply('/mobile/goals', 401, const {});
      await w.goals();

      expect(w.store.token, isNull);
      expect(w.store.userJson, isNull);
      expect(w.google.signOutCalls, 1);
      expect(w.adapter.requests.single.headers['Cookie'], isNull);
    });
  });

  group('sign-in through the real repository', () {
    Future<Object?> signInError(_World w) async {
      await w.settled();
      try {
        await w.auth.signIn();
      } on Object catch (e) {
        return e;
      }
      return null;
    }

    test('stores token + user, then the cookie goes on API calls', () async {
      final w = _World();
      await w.settled();
      w.adapter.reply('/mobile/session', 200, _sessionBody('fresh'));

      await w.auth.signIn();

      expect(w.container.read(authStateProvider), isA<AuthSignedIn>());
      expect(w.store.token, 'fresh');
      expect(jsonDecode(w.store.userJson!), containsPair('id', 'u1'));
      final post = w.adapter.requests.single;
      expect(post.method, 'POST');
      expect(post.data, {'idToken': 'google-id-token'});

      w.adapter.reply('/mobile/goals', 200, const {'ok': true});
      await w.goals();
      expect(w.adapter.requests.last.headers['Cookie'], '$_cookie=fresh');
    });

    test('403 not_allowed -> allowlist message, nothing stored', () async {
      final w = _World();
      w.adapter.reply('/mobile/session', 403, {
        'ok': false,
        'error': 'not_allowed',
        'message': 'Akun ini belum terdaftar di tepira.id.',
      });

      final e = await signInError(w);
      expect((e! as AppException).message, kNotAllowedMessage);
      expect(w.store.token, isNull);
      expect(w.container.read(authStateProvider), const AuthSignedOut());
    });

    test('403 account_not_linked keeps the server explanation', () async {
      final w = _World();
      const msg = 'Email ini sudah terdaftar dengan akun lain. '
          'Masuk lewat web tepira.id dulu.';
      w.adapter.reply('/mobile/session', 403, {
        'ok': false,
        'error': 'account_not_linked',
        'message': msg,
      });

      expect(
        await signInError(w),
        isA<ForbiddenException>().having((e) => e.message, 'message', msg),
      );
    });

    test('429 rate_limited -> wait message', () async {
      final w = _World();
      w.adapter.reply('/mobile/session', 429, {
        'ok': false,
        'error': 'rate_limited',
        'message': 'x',
      });

      expect(
        await signInError(w),
        isA<AppException>()
            .having((e) => e.message, 'message', kTooManyAttemptsMessage),
      );
    });

    test('401 invalid_token on sign-in shows no SesiBerakhir overlay',
        () async {
      final w = _World();
      w.adapter.reply('/mobile/session', 401, {
        'ok': false,
        'error': 'invalid_token',
        'message': 'x',
      });

      final e = await signInError(w);
      expect((e! as AppException).message, kInvalidTokenMessage);
      expect(await w.settled(), const AuthSignedOut());
    });

    test('500 surfaces a ServerException message', () async {
      final w = _World();
      w.adapter.reply('/mobile/session', 500, {
        'ok': false,
        'error': 'server_error',
      });

      expect(await signInError(w), isA<ServerException>());
    });

    test('Google token source network failure -> network message', () async {
      final w = _World();
      w.google.error = const NetworkException();

      expect(
        await signInError(w),
        isA<NetworkException>().having(
          (e) => e.message,
          'message',
          'Koneksi bermasalah. Coba lagi.',
        ),
      );
      expect(w.adapter.requests, isEmpty);
    });
  });

  testWidgets('Login button ignores taps while a sign-in is running',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _GatedSignInRepo();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp(theme: buildVillageTheme(), home: const LoginScreen()),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pump();
    expect(find.text('Menghubungkan…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pump();

    expect(repository.signInCalls, 1);
    repository.gate.complete();
    await tester.pumpAndSettle();
  });

  group('source hygiene', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (f.path, f.readAsStringSync()))
        .toList();

    test('no Google OAuth client ID is hardcoded in lib/', () {
      final hits = [
        for (final (path, src) in sources)
          if (RegExp(r'\d+-[a-z0-9]+\.apps\.googleusercontent\.com')
              .hasMatch(src))
            path,
      ];
      expect(hits, isEmpty);
    });

    test('Google client IDs come only from --dart-define', () {
      expect(kGoogleServerClientId, isEmpty);
      expect(kGoogleIosClientId, isEmpty);
      final src =
          File('lib/data/auth/google_id_token_source.dart').readAsStringSync();
      for (final name in [
        'TEPIRA_GOOGLE_SERVER_CLIENT_ID',
        'TEPIRA_GOOGLE_IOS_CLIENT_ID',
      ]) {
        expect(src, contains("String.fromEnvironment(\n  '$name'"));
      }
    });

    test('nothing in lib/ logs (print, debugPrint, log, LogInterceptor)', () {
      final logging = RegExp(
        r'(^|[^.\w])(print|debugPrint|log)\(|LogInterceptor|dart:developer',
        multiLine: true,
      );
      final hits = [
        for (final (path, src) in sources)
          if (logging.hasMatch(src)) path,
      ];
      expect(hits, isEmpty);
    });

    test('the token is only kept in the secure store', () {
      final hits = [
        for (final (path, src) in sources)
          if (src.contains('shared_preferences') ||
              src.contains('SharedPreferences'))
            path,
      ];
      // session_store.dart only names Android's EncryptedSharedPreferences
      // backend of flutter_secure_storage and a doc comment.
      expect(hits.where((p) => !p.endsWith('session_store.dart')), isEmpty);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('shared_preferences')),
      );
    });
  });
}

class _ThrowingRestoreRepo extends FakeAuthRepository {
  @override
  Future<Never> restore() async =>
      throw const ServerException(message: 'keystore unreadable');
}

class _GatedSignInRepo extends FakeAuthRepository {
  final gate = Completer<void>();

  @override
  Future<AuthUser?> signInWithGoogle() async {
    signInCalls++;
    await gate.future;
    return null;
  }
}
