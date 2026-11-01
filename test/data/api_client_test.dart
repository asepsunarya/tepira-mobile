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

    test('{ok:false} with a 4xx status -> ServerException with API message',
        () {
      final dio = _dio(
        FakeHttpAdapter(
          status: 400,
          body: {
            'ok': false,
            'error': 'invalid_target',
            'message': 'Target harus lebih dari 0.',
          },
        ),
      );

      expect(
        dio.post<Object?>('/mobile/goals'),
        _failsWith<ServerException>(
          (e) =>
              e.code == 'invalid_target' &&
              e.message == 'Target harus lebih dari 0.',
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
}
