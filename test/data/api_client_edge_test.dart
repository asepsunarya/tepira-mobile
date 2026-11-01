import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

// Edge cases for T4 beyond the per-status happy paths in api_client_test.dart.

const _baseUrl = 'https://api.test/api';

Dio _dio(
  HttpClientAdapter adapter, {
  FakeSessionStore? store,
  String baseUrl = _baseUrl,
}) {
  return createApiDio(
    baseUrl: baseUrl,
    sessionStore: store ?? FakeSessionStore(),
  )..httpClientAdapter = adapter;
}

Matcher _failsWith<T extends AppException>([
  bool Function(T error)? check,
]) {
  return throwsA(
    isA<DioException>().having(
      (e) => e.error,
      'error',
      isA<T>().having((e) => check?.call(e) ?? true, 'check', isTrue),
    ),
  );
}

/// Adapter that throws a raw (non-Dio) error, as dart:io does for failures
/// after the connection is open (reset mid-body, TLS handshake, ...). dio
/// wraps these as [DioExceptionType.unknown].
class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final Object error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      throw error;

  @override
  void close({bool force = false}) {}
}

String? _cookie(FakeHttpAdapter adapter, [int index = 0]) =>
    adapter.requests[index].headers['Cookie'] as String?;

void main() {
  group('session cookie scope', () {
    for (final url in [
      'https://api.test.evil.example/x', // API host as a prefix
      'https://evil-api.test/x', // API host as a suffix
      'https://sub.api.test/x', // subdomain
      'https://elsewhere.test/api/mobile/goals', // same path, other host
    ]) {
      test('is not sent to $url', () async {
        final adapter = FakeHttpAdapter();
        final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

        await dio.get<Object?>(url);

        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      });
    }

    test('is sent for an absolute URL on the API host', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>('https://api.test/api/mobile/goals');

      expect(_cookie(adapter), 'authjs.session-token=jwe');
    });

    test('matches the API host case-insensitively', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>('https://API.TEST/api/mobile/goals');

      expect(_cookie(adapter), 'authjs.session-token=jwe');
    });

    test('works with a local dev base URL with a port', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(
        adapter,
        baseUrl: 'http://10.0.2.2:3000/api',
        store: FakeSessionStore(token: 'jwe'),
      );

      await dio.get<Object?>('/mobile/goals');

      expect(_cookie(adapter), 'authjs.session-token=jwe');
    });

    // BUG (reported, not fixed here): the interceptor compares only the host,
    // not scheme/port, so the session token goes out over plain HTTP, or to
    // another port on the same host. dart:io's own redirect handling uses
    // full same-origin (scheme+host+port) for Cookie; the interceptor should
    // too. Remove `skip` once lib/data/api_client.dart compares origins.
    test(
      'is not sent over plain http to the API host',
      () async {
        final adapter = FakeHttpAdapter();
        final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

        await dio.get<Object?>('http://api.test/api/mobile/goals');

        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      },
      skip: 'BUG: SessionCookieInterceptor ignores scheme (token over http)',
    );

    test(
      'is not sent to another port on the API host',
      () async {
        final adapter = FakeHttpAdapter();
        final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

        await dio.get<Object?>('https://api.test:8443/other');

        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      },
      skip: 'BUG: SessionCookieInterceptor ignores port',
    );
  });

  group('session cookie lifecycle', () {
    test('is read per request: stops after the session is cleared', () async {
      final adapter = FakeHttpAdapter();
      final store = FakeSessionStore(token: 'jwe');
      final dio = _dio(adapter, store: store);

      await dio.get<Object?>('/mobile/goals');
      await store.clear();
      await dio.get<Object?>('/mobile/goals');

      expect(_cookie(adapter, 0), 'authjs.session-token=jwe');
      expect(adapter.requests[1].headers.containsKey('Cookie'), isFalse);
    });

    test('picks up a token saved after the client was built', () async {
      final adapter = FakeHttpAdapter();
      final store = FakeSessionStore();
      final dio = _dio(adapter, store: store);

      await dio.get<Object?>('/mobile/goals');
      await store.save(token: 'new-jwe', userJson: '{}');
      await dio.get<Object?>('/mobile/goals');

      expect(adapter.requests[0].headers.containsKey('Cookie'), isFalse);
      expect(_cookie(adapter, 1), 'authjs.session-token=new-jwe');
    });

    test('is not sent for an empty token', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: ''));

      await dio.get<Object?>('/mobile/goals');

      expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    });
  });

  group('error mapping edge cases', () {
    test('2xx {ok:false} keeps the API code, message and status', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 201,
          body: {'ok': false, 'error': 'quota', 'message': 'Kuota habis.'},
        ),
      );

      expect(
        dio.post<Object?>('/mobile/goals'),
        _failsWith<ServerException>(
          (e) =>
              e.code == 'quota' &&
              e.message == 'Kuota habis.' &&
              e.statusCode == 201,
        ),
      );
    });

    test('2xx {ok:"false"} (string) is not treated as a failure', () async {
      final dio = _dio(FakeHttpAdapter(body: {'ok': 'false'}));

      final res = await dio.get<Object?>('/mobile/goals');

      expect(res.statusCode, 200);
    });

    test('2xx list body passes through', () async {
      final dio = _dio(FakeHttpAdapter(body: [1, 2]));

      final res = await dio.get<Object?>('/mobile/goals');

      expect(res.data, [1, 2]);
    });

    test('401 wins over {ok:false} with a message', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 401,
          body: {'ok': false, 'error': 'x', 'message': 'nope'},
        ),
      );

      expect(
        dio.get<Object?>('/mobile/goals'),
        _failsWith<UnauthorizedException>(),
      );
    });

    test('403 without a JSON object body -> default ForbiddenException', () {
      final dio = _dio(FakeHttpAdapter(status: 403, body: 'Forbidden'));

      expect(
        dio.get<Object?>('/mobile/goals'),
        _failsWith<ForbiddenException>(
          (e) => e.code == null && e.message.isNotEmpty,
        ),
      );
    });

    test('403 with non-string code/message falls back to defaults', () {
      final dio = _dio(
        FakeHttpAdapter(status: 403, body: {'error': 42, 'message': null}),
      );

      expect(
        dio.get<Object?>('/mobile/goals'),
        _failsWith<ForbiddenException>(
          (e) =>
              e.code == null && e.message == const ForbiddenException().message,
        ),
      );
    });

    test('500 with a non-JSON body -> ServerException with default message',
        () {
      final dio = _dio(FakeHttpAdapter(status: 500, body: '<html>oops'));

      expect(
        dio.get<Object?>('/mobile/goals'),
        _failsWith<ServerException>(
          (e) =>
              e.statusCode == 500 &&
              e.message == const ServerException().message,
        ),
      );
    });

    test('4xx without {ok:false} -> ApiException with the API message', () {
      final dio = _dio(
        FakeHttpAdapter(status: 409, body: {'message': 'Sudah ada.'}),
      );

      expect(
        dio.post<Object?>('/mobile/goals'),
        _failsWith<ApiException>(
          (e) => e.statusCode == 409 && e.message == 'Sudah ada.',
        ),
      );
    });

    test('a cancelled request is not mapped to an AppException', () {
      final token = CancelToken()..cancel('bye');
      final dio = _dio(FakeHttpAdapter());

      expect(
        dio.get<Object?>('/mobile/goals', cancelToken: token),
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having((e) => e.error, 'error', isNot(isA<AppException>())),
        ),
      );
    });

    // GAP (reported): dio's IO adapter only maps SocketException to
    // connectionError while *opening* the connection. A reset mid-response or
    // a TLS HandshakeException reaches the interceptor as
    // DioExceptionType.unknown, which mapDioException leaves unmapped, so
    // callers get a raw DioException instead of NetworkException.
    for (final error in [
      const SocketException('Connection reset by peer'),
      const HandshakeException('Handshake error in client'),
      const HttpException('Connection closed while receiving data'),
    ]) {
      test(
        '${error.runtimeType} during transfer -> NetworkException',
        () {
          final dio = _dio(_ThrowingAdapter(error));

          expect(
            dio.get<Object?>('/mobile/goals'),
            _failsWith<NetworkException>(),
          );
        },
        skip: 'GAP: DioExceptionType.unknown with an IO error is unmapped',
      );
    }
  });
}
