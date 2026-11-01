import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

// Independent verification probes for the T4 origin-scoping / Cookie merge /
// IO error mapping fix. Complements api_client_edge_test.dart.

Dio _dio(HttpClientAdapter adapter, {required String baseUrl}) => createApiDio(
      baseUrl: baseUrl,
      sessionStore: FakeSessionStore(token: 'jwe'),
    )..httpClientAdapter = adapter;

Future<Object?> _cookieFor(
  String baseUrl,
  String url, {
  Map<String, dynamic>? headers,
}) async {
  final adapter = FakeHttpAdapter();
  await _dio(adapter, baseUrl: baseUrl)
      .get<Object?>(url, options: Options(headers: headers));
  return adapter.requests.single.headers['Cookie'];
}

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

void main() {
  group('origin matching', () {
    final sent = <String, String>{
      // base URL -> request URL that MUST get the cookie
      'https://api.test/api': 'https://api.test:443/api/x',
      'https://api.test:443/api': 'https://api.test/api/x',
      'https://API.Test/api': 'https://api.test/api/x',
      'HTTPS://api.test/api': 'https://api.test/api/x',
      'http://localhost/api': 'http://localhost:80/api/x',
      'http://[::1]:3000/api': 'http://[::1]:3000/api/x',
      'http://[::1]/api': 'http://[::1]/api/x',
    };
    sent.forEach((base, url) {
      test('$base -> $url gets cookie', () async {
        expect(await _cookieFor(base, url), 'authjs.session-token=jwe');
      });
    });

    const notSent = <(String, String)>[
      ('https://api.test/api', 'https://evilapi.test/x'),
      ('https://api.test/api', 'https://api.test.evil.com/x'),
      ('https://api.test/api', 'http://api.test:443/x'),
      ('https://api.test/api', 'https://api.test:80/x'),
      ('http://api.test/api', 'https://api.test/x'),
      ('http://[::1]:3000/api', 'http://[::1]:3001/x'),
      ('http://[::1]/api', 'http://[::2]/x'),
      ('http://10.0.2.2:3000/api', 'http://10.0.2.2/x'),
    ];
    for (final (base, url) in notSent) {
      test('$base -> $url gets NO cookie', () async {
        expect(await _cookieFor(base, url), isNull);
      });
    }
  });

  group('Cookie header merge', () {
    const base = 'https://api.test/api';
    test('empty caller Cookie header', () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': ''}),
        'authjs.session-token=jwe',
      );
    });
    test('caller header with trailing "; "', () async {
      expect(
        await _cookieFor(base, '/x', headers: {'Cookie': 'a=1; '}),
        'a=1; authjs.session-token=jwe',
      );
    });
    test('caller-set (different) session token is kept, not overwritten',
        () async {
      expect(
        await _cookieFor(
          base,
          '/x',
          headers: {'Cookie': 'authjs.session-token=other'},
        ),
        'authjs.session-token=other',
      );
    });
    test('lowercase "cookie" key is merged, not duplicated', () async {
      final adapter = FakeHttpAdapter();
      await _dio(adapter, baseUrl: base).get<Object?>(
        '/x',
        options: Options(headers: {'cookie': 'a=1'}),
      );
      final h = adapter.requests.single.headers;
      final keys = h.keys.where((k) => k.toLowerCase() == 'cookie').toList();
      expect(keys, hasLength(1));
      expect(h[keys.single], 'a=1; authjs.session-token=jwe');
    });
    test('similarly-named cookie does not suppress session cookie', () async {
      expect(
        await _cookieFor(
          base,
          '/x',
          headers: {'Cookie': '__Secure-authjs.session-token=z'},
        ),
        '__Secure-authjs.session-token=z; authjs.session-token=jwe',
      );
    });
  });

  group('unknown error mapping', () {
    Future<DioException> failWith(Object error) async {
      try {
        await _dio(_ThrowingAdapter(error), baseUrl: 'https://api.test/api')
            .get<Object?>('/x');
      } on DioException catch (e) {
        return e;
      }
      fail('expected DioException');
    }

    test('plain TlsException -> NetworkException', () async {
      expect(
        (await failWith(const TlsException('x'))).error,
        isA<NetworkException>(),
      );
    });
    test('unknown with StateError -> not mapped', () async {
      final e = await failWith(StateError('boom'));
      expect(e.type, DioExceptionType.unknown);
      expect(e.error, isNot(isA<AppException>()));
    });
    test('unknown with FormatException -> not mapped', () async {
      final e = await failWith(const FormatException('x'));
      expect(e.error, isNot(isA<AppException>()));
    });
    test('mapDioException: badCertificate -> null', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.badCertificate,
            error: const HandshakeException('x'),
          ),
        ),
        isNull,
      );
    });
    test('mapDioException: cancel -> null', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.cancel,
          ),
        ),
        isNull,
      );
    });
    test('mapDioException: unknown + SocketException -> NetworkException', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.unknown,
            error: const SocketException('x'),
          ),
        ),
        isA<NetworkException>(),
      );
    });
    test('mapDioException: unknown + null error -> null', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.unknown,
          ),
        ),
        isNull,
      );
    });
  });
}
