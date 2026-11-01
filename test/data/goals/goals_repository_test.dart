import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/goals/goal_dto.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

class _Setup {
  _Setup(this.adapter) {
    final dio = createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(token: 'jwe-token'),
      onUnauthorized: () => unauthorizedEvents++,
    )..httpClientAdapter = adapter;
    repository = ApiGoalsRepository(dio: dio);
  }

  final FakeHttpAdapter adapter;
  late final ApiGoalsRepository repository;
  int unauthorizedEvents = 0;

  RequestOptions get request => adapter.requests.single;
}

Map<String, Object?> _error(String code, [String message = 'Pesan server']) =>
    {'ok': false, 'error': code, 'message': message};

const _createdGoal = {
  'id': 16,
  'title': 'Kamera mirrorless',
  'description': 'Untuk konten',
  'target': 9000000,
  'saved': 0,
  'percent': 0,
  'remaining': 9000000,
  'deadline': '2027-06-30',
  'daysLeft': 241,
  'perMonthNeeded': 1000000,
  'createdAt': '2026-11-01T07:00:00.000Z',
  'lastContribution': null,
  'contributionCount': 0,
};

void main() {
  group('list', () {
    test('GETs /mobile/goals with the session cookie and parses the fixture',
        () async {
      final body = _fixture('mobile_goals.json');
      final s = _Setup(FakeHttpAdapter(body: body));

      final goals = await s.repository.list();

      expect(s.request.method, 'GET');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/goals');
      expect(
        s.request.headers['Cookie'],
        '__Secure-authjs.session-token=jwe-token',
      );
      expect(goals, [
        for (final item in body['goals']! as List)
          goalFromJson(item as Map<String, Object?>),
      ]);
    });

    test('401 unauthorized throws and ends the session', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 401, body: _error('unauthorized')),
      );

      await expectLater(
        s.repository.list(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(s.unauthorizedEvents, 1);
    });

    test('500 server_error throws ServerException with the server message',
        () async {
      final s = _Setup(
        FakeHttpAdapter(status: 500, body: _error('server_error', 'Gagal.')),
      );

      await expectLater(
        s.repository.list(),
        throwsA(
          isA<ServerException>()
              .having((e) => e.message, 'message', 'Gagal.')
              .having((e) => e.code, 'code', 'server_error')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('a timeout throws NetworkException', () async {
      final s = _Setup(
        FakeHttpAdapter.failing(DioExceptionType.connectionTimeout),
      );

      await expectLater(
        s.repository.list(),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a malformed goal throws ServerException, not FormatException',
        () async {
      final s = _Setup(
        FakeHttpAdapter(
          body: {
            'ok': true,
            'goals': [
              {'id': 'twelve'},
            ],
          },
        ),
      );

      await expectLater(
        s.repository.list(),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            kUnrecognizedResponseMessage,
          ),
        ),
      );
    });

    test('a body without goals throws ServerException', () async {
      final s = _Setup(FakeHttpAdapter(body: {'ok': true}));

      await expectLater(
        s.repository.list(),
        throwsA(isA<ServerException>()),
      );
    });

    test('a non-object body throws ServerException', () async {
      final s = _Setup(FakeHttpAdapter(body: const ['not', 'an', 'object']));

      await expectLater(
        s.repository.list(),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('detail', () {
    test('GETs /mobile/goals/{id} and parses the fixture', () async {
      final body = _fixture('mobile_goal_detail.json');
      final s = _Setup(FakeHttpAdapter(body: body));

      final detail = await s.repository.detail(12);

      expect(s.request.method, 'GET');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/goals/12');
      expect(
        detail,
        goalDetailFromJson(body['goal']! as Map<String, Object?>),
      );
      expect(detail.contributions, hasLength(4));
    });

    test('404 not_found throws NotFoundException', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 404, body: _error('not_found')),
      );

      await expectLater(
        s.repository.detail(99),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('401 unauthorized throws and ends the session', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 401, body: _error('unauthorized')),
      );

      await expectLater(
        s.repository.detail(12),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(s.unauthorizedEvents, 1);
    });

    test('a detail without contributions throws ServerException', () async {
      final s = _Setup(
        FakeHttpAdapter(body: {'ok': true, 'goal': _createdGoal}),
      );

      await expectLater(
        s.repository.detail(16),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('create', () {
    test('POSTs JSON with every field and parses the 201 goal', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 201, body: {'ok': true, 'goal': _createdGoal}),
      );

      final goal = await s.repository.create(
        title: 'Kamera mirrorless',
        target: 9000000,
        description: 'Untuk konten',
        deadline: DateTime(2027, 6, 30),
      );

      expect(s.request.method, 'POST');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/goals');
      expect(s.request.contentType, startsWith('application/json'));
      expect(s.request.data, {
        'title': 'Kamera mirrorless',
        'target': 9000000,
        'description': 'Untuk konten',
        'deadline': '2027-06-30',
      });
      expect(goal, goalFromJson(_createdGoal));
    });

    test('sends null description and deadline when omitted', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 201, body: {'ok': true, 'goal': _createdGoal}),
      );

      await s.repository.create(title: 'Dana pendidikan', target: 20000000);

      expect(s.request.data, {
        'title': 'Dana pendidikan',
        'target': 20000000,
        'description': null,
        'deadline': null,
      });
    });

    test('pads single-digit months and days in the deadline', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 201, body: {'ok': true, 'goal': _createdGoal}),
      );

      await s.repository.create(
        title: 'x',
        target: 1,
        deadline: DateTime.utc(2027, 1, 5),
      );

      expect((s.request.data as Map)['deadline'], '2027-01-05');
    });

    // The client maps every `{ok: false}` 4xx without its own class to
    // ServerException, keeping code and status for the form to branch on.
    test('400 bad_request keeps the server validation message', () async {
      const message = 'Judul harus diisi, maksimal 60 karakter.';
      final s = _Setup(
        FakeHttpAdapter(status: 400, body: _error('bad_request', message)),
      );

      await expectLater(
        s.repository.create(title: '', target: 1),
        throwsA(
          isA<ServerException>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('401 unauthorized throws and ends the session', () async {
      final s = _Setup(
        FakeHttpAdapter(status: 401, body: _error('unauthorized')),
      );

      await expectLater(
        s.repository.create(title: 'x', target: 1),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(s.unauthorizedEvents, 1);
    });
  });

  group('contribute', () {
    test('POSTs multipart form goalId, amount, note to /contribution',
        () async {
      final s = _Setup(FakeHttpAdapter(body: {'success': true}));

      await s.repository.contribute(12, 20000, 'Sisa jajan');

      expect(s.request.method, 'POST');
      expect(s.request.uri.toString(), 'https://api.test/api/contribution');
      expect(s.request.contentType, startsWith('multipart/form-data'));
      expect(
        s.request.headers['Cookie'],
        '__Secure-authjs.session-token=jwe-token',
      );
      final form = s.request.data as FormData;
      expect(Map.fromEntries(form.fields), {
        'goalId': '12',
        'amount': '20000',
        'note': 'Sisa jajan',
      });
    });

    test('omits note when there is none', () async {
      final s = _Setup(FakeHttpAdapter(body: {'success': true}));

      await s.repository.contribute(12, 20000);

      final form = s.request.data as FormData;
      expect(Map.fromEntries(form.fields), {
        'goalId': '12',
        'amount': '20000',
      });
    });

    test('400 shows the legacy route message', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 400,
          body: {'success': false, 'message': 'Nominal harus lebih dari 0.'},
        ),
      );

      await expectLater(
        s.repository.contribute(12, 0),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.message,
                'message',
                'Nominal harus lebih dari 0.',
              )
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('404 throws NotFoundException', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 404,
          body: {'success': false, 'message': 'Goal tidak ditemukan.'},
        ),
      );

      await expectLater(
        s.repository.contribute(99, 20000),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('401 throws and ends the session', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 401,
          body: {'success': false, 'message': 'Unauthorized'},
        ),
      );

      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(s.unauthorizedEvents, 1);
    });

    test('500 throws ServerException', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 500,
          body: {'success': false, 'message': 'Terjadi kesalahan.'},
        ),
      );

      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
