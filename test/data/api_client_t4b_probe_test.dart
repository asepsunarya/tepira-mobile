import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

// Independent verification probes for T4b: badCertificate mapping and the
// scheme-dependent Auth.js session cookie name.

const _secure = '__Secure-authjs.session-token';
const _plain = 'authjs.session-token';

Future<Object?> _cookieFor(
  String baseUrl,
  String url, {
  Map<String, dynamic>? headers,
}) async {
  final adapter = FakeHttpAdapter();
  final dio = createApiDio(
    baseUrl: baseUrl,
    sessionStore: FakeSessionStore(token: 'jwe'),
  )..httpClientAdapter = adapter;
  await dio.get<Object?>(url, options: Options(headers: headers));
  return adapter.requests.single.headers['Cookie'];
}

void main() {
  group('sessionCookieNameFor', () {
    const cases = <String, String>{
      'https://api.test/api': _secure,
      'HTTPS://api.test/api': _secure,
      'Https://api.test/api': _secure,
      'hTtPs://api.test:8443/api': _secure,
      'https://api.test:8443/api': _secure,
      'https://127.0.0.1/api': _secure,
      'https://[::1]:8443/api': _secure,
      'http://api.test/api': _plain,
      'HTTP://api.test/api': _plain,
      'http://10.0.2.2:3000/api': _plain,
      'http://localhost:443/api': _plain,
    };
    cases.forEach((base, name) {
      test('$base -> $name', () {
        expect(sessionCookieNameFor(Uri.parse(base)), name);
      });
    });

    test('kSessionCookieName / kSecureSessionCookieName values', () {
      expect(kSessionCookieName, _plain);
      expect(kSecureSessionCookieName, _secure);
    });
  });

  group('interceptor uses scheme name end-to-end', () {
    test('uppercase HTTPS base -> __Secure- name', () async {
      expect(
        await _cookieFor('HTTPS://api.test/api', '/mobile/goals'),
        '$_secure=jwe',
      );
    });
    test('https base with non-default port -> __Secure- name', () async {
      expect(
        await _cookieFor('https://api.test:8443/api', '/mobile/goals'),
        '$_secure=jwe',
      );
      expect(
        await _cookieFor(
          'https://api.test:8443/api',
          'https://api.test:8443/api/x',
        ),
        '$_secure=jwe',
      );
    });
    test('https base with non-default port: other port gets no cookie',
        () async {
      expect(
        await _cookieFor('https://api.test:8443/api', 'https://api.test/x'),
        isNull,
      );
    });
    test('http base never sends the __Secure- name', () async {
      final c = await _cookieFor('http://api.test/api', '/mobile/goals');
      expect(c, '$_plain=jwe');
      expect(c.toString(), isNot(contains('__Secure-')));
    });
    test('http base on port 443 still uses plain name', () async {
      expect(
        await _cookieFor('http://localhost:443/api', '/x'),
        '$_plain=jwe',
      );
    });
    test('https base never sends the plain name on its own', () async {
      final c = await _cookieFor('https://api.test/api', '/x');
      expect(c.toString().split('; '), ['$_secure=jwe']);
    });
  });

  group('caller cookies (unchanged behaviour)', () {
    test('https: caller __Secure- value wins, order kept, no dup', () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          '/x',
          headers: {'Cookie': 'a=1; $_secure=mine; b=2'},
        ),
        'a=1; $_secure=mine; b=2',
      );
    });
    test('https: caller plain cookie does not suppress __Secure-', () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          '/x',
          headers: {'Cookie': '$_plain=mine'},
        ),
        '$_plain=mine; $_secure=jwe',
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
    test('https: caller cookie as list is merged', () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          '/x',
          headers: {
            'Cookie': ['a=1', 'b=2'],
          },
        ),
        'a=1; b=2; $_secure=jwe',
      );
    });
    test('https: caller session cookie with spaces around name kept', () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          '/x',
          headers: {'Cookie': ' $_secure =mine'},
        ),
        '$_secure =mine',
      );
    });
    test('cross-origin request keeps caller cookie, adds nothing', () async {
      expect(
        await _cookieFor(
          'https://api.test/api',
          'https://other.test/x',
          headers: {'Cookie': 'a=1'},
        ),
        'a=1',
      );
    });
  });

  group('badCertificate vs cancel', () {
    test('mapDioException: badCertificate without error -> Network', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.badCertificate,
          ),
        ),
        isA<NetworkException>(),
      );
    });
    test('mapDioException: cancel with IO error payload -> null', () {
      expect(
        mapDioException(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.cancel,
            error: const SocketException('x'),
          ),
        ),
        isNull,
      );
    });

    Future<DioException> failWith(DioExceptionType type) async {
      final dio = createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: FakeSessionStore(token: 'jwe'),
      )..httpClientAdapter = FakeHttpAdapter.failing(type);
      try {
        await dio.get<Object?>('/x');
      } on DioException catch (e) {
        return e;
      }
      fail('expected DioException');
    }

    test('end-to-end badCertificate -> NetworkException', () async {
      final e = await failWith(DioExceptionType.badCertificate);
      expect(e.type, DioExceptionType.badCertificate);
      expect(e.error, isA<NetworkException>());
    });
    test('end-to-end cancel -> not an AppException', () async {
      final e = await failWith(DioExceptionType.cancel);
      expect(e.type, DioExceptionType.cancel);
      expect(e.error, isNot(isA<AppException>()));
    });
    test('real CancelToken cancel -> not an AppException', () async {
      final dio = createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: FakeSessionStore(token: 'jwe'),
      )..httpClientAdapter = FakeHttpAdapter();
      final token = CancelToken()..cancel('bye');
      try {
        await dio.get<Object?>('/x', cancelToken: token);
        fail('expected DioException');
      } on DioException catch (e) {
        expect(e.type, DioExceptionType.cancel);
        expect(e.error, isNot(isA<AppException>()));
      }
    });
  });
}
