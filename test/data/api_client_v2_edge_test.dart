// Independent edge cases for the v2 error mapping (api-contract-v2 §Error
// codes): bodies that are not JSON (proxy pages), headers on statuses that
// must ignore them, and the 401 path staying unchanged.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

const _baseUrl = 'https://api.test/api';

/// Answers with a raw text body and content type, e.g. an nginx HTML page.
class _RawAdapter implements HttpClientAdapter {
  _RawAdapter(
    this.status,
    this.text, {
    this.contentType = 'text/html',
    this.headers = const {},
  });

  final int status;
  final String text;
  final String contentType;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter, {void Function()? onUnauthorized}) {
  return createApiDio(
    baseUrl: _baseUrl,
    sessionStore: FakeSessionStore(token: 'jwe-token'),
    onUnauthorized: onUnauthorized,
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

const _html = '<html><body><h1>Error</h1></body></html>';

void main() {
  group('non-JSON error bodies (proxy / CDN pages)', () {
    test('400 HTML -> BadRequestException with default code and message', () {
      expect(
        _dio(_RawAdapter(400, _html)).post<Object?>('/mobile/wallets'),
        _failsWith<BadRequestException>(
          (e) =>
              e.code == 'bad_request' &&
              e.message == const BadRequestException().message,
        ),
      );
    });

    test('413 HTML (nginx client_max_body_size) -> default message', () {
      expect(
        _dio(_RawAdapter(413, _html)).post<Object?>('/mobile/wallets'),
        _failsWith<PayloadTooLargeException>(
          (e) => e.message == const PayloadTooLargeException().message,
        ),
      );
    });

    test('415 plain text -> UnsupportedMediaTypeException default', () {
      expect(
        _dio(_RawAdapter(415, 'Unsupported', contentType: 'text/plain'))
            .post<Object?>('/mobile/wallets'),
        _failsWith<UnsupportedMediaTypeException>(
          (e) => e.message == const UnsupportedMediaTypeException().message,
        ),
      );
    });

    test('429 HTML with Retry-After still reads the wait', () {
      expect(
        _dio(
          _RawAdapter(
            429,
            _html,
            headers: {
              'retry-after': ['3'],
            },
          ),
        ).get<Object?>('/mobile/expenses'),
        _failsWith<RateLimitedException>(
          (e) =>
              e.retryAfter == const Duration(seconds: 3) &&
              e.message == const RateLimitedException().message,
        ),
      );
    });

    test('403 HTML (WAF) -> ForbiddenException with null code', () {
      expect(
        _dio(_RawAdapter(403, _html)).post<Object?>('/mobile/wallets'),
        _failsWith<ForbiddenException>(
          (e) =>
              e.code == null && e.message == const ForbiddenException().message,
        ),
      );
    });

    test('502 HTML -> gateway ServerException without retryAfter', () {
      expect(
        _dio(_RawAdapter(502, _html)).post<Object?>('/mobile/wallets'),
        _failsWith<ServerException>(
          (e) =>
              e.statusCode == 502 && e.retryAfter == null && isGatewayError(e),
        ),
      );
    });
  });

  group('Retry-After edge values', () {
    Dio withHeader(int status, String value) => _dio(
          FakeHttpAdapter(
            status: status,
            headers: {
              'retry-after': [value],
            },
            body: {'ok': false, 'error': 'x', 'message': 'm'},
          ),
        );

    for (final value in [
      '1.5',
      '-2',
      'soon',
      'Wed, 21 Oct 2026 07:28:00 GMT'
    ]) {
      test('429 with "$value" -> retryAfter null, still RateLimited', () {
        expect(
          withHeader(429, value).post<Object?>('/mobile/expenses'),
          _failsWith<RateLimitedException>((e) => e.retryAfter == null),
        );
      });

      test('500 with "$value" -> retryAfter null, still ServerException', () {
        expect(
          withHeader(500, value).post<Object?>('/mobile/expenses'),
          _failsWith<ServerException>(
            (e) => e.retryAfter == null && e.statusCode == 500,
          ),
        );
      });
    }

    test('429 with Retry-After: 0 -> Duration.zero', () {
      expect(
        withHeader(429, '0').post<Object?>('/mobile/expenses'),
        _failsWith<RateLimitedException>((e) => e.retryAfter == Duration.zero),
      );
    });

    test('503 with Retry-After keeps the wait and is a gateway error', () {
      expect(
        withHeader(503, '4').get<Object?>('/mobile/expenses'),
        _failsWith<ServerException>(
          (e) =>
              e.retryAfter == const Duration(seconds: 4) && isGatewayError(e),
        ),
      );
    });

    test('400 ignores Retry-After (no retryAfter field, code kept)', () {
      expect(
        withHeader(400, '5').post<Object?>('/mobile/expenses'),
        _failsWith<BadRequestException>((e) => e.code == 'x'),
      );
    });
  });

  group('401 unchanged by the v2 mapping', () {
    test('401 with the {ok:false} envelope and Retry-After -> Unauthorized',
        () async {
      var reported = 0;
      final dio = _dio(
        FakeHttpAdapter(
          status: 401,
          headers: {
            'retry-after': ['1'],
          },
          body: {
            'ok': false,
            'error': 'unauthorized',
            'message': 'Sesi tidak valid.',
          },
        ),
        onUnauthorized: () => reported++,
      );
      await expectLater(
        dio.get<Object?>('/mobile/wallets'),
        _failsWith<UnauthorizedException>(
          (e) => e.message == const UnauthorizedException().message,
        ),
      );
      expect(reported, 1);
    });

    test('401 HTML body -> UnauthorizedException', () {
      expect(
        _dio(_RawAdapter(401, _html)).get<Object?>('/mobile/wallets'),
        _failsWith<UnauthorizedException>(),
      );
    });
  });

  group('contract bodies verbatim (api-contract-v2)', () {
    Dio contract(int status, String error, String message) => _dio(
          FakeHttpAdapter(
            status: status,
            body: {'ok': false, 'error': error, 'message': message},
          ),
        );

    test('403 forbidden_origin', () {
      expect(
        contract(
          403,
          'forbidden_origin',
          'Permintaan dari situs lain tidak diizinkan.',
        ).delete<Object?>('/mobile/expenses/1'),
        _failsWith<ForbiddenException>(
          (e) =>
              e.code == 'forbidden_origin' &&
              e.message == 'Permintaan dari situs lain tidak diizinkan.',
        ),
      );
    });

    test('400 Tidak ada perubahan (PATCH wallet)', () {
      expect(
        contract(400, 'bad_request', 'Tidak ada perubahan.')
            .patch<Object?>('/mobile/wallets/1'),
        _failsWith<BadRequestException>(
          (e) => e.code == 'bad_request' && e.message == 'Tidak ada perubahan.',
        ),
      );
    });

    test('404 not_found (bad path id) -> NotFoundException', () {
      expect(
        contract(404, 'not_found', 'Data tidak ditemukan.')
            .patch<Object?>('/mobile/wallets/abc'),
        _failsWith<NotFoundException>(),
      );
    });

    test('413 / 415 keep the server message', () {
      expect(
        contract(413, 'payload_too_large', 'Isi permintaan terlalu besar.')
            .post<Object?>('/mobile/wallets'),
        _failsWith<PayloadTooLargeException>(
          (e) => e.message == 'Isi permintaan terlalu besar.',
        ),
      );
      expect(
        contract(415, 'unsupported_media_type', 'Format permintaan harus JSON.')
            .post<Object?>('/mobile/wallets'),
        _failsWith<UnsupportedMediaTypeException>(
          (e) => e.message == 'Format permintaan harus JSON.',
        ),
      );
    });
  });
}
