// Independent edge tests for the Retry-After follow-up: first value of a
// repeated header, the 300 s cap, and no automatic retry.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

Dio _dio(FakeHttpAdapter adapter) => createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(),
    )..httpClientAdapter = adapter;

FakeHttpAdapter _with(int status, List<String> retryAfter, {String? key}) =>
    FakeHttpAdapter(
      status: status,
      headers: {key ?? 'retry-after': retryAfter},
      body: {'ok': false, 'error': 'x', 'message': 'Coba lagi.'},
    );

/// The mapped error, which must be an [AppException] (never a raw error).
Future<AppException> _errorOf(FakeHttpAdapter adapter) async {
  try {
    await _dio(adapter).post<Object?>('/mobile/expenses', data: {'a': 1});
  } on DioException catch (e) {
    expect(e.error, isA<AppException>());
    return e.error! as AppException;
  }
  fail('request did not fail');
}

Duration? _retryAfter(AppException e) => switch (e) {
      RateLimitedException(:final retryAfter) => retryAfter,
      ServerException(:final retryAfter) => retryAfter,
      _ => throw StateError('unexpected ${e.runtimeType}'),
    };

void main() {
  group('parseRetryAfter edge values', () {
    test('whitespace padding is trimmed', () {
      for (final value in [' 5', '5 ', '\t5\n', '\u00A05\u00A0', '\r\n 5 ']) {
        expect(
          parseRetryAfter(value),
          const Duration(seconds: 5),
          reason: value,
        );
      }
    });

    test('zero and leading zeros', () {
      expect(parseRetryAfter('0'), Duration.zero);
      expect(parseRetryAfter('00'), Duration.zero);
      expect(parseRetryAfter('000005'), const Duration(seconds: 5));
      expect(parseRetryAfter('000301'), kMaxRetryAfter);
    });

    test('cap boundary', () {
      expect(kMaxRetryAfter, const Duration(seconds: 300));
      expect(parseRetryAfter('299'), const Duration(seconds: 299));
      expect(parseRetryAfter('300'), const Duration(seconds: 300));
      expect(parseRetryAfter('301'), kMaxRetryAfter);
      expect(parseRetryAfter('100000'), kMaxRetryAfter);
    });

    test('never returns a negative or over-cap wait', () {
      for (final value in [
        for (var i = 0; i <= 1000; i += 7) '$i',
        '999999',
        '9999999',
        '99999999999999999999',
        '-0',
        '-1',
        '-300',
      ]) {
        final wait = parseRetryAfter(value);
        if (wait == null) continue;
        expect(wait.isNegative, isFalse, reason: value);
        expect(wait <= kMaxRetryAfter, isTrue, reason: value);
      }
    });

    test('non-numeric, signed, fractional and dated values are null', () {
      for (final value in [
        ' ',
        '\t',
        '+5',
        '-0',
        '-5',
        '5s',
        '5 5',
        '5,5',
        '2, 9', // proxies may fold a repeated header into one line
        '1e3',
        '0x10',
        '5.0',
        '½',
        '١', // Arabic-Indic one
        '５', // full-width five
        'NaN',
        'Infinity',
        'null',
        // HTTP-date in all three RFC 9110 formats
        'Wed, 21 Oct 2026 07:28:00 GMT',
        'Wednesday, 21-Oct-26 07:28:00 GMT',
        'Wed Oct 21 07:28:00 2026',
      ]) {
        expect(parseRetryAfter(value), isNull, reason: '"$value"');
      }
    });

    test('seven or more digits give the cap', () {
      expect(parseRetryAfter('1000000'), kMaxRetryAfter);
      expect(parseRetryAfter('99999999999999999999'), kMaxRetryAfter);
      expect(
        parseRetryAfter('0000000000000000000005'),
        const Duration(seconds: 5),
      );
    });
  });

  group('Retry-After through the dio error mapping', () {
    for (final status in [429, 500, 503]) {
      test('$status: header name in any case is read', () async {
        final e = await _errorOf(_with(status, ['7'], key: 'Retry-After'));
        expect(_retryAfter(e), const Duration(seconds: 7));
      });

      test('$status: empty header list gives null, no raw exception', () async {
        final e = await _errorOf(_with(status, []));
        expect(_retryAfter(e), isNull);
      });

      test('$status: invalid first value wins over a valid second', () async {
        final e = await _errorOf(_with(status, ['soon', '5']));
        expect(_retryAfter(e), isNull);
      });

      test('$status: three repeated values use the first', () async {
        final e = await _errorOf(_with(status, ['3', '400', 'x']));
        expect(_retryAfter(e), const Duration(seconds: 3));
      });

      test('$status: huge repeated values are capped', () async {
        final e = await _errorOf(_with(status, ['86400', '1']));
        expect(_retryAfter(e), kMaxRetryAfter);
      });

      test('$status: HTTP-date gives null', () async {
        final e = await _errorOf(
          _with(status, ['Wed, 21 Oct 2026 07:28:00 GMT']),
        );
        expect(_retryAfter(e), isNull);
      });

      test('$status: negative and whitespace-padded values', () async {
        expect(_retryAfter(await _errorOf(_with(status, ['-1']))), isNull);
        expect(
          _retryAfter(await _errorOf(_with(status, ['  4  ']))),
          const Duration(seconds: 4),
        );
      });
    }

    test('429 maps to RateLimitedException, 503 to ServerException', () async {
      expect(await _errorOf(_with(429, ['1'])), isA<RateLimitedException>());
      expect(
        await _errorOf(_with(503, ['1'])),
        isA<ServerException>().having((e) => e.statusCode, 'statusCode', 503),
      );
    });
  });

  group('no automatic retry', () {
    for (final status in [429, 500, 502, 503]) {
      test('$status with Retry-After: 0 sends exactly one request', () async {
        final adapter = _with(status, ['0']);
        await expectLater(
          _dio(adapter).get<Object?>('/mobile/wallets'),
          throwsA(isA<DioException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(adapter.requests, hasLength(1));
      });
    }

    test('two calls send exactly two requests', () async {
      final adapter = _with(429, ['0']);
      final dio = _dio(adapter);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          dio.get<Object?>('/mobile/wallets'),
          throwsA(isA<DioException>()),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(adapter.requests, hasLength(2));
    });
  });
}
