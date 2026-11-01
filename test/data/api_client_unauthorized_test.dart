import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/api_client.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/fake_session_store.dart';

void main() {
  late int events;

  Dio dio(FakeHttpAdapter adapter) => createApiDio(
        baseUrl: 'https://api.test/api',
        sessionStore: FakeSessionStore(token: 't'),
        onUnauthorized: () => events++,
      )..httpClientAdapter = adapter;

  setUp(() => events = 0);

  test('a 401 from any endpoint raises the unauthorized event', () async {
    await expectLater(
      dio(FakeHttpAdapter(status: 401, body: const {}))
          .get<Object?>('/mobile/goals'),
      throwsA(isA<DioException>()),
    );

    expect(events, 1);
  });

  test('requests marked with kSkipUnauthorizedEvent do not raise it', () async {
    await expectLater(
      dio(FakeHttpAdapter(status: 401, body: const {})).post<Object?>(
        '/mobile/session',
        options: Options(extra: const {kSkipUnauthorizedEvent: true}),
      ),
      throwsA(isA<DioException>()),
    );

    expect(events, 0);
  });

  test('other errors do not raise it', () async {
    await expectLater(
      dio(FakeHttpAdapter(status: 403, body: const {}))
          .get<Object?>('/mobile/goals'),
      throwsA(isA<DioException>()),
    );

    expect(events, 0);
  });

  test('UnauthorizedEvents broadcasts notify() to listeners', () async {
    final unauthorized = UnauthorizedEvents();
    final received = <void>[];
    final sub = unauthorized.stream.listen(received.add);

    unauthorized.notify();
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    await sub.cancel();
    await unauthorized.close();
  });
}
