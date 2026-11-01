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

const _secure = '__Secure-authjs.session-token';
const _plain = 'authjs.session-token';

/// Cookie header sent for [url] by a client on [baseUrl] holding token `jwe`.
Future<Object?> _cookieFor(
  String baseUrl,
  String url, {
  Map<String, dynamic>? headers,
}) async {
  final adapter = FakeHttpAdapter();
  await _dio(adapter, baseUrl: baseUrl, store: FakeSessionStore(token: 'jwe'))
      .get<Object?>(url, options: Options(headers: headers));
  return adapter.requests.single.headers['Cookie'];
}

DioException _dioError(DioExceptionType type, [Object? error]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      error: error,
    );

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

      expect(_cookie(adapter), '__Secure-authjs.session-token=jwe');
    });

    test('matches the API host case-insensitively', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>('https://API.TEST/api/mobile/goals');

      expect(_cookie(adapter), '__Secure-authjs.session-token=jwe');
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

    // The cookie is scoped to the full API origin (scheme + host + port),
    // matching dart:io's same-origin rule for Cookie on redirects.
    test(
      'is not sent over plain http to the API host',
      () async {
        final adapter = FakeHttpAdapter();
        final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

        await dio.get<Object?>('http://api.test/api/mobile/goals');

        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      },
    );

    test(
      'is not sent to another port on the API host',
      () async {
        final adapter = FakeHttpAdapter();
        final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

        await dio.get<Object?>('https://api.test:8443/other');

        expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
      },
    );

    // Origin = scheme + host + port, with default ports and case normalised.
    const sameOrigin = <(String, String)>[
      ('https://api.test/api', 'https://api.test:443/api/x'),
      ('https://api.test:443/api', 'https://api.test/api/x'),
      ('https://API.Test/api', 'https://api.test/api/x'),
      ('HTTPS://api.test/api', 'https://api.test/api/x'),
      ('http://localhost/api', 'http://localhost:80/api/x'),
      ('http://[::1]:3000/api', 'http://[::1]:3000/api/x'),
      ('http://[::1]/api', 'http://[::1]/api/x'),
      ('https://api.test:8443/api', 'https://api.test:8443/api/x'),
    ];
    for (final (base, url) in sameOrigin) {
      test('base $base: is sent to $url', () async {
        final name = sessionCookieNameFor(Uri.parse(base));
        expect(await _cookieFor(base, url), '$name=jwe');
      });
    }

    const otherOrigin = <(String, String)>[
      ('https://api.test/api', 'https://evilapi.test/x'),
      ('https://api.test/api', 'https://api.test.evil.com/x'),
      ('https://api.test/api', 'http://api.test:443/x'),
      ('https://api.test/api', 'https://api.test:80/x'),
      ('http://api.test/api', 'https://api.test/x'),
      ('http://[::1]:3000/api', 'http://[::1]:3001/x'),
      ('http://[::1]/api', 'http://[::2]/x'),
      ('http://10.0.2.2:3000/api', 'http://10.0.2.2/x'),
      ('https://api.test:8443/api', 'https://api.test/x'),
    ];
    for (final (base, url) in otherOrigin) {
      test('base $base: is not sent to $url', () async {
        expect(await _cookieFor(base, url), isNull);
      });
    }

    test('cross-origin request keeps the caller cookie and adds nothing',
        () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          'https://other.test/x',
          headers: {'Cookie': 'a=1'},
        ),
        'a=1',
      );
    });

    test('is merged with a caller-set Cookie header', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>(
        '/mobile/goals',
        options: Options(headers: {'Cookie': 'locale=id'}),
      );

      expect(_cookie(adapter), 'locale=id; __Secure-authjs.session-token=jwe');
    });

    test('is not duplicated when the caller already set it', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>(
        '/mobile/goals',
        options: Options(
          headers: {'Cookie': '__Secure-authjs.session-token=jwe; locale=id'},
        ),
      );

      expect(_cookie(adapter), '__Secure-authjs.session-token=jwe; locale=id');
    });
  });

  group('Cookie header merge', () {
    const base = 'https://api.test/api';

    test('empty caller Cookie header', () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': ''}),
        '$_secure=jwe',
      );
    });

    test('caller header with a trailing "; "', () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': 'a=1; '}),
        'a=1; $_secure=jwe',
      );
    });

    test('lowercase "cookie" key is merged, not duplicated', () async {
      final adapter = FakeHttpAdapter();
      await _dio(adapter, store: FakeSessionStore(token: 'jwe')).get<Object?>(
        '/x',
        options: Options(headers: {'cookie': 'a=1'}),
      );
      final h = adapter.requests.single.headers;
      final keys = h.keys.where((k) => k.toLowerCase() == 'cookie').toList();
      expect(keys, hasLength(1));
      expect(h[keys.single], 'a=1; $_secure=jwe');
    });

    test('caller cookie as a list is merged', () async {
      expect(
        await _cookieFor(
          base,
          '/x',
          headers: {
            'Cookie': ['a=1', 'b=2'],
          },
        ),
        'a=1; b=2; $_secure=jwe',
      );
    });

    test('https: caller session value wins, order kept, no duplicate',
        () async {
      expect(
        await _cookieFor(
          base,
          '/x',
          headers: {'Cookie': 'a=1; $_secure=mine; b=2'},
        ),
        'a=1; $_secure=mine; b=2',
      );
    });

    test('https: caller session cookie with spaces around the name is kept',
        () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': ' $_secure =mine'}),
        '$_secure =mine',
      );
    });

    test('https: plain-named caller cookie does not suppress __Secure-',
        () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': '$_plain=z'}),
        '$_plain=z; $_secure=jwe',
      );
    });

    test('http: __Secure-named caller cookie does not suppress plain name',
        () async {
      expect(
        await _cookieFor(
          'http://10.0.2.2:3000/api',
          '/x',
          headers: {'Cookie': '$_secure=z'},
        ),
        '$_secure=z; $_plain=jwe',
      );
    });

    test('http: caller plain value wins, no __Secure- added', () async {
      expect(
        await _cookieFor(
          'http://api.test/api',
          '/x',
          headers: {'Cookie': '$_plain=mine; b=2'},
        ),
        '$_plain=mine; b=2',
      );
    });
  });

  group('session cookie name follows the API scheme', () {
    test('sessionCookieNameFor: https -> __Secure- prefixed name', () {
      expect(
        sessionCookieNameFor(Uri.parse('https://api.test/api')),
        '__Secure-authjs.session-token',
      );
      expect(
        sessionCookieNameFor(Uri.parse('HTTPS://api.test/api')),
        '__Secure-authjs.session-token',
      );
    });

    test('sessionCookieNameFor: http -> plain name', () {
      expect(
        sessionCookieNameFor(Uri.parse('http://10.0.2.2:3000/api')),
        'authjs.session-token',
      );
    });

    const names = <String, String>{
      'Https://api.test/api': _secure,
      'hTtPs://api.test:8443/api': _secure,
      'https://api.test:8443/api': _secure,
      'https://127.0.0.1/api': _secure,
      'https://[::1]:8443/api': _secure,
      'http://api.test/api': _plain,
      'HTTP://api.test/api': _plain,
      'http://localhost:443/api': _plain,
    };
    names.forEach((base, name) {
      test('sessionCookieNameFor: $base -> $name', () {
        expect(sessionCookieNameFor(Uri.parse(base)), name);
      });
    });

    test('kSessionCookieName / kSecureSessionCookieName values', () {
      expect(kSessionCookieName, _plain);
      expect(kSecureSessionCookieName, _secure);
    });

    test('uppercase HTTPS base sends the __Secure- name', () async {
      expect(
        await _cookieFor('HTTPS://api.test/api', '/mobile/goals'),
        '$_secure=jwe',
      );
    });

    test('https base with a non-default port sends the __Secure- name',
        () async {
      expect(
        await _cookieFor('https://api.test:8443/api', '/mobile/goals'),
        '$_secure=jwe',
      );
    });

    test('http base never sends the __Secure- name', () async {
      final c = await _cookieFor('http://api.test/api', '/mobile/goals');
      expect(c, '$_plain=jwe');
      expect(c.toString(), isNot(contains('__Secure-')));
    });

    test('http base on port 443 still uses the plain name', () async {
      expect(await _cookieFor('http://localhost:443/api', '/x'), '$_plain=jwe');
    });

    test('https base sends only the __Secure- cookie', () async {
      final c = await _cookieFor('https://api.test/api', '/x');
      expect(c.toString().split('; '), ['$_secure=jwe']);
    });

    test('https base sends __Secure-authjs.session-token', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>('/mobile/goals');

      expect(_cookie(adapter), '__Secure-authjs.session-token=jwe');
    });

    test('http base sends authjs.session-token', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(
        adapter,
        baseUrl: 'http://localhost:3000/api',
        store: FakeSessionStore(token: 'jwe'),
      );

      await dio.get<Object?>('/mobile/goals');

      expect(_cookie(adapter), 'authjs.session-token=jwe');
    });

    test('https: caller-set __Secure- session cookie is preserved', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(adapter, store: FakeSessionStore(token: 'jwe'));

      await dio.get<Object?>(
        '/mobile/goals',
        options: Options(
          headers: {'Cookie': 'locale=id; __Secure-authjs.session-token=mine'},
        ),
      );

      expect(_cookie(adapter), 'locale=id; __Secure-authjs.session-token=mine');
    });

    test('http: caller-set plain session cookie is preserved', () async {
      final adapter = FakeHttpAdapter();
      final dio = _dio(
        adapter,
        baseUrl: 'http://localhost:3000/api',
        store: FakeSessionStore(token: 'jwe'),
      );

      await dio.get<Object?>(
        '/mobile/goals',
        options: Options(headers: {'Cookie': 'authjs.session-token=mine'}),
      );

      expect(_cookie(adapter), 'authjs.session-token=mine');
    });
  });

  group('session cookie lifecycle', () {
    test('is read per request: stops after the session is cleared', () async {
      final adapter = FakeHttpAdapter();
      final store = FakeSessionStore(token: 'jwe');
      final dio = _dio(adapter, store: store);

      await dio.get<Object?>('/mobile/goals');
      await store.clear();
      await dio.get<Object?>('/mobile/goals');

      expect(_cookie(adapter, 0), '__Secure-authjs.session-token=jwe');
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
      expect(_cookie(adapter, 1), '__Secure-authjs.session-token=new-jwe');
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

    test('end-to-end cancel (adapter) is not mapped to an AppException',
        () async {
      final dio = _dio(FakeHttpAdapter.failing(DioExceptionType.cancel));
      expect(
        dio.get<Object?>('/x'),
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having((e) => e.error, 'error', isNot(isA<AppException>())),
        ),
      );
    });

    test('TlsException during transfer -> NetworkException', () {
      final dio = _dio(_ThrowingAdapter(const TlsException('x')));
      expect(dio.get<Object?>('/x'), _failsWith<NetworkException>());
    });

    for (final error in [StateError('boom'), const FormatException('x')]) {
      test('${error.runtimeType} (non-IO unknown) is not mapped', () {
        final dio = _dio(_ThrowingAdapter(error));
        expect(
          dio.get<Object?>('/x'),
          throwsA(
            isA<DioException>()
                .having((e) => e.type, 'type', DioExceptionType.unknown)
                .having((e) => e.error, 'error', isNot(isA<AppException>())),
          ),
        );
      });
    }

    // dio's IO adapter only maps SocketException to connectionError while
    // *opening* the connection. A reset mid-response or a TLS
    // HandshakeException reaches the interceptor as DioExceptionType.unknown;
    // mapDioException must still map it to NetworkException.
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
      );
    }
  });

  group('mapDioException', () {
    test('badCertificate with a HandshakeException -> NetworkException', () {
      expect(
        mapDioException(
          _dioError(
            DioExceptionType.badCertificate,
            const HandshakeException('x'),
          ),
        ),
        isA<NetworkException>(),
      );
    });

    test('badCertificate without an error -> NetworkException', () {
      expect(
        mapDioException(_dioError(DioExceptionType.badCertificate)),
        isA<NetworkException>(),
      );
    });

    test('cancel -> null', () {
      expect(mapDioException(_dioError(DioExceptionType.cancel)), isNull);
    });

    test('cancel with an IO error payload -> null', () {
      expect(
        mapDioException(
          _dioError(DioExceptionType.cancel, const SocketException('x')),
        ),
        isNull,
      );
    });

    test('unknown + SocketException -> NetworkException', () {
      expect(
        mapDioException(
          _dioError(DioExceptionType.unknown, const SocketException('x')),
        ),
        isA<NetworkException>(),
      );
    });

    test('unknown + null error -> null', () {
      expect(mapDioException(_dioError(DioExceptionType.unknown)), isNull);
    });
  });
}
