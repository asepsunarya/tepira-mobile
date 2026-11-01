// Independent edge-case tests for the 401 / sign-in races, wired end to end:
// real dio client + interceptors, real ApiAuthRepository, real AuthController.
// Only the HTTP transport, the session store and Google are faked.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';
import 'package:tepira_mobile/data/session_store.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';

const _userJson = {'id': 'u1', 'name': 'Asep', 'email': 'asep@example.com'};

/// Session store whose `clear()` can be held open, to model a slow keystore.
class _GatedStore implements SessionStore {
  _GatedStore({this.token, this.userJson});

  String? token;
  String? userJson;
  Completer<void>? clearGate;
  int clearCalls = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> save({required String token, required String userJson}) async {
    this.token = token;
    this.userJson = userJson;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    await clearGate?.future;
    token = null;
    userJson = null;
  }
}

/// Google source that counts pickers and can be held open.
class _Google implements GoogleIdTokenSource {
  int signInCalls = 0;
  Completer<void>? gate;

  @override
  Future<String?> signIn() async {
    signInCalls++;
    await gate?.future;
    return 'google-id-token';
  }

  @override
  Future<void> signOut() async {}
}

/// Routes: POST /mobile/session -> new session; everything else -> [status].
/// Requests to /mobile/goals wait for [hold] when set.
class _Adapter implements HttpClientAdapter {
  final int status = 401;
  final String newToken = 'new-token';
  Completer<void>? hold;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/mobile/session')) {
      return _json(200, {'ok': true, 'token': newToken, 'user': _userJson});
    }
    await hold?.future;
    return _json(status, status == 401 ? const {} : const {'ok': true});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _World {
  _World({String? storedToken = 'old-token'})
      : store = _GatedStore(
          token: storedToken,
          userJson: storedToken == null ? null : jsonEncode(_userJson),
        ) {
    container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        googleIdTokenSourceProvider.overrideWithValue(google),
        dioProvider.overrideWith(
          (ref) => createApiDio(
            baseUrl: 'https://api.test/api',
            sessionStore: store,
            onUnauthorized: ref.watch(unauthorizedEventsProvider).notify,
          )..httpClientAdapter = adapter,
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  final _GatedStore store;
  final google = _Google();
  final adapter = _Adapter();
  late final ProviderContainer container;

  Dio get dio => container.read(dioProvider);
  AuthController get auth => container.read(authStateProvider.notifier);
  AuthState get state => container.read(authStateProvider);

  Future<void> settle() async {
    container.read(authStateProvider);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> failingGet() async {
    try {
      await dio.get<Object?>('/mobile/goals');
    } on DioException {
      // expected
    }
  }
}

void main() {
  test('parallel 401s for the same session end it exactly once', () async {
    final world = _World();
    await world.settle();
    expect(world.state, isA<AuthSignedIn>());

    await Future.wait(List.generate(6, (_) => world.failingGet()));
    await world.settle();

    expect(world.state, const AuthSignedOut(sessionExpired: true));
    expect(world.store.clearCalls, 1);
    expect(world.store.token, isNull);
  });

  test('a 401 for a request sent without a token keeps the session', () async {
    // Signed out at start: the request goes out with no cookie...
    final world = _World(storedToken: null);
    await world.settle();
    world.adapter.hold = Completer<void>();
    final pending = world.failingGet();
    await world.settle();

    // ...then the user signs in before the anonymous 401 lands.
    await world.auth.signIn();
    expect(world.state, isA<AuthSignedIn>());
    world.adapter.hold!.complete();
    await pending;
    await world.settle();

    expect(world.adapter.requests.first.headers['Cookie'], isNull);
    expect(world.state, isA<AuthSignedIn>());
    expect(world.store.token, 'new-token');
    expect(world.store.clearCalls, 0);
  });

  test('a 401 sign-out racing a fast re-sign-in keeps the new session',
      () async {
    final world = _World();
    await world.settle();
    world.store.clearGate = Completer<void>(); // slow keystore delete

    await world.failingGet();
    await world.settle();
    expect(world.state, const AuthSignedOut(sessionExpired: true));

    // User taps "Masuk lagi" while the old session is still being deleted.
    final signIn = world.auth.signIn();
    await world.settle();
    expect(world.google.signInCalls, 0, reason: 'must wait for the clear');

    world.store.clearGate!.complete();
    await signIn;
    await world.settle();

    expect(world.state, isA<AuthSignedIn>());
    expect(world.store.token, 'new-token');
  });

  test('a late 401 for the old token after re-sign-in is ignored', () async {
    final world = _World();
    await world.settle();

    final hold = Completer<void>();
    world.adapter.hold = hold;
    final slow = world.failingGet(); // leaves with old-token, then waits
    await world.settle();

    // The session ends elsewhere (another request's 401) and the user signs
    // back in.
    world.container.read(unauthorizedEventsProvider).notify();
    await world.settle();
    expect(world.state, const AuthSignedOut(sessionExpired: true));
    await world.auth.signIn();
    expect(world.store.token, 'new-token');

    hold.complete();
    await slow;
    await world.settle();

    expect(
      world.adapter.requests.first.headers['Cookie'],
      contains('old-token'),
    );
    expect(world.state, isA<AuthSignedIn>());
    expect(world.store.token, 'new-token');
    expect(world.store.clearCalls, 1);
  });

  test('a 401 for the new session after a re-sign-in ends it again', () async {
    final world = _World();
    await world.settle();
    await world.failingGet();
    await world.settle();
    await world.auth.signIn();
    expect(world.state, isA<AuthSignedIn>());

    await world.failingGet(); // sent with new-token
    await world.settle();

    expect(world.state, const AuthSignedOut(sessionExpired: true));
    expect(world.store.clearCalls, 2);
    expect(world.store.token, isNull);
  });

  test('taps during a sign-in that waits on a 401 sign-out join it', () async {
    final world = _World();
    await world.settle();
    world.store.clearGate = Completer<void>();
    await world.failingGet();
    await world.settle();

    final calls = [world.auth.signIn(), world.auth.signIn()];
    await world.settle();
    calls.add(world.auth.signIn());
    world.store.clearGate!.complete();
    await Future.wait(calls);

    expect(world.google.signInCalls, 1);
    expect(world.state, isA<AuthSignedIn>());
  });
}
