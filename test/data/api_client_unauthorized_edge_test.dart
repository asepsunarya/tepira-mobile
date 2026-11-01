// Independent edge cases for UnauthorizedInterceptor (session-token guard).
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/session_store.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

/// Store whose token reads fail after [failAfter] successful reads.
class _FlakyStore extends FakeSessionStore {
  _FlakyStore({super.token, required this.failAfter});

  final int failAfter;
  int reads = 0;

  @override
  Future<String?> readToken() async {
    reads++;
    if (reads > failAfter) throw StateError('keystore unavailable');
    return token;
  }
}

void main() {
  late int events;
  setUp(() => events = 0);

  Dio build(SessionStore store, HttpClientAdapter adapter) => createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: store,
        onUnauthorized: () => events++,
      )..httpClientAdapter = adapter;

  Future<Object?> errorOf(Future<Object?> request) async {
    try {
      await request;
    } on DioException catch (e) {
      return e.error;
    }
    fail('expected a DioException');
  }

  test('a 401 is not reported when the session was cleared meanwhile',
      () async {
    final store = FakeSessionStore(token: 't');
    final adapter = _HoldingAdapter();
    final dio = build(store, adapter);

    final pending = errorOf(dio.get<Object?>('/mobile/goals'));
    await adapter.started.future;
    await store.clear(); // signed out while the request was in flight
    adapter.release.complete();

    expect(await pending, isA<UnauthorizedException>());
    expect(events, 0);
  });

  test('a 401 is not reported for a token that was replaced', () async {
    final store = FakeSessionStore(token: 'old');
    final adapter = _HoldingAdapter();
    final dio = build(store, adapter);

    final pending = errorOf(dio.get<Object?>('/mobile/goals'));
    await adapter.started.future;
    store.token = 'new';
    adapter.release.complete();

    expect(await pending, isA<UnauthorizedException>());
    expect(events, 0);
  });

  test('every parallel 401 for the live token is reported (deduped upstream)',
      () async {
    final dio = build(
      FakeSessionStore(token: 't'),
      FakeHttpAdapter(status: 401, body: const {}),
    );

    await Future.wait(
      List.generate(4, (_) => errorOf(dio.get<Object?>('/mobile/goals'))),
    );

    expect(events, 4);
  });

  test('a 401 from another origin is not reported (no token was sent)',
      () async {
    final adapter = FakeHttpAdapter(status: 401, body: const {});
    final dio = build(FakeSessionStore(token: 't'), adapter);

    await errorOf(dio.get<Object?>('https://other.test/api/x'));

    expect(adapter.requests.single.headers['Cookie'], isNull);
    expect(events, 0);
  });

  test('a stored token that fails to read on 401 does not hang the request',
      () async {
    // First read (cookie interceptor) works, the 401 re-read throws.
    final dio = build(
      _FlakyStore(token: 't', failAfter: 1),
      FakeHttpAdapter(status: 401, body: const {}),
    );

    final outcome = await dio
        .get<Object?>('/mobile/goals')
        .then<Object?>((_) => 'ok', onError: (Object e) => e)
        .timeout(const Duration(seconds: 2), onTimeout: () => 'TIMED OUT');

    expect(outcome, isNot('TIMED OUT'));
    expect(outcome, isA<DioException>());
  });
}

/// Answers 401 once [release] completes; [started] completes on fetch.
class _HoldingAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final release = Completer<void>();
  final _inner = FakeHttpAdapter(status: 401, body: const {});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return _inner.fetch(options, null, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
