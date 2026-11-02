// Independent edge tests for the Retry-After digit-length cap and leading
// zeros (PR #19, 3811118).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

const _cap = kMaxRetryAfter;
Duration _s(int seconds) => Duration(seconds: seconds);

void _expectAll(Map<String, Duration?> cases) {
  for (final MapEntry(:key, :value) in cases.entries) {
    expect(parseRetryAfter(key), value, reason: 'Retry-After "$key"');
  }
}

void main() {
  test('cap is 300 s', () => expect(_cap, _s(300)));

  group('digit length around the cap', () {
    test('exactly 6 digits', () {
      _expectAll({
        '100000': _cap,
        '999999': _cap,
        '000300': _s(300),
        '000301': _cap,
        '000005': _s(5),
        '000000': _s(0),
      });
    });

    test('exactly 7 digits', () {
      _expectAll({
        '1000000': _cap,
        '9999999': _cap,
        '0000300': _s(300),
        '0000299': _s(299),
        '0000005': _s(5),
        '0000000': _s(0),
      });
    });

    test('values just below, at and above 300', () {
      _expectAll({
        '298': _s(298),
        '299': _s(299),
        '300': _s(300),
        '301': _cap,
        '302': _cap,
        '0299': _s(299),
        '0301': _cap,
        '999': _cap,
        '1000': _cap,
      });
    });
  });

  group('zeros', () {
    test('all zeros of any length are 0 s', () {
      for (var n = 1; n <= 64; n++) {
        expect(parseRetryAfter('0' * n), Duration.zero, reason: '$n zeros');
      }
    });

    test('long zero padding is ignored', () {
      _expectAll({
        '${'0' * 50}5': _s(5),
        '${'0' * 1000}300': _s(300),
        '${'0' * 1000}301': _cap,
        '${'0' * 20}1${'0' * 20}': _cap,
      });
    });
  });

  group('huge values do not overflow', () {
    test('values beyond int64 give the cap', () {
      _expectAll({
        '9223372036854775807': _cap, // int64 max
        '9223372036854775808': _cap, // int64 max + 1
        '18446744073709551616': _cap, // 2^64
        '9' * 400: _cap,
        '1${'0' * 10000}': _cap,
      });
    });
  });

  group('whitespace', () {
    test('surrounding whitespace is trimmed', () {
      _expectAll({
        ' 5': _s(5),
        '5 ': _s(5),
        '\t5\n': _s(5),
        '\r\n 300 \r\n': _s(300),
        ' 0000007 ': _s(7),
        ' 1000000 ': _cap,
      });
    });

    test('empty, blank and inner whitespace give null', () {
      _expectAll({
        '': null,
        ' ': null,
        '\t\n': null,
        '5 5': null,
        '1 000': null,
        '1\t0': null,
      });
      expect(parseRetryAfter(null), isNull);
    });
  });

  group('non delta-seconds forms give null', () {
    test('negative and signed', () {
      _expectAll({
        '-1': null,
        '-0': null,
        '-300': null,
        '-1000000': null,
        '+5': null,
        '+0': null,
      });
    });

    test('decimals and exponents', () {
      _expectAll({
        '1.5': null,
        '5.0': null,
        '0.0': null,
        '.5': null,
        '5.': null,
        '1,5': null,
        '1e3': null,
        '0x10': null,
      });
    });

    test('HTTP-date and other text', () {
      _expectAll({
        'Wed, 21 Oct 2026 07:28:00 GMT': null,
        'Mon, 02 Nov 2026 10:00:00 GMT': null,
        'Sunday, 06-Nov-94 08:49:37 GMT': null,
        'Sun Nov  6 08:49:37 1994': null,
        'soon': null,
        '5s': null,
        '5 seconds': null,
      });
    });

    test('non-ASCII digits are not delta-seconds', () {
      _expectAll({
        '５': null, // fullwidth 5
        '٥': null, // Arabic-Indic 5
        '५': null, // Devanagari 5
      });
    });
  });

  group('through the dio error mapping', () {
    Future<Duration?> retryAfterFor(int status, String header) async {
      final dio = createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: FakeSessionStore(),
      )..httpClientAdapter = FakeHttpAdapter(
          status: status,
          headers: {
            'retry-after': [header],
          },
          body: {'ok': false, 'error': 'x', 'message': 'Coba lagi.'},
        );
      try {
        await dio.get<Object?>('/mobile/wallets');
      } on DioException catch (e) {
        return switch (e.error) {
          RateLimitedException(:final retryAfter) => retryAfter,
          ServerException(:final retryAfter) => retryAfter,
          final other => fail('unexpected ${other.runtimeType}'),
        };
      }
      fail('request did not fail');
    }

    for (final status in [429, 503]) {
      test('$status: 7 digits are capped, padded zeros ignored', () async {
        expect(await retryAfterFor(status, '1000000'), _cap);
        expect(await retryAfterFor(status, '${'0' * 30}5'), _s(5));
        expect(await retryAfterFor(status, '9' * 100), _cap);
        expect(await retryAfterFor(status, '-5'), isNull);
      });
    }
  });
}
