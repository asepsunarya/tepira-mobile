import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';

ApiGoalsRepository _repository(FakeHttpAdapter adapter) {
  final dio = createApiDio(
    baseUrl: 'https://api.test/api',
    sessionStore: FakeSessionStore(token: 'jwe-token'),
    onUnauthorized: () {},
  )..httpClientAdapter = adapter;
  return ApiGoalsRepository(dio: dio);
}

void main() {
  // A gateway status means the request may have reached the backend and
  // been stored. The Setor screen can only tell it apart from a definite
  // failure by ServerException.statusCode, so the status must survive.
  for (final status in [502, 503, 504]) {
    for (final body in <Object>[
      {'success': false, 'message': 'Bad gateway'},
      {'ok': false, 'error': 'upstream', 'message': 'Upstream down'},
      <String, Object?>{},
    ]) {
      test('contribute $status $body throws ServerException with the status',
          () async {
        final adapter = FakeHttpAdapter(status: status, body: body);
        await expectLater(
          _repository(adapter).contribute(1, 20000),
          throwsA(
            isA<ServerException>()
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
        expect(adapter.requests, hasLength(1), reason: 'no transport retry');
      });
    }
  }

  test('receive timeout on contribute is a NetworkException, not retried',
      () async {
    final adapter = FakeHttpAdapter.failing(DioExceptionType.receiveTimeout);
    await expectLater(
      _repository(adapter).contribute(1, 20000),
      throwsA(isA<NetworkException>()),
    );
    expect(adapter.requests, hasLength(1));
  });
}
