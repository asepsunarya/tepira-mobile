import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart'
    show kUnrecognizedResponseMessage;
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/features/today/model/today_summary.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';
import '../../helpers/fake_today_repository.dart';

TodayRepository _repository(FakeHttpAdapter adapter) => ApiTodayRepository(
      dio: createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: FakeSessionStore(token: 'jwe-token'),
        onUnauthorized: () {},
      )..httpClientAdapter = adapter,
    );

void main() {
  test('GETs /mobile/today with the session cookie', () async {
    final adapter = FakeHttpAdapter(body: readFixture('mobile_today_budget'));

    final today = await _repository(adapter).get();

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), 'https://api.test/api/mobile/today');
    expect(
      request.headers['Cookie'],
      '__Secure-authjs.session-token=jwe-token',
    );
    expect(today.safeToday.state, SafeTodayState.ok);
  });

  test('an unknown state -> ServerException, never a guessed card', () {
    final body = readFixture('mobile_today_budget');
    body['safeToday'] = {
      ...(body['safeToday'] as Map<String, Object?>),
      'state': 'santai',
    };

    expect(
      _repository(FakeHttpAdapter(body: body)).get(),
      throwsA(
        isA<ServerException>().having(
          (e) => e.message,
          'message',
          kUnrecognizedResponseMessage,
        ),
      ),
    );
  });

  test('401 -> UnauthorizedException', () {
    final adapter = FakeHttpAdapter(
      status: 401,
      body: {
        'ok': false,
        'error': 'unauthorized',
        'message': 'Sesi sudah berakhir. Silakan masuk lagi.',
      },
    );

    expect(
      _repository(adapter).get(),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('500 -> ServerException', () {
    final adapter = FakeHttpAdapter(
      status: 500,
      body: {
        'ok': false,
        'error': 'server_error',
        'message': 'Terjadi kesalahan di server. Coba lagi nanti.',
      },
    );

    expect(_repository(adapter).get(), throwsA(isA<ServerException>()));
  });
}
