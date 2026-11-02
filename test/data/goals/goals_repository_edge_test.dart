import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';

import '../../helpers/fake_session_store.dart';

/// Adapter that records the serialized request body (the bytes dio would put
/// on the wire) and answers with a canned status, body, or transport failure.
class _WireAdapter implements HttpClientAdapter {
  _WireAdapter({this.status = 200, this.body = const {'ok': true}})
      : failWith = null,
        rawBody = null;

  _WireAdapter.raw(String this.rawBody)
      : status = 200,
        body = null,
        failWith = null;

  _WireAdapter.failing(DioExceptionType this.failWith)
      : status = 0,
        body = null,
        rawBody = null;

  final int status;
  final Object? body;
  final String? rawBody;
  final DioExceptionType? failWith;
  final List<RequestOptions> requests = [];
  final List<String> wireBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    wireBodies.add(utf8.decode(bytes));
    final failure = failWith;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }
    final raw = rawBody;
    return ResponseBody.fromString(
      raw ?? jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [
          raw == null ? Headers.jsonContentType : 'text/html; charset=utf-8',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Setup {
  _Setup(this.adapter) {
    final dio = createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(token: 'jwe-token'),
      onUnauthorized: () => unauthorizedEvents++,
    )..httpClientAdapter = adapter;
    repository = ApiGoalsRepository(dio: dio);
  }

  final _WireAdapter adapter;
  late final ApiGoalsRepository repository;
  int unauthorizedEvents = 0;

  RequestOptions get request => adapter.requests.single;
  String get wire => adapter.wireBodies.single;
}

Map<String, Object?> _error(String code, [String message = 'Pesan server']) =>
    {'ok': false, 'error': code, 'message': message};

const _goal = {
  'id': 17,
  'title': 'Dana pendidikan',
  'description': null,
  'target': 20000000,
  'saved': 0,
  'percent': 0,
  'remaining': 20000000,
  'deadline': null,
  'daysLeft': null,
  'perMonthNeeded': null,
  'createdAt': '2026-11-01T07:00:00.000Z',
  'lastContribution': null,
  'contributionCount': 0,
};

/// The value of multipart part [name] in [wire], or null if absent.
String? _part(String wire, String name) {
  final match = RegExp(
    'content-disposition: form-data; name="$name"\r\n\r\n(.*?)\r\n--',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(wire);
  return match?.group(1);
}

void main() {
  group('list', () {
    test('an empty goals list returns an empty list', () async {
      final s = _Setup(
        _WireAdapter(
          body: {'ok': true, 'asOf': '2026-11-01T07:00:00.000Z', 'goals': []},
        ),
      );
      expect(await s.repository.list(), isEmpty);
    });

    test('unknown top-level and item fields are ignored', () async {
      final s = _Setup(
        _WireAdapter(
          body: {
            'ok': true,
            'asOf': '2026-11-01T07:00:00.000Z',
            'nextCursor': null,
            'goals': [
              {..._goal, 'stage': 'lahan'},
            ],
          },
        ),
      );
      final goals = await s.repository.list();
      expect(goals.single.id, 17);
    });

    test('goals null throws ServerException', () async {
      final s = _Setup(_WireAdapter(body: {'ok': true, 'goals': null}));
      await expectLater(s.repository.list(), throwsA(isA<ServerException>()));
    });

    test('a non-object goal item throws ServerException', () async {
      final s = _Setup(
        _WireAdapter(
          body: {
            'ok': true,
            'goals': [17],
          },
        ),
      );
      await expectLater(s.repository.list(), throwsA(isA<ServerException>()));
    });

    test('a 200 with ok:false throws ServerException with code and message',
        () async {
      final s = _Setup(_WireAdapter(body: _error('server_error', 'Rusak')));
      await expectLater(
        s.repository.list(),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'code', 'server_error')
              .having((e) => e.message, 'message', 'Rusak'),
        ),
      );
    });

    test('a 200 HTML body (proxy/login page) throws ServerException', () async {
      final s = _Setup(_WireAdapter.raw('<html>login</html>'));
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

    test('connection error throws NetworkException', () async {
      final s = _Setup(
        _WireAdapter.failing(DioExceptionType.connectionError),
      );
      await expectLater(s.repository.list(), throwsA(isA<NetworkException>()));
    });

    test('a cancelled request throws the generic ApiException', () async {
      final s = _Setup(_WireAdapter.failing(DioExceptionType.cancel));
      await expectLater(s.repository.list(), throwsA(isA<ApiException>()));
    });
  });

  group('detail', () {
    test('goal null throws ServerException', () async {
      final s = _Setup(_WireAdapter(body: {'ok': true, 'goal': null}));
      await expectLater(
        s.repository.detail(1),
        throwsA(isA<ServerException>()),
      );
    });

    test('a goal with an empty history parses', () async {
      final s = _Setup(
        _WireAdapter(
          body: {
            'ok': true,
            'goal': {..._goal, 'contributions': []},
          },
        ),
      );
      final detail = await s.repository.detail(17);
      expect(s.request.uri.path, '/api/mobile/goals/17');
      expect(detail.contributions, isEmpty);
    });

    test('500 throws ServerException with the status code', () async {
      final s = _Setup(_WireAdapter(status: 500, body: _error('server_error')));
      await expectLater(
        s.repository.detail(1),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('403 throws ForbiddenException', () async {
      final s = _Setup(_WireAdapter(status: 403, body: _error('not_allowed')));
      await expectLater(
        s.repository.detail(1),
        throwsA(isA<ForbiddenException>()),
      );
      expect(s.unauthorizedEvents, 0);
    });

    test('a receive timeout throws NetworkException', () async {
      final s = _Setup(
        _WireAdapter.failing(DioExceptionType.receiveTimeout),
      );
      await expectLater(
        s.repository.detail(1),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('create', () {
    test('wire body is JSON matching the backend parseNewGoal input', () async {
      final s = _Setup(
        _WireAdapter(status: 201, body: {'ok': true, 'goal': _goal}),
      );

      final goal = await s.repository.create(
        title: 'Dana pendidikan',
        target: 20000000,
      );

      expect(s.request.method, 'POST');
      expect(s.request.uri.path, '/api/mobile/goals');
      expect(s.request.contentType, startsWith('application/json'));
      final sent = jsonDecode(s.wire) as Map<String, Object?>;
      expect(sent, {
        'title': 'Dana pendidikan',
        'target': 20000000,
        'description': null,
        'deadline': null,
      });
      // target goes out as a JSON number; the backend rejects strings.
      expect(sent['target'], isA<int>());
      expect(goal.id, 17);
      expect(goal.deadline, isNull);
    });

    test('a UTC deadline from a parsed goal round-trips to the same date',
        () async {
      final s = _Setup(
        _WireAdapter(status: 201, body: {'ok': true, 'goal': _goal}),
      );
      await s.repository.create(
        title: 'x',
        target: 1,
        deadline: DateTime.utc(2027, 12, 31),
      );
      expect((jsonDecode(s.wire) as Map)['deadline'], '2027-12-31');
    });

    test('a local date with a time of day sends only its calendar date',
        () async {
      final s = _Setup(
        _WireAdapter(status: 201, body: {'ok': true, 'goal': _goal}),
      );
      await s.repository.create(
        title: 'x',
        target: 1,
        deadline: DateTime(2027, 1, 5, 23, 59),
      );
      expect((jsonDecode(s.wire) as Map)['deadline'], '2027-01-05');
    });

    test('400 bad_request maps to BadRequestException with code and message',
        () async {
      final s = _Setup(
        _WireAdapter(
          status: 400,
          body: _error(
            'bad_request',
            'Target harus berupa angka bulat lebih dari 0.',
          ),
        ),
      );
      await expectLater(
        s.repository.create(title: 'x', target: 0),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'bad_request')
              .having(
                (e) => e.message,
                'message',
                'Target harus berupa angka bulat lebih dari 0.',
              ),
        ),
      );
      expect(s.unauthorizedEvents, 0);
    });

    test('415 unsupported_media_type maps to UnsupportedMediaTypeException',
        () async {
      final s = _Setup(
        _WireAdapter(
          status: 415,
          body: _error(
            'unsupported_media_type',
            'Format permintaan harus JSON.',
          ),
        ),
      );
      await expectLater(
        s.repository.create(title: 'x', target: 1),
        throwsA(
          isA<UnsupportedMediaTypeException>().having(
            (e) => e.message,
            'message',
            'Format permintaan harus JSON.',
          ),
        ),
      );
    });

    test('500 throws ServerException', () async {
      final s = _Setup(_WireAdapter(status: 500, body: _error('server_error')));
      await expectLater(
        s.repository.create(title: 'x', target: 1),
        throwsA(isA<ServerException>()),
      );
    });

    test('a 201 without goal throws ServerException', () async {
      final s = _Setup(_WireAdapter(status: 201, body: {'ok': true}));
      await expectLater(
        s.repository.create(title: 'x', target: 1),
        throwsA(isA<ServerException>()),
      );
    });

    test('a send timeout throws NetworkException', () async {
      final s = _Setup(_WireAdapter.failing(DioExceptionType.sendTimeout));
      await expectLater(
        s.repository.create(title: 'x', target: 1),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('contribute', () {
    test('wire body is multipart form-data with goalId, amount and note',
        () async {
      final s = _Setup(_WireAdapter(body: {'success': true}));

      await s.repository.contribute(12, 1500000, 'Bonus proyek');

      expect(s.request.uri.path, '/api/contribution');
      final contentType =
          s.request.headers[Headers.contentTypeHeader] as String;
      expect(contentType, startsWith('multipart/form-data; boundary='));
      final boundary = contentType.split('boundary=').last;
      expect(s.wire, contains('--$boundary\r\n'));
      expect(s.wire.trimRight(), endsWith('--$boundary--'));
      expect(_part(s.wire, 'goalId'), '12');
      expect(_part(s.wire, 'amount'), '1500000');
      expect(_part(s.wire, 'note'), 'Bonus proyek');
      // The legacy route reads fields with formData.get(); no file parts.
      expect(s.wire, isNot(contains('filename=')));
    });

    test('without a note the wire body has no note part', () async {
      final s = _Setup(_WireAdapter(body: {'success': true}));
      await s.repository.contribute(12, 20000);
      expect(_part(s.wire, 'goalId'), '12');
      expect(_part(s.wire, 'amount'), '20000');
      expect(_part(s.wire, 'note'), isNull);
    });

    test('a note with emoji and a newline goes out as UTF-8 verbatim',
        () async {
      final s = _Setup(_WireAdapter(body: {'success': true}));
      await s.repository.contribute(12, 20000, 'Gaji 🎉\nOktober');
      expect(_part(s.wire, 'note'), 'Gaji 🎉\nOktober');
    });

    test('an empty note is sent as an empty part (backend stores null)',
        () async {
      final s = _Setup(_WireAdapter(body: {'success': true}));
      await s.repository.contribute(12, 20000, '');
      expect(_part(s.wire, 'note'), '');
    });

    test('a 200 {success:true} completes without reading goal data', () async {
      final s = _Setup(_WireAdapter(body: {'success': true}));
      await expectLater(s.repository.contribute(12, 20000), completes);
    });

    test('403 throws ForbiddenException', () async {
      final s = _Setup(
        _WireAdapter(
          status: 403,
          body: {'success': false, 'message': 'Forbidden'},
        ),
      );
      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('413 (proxy limit) throws PayloadTooLargeException', () async {
      final s = _Setup(_WireAdapter(status: 413, body: {}));
      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(isA<PayloadTooLargeException>()),
      );
    });

    test('500 keeps the legacy message', () async {
      final s = _Setup(
        _WireAdapter(
          status: 500,
          body: {'success': false, 'message': 'Terjadi kesalahan.'},
        ),
      );
      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(
          isA<ServerException>()
              .having((e) => e.message, 'message', 'Terjadi kesalahan.')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('connection error throws NetworkException', () async {
      final s = _Setup(
        _WireAdapter.failing(DioExceptionType.connectionError),
      );
      await expectLater(
        s.repository.contribute(12, 20000),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
