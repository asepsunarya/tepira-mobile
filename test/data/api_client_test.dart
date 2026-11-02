import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

const _baseUrl = 'https://api.test/api';

Dio _dio(FakeHttpAdapter adapter, {String? token}) {
  return createApiDio(
    baseUrl: _baseUrl,
    sessionStore: FakeSessionStore(token: token),
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

void main() {
  group('session cookie', () {
    test('is sent when a token is stored', () async {
      final adapter = FakeHttpAdapter();

      await _dio(adapter, token: 'jwe-token').get<Object?>('/mobile/goals');

      expect(
        adapter.requests.single.headers['Cookie'],
        '__Secure-authjs.session-token=jwe-token',
      );
    });

    test('is absent when no token is stored', () async {
      final adapter = FakeHttpAdapter();

      await _dio(adapter).get<Object?>('/mobile/goals');

      expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    });

    test('is never sent to another host', () async {
      final adapter = FakeHttpAdapter();

      await _dio(
        adapter,
        token: 'jwe-token',
      ).get<Object?>('https://elsewhere.test/avatar.png');

      expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    });
  });

  group('error mapping', () {
    test('401 -> UnauthorizedException', () {
      final dio = _dio(FakeHttpAdapter(status: 401, body: {'ok': false}));

      expect(
        dio.get<Object?>('/mobile/goals'),
        _failsWith<UnauthorizedException>(),
      );
    });

    test('403 -> ForbiddenException with the API code and message', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 403,
          body: {
            'ok': false,
            'error': 'not_allowed',
            'message': 'Akun ini belum terdaftar di tepira.id',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/session'),
        _failsWith<ForbiddenException>(
          (e) =>
              e.code == 'not_allowed' &&
              e.message == 'Akun ini belum terdaftar di tepira.id',
        ),
      );
    });

    test('404 -> NotFoundException', () {
      final dio = _dio(
        FakeHttpAdapter(status: 404, body: {'ok': false, 'error': 'not_found'}),
      );

      expect(
        dio.get<Object?>('/mobile/goals/x'),
        _failsWith<NotFoundException>(),
      );
    });

    for (final status in [500, 502, 503]) {
      test('$status -> ServerException', () {
        final dio = _dio(FakeHttpAdapter(status: status, body: {}));

        expect(
          dio.get<Object?>('/mobile/goals'),
          _failsWith<ServerException>((e) => e.statusCode == status),
        );
      });
    }

    group('400', () {
      test('bad_request -> BadRequestException with the server message', () {
        final dio = _dio(
          FakeHttpAdapter(
            status: 400,
            body: {
              'ok': false,
              'error': 'bad_request',
              'message': 'Dompet wajib dipilih.',
            },
          ),
        );

        expect(
          dio.post<Object?>('/mobile/expenses'),
          _failsWith<BadRequestException>(
            (e) =>
                e.code == 'bad_request' && e.message == 'Dompet wajib dipilih.',
          ),
        );
      });

      test('wallet_not_found keeps its own code', () {
        final dio = _dio(
          FakeHttpAdapter(
            status: 400,
            body: {
              'ok': false,
              'error': 'wallet_not_found',
              'message': 'Dompet tidak ditemukan. Pilih dompet lain.',
            },
          ),
        );

        expect(
          dio.post<Object?>('/mobile/expenses'),
          _failsWith<BadRequestException>(
            (e) =>
                e.code == 'wallet_not_found' &&
                e.message == 'Dompet tidak ditemukan. Pilih dompet lain.',
          ),
        );
      });

      test('without an envelope -> bad_request with a default message', () {
        final dio = _dio(FakeHttpAdapter(status: 400, body: 'Bad Request'));

        expect(
          dio.post<Object?>('/mobile/expenses'),
          _failsWith<BadRequestException>(
            (e) => e.code == 'bad_request' && e.message.isNotEmpty,
          ),
        );
      });

      test('legacy {success:false, message} keeps the message', () {
        final dio = _dio(
          FakeHttpAdapter(
            status: 400,
            body: {'success': false, 'message': 'Nominal harus lebih dari 0.'},
          ),
        );

        expect(
          dio.post<Object?>('/contribution'),
          _failsWith<BadRequestException>(
            (e) =>
                e.code == 'bad_request' &&
                e.message == 'Nominal harus lebih dari 0.',
          ),
        );
      });
    });

    test('403 forbidden_origin -> ForbiddenException with its code', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 403,
          body: {
            'ok': false,
            'error': 'forbidden_origin',
            'message': 'Permintaan dari situs lain tidak diizinkan.',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/wallets'),
        _failsWith<ForbiddenException>(
          (e) =>
              e.code == 'forbidden_origin' &&
              e.message == 'Permintaan dari situs lain tidak diizinkan.',
        ),
      );
    });

    test('413 payload_too_large -> PayloadTooLargeException', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 413,
          body: {
            'ok': false,
            'error': 'payload_too_large',
            'message': 'Isi permintaan terlalu besar.',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/expenses'),
        _failsWith<PayloadTooLargeException>(
          (e) => e.message == 'Isi permintaan terlalu besar.',
        ),
      );
    });

    test('413 from a proxy (no envelope) -> PayloadTooLargeException', () {
      final dio = _dio(FakeHttpAdapter(status: 413, body: ''));

      expect(
        dio.post<Object?>('/mobile/expenses'),
        _failsWith<PayloadTooLargeException>(
          (e) => e.message == 'Isi permintaan terlalu besar.',
        ),
      );
    });

    test('415 unsupported_media_type -> UnsupportedMediaTypeException', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 415,
          body: {
            'ok': false,
            'error': 'unsupported_media_type',
            'message': 'Format permintaan harus JSON.',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/wallets'),
        _failsWith<UnsupportedMediaTypeException>(
          (e) => e.message == 'Format permintaan harus JSON.',
        ),
      );
    });

    group('429 rate_limited', () {
      Dio rateLimited(Map<String, List<String>> headers) => _dio(
            FakeHttpAdapter(
              status: 429,
              headers: headers,
              body: {
                'ok': false,
                'error': 'rate_limited',
                'message':
                    'Terlalu banyak permintaan. Coba lagi sebentar lagi.',
              },
            ),
          );

      test('-> RateLimitedException with the Retry-After wait', () {
        expect(
          rateLimited({
            'retry-after': ['17'],
          }).post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>(
            (e) =>
                e.retryAfter == const Duration(seconds: 17) &&
                e.message ==
                    'Terlalu banyak permintaan. Coba lagi sebentar lagi.',
          ),
        );
      });

      test('without Retry-After -> retryAfter is null', () {
        expect(
          rateLimited({}).post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>((e) => e.retryAfter == null),
        );
      });

      test('with an unreadable Retry-After -> retryAfter is null', () {
        expect(
          rateLimited({
            'retry-after': ['Wed, 21 Oct 2026 07:28:00 GMT'],
          }).post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>((e) => e.retryAfter == null),
        );
      });

      test('on a GET read too', () {
        expect(
          rateLimited({
            'retry-after': ['5'],
          }).get<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>(
            (e) => e.retryAfter == const Duration(seconds: 5),
          ),
        );
      });

      test('does not report an expired session', () async {
        var reported = 0;
        final dio = createApiDio(
          baseUrl: _baseUrl,
          sessionStore: FakeSessionStore(token: 'jwe-token'),
          onUnauthorized: () => reported++,
        )..httpClientAdapter = FakeHttpAdapter(status: 429, body: {});

        await expectLater(
          dio.post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>(),
        );
        expect(reported, 0);
      });
    });

    test('500 with Retry-After (deadlock) -> ServerException.retryAfter', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 500,
          headers: {
            'retry-after': ['1'],
          },
          body: {
            'ok': false,
            'error': 'server_error',
            'message': 'Terjadi kesalahan di server. Coba lagi nanti.',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/expenses'),
        _failsWith<ServerException>(
          (e) =>
              e.statusCode == 500 &&
              e.code == 'server_error' &&
              e.retryAfter == const Duration(seconds: 1),
        ),
      );
    });

    test('500 without Retry-After -> retryAfter is null', () {
      final dio = _dio(
        FakeHttpAdapter(status: 500, body: {'ok': false, 'error': 'x'}),
      );

      expect(
        dio.get<Object?>('/mobile/expenses'),
        _failsWith<ServerException>((e) => e.retryAfter == null),
      );
    });

    group('a repeated Retry-After header', () {
      FakeHttpAdapter doubled(int status) => FakeHttpAdapter(
            status: status,
            headers: {
              'retry-after': ['2', '9'],
            },
            body: {'ok': false, 'error': 'x', 'message': 'Coba lagi.'},
          );

      test('on 429 -> RateLimitedException with the first value', () {
        expect(
          _dio(doubled(429)).post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>(
            (e) => e.retryAfter == const Duration(seconds: 2),
          ),
        );
      });

      test('on 500 -> ServerException with the first value', () {
        expect(
          _dio(doubled(500)).post<Object?>('/mobile/expenses'),
          _failsWith<ServerException>(
            (e) =>
                e.statusCode == 500 &&
                e.retryAfter == const Duration(seconds: 2),
          ),
        );
      });
    });

    group('never retries on its own', () {
      for (final status in [429, 500]) {
        test('$status with Retry-After: 1 sends exactly one request', () async {
          final adapter = FakeHttpAdapter(
            status: status,
            headers: {
              'retry-after': ['1'],
            },
            body: {'ok': false, 'error': 'x'},
          );

          await expectLater(
            _dio(adapter).post<Object?>('/mobile/expenses', data: {'a': 1}),
            throwsA(isA<DioException>()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 1100));

          expect(adapter.requests, hasLength(1));
        });
      }
    });

    test('{ok:false} with an unmapped 4xx status -> ServerException', () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 409,
          body: {'ok': false, 'error': 'conflict', 'message': 'Bentrok.'},
        ),
      );

      expect(
        dio.post<Object?>('/mobile/goals'),
        _failsWith<ServerException>(
          (e) => e.code == 'conflict' && e.statusCode == 409,
        ),
      );
    });

    test('{ok:false} with a 200 status -> ServerException', () {
      final dio = _dio(FakeHttpAdapter(body: {'ok': false}));

      expect(dio.get<Object?>('/mobile/goals'), _failsWith<ServerException>());
    });

    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.badCertificate,
    ]) {
      test('${type.name} -> NetworkException', () {
        final dio = _dio(FakeHttpAdapter.failing(type));

        expect(
          dio.get<Object?>('/mobile/goals'),
          _failsWith<NetworkException>(),
        );
      });
    }

    test('successful responses pass through untouched', () async {
      final dio = _dio(FakeHttpAdapter(body: {'ok': true, 'goals': []}));

      final response = await dio.get<Map<String, Object?>>('/mobile/goals');

      expect(response.data, {'ok': true, 'goals': <Object?>[]});
    });
  });

  group('parseRetryAfter', () {
    test('reads whole seconds', () {
      expect(parseRetryAfter('1'), const Duration(seconds: 1));
      expect(parseRetryAfter(' 60 '), const Duration(seconds: 60));
      expect(parseRetryAfter('0'), Duration.zero);
    });

    test('is null for missing, negative, fractional or dated values', () {
      for (final value in [
        null,
        '',
        '-1',
        '1.5',
        'soon',
        'Wed, 21 Oct 2026 07:28:00 GMT',
      ]) {
        expect(parseRetryAfter(value), isNull, reason: '$value');
      }
    });

    test('caps long waits at 300 seconds', () {
      expect(parseRetryAfter('300'), const Duration(seconds: 300));
      expect(parseRetryAfter('301'), kMaxRetryAfter);
      expect(parseRetryAfter('86400'), const Duration(seconds: 300));
      expect(parseRetryAfter('999999'), const Duration(seconds: 300));
      expect(parseRetryAfter('9999999'), kMaxRetryAfter);
    });
  });
}
